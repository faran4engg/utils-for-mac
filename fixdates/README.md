# fixdates

Fixes photo dates in two ways. Scans the folder (default: current folder) and all subfolders. Shows a preview first and can be undone.

Requires: `brew install exiftool`

## Canon EOS M50 handling

The Canon EOS M50's clock was not set, so its photos have a wrong date taken (e.g. 2000-01-01). For this camera, the file's **Created date** is treated as the real date. It is the default `--model`, and you can pick another camera with `-m`.

## Usage

```bash
fixdates                              # preview: M50 date taken -> Created date
fixdates --go                         # write it
fixdates --sync-finder-dates          # preview: Finder dates -> date taken
fixdates --sync-finder-dates --go     # write it
fixdates --undo ~/photosort-reports/<date>-...-undo.csv
```

| Option | What it does |
|---|---|
| *(default mode)* | Writes the Created date into the date taken of files from the `--model` camera. Finder dates are kept. |
| `--sync-finder-dates` | Sets Finder's Created and Modified dates to each file's date taken. Skips `--model` files (their date taken is wrong) and files with no date taken. |
| `-m`, `--model NAME` | Camera with the wrong clock (default `Canon EOS M50`) |
| `--go` | Actually write (without it: preview only) |
| `--undo CSV` | Put the old dates back |
| `-a`, `--all` | Include hidden files and folders |
| `-h`, `--help` | Show help |

Run the default mode **before** `--sync-finder-dates`. Previews and undo files go to `~/photosort-reports/`.

## Install on a new Mac

```bash
brew install exiftool
chmod +x ~/Code/utils-for-mac/fixdates/fixdates.sh
ln -sf ~/Code/utils-for-mac/fixdates/fixdates.sh ~/bin/fixdates
```
