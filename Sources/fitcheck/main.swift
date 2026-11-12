import Foundation
import FitKit

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

// MARK: - Summary

if failures > 0 {
    print("\(failures) check(s) failed")
    exit(1)
}
print("all checks passed")
