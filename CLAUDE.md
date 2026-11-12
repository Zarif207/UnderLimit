# UnderLimit — shrink a file to fit under a size limit

Project name: **UnderLimit**. Command name: `fit`. Swift package name:
`UnderLimit`. Targets keep their names (FitKit, fit, fitcheck, FitApp).

A small native macOS tool. You give it an image or PDF and a size limit
(`--max 200kb`); it writes the best-looking copy that fits under the limit.
Everything runs locally. The owner is new to Swift and has a limited token
budget — see "Working rules" before doing anything.

```
fit passport.jpg --max 200kb
done     passport.jpg -> passport-fit.jpg   1.8 MB -> 196 KB   (q 0.62, 1200x1500)
```

## Stack

- Swift, Swift Package Manager. `swift-tools-version: 5.9`, Swift 5 language
  mode (no strict-concurrency work). Platform: macOS 13+. Apple Silicon.
- ImageIO + CoreGraphics (images), PDFKit (PDFs), SwiftUI (app window).
- One dependency only: `apple/swift-argument-parser`.
- No Xcode on this Mac — only Apple's Command Line Tools. So: no `swift test`,
  no XCTest, no Swift Testing, no `xcodebuild`, and no Swift macros
  (`@Observable`, `#Preview`; use `ObservableObject` instead).
- Checks live in a small executable target, `fitcheck`, run with
  `swift run fitcheck`. It prints PASS/FAIL per check and exits 1 on any FAIL.

## Layout

```
Package.swift
Sources/FitKit/     library: all logic, no printing, no UI
  Model.swift         ByteLimit, FitOptions, FitResult
  SizeParser.swift    "200kb" / "1.5mb" -> bytes
  ImageFitter.swift   image search loop
  PDFFitter.swift     PDF search loop
  Fitter.swift        entry point: one file or a folder -> [FitResult]
Sources/fit/        CLI: parse arguments, call FitKit, print lines
Sources/FitApp/     SwiftUI window (last step, optional)
Sources/fitcheck/   self-checks for FitKit (replaces a test target)
```

## Behaviour (the spec)

Sizes: `kb` = 1000 bytes, `mb` = 1000 * 1000 bytes (the stricter reading, so
the output is accepted by every portal). Case-insensitive, decimals allowed.

Every input file ends as exactly one `FitResult`:
- `done(input, output, bytesBefore, bytesAfter, detail)`
- `skipped(input, reason)` — e.g. "already fits", "unsupported type"
- `failed(input, reason)` — e.g. "cannot reach 50 KB above 400 px"

Images (jpg, jpeg, png, heic, tiff in; always `.jpg` out):
1. Input already <= limit -> `skipped("already fits")`.
2. Binary-search JPEG quality in 0.30...0.95, 7 steps, keep the highest
   quality whose encoded size is <= limit.
3. If quality 0.30 is still too big, scale the long edge to 80% and repeat
   step 2. Stop and fail if the long edge would go below 400 px.
4. Apply EXIF orientation to the pixels. Flatten transparency onto white.
   Do not copy metadata (drops GPS location — a feature, mention in output).

PDFs (`.pdf` in and out):
1. Input already <= limit -> `skipped("already fits")`.
2. Render each page to an image, JPEG-encode it, rebuild a PDF with the same
   page sizes. Start at 150 DPI and binary-search one quality for all pages
   (same range and steps as images).
3. If quality 0.30 is still too big, lower DPI: 150 -> 120 -> 100 -> 72.
   Below 72 DPI -> `failed`.
4. Output text is no longer selectable; the CLI says so once per PDF.
5. Encrypted / locked PDFs -> `failed("PDF is locked")`.

Verify before accepting (both types): re-open the output from disk, check it
decodes, page count / non-zero dimensions match, and size <= limit. A failed
check deletes the output and returns `failed`.

Output: `<name>-fit.<ext>` next to the input, or inside `--out <dir>`.
Write to a temp file, then move into place (atomic).

## Guardrails — never break these

- Never modify, move, or delete an input file. No flag enables it.
- Never write an output that is over the limit or failed verification.
- Never overwrite an existing file unless `--overwrite` is passed.
- Never silently skip: every input produces one result line.
- Folder mode ignores files whose name already ends in `-fit`.

## CLI

```
fit <path>... --max <size> [--out <dir>] [--recursive] [--overwrite]
```
A path may be a file or a folder (folders are not recursive by default).
One line per file, then a summary line. Exit code 0 if nothing failed, else 1.

## Commands

```
swift build
swift run fitcheck
swift run fit <file> --max 200kb
swift build -c release        # binary at .build/release/fit
```

## Working rules (token budget is small)

- Do only the step asked. Do not start the next step.
- Read only the files the step needs. Do not explore or re-read the tree.
- No refactors, renames, extra features, or extra docs unless asked.
- Checks create their own images/PDFs in code (CoreGraphics noise images)
  inside a temp folder and clean up after; do not add fixture files.
- Finish each step with `swift build && swift run fitcheck` passing, then reply with
  a short summary: files changed, and one sentence per file on what it does.
- If something in this spec is impossible with the SDK, stop and say so in
  two lines instead of working around it.
- The owner commits; do not run git commands.
