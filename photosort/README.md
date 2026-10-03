# photosort

Sorts photos and videos into date folders (like `2023/08-August`) by the date they were actually taken, read from the file's metadata with exiftool. Scans all subfolders. Shows a preview first and never overwrites a file.

Requires: `brew install exiftool`

## Usage

```
photosort [options] [SOURCE] [DEST]
```

SOURCE defaults to the current folder. DEST defaults to `SOURCE (sorted)` next to it.

| Option | What it does |
|---|---|
| `--go` | Actually move the files (without it: preview only) |
| `--copy` | Copy instead of move |
| `--by LAYOUT` | `month` = 2023/08-August (default), `day` = 2023/08-August/14, `year` = 2023 |
| `--strict` | Put undated files in `Unknown date/` instead of using their Created date |
| `--ignore-camera NAME` | Ignore date taken from this camera, use Created date (Canon EOS M50 built in) |
| `--min-year YEAR` | Use Created date when date taken is before YEAR (off by default) |
| `-a`, `--all` | Include hidden files and folders |
| `--undo LOG` | Move everything back using the log from a `--go` run |
| `-h`, `--help` | Show help |

```
photosort ~/Pictures/Export          # preview
photosort ~/Pictures/Export --go     # do it
photosort --undo ~/photosort-reports/<date>-move.log
```

Live Photo videos and `.AAE` / `.XMP` sidecars follow their photo. Name clashes get a number (`IMG_0001 (2).jpg`). Identical files already in the destination are left in place. Previews and logs go to `~/photosort-reports/`.

## Install on a new Mac

```bash
brew install exiftool
chmod +x ~/Code/utils-for-mac/photosort/photosort.sh
ln -sf ~/Code/utils-for-mac/photosort/photosort.sh ~/bin/photosort
```
