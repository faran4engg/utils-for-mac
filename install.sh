#!/bin/bash
# install.sh - link every tool in this repo into ~/bin so it works as a command.
#
# Usage: ./install.sh
#
# Safe to run again any time (after a git pull, a move of the repo, a new tool).
# Fixes broken links and replaces old copied scripts (the old one is kept as <name>.bak).
# Because the commands are links to the scripts here, edits take effect immediately.

repo="$(cd "$(dirname "$0")" && pwd -P)"
bin="$HOME/bin"
mkdir -p "$bin"

for dir in "$repo"/*/; do
  name=$(basename "$dir"); script="$dir$name.sh"
  [ -f "$script" ] || continue
  chmod +x "$script"
  link="$bin/$name"
  if [ -L "$link" ]; then
    [ "$(readlink "$link")" = "$script" ] && { echo "ok       $name"; continue; }
    ln -sf "$script" "$link"; echo "relinked $name"
  elif [ -e "$link" ]; then
    mv "$link" "$link.bak"; ln -s "$script" "$link"; echo "replaced $name (old copy saved as $name.bak)"
  else
    ln -s "$script" "$link"; echo "linked   $name"
  fi
done

if ! echo ":$PATH:" | grep -q ":$bin:"; then
  grep -q 'HOME/bin' ~/.zshrc 2>/dev/null || echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
  echo; echo "Added ~/bin to PATH in ~/.zshrc. Run: source ~/.zshrc"
fi
