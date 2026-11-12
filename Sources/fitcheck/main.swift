import Foundation
import FitKit
import CoreGraphics
import ImageIO

var failures = 0

func check(_ name: String, _ condition: Bool) {
    print("\(condition ? "PASS" : "FAIL")  \(name)")
    if !condition { failures += 1 }
}

// MARK: - Checks

check("ByteLimit stores bytes", ByteLimit(bytes: 200_000).bytes == 200_000)

// SizeParser.parse
func parsed(_ s: String) -> Int? { try? SizeParser.parse(s).bytes }

check("parse 200kb", parsed("200kb") == 200_000)
check("parse 1.5MB", parsed("1.5MB") == 1_500_000)
check("parse '2 mb'", parsed("2 mb") == 2_000_000)
check("parse 500000", parsed("500000") == 500_000)
check("parse 750b", parsed("750b") == 750)
check("parse 0.5kb", parsed("0.5kb") == 500)
check("parse ' 200KB '", parsed(" 200KB ") == 200_000)
for bad in ["abc", "-5kb", "", "0kb", "1.2.3mb", "5gb", "kb", "12kbx", "."] {
    check("parse rejects '\(bad)'", parsed(bad) == nil)
}
do {
    _ = try SizeParser.parse("abc")
    check("error message is clear", false)
} catch {
    check("error message is clear", "\(error)".contains("abc"))
}

// SizeParser.format
check("format 512 B", SizeParser.format(bytes: 512) == "512 B")
check("format 196 KB", SizeParser.format(bytes: 196_000) == "196 KB")
check("format 1.8 MB", SizeParser.format(bytes: 1_800_000) == "1.8 MB")
check("format 999_700 -> 1.0 MB", SizeParser.format(bytes: 999_700) == "1.0 MB")

// MARK: - ImageFitter

/// Writes a random-noise PNG (compresses badly, so it is large).
func writeNoisePNG(_ url: URL, width: Int, height: Int) {
    let bytesPerRow = width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * height)
    arc4random_buf(&pixels, pixels.count)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = pixels.withUnsafeMutableBytes { buf in
        CGContext(data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8,
                  bytesPerRow: bytesPerRow, space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    }
    let image = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("fitcheck-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

let noise = tmp.appendingPathComponent("noise.png")
writeNoisePNG(noise, width: 1600, height: 1200)
let noiseBytes = try! Data(contentsOf: noise)

// Fits under the limit.
let limit200 = FitOptions(limit: ByteLimit(bytes: 200_000))
let r1 = ImageFitter.fit(noise, options: limit200)
if case .done(_, let out, _, let after, let detail) = r1 {
    let onDisk = (try? Data(contentsOf: out))?.count ?? Int.max
    check("image: output under limit (\(detail))", after <= 200_000 && onDisk <= 200_000)
    check("image: output is <name>-fit.jpg", out.lastPathComponent == "noise-fit.jpg")
} else {
    check("image: output under limit (got \(r1))", false)
}
check("image: input bytes unchanged", (try? Data(contentsOf: noise)) == noiseBytes)

// Small file is skipped.
let small = tmp.appendingPathComponent("small.png")
writeNoisePNG(small, width: 40, height: 40)
if case .skipped(_, let reason) = ImageFitter.fit(small, options: limit200) {
    check("image: small file skipped (\(reason))", reason == "already fits")
} else {
    check("image: small file skipped", false)
}

// Impossible limit fails and writes nothing.
let impossibleDir = tmp.appendingPathComponent("impossible")
try! FileManager.default.createDirectory(at: impossibleDir, withIntermediateDirectories: true)
let r3 = ImageFitter.fit(noise, options: FitOptions(limit: ByteLimit(bytes: 1_000), outDir: impossibleDir))
if case .failed(_, let reason) = r3 {
    check("image: impossible limit fails (\(reason))", true)
} else {
    check("image: impossible limit fails (got \(r3))", false)
}
check("image: failed run leaves no files",
      (try? FileManager.default.contentsOfDirectory(atPath: impossibleDir.path))?.isEmpty == true)

// Existing output is not overwritten without the option.
let keepDir = tmp.appendingPathComponent("keep")
try! FileManager.default.createDirectory(at: keepDir, withIntermediateDirectories: true)
let existing = keepDir.appendingPathComponent("noise-fit.jpg")
let placeholder = Data("keep me".utf8)
try! placeholder.write(to: existing)
let r4 = ImageFitter.fit(noise, options: FitOptions(limit: ByteLimit(bytes: 200_000), outDir: keepDir))
if case .done = r4 {
    check("image: existing output not overwritten", false)
} else {
    check("image: existing output not overwritten",
          (try? Data(contentsOf: existing)) == placeholder)
}
let r5 = ImageFitter.fit(noise, options: FitOptions(limit: ByteLimit(bytes: 200_000), outDir: keepDir, overwrite: true))
if case .done = r5 {
    check("image: --overwrite replaces existing output", (try? Data(contentsOf: existing)) != placeholder)
} else {
    check("image: --overwrite replaces existing output (got \(r5))", false)
}

try? FileManager.default.removeItem(at: tmp)

// MARK: - Summary

if failures > 0 {
    print("\(failures) check(s) failed")
    exit(1)
}
print("all checks passed")
