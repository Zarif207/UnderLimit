import Foundation
import CoreGraphics
import ImageIO
import PDFKit

/// Shrinks a PDF by rendering every page to a JPEG and rebuilding the PDF.
public enum PDFFitter {
    static let dpiLadder: [Double] = [150, 120, 100, 72]

    public static func fit(_ input: URL, options: FitOptions) -> FitResult {
        let limit = options.limit.bytes

        guard input.pathExtension.lowercased() == "pdf" else {
            return .skipped(input: input, reason: "unsupported type")
        }
        guard let bytesBefore = ImageFitter.fileSize(input) else {
            return .failed(input: input, reason: "cannot read file")
        }
        if bytesBefore <= limit {
            return .skipped(input: input, reason: "already fits")
        }

        let output = outputURL(for: input, outDir: options.outDir)
        if output.standardizedFileURL == input.standardizedFileURL {
            return .failed(input: input, reason: "output would replace the input")
        }
        if FileManager.default.fileExists(atPath: output.path) && !options.overwrite {
            return .failed(input: input, reason: "\(output.lastPathComponent) already exists (use --overwrite)")
        }

        guard let doc = PDFDocument(url: input) else {
            return .failed(input: input, reason: "cannot open PDF")
        }
        if doc.isEncrypted || doc.isLocked {
            return .failed(input: input, reason: "PDF is locked")
        }
        guard doc.pageCount > 0 else {
            return .failed(input: input, reason: "PDF has no pages")
        }

        // Page sizes as displayed (crop box, rotation applied), in points.
        var sizes: [CGSize] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else {
                return .failed(input: input, reason: "cannot read page \(i + 1)")
            }
            sizes.append(displaySize(page))
        }

        // Search: one shared quality per DPI, then step down the DPI ladder.
        var found: (data: Data, quality: Double, dpi: Double)?
        for dpi in dpiLadder {
            var images: [CGImage] = []
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i), let image = render(page, size: sizes[i], dpi: dpi) else {
                    return .failed(input: input, reason: "cannot render page \(i + 1)")
                }
                images.append(image)
            }
            if let (data, q) = bestQuality(images, sizes: sizes, limit: limit) {
                found = (data, q, dpi)
                break
            }
        }
        guard let result = found else {
            return .failed(input: input,
                           reason: "cannot reach \(SizeParser.format(bytes: limit)) at \(Int(dpiLadder.last!)) DPI")
        }

        // Write to a temp file beside the output, verify it, then move into place.
        let dir = output.deletingLastPathComponent()
        let temp = dir.appendingPathComponent(".\(output.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try result.data.write(to: temp)
        } catch {
            return .failed(input: input, reason: "cannot write output: \(error.localizedDescription)")
        }
        guard verify(temp, limit: limit, sizes: sizes) else {
            try? FileManager.default.removeItem(at: temp)
            return .failed(input: input, reason: "output failed verification")
        }
        do {
            if FileManager.default.fileExists(atPath: output.path) {
                guard options.overwrite else {
                    try? FileManager.default.removeItem(at: temp)
                    return .failed(input: input, reason: "\(output.lastPathComponent) already exists (use --overwrite)")
                }
                _ = try FileManager.default.replaceItemAt(output, withItemAt: temp)
            } else {
                try FileManager.default.moveItem(at: temp, to: output)
            }
        } catch {
            try? FileManager.default.removeItem(at: temp)
            return .failed(input: input, reason: "cannot move output into place: \(error.localizedDescription)")
        }

        let bytesAfter = ImageFitter.fileSize(output) ?? result.data.count
        let detail = String(format: "q %.2f, %d DPI, %d pages", result.quality, Int(result.dpi), sizes.count)
        return .done(input: input, output: output, bytesBefore: bytesBefore, bytesAfter: bytesAfter, detail: detail)
    }

    /// `<name>-fit.pdf` next to the input, or inside `outDir`.
    public static func outputURL(for input: URL, outDir: URL?) -> URL {
        let name = input.deletingPathExtension().lastPathComponent + "-fit.pdf"
        return (outDir ?? input.deletingLastPathComponent()).appendingPathComponent(name)
    }

    // MARK: - Steps

    /// Crop-box size with the page rotation applied.
    static func displaySize(_ page: PDFPage) -> CGSize {
        let box = page.bounds(for: .cropBox).size
        return page.rotation % 180 == 0 ? box : CGSize(width: box.height, height: box.width)
    }

    /// Renders one page onto a white sRGB bitmap at the given DPI.
    static func render(_ page: PDFPage, size: CGSize, dpi: Double) -> CGImage? {
        let scale = dpi / 72
        let width = max(1, Int((size.width * scale).rounded()))
        let height = max(1, Int((size.height * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.interpolationQuality = .high
        ctx.scaleBy(x: CGFloat(width) / size.width, y: CGFloat(height) / size.height)
        // PDFKit applies the page rotation and draws the crop box at the origin.
        page.draw(with: .cropBox, to: ctx)
        return ctx.makeImage()
    }

    /// Highest shared quality in 0.30...0.95 whose rebuilt PDF fits, or nil if 0.30 is too big.
    static func bestQuality(_ images: [CGImage], sizes: [CGSize], limit: Int) -> (Data, Double)? {
        guard let floor = buildPDF(images, sizes: sizes, quality: ImageFitter.minQuality),
              floor.count <= limit else { return nil }
        var best = (floor, ImageFitter.minQuality)
        var lo = ImageFitter.minQuality, hi = ImageFitter.maxQuality
        for _ in 0..<ImageFitter.searchSteps {
            let mid = (lo + hi) / 2
            if let data = buildPDF(images, sizes: sizes, quality: mid), data.count <= limit {
                best = (data, mid)
                lo = mid
            } else {
                hi = mid
            }
        }
        return best
    }

    /// Builds a PDF in memory: one JPEG image per page, same page sizes as the input.
    static func buildPDF(_ images: [CGImage], sizes: [CGSize], quality: Double) -> Data? {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: nil, nil) else { return nil }
        for (image, size) in zip(images, sizes) {
            let ok: Bool = autoreleasepool {
                // A JPEG-backed CGImage is embedded as-is (DCTDecode), not re-compressed.
                guard let jpeg = ImageFitter.encodeJPEG(image, quality: quality),
                      let provider = CGDataProvider(data: jpeg as CFData),
                      let jpegImage = CGImage(jpegDataProviderSource: provider, decode: nil,
                                              shouldInterpolate: true, intent: .defaultIntent) else { return false }
                var box = CGRect(origin: .zero, size: size)
                ctx.beginPage(mediaBox: &box)
                ctx.draw(jpegImage, in: box)
                ctx.endPage()
                return true
            }
            if !ok { ctx.closePDF(); return nil }
        }
        ctx.closePDF()
        return data as Data
    }

    /// Re-opens the file from disk: opens, page count and page sizes match, size within limit.
    static func verify(_ url: URL, limit: Int, sizes: [CGSize]) -> Bool {
        guard let size = ImageFitter.fileSize(url), size > 0, size <= limit,
              let doc = PDFDocument(url: url), !doc.isLocked,
              doc.pageCount == sizes.count else { return false }
        for (i, expected) in sizes.enumerated() {
            guard let page = doc.page(at: i) else { return false }
            let got = displaySize(page)
            guard got.width > 0, got.height > 0,
                  abs(got.width - expected.width) < 0.5, abs(got.height - expected.height) < 0.5 else { return false }
        }
        return true
    }
}
