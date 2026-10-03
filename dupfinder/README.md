# dupfinder

Finds exact duplicate files (identical contents, any name) across one or more folders and all their subfolders. You review them visually, then the extras are moved to the Trash. Nothing is ever deleted permanently.

## Usage

```bash
dupfinder ~/Pictures ~/Downloads          # 1. scan, opens a review page in Safari
                                          # 2. pick Keep / Remove, click "Download decisions"
dupfinder --apply ~/Downloads/dupfinder-decisions.txt   # 3. re-checks, asks, moves to Trash
```

| Option | What it does |
|---|---|
| `-p`, `--prefer DIR` | Suggest keeping the copy inside DIR |
| `-m`, `--min SIZE` | Ignore files smaller than SIZE, e.g. `100K`, `1M` |
| `-o`, `--out DIR` | Where to save reports (default `~/dupfinder-reports`) |
| `-a`, `--all` | Include hidden files/folders and `node_modules` |
| `--no-open` | Don't open the review page automatically |
| `--apply FILE` | Move files marked REMOVE to the Trash |
| `-y` | With `--apply`, don't ask for confirmation |
| `-h`, `--help` | Show help |

Each scan saves `review.html` and `report.txt` in `~/dupfinder-reports/<date>/`. You can also edit `report.txt` by hand and apply it instead. Open the review page in Safari for HEIC and video previews. Undo with Put Back in the Trash.

## Install on a new Mac

```bash
chmod +x ~/Code/utils-for-mac/dupfinder/dupfinder.sh
ln -sf ~/Code/utils-for-mac/dupfinder/dupfinder.sh ~/bin/dupfinder
```
