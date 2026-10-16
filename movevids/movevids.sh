#!/bin/bash
# movevids - collect every video in a folder (subfolders included) into one "videos" folder
#            inside it.
#
# Usage: movevids [options] [folder]
#   folder        folder to scan (default: the current folder, subfolders included)
#   --go          actually move the files (without it you only get a preview)
#   -n, --dry-run only preview: list the videos with their sizes, move nothing (the default)
#   --keep-path   keep each video's subfolder path inside videos/ instead of putting all in one
#   -a, --all     include hidden files and folders
#   --undo LOG    move everything back, using the log from an earlier --go run
#   -h, --help    show this help
#
# Videos already in <folder>/videos are left alone. Never overwrites a file: name clashes get
# a number (like "clip (2).mov"). Offers to remove folders left empty.

die() { echo "Error: $*" >&2; exit 1; }
ask() { printf "%s [y/N] " "$1"; local a; read -r a < /dev/tty; case "$a" in y|Y|yes|Yes|YES) return 0 ;; *) return 1 ;; esac; }
human() { awk -v b="$1" 'BEGIN { split("B KB MB GB TB", u, " "); i = 1; while (b >= 1000 && i < 5) { b /= 1000; i++ }
  if (i == 1) printf "%d B", b; else printf "%.1f %s", b, u[i] }'; }

go=0; dryrun=0; keeppath=0; all=0; undo=""; args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --go)        go=1 ;;
    --keep-path) keeppath=1 ;;
    -a|--all)    all=1 ;;
    --undo)      undo="$2"; shift ;;
    -n|--dry-run) dryrun=1 ;;
    -h|--help)   sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)          die "Unknown option: $1 (try -h)" ;;
    *)           args+=("$1") ;;
  esac
  shift
done
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
reports="$HOME/movevids-reports"

# --------------------------------------------------------------------------- undo
if [ -n "$undo" ]; then
  [ -f "$undo" ] || die "'$undo' not found."
  head -1 "$undo" | grep -q '^# movevids log' || die "'$undo' doesn't look like a movevids log."
  dest=$(sed -n 's/^# dest: //p' "$undo" | head -1)
  grep -v '^#' "$undo" > "$work/undo.tsv"
  echo "This moves $(wc -l < "$work/undo.tsv" | tr -d ' ') file(s) back to where they were."
  ask "Continue?" || { echo "Cancelled. Nothing was moved."; exit 0; }
  ok=0; skip=0
  while IFS=$'\t' read -r from to; do
    if [ -e "$to" ] && [ ! -e "$from" ] && mkdir -p "$(dirname "$from")" && mv -n "$to" "$from" && [ -e "$from" ]; then ok=$((ok + 1))
    else skip=$((skip + 1)); echo "  Skipped: $to" >&2; fi
  done < "$work/undo.tsv"
  [ -n "$dest" ] && [ -d "$dest" ] && find "$dest" -depth -type d -empty -delete 2>/dev/null
  echo "Moved $ok file(s) back.$([ $skip -gt 0 ] && echo " Skipped $skip (already moved or missing).")"
  exit 0
fi

# --------------------------------------------------------------------------- scan
[ ${#args[@]} -le 1 ] || die "Too many folders. Usage: movevids [options] [folder]"
[ ${#args[@]} -eq 1 ] || args=(.)
[ -d "${args[0]}" ] || die "'${args[0]}' is not a folder."
src=$(cd "${args[0]}" && pwd -P); [ "$src" = "/" ] && die "Please pick a more specific folder than /."
dest="$src/videos"

prune=( -name '*.photoslibrary' -o -path "$dest" )
[ $all -eq 0 ] && prune+=( -o -name '.*' )
if [ $all -eq 1 ]; then hidden=(); else hidden=( ! -name '.*' ); fi
find "$src" \( -type d ! -path "$src" \( "${prune[@]}" \) -prune \) -o \( -type f "${hidden[@]}" -print \) 2>/dev/null |
  awk '
    BEGIN { n = split("mov mp4 m4v avi mkv mts m2ts ts 3gp 3g2 wmv mpg mpeg mpe vob flv webm ogv dv insv lrv", a, " ")
            for (i = 1; i <= n; i++) V[a[i]] = 1 }
    { k = split($0, p, "/"); if (match(p[k], /\.[^.]+$/) && RSTART > 1 && tolower(substr(p[k], RSTART + 1)) in V) print }' \
  > "$work/vids.txt"

nvids=$(wc -l < "$work/vids.txt" | tr -d ' ')
echo "Folder:      $src (subfolders included)"
echo "Videos go to: $dest/$( [ $keeppath -eq 1 ] && echo '<same subfolder path>' )"
echo
[ "$nvids" -gt 0 ] || { echo "No videos to move."; exit 0; }

# Plan: source <TAB> target folder <TAB> size <TAB> extension
if [ "$(uname)" = "Darwin" ]; then sargs=(-f '%z'); else sargs=(-c '%s'); fi
export MV_SRC="$src" MV_DEST="$dest"
tr '\n' '\0' < "$work/vids.txt" | xargs -0 stat "${sargs[@]}" > "$work/sizes.txt"
paste "$work/vids.txt" "$work/sizes.txt" | awk -F'\t' -v keeppath="$keeppath" '
  { p = $1; rel = substr(p, length(ENVIRON["MV_SRC"]) + 2); k = split(rel, parts, "/")
    match(parts[k], /\.[^.]+$/); e = tolower(substr(parts[k], RSTART + 1))
    t = ENVIRON["MV_DEST"]; if (keeppath && k > 1) t = t "/" substr(rel, 1, length(rel) - length(parts[k]) - 1)
    print p "\t" t "\t" $2 "\t" e }' > "$work/plan.tsv"

total=$(awk -F'\t' '{ s += $3 } END { printf "%.0f", s }' "$work/plan.tsv")
echo "Videos to move: $nvids, total size $(human "$total")"
echo "By type:"
awk -F'\t' '{ c[$4]++; s[$4] += $3 } END { for (e in c) printf "%.0f\t%d\t%s\n", s[e], c[e], e }' "$work/plan.tsv" |
  sort -t$'\t' -k1,1nr |
  while IFS=$'\t' read -r b c e; do printf "  %-8s %6d files  %10s\n" "$e" "$c" "$(human "$b")"; done
echo
echo "Biggest videos (top 10):"
sort -t$'\t' -k3,3nr "$work/plan.tsv" | head -n 10 | while IFS=$'\t' read -r p t s e; do
  printf "  %10s  %s  ->  %s/\n" "$(human "$s")" "${p#"$src"/}" "${t#"$src"/}"
done
mkdir -p "$reports"; stamp=$(date +%Y-%m-%d_%H%M%S)
{ printf 'size\tbytes\tfrom\tto\n'; sort -t$'\t' -k3,3nr "$work/plan.tsv" | while IFS=$'\t' read -r p t s e; do
  printf '%s\t%s\t%s\t%s/\n' "$(human "$s")" "$s" "$p" "$t"; done; } > "$reports/$stamp-preview.tsv"
echo "  Full list with sizes: $reports/$stamp-preview.tsv"
echo
echo "Moving stays on the same disk, so it needs no extra free space."

if [ $go -eq 0 ] || [ $dryrun -eq 1 ]; then
  echo; echo "Dry run: nothing was moved. Run again with --go to move the files."; exit 0
fi
echo
ask "Move $nvids video(s) to $dest/ ?" || { echo "Cancelled. Nothing was moved."; exit 0; }

# --------------------------------------------------------------------------- move
log="$reports/$stamp-move.log"
{ echo "# movevids log, $(date '+%Y-%m-%d %H:%M')"; echo "# source: $src"; echo "# dest: $dest"; } > "$log"
moved=0; renamed=0; failed=0; mtotal=0
while IFS=$'\t' read -r p t s e; do
  name="${p##*/}"; target="$t/$name"
  mkdir -p "$t" || { failed=$((failed + 1)); continue; }
  if [ -e "$target" ]; then
    base="${name%.*}"; ext="${name##*.}"
    i=2; while [ -e "$t/$base ($i).$ext" ]; do i=$((i + 1)); done
    target="$t/$base ($i).$ext"; renamed=$((renamed + 1))
  fi
  if mv -n "$p" "$target" && [ -e "$target" ] && [ ! -e "$p" ]; then
    printf '%s\t%s\n' "$p" "$target" >> "$log"; moved=$((moved + 1)); mtotal=$((mtotal + s))
  else failed=$((failed + 1)); echo "  Could not move: $p" >&2; fi
done < "$work/plan.tsv"

echo
echo "Done. Moved $moved video(s), $(human "$mtotal"), to:"
echo "  $dest/"
[ $renamed -gt 0 ] && echo "  $renamed got a number added (like \"clip (2).mov\") because the name was taken."
[ $failed -gt 0 ]  && echo "  $failed could not be moved (see messages above)."
echo "  Log: $log"
echo "  To undo: movevids --undo \"$log\""

# Offer to remove folders in the source that are now empty (or only hold .DS_Store)
: > "$work/empty.txt"
find "$src" -mindepth 1 -depth -type d 2>/dev/null | while IFS= read -r d; do
  case "$d/" in "$dest/"*) continue ;; esac
  busy=0
  while IFS= read -r e; do
    [ -z "$e" ] || [ "$e" = ".DS_Store" ] && continue
    if [ -d "$d/$e" ] && grep -Fxq "$d/$e" "$work/empty.txt"; then continue; fi
    busy=1; break
  done <<< "$(ls -A "$d" 2>/dev/null)"
  [ $busy -eq 0 ] && printf '%s\n' "$d" >> "$work/empty.txt"
done
nempty=$(wc -l < "$work/empty.txt" | tr -d ' ')
if [ "$nempty" -gt 0 ]; then
  echo
  if ask "$nempty folder(s) are now empty. Remove them?"; then
    while IFS= read -r d; do rm -f "$d/.DS_Store"; rmdir "$d" 2>/dev/null; done < "$work/empty.txt"
    echo "Removed the empty folders."
  fi
fi
