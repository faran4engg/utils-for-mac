# filesummary

Counts the files in a folder by extension and by actual type (image, video, audio, PDF, text/code, etc.). The type is detected from file contents, not the name.

## Usage

```
filesummary [options] [folder]
```

| Option | What it does |
|---|---|
| `-r`, `--recursive` | Include subfolders (skips hidden folders and `node_modules`) |
| `-a`, `--all` | Also include hidden files/folders and `node_modules` |
| `-h`, `--help` | Show help |

With no folder given, it scans the current folder. Options can go before or after the folder.

```
filesummary                   # current folder only
filesummary ~/Pictures        # a specific folder
filesummary -r ~/Code/my-app  # folder + all subfolders
```

## Install on a new Mac

```bash
git clone <repo-url> ~/Code/utils-for-mac
chmod +x ~/Code/utils-for-mac/filesummary/filesummary.sh
mkdir -p ~/bin
ln -sf ~/Code/utils-for-mac/filesummary/filesummary.sh ~/bin/filesummary
grep -q 'HOME/bin' ~/.zshrc || echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

The command is a symlink to the repo, so `git pull` updates it automatically.
