import Foundation
import CoreGraphics
import ImageIO

/// Shrinks one image (jpg, jpeg, png, heic, tiff) to a JPEG under the limit.
public enum ImageFitter {
    public static let supportedExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "tiff", "tif"]

    static let minQuality = 0.30
    static let maxQuality = 0.95
    static let searchSteps = 7
    static let scaleFactor = 0.8
    static let minLongEdge = 400

    public static func fit(_ input: URL, options: FitOptions) -> FitResult {
        let limit = options.limit.bytes

        guard supportedExtensions.contains(input.pathExtension.lowercased()) else {
            return .skipped(input: input, reason: "unsupported type")
        }
        guard let bytesBefore = fileSize(input) else {
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

        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let full = orientedImage(source, maxLongEdge: nil) else {
            return .failed(input: input, reason: "cannot decode image")
        }

        // Search: quality first, then shrink the long edge by 80% and retry.
        var longEdge = max(full.width, full.height)
        var found: (data: Data, quality: Double, width: Int, height: Int)?
        while found == nil {
            let image: CGImage?
            if longEdge == max(full.width, full.height) {
                image = full
            } else {
                image = orientedImage(source, maxLongEdge: longEdge)
            }
            guard let image, let flat = flattenOnWhite(image) else {
                return .failed(input: input, reason: "cannot decode image")
            }
            if let (data, q) = bestQuality(flat, limit: limit) {
                found = (data, q, flat.width, flat.height)
                break
            }
            let next = Int(Double(longEdge) * scaleFactor)
            if next < minLongEdge {
                return .failed(input: input,
                               reason: "cannot reach \(SizeParser.format(bytes: limit)) above \(minLongEdge) px")
            }
            longEdge = next
        }
        guard let result = found else {
            return .failed(input: input, reason: "cannot encode image")
        }

        // Write once to a temp file beside the output, verify it, then move into place.
        let dir = output.deletingLastPathComponent()
        let temp = dir.appendingPathComponent(".\(output.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try result.data.write(to: temp)
        } catch {
            return .failed(input: input, reason: "cannot write output: \(error.localizedDescription)")
        }
        guard verify(temp, limit: limit, width: result.width, height: result.height) else {
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

        let bytesAfter = fileSize(output) ?? result.data.count
        let detail = String(format: "q %.2f, %dx%d", result.quality, result.width, result.height)
        return .done(input: input, output: output, bytesBefore: bytesBefore, bytesAfter: bytesAfter, detail: detail)
    }

    /// `<name>-fit.jpg` next to the input, or inside `outDir`.
    public static func outputURL(for input: URL, outDir: URL?) -> URL {
        let name = input.deletingPathExtension().lastPathComponent + "-fit.jpg"
        return (outDir ?? input.deletingLastPathComponent()).appendingPathComponent(name)
    }

    // MARK: - Steps

    /// Decodes the image with EXIF orientation applied to the pixels,
    /// optionally scaled so the long edge is at most `maxLongEdge`.
    static func orientedImage(_ source: CGImageSource, maxLongEdge: Int?) -> CGImage? {
        var opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if let maxLongEdge {
            opts[kCGImageSourceThumbnailMaxPixelSize] = maxLongEdge
        } else if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let w = props[kCGImagePropertyPixelWidth] as? Int,
                  let h = props[kCGImagePropertyPixelHeight] as? Int {
            opts[kCGImageSourceThumbnailMaxPixelSize] = max(w, h)
        }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary)
    }

    /// Draws the image onto an opaque white sRGB canvas (removes transparency).
    static func flattenOnWhite(_ image: CGImage) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: image.width, height: image.height,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(rect)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: rect)
        return ctx.makeImage()
    }

    /// Highest quality in 0.30...0.95 whose JPEG fits, or nil if 0.30 is too big.
    static func bestQuality(_ image: CGImage, limit: Int) -> (Data, Double)? {
        guard let floor = encodeJPEG(image, quality: minQuality), floor.count <= limit else { return nil }
        var best = (floor, minQuality)
        var lo = minQuality, hi = maxQuality
        for _ in 0..<searchSteps {
            let mid = (lo + hi) / 2
            if let data = encodeJPEG(image, quality: mid), data.count <= limit {
                best = (data, mid)
                lo = mid
            } else {
                hi = mid
            }
        }
        return best
    }

    /// Encodes to JPEG in memory. No metadata is passed, so none is written.
    static func encodeJPEG(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// Re-opens the file from disk: decodes, dimensions match, size within limit.
    static func verify(_ url: URL, limit: Int, width: Int, height: Int) -> Bool {
        guard let size = fileSize(url), size > 0, size <= limit,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return false }
        return image.width == width && image.height == height && width > 0 && height > 0
    }

    static func fileSize(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
    }
}
