import Foundation

/// A size limit in bytes. `kb` = 1000 bytes, `mb` = 1000 * 1000 bytes.
public struct ByteLimit: Equatable {
    public let bytes: Int

    public init(bytes: Int) {
        self.bytes = bytes
    }
}

/// Settings for one `fit` run.
public struct FitOptions {
    public var limit: ByteLimit
    public var outDir: URL?
    public var recursive: Bool
    public var overwrite: Bool

    public init(limit: ByteLimit, outDir: URL? = nil, recursive: Bool = false, overwrite: Bool = false) {
        self.limit = limit
        self.outDir = outDir
        self.recursive = recursive
        self.overwrite = overwrite
    }
}

/// Every input file ends as exactly one result.
public enum FitResult {
    case done(input: URL, output: URL, bytesBefore: Int, bytesAfter: Int, detail: String)
    case skipped(input: URL, reason: String)
    case failed(input: URL, reason: String)

    public var input: URL {
        switch self {
        case .done(let input, _, _, _, _), .skipped(let input, _), .failed(let input, _):
            return input
        }
    }
}
