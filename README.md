# UnderLimit

## What it does

UnderLimit is a small native macOS tool that shrinks an image or PDF until it
fits under a size limit you choose. You give it a file and a limit such as
`--max 200kb`, and it writes the best-looking copy that still fits, next to
the original. It comes as a command-line tool (`fit`) and an optional
SwiftUI window (`FitApp`).

```
fit passport.jpg --max 200kb
done     passport.jpg -> passport-fit.jpg   1.8 MB -> 196 KB   (q 0.62, 1200x1500)
```

## Why

- Upload portals (visa forms, job sites, university applications) often reject
  files over 200 KB, 500 KB or 1 MB, and online compressors give no guarantee.
- Everything runs locally. Your files never leave your Mac.
- Sizes are strict: `kb` = 1000 bytes and `mb` = 1,000,000 bytes, so the
  output is accepted even by portals that use the smaller definition.

## Install from source

Requires macOS 13+ and Apple's Command Line Tools (Xcode is not needed).

```
git clone https://github.com/Zarif207/UnderLimit.git
cd UnderLimit
swift build -c release
sudo cp .build/release/fit /usr/local/bin/
```

To open the window app instead: `swift run FitApp`.

## Usage

```
fit <path>... --max <size> [--out <dir>] [--recursive] [--overwrite]
```

Image:

```
fit passport.jpg --max 200kb
```

PDF:

```
fit transcript.pdf --max 1mb
```

Folder (add `--recursive` to include subfolders, `--out` to write elsewhere):

```
fit ~/Desktop/scans --max 500kb --out ~/Desktop/upload
```

Each file gets one line (`done`, `skipped` or `failed`), followed by a
summary line. The exit code is 0 if nothing failed, otherwise 1.

## How it works

- Images: binary-search JPEG quality from 0.30 to 0.95 and keep the highest
  quality that fits.
- If quality 0.30 is still too big, shrink the long edge to 80% and search
  again, stopping at 400 px.
- PDFs: render each page to a JPEG at 150 DPI and rebuild the PDF with the
  same page sizes, lowering to 120, 100 and 72 DPI if needed.
- Images are rotated upright from EXIF, transparency is flattened onto white,
  and metadata (including GPS location) is dropped.
- Every output is re-opened from disk and checked (decodes, pages and
  dimensions match, size under the limit) before it is kept.

## Guardrails

- Never modifies, moves or deletes an input file.
- Never writes an output that is over the limit or failed verification.
- Never overwrites an existing file unless `--overwrite` is passed.
- Never skips silently: every input produces one result line.
- Folder mode ignores files whose name already ends in `-fit`.

## Limits

- PDF text is no longer selectable or searchable, because pages are
  re-rendered as images.
- Output images are always JPEG (`<name>-fit.jpg`), even from PNG, HEIC or TIFF.
- Locked or encrypted PDFs are not supported.

## Results

| File | Type | Before | Limit | After | Settings |
|------|------|--------|-------|-------|----------|
|      |      |        |       |       |          |
|      |      |        |       |       |          |
|      |      |        |       |       |          |
