# vidshrink

Makes videos smaller by re-encoding them to HEVC (H.265), keeping date taken, location, camera info and Finder dates. Scans the folder (default: current folder) and all subfolders. Shows a preview first.

Each new file is checked (plays, same length, same date taken, at least 10% smaller) before the original is touched. Originals go to the Trash, not deleted.

Requires: `brew install ffmpeg exiftool`

## Usage

```bash
vidshrink                  # preview
vidshrink --keep --go      # keep originals, save "name (shrunk).mov" next to them
vidshrink --go             # replace originals (they go to the Trash)
vidshrink --max-height 1080 --go   # also turn 4K into 1080p
```

| Option | What it does |
|---|---|
| `--go` | Actually shrink (without it: preview only) |
| `--keep` | Keep originals; new files are saved as `name (shrunk)` |
| `--max-height N` | Also downsize, e.g. `1080` (works on HEVC videos too) |
| `--crf N` | Quality: lower = better and bigger (default 24, range 20-28) |
| `--fast` | Mac hardware encoder: much faster, bigger files |
| `--min SIZE` | Skip videos smaller than SIZE (default `50M`) |
| `--force` | Also re-encode videos that are already HEVC |
| `-a`, `--all` | Include hidden files and folders |
| `-h`, `--help` | Show help |

Skipped by default: videos under 50 MB (incl. Live Photo clips) and videos already in HEVC. Portrait videos stay upright, 10-bit/HDR stays 10-bit. `.avi`, `.mkv`, `.mts` etc. become `.mp4`. Logs go to `~/vidshrink-reports/`. Empty the Trash afterwards to actually free the space.

## Install on a new Mac

```bash
brew install ffmpeg exiftool
chmod +x ~/Code/utils-for-mac/vidshrink/vidshrink.sh
ln -sf ~/Code/utils-for-mac/vidshrink/vidshrink.sh ~/bin/vidshrink
```
