import Foundation

/// Why a size string could not be read.
public struct SizeParseError: Error, Equatable, CustomStringConvertible {
    public let input: String
    public let message: String

    public var description: String { "invalid size \"\(input)\": \(message)" }
}

extension SizeParseError: LocalizedError {
    public var errorDescription: String? { description }
}

/// Reads sizes like "200kb", "1.5MB", "2 mb", "500000" and formats byte counts for display.
/// Units are decimal: kb = 1000 bytes, mb = 1000 * 1000 bytes.
public enum SizeParser {

    public static func parse(_ text: String) throws -> ByteLimit {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        func fail(_ message: String) -> SizeParseError { SizeParseError(input: text, message: message) }

        guard !trimmed.isEmpty else { throw fail("empty") }
        if trimmed.hasPrefix("-") { throw fail("size must be positive") }

        // Split into number part and unit part ("2 mb" -> "2", "mb").
        let numberPart = String(trimmed.prefix { $0.isASCII && ($0.isNumber || $0 == ".") })
        let unitPart = trimmed.dropFirst(numberPart.count).trimmingCharacters(in: .whitespaces)

        guard !numberPart.isEmpty,
              numberPart.filter({ $0 == "." }).count <= 1,
              numberPart.contains(where: { $0.isNumber }) else {
            throw fail("expected a number like 200kb, 1.5mb or 500000")
        }

        let multiplier: Decimal
        switch unitPart {
        case "", "b": multiplier = 1
        case "kb": multiplier = 1000
        case "mb": multiplier = 1_000_000
        default: throw fail("unknown unit \"\(unitPart)\" (use b, kb or mb)")
        }

        guard let number = Decimal(string: numberPart, locale: Locale(identifier: "en_US_POSIX")) else {
            throw fail("not a number")
        }
        var exact = number * multiplier
        guard exact <= Decimal(Int.max) else { throw fail("too large") }

        // Round down: never allow more bytes than asked for.
        var whole = Decimal()
        NSDecimalRound(&whole, &exact, 0, .down)
        let bytes = NSDecimalNumber(decimal: whole).intValue
        guard bytes > 0 else { throw fail("size must be at least 1 byte") }

        return ByteLimit(bytes: bytes)
    }

    /// "512 B", "196 KB", "1.8 MB" (decimal units).
    public static func format(bytes: Int) -> String {
        if bytes < 1000 { return "\(bytes) B" }
        let kb = (Double(bytes) / 1000).rounded()
        if kb < 1000 { return "\(Int(kb)) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1_000_000)
    }
}
