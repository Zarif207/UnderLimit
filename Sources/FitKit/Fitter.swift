import Foundation

/// Entry point: routes each input file to the right fitter.
public enum Fitter {
    /// One result per path, in the same order.
    public static func fit(_ paths: [URL], options: FitOptions) -> [FitResult] {
        paths.map { fitOne($0, options: options) }
    }

    static func fitOne(_ input: URL, options: FitOptions) -> FitResult {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: input.path, isDirectory: &isDir) else {
            return .failed(input: input, reason: "file not found")
        }
        if isDir.boolValue {
            return .skipped(input: input, reason: "folder support not built yet")
        }
        let ext = input.pathExtension.lowercased()
        if ext == "pdf" {
            return PDFFitter.fit(input, options: options)
        }
        if ImageFitter.supportedExtensions.contains(ext) {
            return ImageFitter.fit(input, options: options)
        }
        return .skipped(input: input, reason: "unsupported type")
    }
}
