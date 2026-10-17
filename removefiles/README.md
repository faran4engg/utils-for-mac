# removefiles

Removes every file with a given extension from a folder and its subfolders. Files go to the Trash by default, so they can be put back. Shows a dry run first.

## Usage

```bash
removefiles .json                  # dry run: list .json files, total size, biggest 10
removefiles .json --go             # move them to the Trash (asks first)
removefiles .json .xml --go        # more than one extension
removefiles .json --in ~/Downloads --go
removefiles .json --permanent --go # delete right away, no Trash
```

| Option | What it does |
|---|---|
| `EXT` | Extension to remove: `.json`, `json` or `*.json`. Case doesn't matter. More than one is fine |
| `--in FOLDER` | Folder to clean (default: current folder) |
| `--go` | Actually remove (without it: dry run only) |
| `-n`, `--dry-run` | Only preview, even with `--go` |
| `--permanent` | Delete right away instead of moving to the Trash. Can't be undone |
| `-a`, `--all` | Include hidden files and folders |
| `-h`, `--help` | Show help |

Hidden folders (like `.git`) and `.photoslibrary` folders are skipped unless you pass `-a`. To undo, open the Trash in Finder, select the files and choose Put Back. Offers to remove folders left empty. A list of what was removed goes to `~/removefiles-reports/`.

## Install / update

```bash
~/Code/faran4engg/utils-for-mac/install.sh
```

See the [main README](../README.md).
