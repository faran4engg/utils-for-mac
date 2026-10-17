# imgcompress

Makes JPEG and PNG images smaller, keeping date taken, location, orientation, colour profile and Finder dates. Shows a dry run with an estimated saving first.

## Usage

```bash
imgcompress                    # dry run: list images, total size, estimated saving
imgcompress --go               # lossless: pictures stay pixel-for-pixel identical
imgcompress --smaller          # dry run for the "smaller" mode
imgcompress --smaller --go     # re-save JPEGs at quality 85: much smaller, looks the same
imgcompress --smaller --keep --go   # keep originals next to "(compressed)" files to compare
```

| Option | What it does |
|---|---|
| `folder` | Folder to scan (default: current folder) |
| `--go` | Actually compress (without it: dry run only) |
| `-n`, `--dry-run` | Only preview, even with `--go` |
| `--smaller` | Re-save JPEGs instead of only repacking them. Often 30-60% smaller; pixels change slightly but you shouldn't see it |
| `--quality N` | JPEG quality for `--smaller` (default 85, sensible range 80-92) |
| `--keep` | Keep the original, save the new one as `name (compressed).jpg` |
| `--min SIZE` | Skip images smaller than this (default `100K`) |
| `-a`, `--all` | Include hidden files and folders |
| `-h`, `--help` | Show help |

## Lossless vs smaller

| | Lossless (default) | `--smaller` |
|---|---|---|
| JPEG | `jpegtran` repacks the file. Typically 5-15% smaller | Re-saved at quality 85. Typically 30-60% smaller |
| PNG | `oxipng` repacks the file. Typically 10-40% smaller | Same as lossless |
| Picture | Identical | Visually the same |

HEIC, WebP and AVIF (like iPhone photos) are skipped: they're already efficiently compressed. Each new file is checked (opens, same size in pixels, same date taken) before the original goes to the Trash. Images that wouldn't get meaningfully smaller (under 2% lossless, under 10% with `--smaller`) are left alone, so running it again doesn't keep degrading photos. Logs go to `~/imgcompress-reports/`.

Needs `brew install jpeg-turbo exiftool`. For PNGs: `brew install oxipng`. Optional: `brew install mozjpeg` makes `--smaller` JPEGs a bit smaller still at the same quality.

## Install / update

```bash
~/Code/faran4engg/utils-for-mac/install.sh
```

See the [main README](../README.md).
