# utils-for-mac

Small command-line tools for cleaning up and organising photos, videos and files on a Mac. Each tool has its own folder with a README.

| Tool | What it does |
|---|---|
| [bigfiles](bigfiles/) | Find the biggest files |
| [dupfinder](dupfinder/) | Find duplicate files |
| [filesummary](filesummary/) | Count files by extension and real type |
| [fixdates](fixdates/) | Fix wrong photo/video dates |
| [keepmedia](keepmedia/) | Leave only photos and videos in a folder |
| [photosort](photosort/) | Sort photos into folders |
| [setdate](setdate/) | Set a date on photos/videos |
| [vidshrink](vidshrink/) | Shrink videos |

## Install / update the commands

```bash
git clone <repo-url> ~/Code/faran4engg/utils-for-mac   # first time only
cd ~/Code/faran4engg/utils-for-mac
git pull                                               # to get updates
./install.sh
```

`install.sh` links every tool into `~/bin` and adds `~/bin` to your PATH if needed. Run it again any time: after a `git pull`, after adding a tool, or if a command says "no such file". Since the commands are links to the scripts in this folder, edits to a script take effect right away. No reinstall needed.
