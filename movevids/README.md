# movevids

Collects every video in a folder (and its subfolders) into one `videos` folder inside it. Shows a preview first and can be undone.

## Usage

```bash
movevids                     # dry run: list videos, total size, size per type, biggest 10
movevids --dry-run           # same, explicitly
movevids --go                # move all videos into ./videos
movevids --keep-path --go    # keep their subfolder path inside videos/
movevids --undo ~/movevids-reports/<date>-move.log
```

| Option | What it does |
|---|---|
| `folder` | Folder to scan (default: current folder) |
| `--go` | Actually move (without it: preview only) |
| `-n`, `--dry-run` | Only preview, even with `--go`. Writes the full list with sizes to `~/movevids-reports/<date>-preview.tsv` |
| `--keep-path` | Keep each video's subfolder path inside `videos/` instead of putting all in one folder |
| `-a`, `--all` | Include hidden files and folders |
| `--undo LOG` | Move everything back |
| `-h`, `--help` | Show help |

Video types: mov, mp4, m4v, avi, mkv, mts, m2ts, ts, 3gp, 3g2, wmv, mpg, mpeg, mpe, vob, flv, webm, ogv, dv, insv, lrv. Videos already in `videos/` are left alone. Nothing is overwritten (name clashes get a number). Offers to remove folders left empty. Logs go to `~/movevids-reports/`.

## Install / update

```bash
~/Code/faran4engg/utils-for-mac/install.sh
```

See the [main README](../README.md).
