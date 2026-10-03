# bigfiles

Lists the largest files (or heaviest subfolders) in a folder and all its subfolders, with a size breakdown by type. Read-only: never moves or deletes anything. Sizes match Finder (1 GB = 1000 MB).

## Usage

```
bigfiles [options] [folder]
```

| Option | What it does |
|---|---|
| `-n NUM` | How many to list (default 20) |
| `-m`, `--min SIZE` | Only files at least this big, e.g. `500K`, `100M`, `1.5G` |
| `-t`, `--type TYPE` | Only one type: `image`, `video`, `audio`, `pdf`, `archive`, `document`, `other` |
| `-d`, `--dirs` | Show heaviest subfolders instead of files |
| `-a`, `--all` | Include hidden files/folders and `node_modules` |
| `-h`, `--help` | Show help |

Apple Photos libraries are always skipped (manage them in the Photos app).

```
bigfiles ~/Pictures                # top 20 largest files
bigfiles -d ~/Pictures             # which subfolders are heaviest
bigfiles -t video -m 500M -n 50 ~  # videos over 500 MB in your home folder
```

## Install on a new Mac

```bash
chmod +x ~/Code/utils-for-mac/bigfiles/bigfiles.sh
ln -sf ~/Code/utils-for-mac/bigfiles/bigfiles.sh ~/bin/bigfiles
```

(Assumes the repo is cloned and `~/bin` is on your PATH, see the filesummary README.)
