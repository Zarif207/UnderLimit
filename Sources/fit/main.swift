import ArgumentParser
import FitKit
import Foundation

struct Fit: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fit",
        abstract: "Shrink images and PDFs to fit under a size limit."
    )

    @Argument(help: "Files to shrink.")
    var paths: [String]

    @Option(help: "Size limit, e.g. 200kb or 1.5mb (kb = 1000 bytes).")
    var max: String

    @Option(help: "Folder to write outputs into (default: next to each input).")
    var out: String?

    @Flag(help: "Look inside subfolders.")
    var recursive = false

    @Flag(help: "Replace an existing -fit output file.")
    var overwrite = false

    func run() throws {
        let limit: ByteLimit
        do {
            limit = try SizeParser.parse(max)
        } catch {
            throw ValidationError("\(error)")
        }

        var outDir: URL?
        if let out {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: out, isDirectory: &isDir), isDir.boolValue else {
                throw ValidationError("--out folder does not exist: \(out)")
            }
            outDir = URL(fileURLWithPath: out)
        }

        let options = FitOptions(limit: limit, outDir: outDir, recursive: recursive, overwrite: overwrite)
        let inputs = paths.map { URL(fileURLWithPath: $0) }
        let results = Fitter.fit(inputs, options: options)

        var done = 0, skipped = 0, failed = 0, imagesDone = 0
        for result in results {
            switch result {
            case .done(let input, let output, let before, let after, let detail):
                done += 1
                if input.pathExtension.lowercased() != "pdf" { imagesDone += 1 }
                print(line("done", input,
                           "-> \(output.lastPathComponent)   "
                           + "\(SizeParser.format(bytes: before)) -> \(SizeParser.format(bytes: after))   (\(detail))"))
                if input.pathExtension.lowercased() == "pdf" {
                    print(String(repeating: " ", count: 9) + "note: text in \(output.lastPathComponent) is no longer selectable")
                }
            case .skipped(let input, let reason):
                skipped += 1
                print(line("skipped", input, "(\(reason))"))
            case .failed(let input, let reason):
                failed += 1
                print(line("failed", input, "(\(reason))"))
            }
        }

        var summary = "\(results.count) file(s): \(done) done, \(skipped) skipped, \(failed) failed"
        if imagesDone > 0 {
            summary += ". Image metadata (incl. GPS location) removed."
        }
        print(summary)

        if failed > 0 { throw ExitCode(1) }
    }

    func line(_ status: String, _ input: URL, _ rest: String) -> String {
        status.padding(toLength: 9, withPad: " ", startingAt: 0) + input.lastPathComponent + " " + rest
    }
}

Fit.main()
