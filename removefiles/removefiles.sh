#!/bin/bash
# removefiles - remove every file with the given extension(s) from a folder and its subfolders.
#               Files go to the Trash, so they can be put back.
#
# Usage: removefiles [options] EXT [EXT...]
#   EXT           extension to remove, like .json, json or *.json (more than one is fine)
#   --in FOLDER   folder to clean (default: the current folder, subfolders included)
#   --go          actually remove the files (without it you only get a preview)
#   -n, --dry-run only preview: list the files with their sizes, remove nothing (the default)
#   --permanent   delete right away instead of moving to the Trash (can't be undone)
#   -a, --all     include hidden files and folders
#   -h, --help    show this help
#
# Example: removefiles .json          preview which .json files would go
#          removefiles .json --go     move them to the Trash
#
# Asks before removing anything. Writes a list of the removed files to ~/removefiles-reports/.
# Offers to remove folders left empty.

IS_MAC=0; [ "$(uname)" = "Darwin" ] && IS_MAC=1
die() { echo "Error: $*" >&2; exit 1; }
ask() { printf "%s [y/N] " "$1"; local a; read -r a < /dev/tty; case "$a" in y|Y|yes|Yes|YES) return 0 ;; *) return 1 ;; esac; }
human() { awk -v b="$1" 'BEGIN { split("B KB MB GB TB", u, " "); i = 1; while (b >= 1000 && i < 5) { b /= 1000; i++ }
  if (i == 1) printf "%d B", b; else printf "%.1f %s", b, u[i] }'; }

go=0; dryrun=0; permanent=0; all=0; folder="."; exts=()
while [ $# -gt 0 ]; do
  case "$1" in
    --go)         go=1 ;;
    -n|--dry-run) dryrun=1 ;;
    --permanent)  permanent=1 ;;
    -a|--all)     all=1 ;;
    --in)         [ -n "$2" ] || die "--in needs a folder."; folder="$2"; shift ;;
    -h|--help)    sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --*|-?)       die "Unknown option: $1 (try -h)" ;;
    *)            e="${1#\*}"; e="${e#.}"; e=$(printf '%s' "$e" | tr '[:upper:]' '[:lower:]')
                  case "$e" in ""|*/*|*" "*) die "'$1' is not an extension. Use something like .json" ;; esac
                  exts+=("$e") ;;
  esac
  shift
done
[ ${#exts[@]} -gt 0 ] || die "Which files? Give an extension, like: removefiles .json (try -h)"
[ -d "$folder" ] || die "'$folder' is not a folder."
src=$(cd "$folder" && pwd -P); [ "$src" = "/" ] && die "Please pick a more specific folder than /."
[ "$src" = "$HOME" ] && ! ask "This cleans your whole home folder. Are you sure?" && { echo "Cancelled."; exit 0; }
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
reports="$HOME/removefiles-reports"

# --------------------------------------------------------------------------- scan
prune=( -name '*.photoslibrary' )
[ $all -eq 0 ] && prune+=( -o -name '.*' )
if [ $all -eq 1 ]; then hidden=(); else hidden=( ! -name '.*' ); fi
find "$src" \( -type d ! -path "$src" \( "${prune[@]}" \) -prune \) -o \( -type f "${hidden[@]}" -print \) 2>/dev/null |
  awk -v list="${exts[*]}" '
    BEGIN { n = split(list, a, " "); for (i = 1; i <= n; i++) X[a[i]] = 1 }
    { k = split($0, p, "/"); if (match(p[k], /\.[^.]+$/) && RSTART > 1 && tolower(substr(p[k], RSTART + 1)) in X) print }' \
  > "$work/files.txt"

nfiles=$(wc -l < "$work/files.txt" | tr -d ' ')
echo "Folder:   $src (subfolders included)"
echo "Removing: $(printf '.%s ' "${exts[@]}")files$( [ $permanent -eq 1 ] && echo ' (permanently!)' || echo ' (to the Trash)')"
echo
[ "$nfiles" -gt 0 ] || { echo "No matching files found."; exit 0; }

if [ $IS_MAC -eq 1 ]; then sargs=(-f '%z'); else sargs=(-c '%s'); fi
tr '\n' '\0' < "$work/files.txt" | xargs -0 stat "${sargs[@]}" > "$work/sizes.txt"
paste "$work/files.txt" "$work/sizes.txt" | awk -F'\t' '
  { k = split($1, p, "/"); match(p[k], /\.[^.]+$/); print $1 "\t" $2 "\t" tolower(substr(p[k], RSTART + 1)) }' > "$work/plan.tsv"

total=$(awk -F'\t' '{ s += $2 } END { printf "%.0f", s }' "$work/plan.tsv")
echo "Files to remove: $nfiles, total size $(human "$total")"
if [ ${#exts[@]} -gt 1 ]; then
  echo "By type:"
  awk -F'\t' '{ c[$3]++; s[$3] += $2 } END { for (e in c) printf "%.0f\t%d\t%s\n", s[e], c[e], e }' "$work/plan.tsv" |
    sort -t$'\t' -k1,1nr |
    while IFS=$'\t' read -r b c e; do printf "  %-8s %6d files  %10s\n" "$e" "$c" "$(human "$b")"; done
fi
echo
echo "Biggest files (top 10):"
sort -t$'\t' -k2,2nr "$work/plan.tsv" | head -n 10 | while IFS=$'\t' read -r p s e; do
  printf "  %10s  %s\n" "$(human "$s")" "${p#"$src"/}"
done
mkdir -p "$reports"; stamp=$(date +%Y-%m-%d_%H%M%S)
{ printf 'size\tbytes\tfile\n'; sort -t$'\t' -k2,2nr "$work/plan.tsv" | while IFS=$'\t' read -r p s e; do
  printf '%s\t%s\t%s\n' "$(human "$s")" "$s" "$p"; done; } > "$reports/$stamp-preview.tsv"
echo "  Full list with sizes: $reports/$stamp-preview.tsv"

if [ $go -eq 0 ] || [ $dryrun -eq 1 ]; then
  echo; echo "Dry run: nothing was removed. Run again with --go to remove the files."; exit 0
fi
echo
if [ $permanent -eq 1 ]; then
  ask "PERMANENTLY delete $nfiles file(s)? This can't be undone." || { echo "Cancelled. Nothing was removed."; exit 0; }
else
  ask "Move $nfiles file(s) to the Trash?" || { echo "Cancelled. Nothing was removed."; exit 0; }
fi

# --------------------------------------------------------------------------- remove
# Removes the files listed in $1 (one per line), in batches.
trash_files() {
  if [ $permanent -eq 1 ]; then tr '\n' '\0' < "$1" | xargs -0 rm -f 2>/dev/null
  elif command -v trash >/dev/null 2>&1; then tr '\n' '\0' < "$1" | xargs -0 -n 200 trash 2>/dev/null
  elif [ $IS_MAC -eq 1 ]; then
    tr '\n' '\0' < "$1" | xargs -0 -n 200 osascript -e '
      on run argv
        set fs to {}
        repeat with f in argv
          set end of fs to (POSIX file (f as text))
        end repeat
        tell application "Finder" to delete fs
      end run' >/dev/null 2>&1
  else die "No way to move files to the Trash here. Use --permanent to delete them instead."; fi
}
log="$reports/$stamp-removed.tsv"
cut -f1 "$work/plan.tsv" > "$work/todo.txt"
trash_files "$work/todo.txt"

removed=0; failed=0; rtotal=0
{ printf 'size\tbytes\tfile\n'; } > "$log"
while IFS=$'\t' read -r p s e; do
  if [ -e "$p" ]; then failed=$((failed + 1)); echo "  Could not remove: $p" >&2
  else removed=$((removed + 1)); rtotal=$((rtotal + s)); printf '%s\t%s\t%s\n' "$(human "$s")" "$s" "$p" >> "$log"; fi
done < "$work/plan.tsv"

echo
if [ $permanent -eq 1 ]; then echo "Done. Deleted $removed file(s), freed $(human "$rtotal")."
else echo "Done. Moved $removed file(s), $(human "$rtotal"), to the Trash."
  echo "  To undo: open the Trash in Finder, select them, right-click > Put Back."
  echo "  Empty the Trash to free the space."
fi
[ $failed -gt 0 ] && echo "  $failed could not be removed (see messages above)."
echo "  List of removed files: $log"

# Offer to remove folders that are now empty (or only hold .DS_Store)
[ $removed -gt 0 ] || exit 0
: > "$work/empty.txt"
find "$src" -mindepth 1 -depth -type d 2>/dev/null | while IFS= read -r d; do
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
