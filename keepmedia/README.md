# keepmedia

Leaves only photos and videos in a folder (and its subfolders). Every other file (zip, pdf, mp3, wav, docs, ...) is moved to a separate folder. Shows a preview first and can be undone.

## Usage

```bash
keepmedia                  # preview
keepmedia --go             # move other files to "<folder> (other files)"
keepmedia --by-type --go   # group them as pdf/, zip/, mp3/ ... instead
keepmedia --check-media --go   # also move empty / broken photos and videos
keepmedia --undo ~/keepmedia-reports/<date>-move.log
```

| Option | What it does |
|---|---|
| `folder` | Folder to clean (default: current folder) |
| `dest` | Where other files go (default: `<folder> (other files)` next to it) |
| `--go` | Actually move (without it: preview only) |
| `--by-type` | Group by extension instead of keeping the subfolder path |
| `--check-media` | Also open photos/videos and move ones that are empty (0 bytes) or not really a photo/video. Slower |
| `-a`, `--all` | Include hidden files and folders |
| `--undo LOG` | Move everything back |
| `-h`, `--help` | Show help |

`.aae` and `.xmp` sidecars are moved too. Ends with a summary by type and offers to move the whole folder to the Trash. Files with an unknown or missing extension are checked by content. Nothing is overwritten (name clashes get a number). Offers to remove folders left empty. Logs go to `~/keepmedia-reports/`.

## Install / update

```bash
~/Code/faran4engg/utils-for-mac/install.sh
```

See the [main README](../README.md).
