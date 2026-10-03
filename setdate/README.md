# setdate

Gives every photo and video in a folder (and its subfolders) the same date: the date taken inside the file, plus Finder's Created and Modified dates. Useful for undated photos from one event, like scanned childhood photos.

Requires: `brew install exiftool`

## Usage

```bash
setdate 2018-11-15                # preview
setdate 2018-11-15 --go           # write it
setdate "2018-11-15 18:30" --go   # with a start time (default 12:00)
setdate --undo ~/photosort-reports/<date>-setdate-undo.csv
```

| Option | What it does |
|---|---|
| `DATE` | `YYYY-MM-DD` or `"YYYY-MM-DD HH:MM"` |
| `folder` | Folder to update (default: current folder) |
| `--go` | Actually write (without it: preview only) |
| `--undo CSV` | Restore every file exactly as it was |
| `-a`, `--all` | Include hidden files and folders |
| `-h`, `--help` | Show help |

Files keep their order: each gets 1 second more than the previous, ordered by current date taken, then name. Every photo/video in the folder is changed, whatever camera it came from, so check the count in the preview.

## Install on a new Mac

```bash
brew install exiftool
chmod +x ~/Code/utils-for-mac/setdate/setdate.sh
ln -sf ~/Code/utils-for-mac/setdate/setdate.sh ~/bin/setdate
```
