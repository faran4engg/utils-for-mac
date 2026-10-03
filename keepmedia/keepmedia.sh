#!/bin/bash
# keepmedia - leave only photos and videos in a folder: every other file (zip, pdf, mp3,
#             wav, docs, ...) is moved to a separate folder, keeping its subfolder path.
#
# Usage: keepmedia [options] [folder] [dest]
#   folder        folder to clean (default: the current folder, subfolders included)
#   dest          where other files go (default: "<folder> (other files)", next to it)
#   --go          actually move the files (without it you only get a preview)
#   --by-type     group moved files by extension (pdf/, zip/, ...) instead of keeping their path
#   --check-media also check the contents of photos/videos: move ones that are empty (0 bytes)
#                 or aren't really a photo/video (broken, wrong extension). Slower.
#   -a, --all     include hidden files and folders
#   --undo LOG    move everything back, using the log from an earlier --go run
#   -h, --help    show this help
#
# Sidecar files (.aae, .xmp) are moved too. Files with an unknown or missing extension are
# checked by their contents. Never overwrites a file. Ends with a summary of what was moved
# and offers to move that folder to the Trash.

IS_MAC=0; [ "$(uname)" = "Darwin" ] && IS_MAC=1
die() { echo "Error: $*" >&2; exit 1; }
ask() { printf "%s [y/N] " "$1"; local a; read -r a < /dev/tty; case "$a" in y|Y|yes|Yes|YES) return 0 ;; *) return 1 ;; esac; }
human() { awk -v b="$1" 'BEGIN { split("B KB MB GB TB", u, " "); i = 1; while (b >= 1000 && i < 5) { b /= 1000; i++ }
  if (i == 1) printf "%d B", b; else printf "%.1f %s", b, u[i] }'; }
abspath() { local p="$1"; case "$p" in /*) ;; *) p="$PWD/$p" ;; esac; if [ -d "$p" ]; then (cd "$p" && pwd -P); else echo "${p%/}"; fi; }

go=0; bytype=0; checkmedia=0; all=0; undo=""; args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --go)       go=1 ;;
    --by-type)  bytype=1 ;;
    --check-media) checkmedia=1 ;;
    -a|--all)   all=1 ;;
    --undo)     undo="$2"; shift ;;
    -h|--help)  sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)         die "Unknown option: $1 (try -h)" ;;
    *)          args+=("$1") ;;
  esac
  shift
done
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
reports="$HOME/keepmedia-reports"

# --------------------------------------------------------------------------- undo
if [ -n "$undo" ]; then
  [ -f "$undo" ] || die "'$undo' not found."
  head -1 "$undo" | grep -q '^# keepmedia log' || die "'$undo' doesn't look like a keepmedia log."
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
[ ${#args[@]} -le 2 ] || die "Too many folders. Usage: keepmedia [options] [folder] [dest]"
[ ${#args[@]} -ge 1 ] || args=(.)
[ -d "${args[0]}" ] || die "'${args[0]}' is not a folder."
src=$(abspath "${args[0]}"); [ "$src" = "/" ] && die "Please pick a more specific folder than /."
if [ ${#args[@]} -eq 2 ]; then dest=$(abspath "${args[1]}"); else dest="$src (other files)"; fi
[ "$dest" = "$src" ] && die "The destination can't be the same folder."
case "$src/" in "$dest/"*) die "The destination can't be a folder that contains the source." ;; esac

prune=( -name '*.photoslibrary' -o -path "$dest" )
[ $all -eq 0 ] && prune+=( -o -name '.*' )
if [ $all -eq 1 ]; then hidden=(); else hidden=( ! -name '.*' ); fi
find "$src" \( -type d ! -path "$src" \( "${prune[@]}" \) -prune \) -o \( -type f "${hidden[@]}" -print \) 2>/dev/null > "$work/all.txt"
[ -s "$work/all.txt" ] || { echo "No files found in $src."; exit 0; }

# Sort by extension: media, sidecar, other, or unknown (= check contents)
awk -v unk="$work/unknown.txt" -v med="$work/media.txt" -v checkmedia="$checkmedia" '
  BEGIN {
    n = split("jpg jpeg jpe jfif heic heif png gif webp tif tiff bmp avif svg dng raw cr2 cr3 crw nef nrw arw srf sr2 orf rw2 raf srw pef x3f 3fr erf kdc mrw rwl iiq psd " \
              "mov mp4 m4v avi mkv mts m2ts ts 3gp 3g2 wmv mpg mpeg mpe vob flv webm ogv dv insv lrv", a, " ")
    for (i = 1; i <= n; i++) K[a[i]] = 1
    n = split("aae xmp zip rar 7z tar gz tgz bz2 xz dmg iso pkg pdf doc docx xls xlsx ppt pptx pages numbers key txt rtf csv md " \
              "mp3 m4a aac wav flac aif aiff ogg opus wma caf mid midi html htm json xml exe app apk ttf otf epub log ini", b, " ")
    for (i = 1; i <= n; i++) O[b[i]] = 1
  }
  { k = split($0, p, "/"); e = ""; if (match(p[k], /\.[^.]+$/) && RSTART > 1) e = tolower(substr(p[k], RSTART + 1))
    if (e in K) { if (checkmedia) print > med; next }
    if (e in O) { print; next }
    print > unk }' "$work/all.txt" > "$work/other.txt"
touch "$work/unknown.txt" "$work/media.txt" "$work/broken.tsv"
nunk=$(wc -l < "$work/unknown.txt" | tr -d ' ')
if [ "$nunk" -gt 0 ]; then
  echo "Checking the contents of $nunk file(s) with an unknown or missing extension..."
  file --mime-type -b -f "$work/unknown.txt" > "$work/unknown.mime" 2>/dev/null
  paste "$work/unknown.txt" "$work/unknown.mime" | awk -F'\t' '$2 !~ /^(image|video)\// { print $1 }' >> "$work/other.txt"
fi
nmed=$(wc -l < "$work/media.txt" | tr -d ' ')
if [ "$nmed" -gt 0 ]; then
  echo "Checking the contents of $nmed photo/video file(s)..."
  file --mime-type -b -f "$work/media.txt" > "$work/media.mime" 2>/dev/null
  # svg is often reported as xml/text, which is fine
  paste "$work/media.txt" "$work/media.mime" | awk -F'\t' '
    $2 ~ /^(image|video)\// { next }
    tolower($1) ~ /\.svg$/ && $2 ~ /svg|xml|plain|html/ { next }
    { print $1 "\t" ($2 == "inode/x-empty" ? "empty" : "not media") }' > "$work/broken.tsv"
  cut -f1 "$work/broken.tsv" >> "$work/other.txt"
fi

nall=$(wc -l < "$work/all.txt" | tr -d ' ')
nmove=$(wc -l < "$work/other.txt" | tr -d ' ')
echo "Folder:       $src (subfolders included)"
echo "Other files go to: $dest/$( [ $bytype -eq 1 ] && echo '<extension>/' || echo '<same subfolder path>' )"
echo
echo "Files scanned: $nall. Photos/videos staying: $((nall - nmove)). Other files to move: $nmove."
[ "$nmove" -gt 0 ] || { echo "Nothing to move."; exit 0; }

# Plan: source <TAB> target folder <TAB> size
if [ $IS_MAC -eq 1 ]; then sargs=(-f '%z'); else sargs=(-c '%s'); fi
export KM_SRC="$src" KM_DEST="$dest"
tr '\n' '\0' < "$work/other.txt" | xargs -0 stat "${sargs[@]}" > "$work/sizes.txt"
paste "$work/other.txt" "$work/sizes.txt" | awk -F'\t' -v bytype="$bytype" -v brk="$work/broken.tsv" '
  BEGIN { while ((getline l < brk) > 0) { split(l, x, "\t"); B[x[1]] = x[2] } }
  { p = $1; rel = substr(p, length(ENVIRON["KM_SRC"]) + 2); k = split(rel, parts, "/")
    e = ""; if (match(parts[k], /\.[^.]+$/) && RSTART > 1) e = tolower(substr(parts[k], RSTART + 1))
    if (bytype) t = ENVIRON["KM_DEST"] "/" (e == "" ? "no extension" : e)
    else { t = ENVIRON["KM_DEST"]; if (k > 1) t = t "/" substr(rel, 1, length(rel) - length(parts[k]) - 1) }
    label = (e == "" ? "(no extension)" : e); if (p in B) label = label " (" B[p] ")"
    print p "\t" t "\t" $2 "\t" label }' > "$work/plan.tsv"

total=$(awk -F'\t' '{ s += $3 } END { printf "%.0f", s }' "$work/plan.tsv")
echo
echo "By type (moving $(human "$total")):"
awk -F'\t' '{ c[$4]++; s[$4] += $3 } END { for (e in c) printf "%.0f\t%d\t%s\n", s[e], c[e], e }' "$work/plan.tsv" |
  sort -t$'\t' -k2,2nr -k1,1nr | head -n 20 |
  while IFS=$'\t' read -r b c e; do printf "  %-16s %6d files  %10s\n" "$e" "$c" "$(human "$b")"; done
echo
echo "Preview (first 10):"
head -n 10 "$work/plan.tsv" | while IFS=$'\t' read -r p t s e; do
  printf "  %s  ->  %s/\n" "${p#"$src"/}" "${t#"$(dirname "$dest")"/}"
done
mkdir -p "$reports"; stamp=$(date +%Y-%m-%d_%H%M%S)
cut -f1,2 "$work/plan.tsv" > "$reports/$stamp-preview.tsv"
echo "  Full list: $reports/$stamp-preview.tsv"

if [ $go -eq 0 ]; then
  echo; echo "This was only a preview. Nothing was moved. Run again with --go to move the files."; exit 0
fi
echo
ask "Move $nmove file(s) to $dest/ ?" || { echo "Cancelled. Nothing was moved."; exit 0; }

# --------------------------------------------------------------------------- move
log="$reports/$stamp-move.log"
{ echo "# keepmedia log, $(date '+%Y-%m-%d %H:%M')"; echo "# source: $src"; echo "# dest: $dest"; } > "$log"
moved=0; renamed=0; failed=0; : > "$work/moved.tsv"
while IFS=$'\t' read -r p t s e; do
  name="${p##*/}"; target="$t/$name"
  mkdir -p "$t" || { failed=$((failed + 1)); continue; }
  if [ -e "$target" ]; then
    base="${name%.*}"; ext="${name##*.}"; [ "$base" = "$name" ] && ext=""
    i=2; while [ -e "$t/$base ($i)${ext:+.$ext}" ]; do i=$((i + 1)); done
    target="$t/$base ($i)${ext:+.$ext}"; renamed=$((renamed + 1))
  fi
  if mv -n "$p" "$target" && [ -e "$target" ] && [ ! -e "$p" ]; then
    printf '%s\t%s\n' "$p" "$target" >> "$log"; moved=$((moved + 1))
    printf '%s\t%s\n' "$e" "$s" >> "$work/moved.tsv"
  else failed=$((failed + 1)); echo "  Could not move: $p" >&2; fi
done < "$work/plan.tsv"

mtotal=$(awk -F'\t' '{ s += $2 } END { printf "%.0f", s }' "$work/moved.tsv")
echo
echo "Done. Moved $moved file(s), $(human "$mtotal"), to:"
echo "  $dest/"
[ $renamed -gt 0 ] && echo "  $renamed got a number added (like \"file (2).pdf\") because the name was taken."
[ $failed -gt 0 ]  && echo "  $failed could not be moved (see messages above)."
echo
echo "Summary of moved files:"
awk -F'\t' '{ c[$1]++; s[$1] += $2 } END { for (e in c) printf "%.0f\t%d\t%s\n", s[e], c[e], e }' "$work/moved.tsv" |
  sort -t$'\t' -k1,1nr |
  while IFS=$'\t' read -r b c e; do
    case "$e" in aae|xmp) note="  (photo edit/sidecar info)" ;; *) note="" ;; esac
    printf "  %-16s %6d files  %10s%s\n" "$e" "$c" "$(human "$b")" "$note"
  done
echo "  Log: $log"
echo "  To undo: keepmedia --undo \"$log\""

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
  if ask "$nempty folder(s) in the source are now empty. Remove them?"; then
    while IFS= read -r d; do rm -f "$d/.DS_Store"; rmdir "$d" 2>/dev/null; done < "$work/empty.txt"
    echo "Removed the empty folders."
  fi
fi

# Offer to move the whole "other files" folder to the Trash
if [ $moved -gt 0 ] && [ -d "$dest" ]; then
  echo
  echo "If you don't need any of these files, the whole folder can go to the Trash."
  echo "Check it first if you're unsure: open \"$dest\""
  if ask "Move \"${dest##*/}\" to the Trash now?"; then
    if command -v trash >/dev/null 2>&1; then trash "$dest" && gone=1
    elif [ $IS_MAC -eq 1 ]; then
      osascript - "$dest" >/dev/null 2>&1 << 'OSA' && gone=1
on run argv
  tell application "Finder" to delete (POSIX file (item 1 of argv as text))
end run
OSA
    fi
    if [ "${gone:-0}" -eq 1 ]; then echo "Moved to the Trash. Empty the Trash to free $(human "$mtotal")."
    else echo "Could not move it to the Trash. You can drag it there in Finder."; fi
  else
    echo "Kept. You can delete it any time."
  fi
fi
