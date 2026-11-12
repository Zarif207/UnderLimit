# UnderLimit

Shrink an image or PDF until it fits under a size limit, and keep the best-looking result that still fits.

```console
$ fit passport.jpg --max 200kb
done     passport.jpg -> passport-fit.jpg   1.8 MB -> 196 KB   (q 0.62, 1200x1500)
1 file(s): 1 done, 0 skipped, 0 failed
```

UnderLimit is a native macOS command-line tool written in Swift. It runs entirely on your machine: no uploads, no accounts, no network access. Portals that cap upload sizes (visa forms, university applications, job portals) are the main use case.

## Features

- **Images**: JPEG, PNG, HEIC and TIFF in; JPEG out. Finds the highest JPEG quality that fits, and scales the image down only when quality alone is not enough.
- **PDFs**: rasterises pages and rebuilds the file at the lowest DPI that fits (150 → 120 → 100 → 72).
- **Folders**: process a directory in one run, with optional recursion and an output directory.
- **Safe by construction**: originals are never modified, and every output is verified before it is accepted.
- **Privacy**: EXIF metadata, including GPS location, is removed from image outputs.

## Requirements

- macOS 13 or later, Apple Silicon
- Swift 5.9+ toolchain (Xcode or the Command Line Tools)

## Installation

Build from source:

```sh
git clone https://github.com/Zarif207/UnderLimit.git
cd UnderLimit
swift build -c release
cp .build/release/fit /usr/local/bin/fit
```

Verify:

```sh
fit --help
```

## Usage

```sh
# One file
fit photo.jpg --max 200kb

# Several files, with an explicit output directory
fit scan.pdf receipt.png --max 1mb --out ~/Desktop/fitted

# A whole folder (non-recursive by default)
fit ~/Pictures/visa-docs --max 500kb

# Include subfolders, and replace existing outputs
fit ~/Pictures --max 2mb --recursive --overwrite
```

### Size limits

| Input     | Meaning                          |
|-----------|----------------------------------|
| `200kb`   | 200 × 1000 bytes                 |
| `1.5mb`   | 1.5 × 1000 × 1000 bytes          |
| `500000`  | 500 000 bytes                    |

Units are decimal (1 KB = 1000 bytes), which is the stricter reading: a file that passes here will also pass portals that count the same way.

### Options

| Flag                 | Purpose                                                      |
|----------------------|--------------------------------------------------------------|
| `--max <size>`       | Required. Target size limit.                                 |
| `--out <dir>`        | Write outputs to this directory (created if missing).        |
| `--recursive`        | Descend into subfolders when a folder is given.              |
| `--overwrite`        | Allow replacing an existing `*-fit.*` output.                |

### Output and exit codes

Each input produces exactly one line: `done`, `skipped` or `failed`, with the reason. Outputs are named `<name>-fit.<ext>`, placed next to the input unless `--out` is given.

The exit code is `0` when nothing failed and `1` otherwise, so the tool can be used in scripts.

## How it works

**Images**

1. If the file already fits, it is skipped.
2. Binary search over JPEG quality (0.30 to 0.95, seven steps) finds the highest quality whose encoding fits.
3. If quality 0.30 still does not fit, the long edge is reduced to 80% and the search repeats. The process stops at a 400 px floor.
4. EXIF orientation is applied to the pixels, transparency is flattened onto white, and metadata is dropped.

**PDFs**

1. If the file already fits, it is skipped.
2. Pages are rendered at 150 DPI, and one shared JPEG quality is searched as above.
3. If that is not enough, the DPI steps down through 120, 100 and 72. Below 72 DPI the file is reported as failed.

**Verification**

Before an output is accepted, it is reopened from disk and checked: it must decode, page count and dimensions must match, and the size must be within the limit. Failed outputs are deleted.

## Guarantees

- Input files are never modified, moved or deleted.
- An output is never written if it exceeds the limit or fails verification.
- Existing outputs are never overwritten without `--overwrite`.
- Writes are atomic: data goes to a temporary file, which is then moved into place.
- Every input is accounted for in the output. Nothing is skipped silently.

## Limitations

- **PDF text is not selectable** after processing, because pages become images. This is inherent to the approach.
- **Image outputs are always JPEG.** Transparency is lost, and very small limits may need a lower resolution.
- **Some limits cannot be met.** Such files are reported as `failed` with the closest reason, not forced through.
- Encrypted or password-protected PDFs are not supported.

## Results

Measured on a MacBook Air M1, macOS 26, using the release build. Replace these rows with your own measurements before sharing.

| Input | Original | Limit | Output | Quality / DPI | Time |
|-------|----------|-------|--------|---------------|------|
|       |          |       |        |               |      |
|       |          |       |        |               |      |

## Development

The project has no XCTest or Swift Testing dependency, so the checks run as a regular executable:

```sh
swift build
swift run fitcheck
```

`fitcheck` generates its own test images and PDFs in a temporary directory, prints `PASS` or `FAIL` for each check, and exits non-zero on any failure.

### Layout

```
Sources/
  FitKit/     Core library: size parsing, image and PDF fitting, verification
  fit/        Command-line interface
  FitApp/     SwiftUI window (optional)
  fitcheck/   Self-checks for FitKit
```

`FitKit` contains all of the logic and has no printing or UI code, so it can be reused by the CLI and the app.

## Roadmap

- Lossless PNG optimisation as an alternative to JPEG conversion
- Preserve PDF text by re-encoding only image-heavy pages
- Homebrew formula for installation without building from source