import Foundation

/// Entry point: routes each input file to the right fitter.
public enum Fitter {
    /// One result per file. Folders expand to their supported files.
    public static func fit(_ paths: [URL], options: FitOptions) -> [FitResult] {
        if let outDir = options.outDir {
            do {
                try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
            } catch {
                return paths.map { .failed(input: $0, reason: "cannot create --out folder") }
            }
        }
        var results: [FitResult] = []
        for path in paths {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path.path, isDirectory: &isDir), isDir.boolValue {
                let files = expand(folder: path, recursive: options.recursive)
                if files.isEmpty {
                    results.append(.skipped(input: path, reason: "no supported files in folder"))
                }
                results += files.map { fitOne($0, options: options) }
            } else {
                results.append(fitOne(path, options: options))
            }
        }
        return results
    }

    /// Supported, non-hidden files in a folder, skipping names ending in `-fit`. Sorted by path.
    public static func expand(folder: URL, recursive: Bool) -> [URL] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey]
        var urls: [URL]
        if recursive {
            let e = fm.enumerator(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
            urls = (e?.allObjects as? [URL]) ?? []
        } else {
            urls = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                options: [.skipsHiddenFiles])) ?? []
        }
        urls = urls.filter { url in
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return false }
            guard isSupported(url) else { return false }
            return !url.deletingPathExtension().lastPathComponent.hasSuffix("-fit")
        }
        return urls.sorted { $0.path < $1.path }
    }

    static func isSupported(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "pdf" || ImageFitter.supportedExtensions.contains(ext)
    }

    static func fitOne(_ input: URL, options: FitOptions) -> FitResult {
        guard FileManager.default.fileExists(atPath: input.path) else {
            return .failed(input: input, reason: "file not found")
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
