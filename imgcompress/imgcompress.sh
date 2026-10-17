#!/bin/bash
# imgcompress - make JPEG and PNG images smaller, keeping their date taken, location and
#               other metadata.
#
# Usage: imgcompress [options] [folder]
#   folder        folder to scan (default: the current folder, subfolders included)
#   --go          actually compress (without it you only get a preview with an estimate)
#   -n, --dry-run only preview, even with --go (the default)
#   --smaller     re-save JPEGs at a high quality instead of only repacking them: much smaller
#                 files (often 30-60%) that look the same, but pixels change slightly
#   --quality N   JPEG quality for --smaller (default 85, sensible range 80-92)
#   --keep        keep the original and save the new file next to it as "name (compressed).jpg"
#                 (default: the original goes to the Trash once the new file checks out)
#   --min SIZE    skip images smaller than this (default 100K)
#   -a, --all     include hidden files and folders
#   -h, --help    show this help
#
# Default mode is lossless: the picture stays pixel-for-pixel identical.
#   JPEG: repacked with jpegtran (typically 5-15% smaller)
#   PNG:  repacked with oxipng (typically 10-40% smaller; needs: brew install oxipng)
# HEIC, WebP and other formats are left alone (already efficiently compressed).
# Each new file is checked (opens, same size in pixels, same date taken, really smaller)
# before the original is touched. Needs exiftool and jpeg tools (brew install jpeg-turbo exiftool).

IS_MAC=0; [ "$(uname)" = "Darwin" ] && IS_MAC=1
die() { echo "Error: $*" >&2; exit 1; }
ask() { printf "%s [y/N] " "$1"; local a; read -r a < /dev/tty; case "$a" in y|Y|yes|Yes|YES) return 0 ;; *) return 1 ;; esac; }
human() { awk -v b="$1" 'BEGIN { split("B KB MB GB TB", u, " "); i = 1; while (b >= 1000 && i < 5) { b /= 1000; i++ }
  if (i == 1) printf "%d B", b; else printf "%.1f %s", b, u[i] }'; }
fsize() { if [ $IS_MAC -eq 1 ]; then stat -f %z "$1"; else stat -c %s "$1"; fi; }
tobytes() { awk -v s="$1" 'BEGIN { n = s + 0; u = toupper(substr(s, length(s)));
  if (u == "K") n *= 1000; else if (u == "M") n *= 1000000; else if (u == "G") n *= 1000000000; printf "%.0f", n }'; }

go=0; dryrun=0; smaller=0; quality=85; keep=0; min="100K"; all=0; dir=""
while [ $# -gt 0 ]; do
  case "$1" in
    --go)         go=1 ;;
    -n|--dry-run) dryrun=1 ;;
    --smaller)    smaller=1 ;;
    --quality)    quality="$2"; shift ;;
    --keep)       keep=1 ;;
    --min)        min="$2"; shift ;;
    -a|--all)     all=1 ;;
    -h|--help)    sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)           die "Unknown option: $1 (try -h)" ;;
    *)            [ -z "$dir" ] || die "Only one folder, please."; dir="$1" ;;
  esac
  shift
done
case "$quality" in ''|*[!0-9]*) die "--quality needs a number, like 85." ;; esac
[ "$quality" -ge 50 ] && [ "$quality" -le 100 ] || die "--quality should be between 50 and 100."
minb=$(tobytes "$min")
[ -n "$dir" ] || dir=.
[ -d "$dir" ] || die "'$dir' is not a folder."
src=$(cd "$dir" && pwd -P); [ "$src" = "/" ] && die "Please pick a more specific folder than /."

for t in jpegtran djpeg cjpeg exiftool; do
  command -v $t >/dev/null 2>&1 || die "$t is missing. Install with: brew install jpeg-turbo exiftool"
done
# mozjpeg makes noticeably smaller JPEGs at the same quality; use it when installed
CJPEG=cjpeg; [ -x /opt/homebrew/opt/mozjpeg/bin/cjpeg ] && CJPEG=/opt/homebrew/opt/mozjpeg/bin/cjpeg
havepng=0; command -v oxipng >/dev/null 2>&1 && havepng=1

work=$(mktemp -d); tmpfile=""
trap 'rm -rf "$work"; [ -n "$tmpfile" ] && rm -f "$tmpfile"' EXIT
trap 'echo; echo "Stopped. The image being worked on was left untouched."; exit 130' INT
reports="$HOME/imgcompress-reports"

# --------------------------------------------------------------------------- scan
prune=( -name '*.photoslibrary' )
[ $all -eq 0 ] && prune+=( -o -name '.*' )
if [ $all -eq 1 ]; then hidden=(); else hidden=( ! -name '.*' ); fi
find "$src" \( -type d ! -path "$src" \( "${prune[@]}" \) -prune \) -o \( -type f "${hidden[@]}" -print \) 2>/dev/null |
  awk '{ k = split($0, p, "/"); e = ""; if (match(p[k], /\.[^.]+$/) && RSTART > 1) e = tolower(substr(p[k], RSTART + 1))
         if (e ~ /^(jpg|jpeg|jpe|jfif)$/) print $0 "\tjpeg"; else if (e == "png") print $0 "\tpng"
         else if (e ~ /^(heic|heif|webp|avif)$/) print $0 "\tskip" }' > "$work/found.tsv"

if [ $IS_MAC -eq 1 ]; then sargs=(-f '%z'); else sargs=(-c '%s'); fi
cut -f1 "$work/found.tsv" | tr '\n' '\0' | xargs -0 stat "${sargs[@]}" > "$work/sizes.txt"
paste "$work/found.tsv" "$work/sizes.txt" | awk -F'\t' -v minb="$minb" -v havepng="$havepng" \
  -v sk="$work/skipped.txt" '
  $2 == "skip" { print "efficient" > sk; next }
  $3 < minb    { print "small" > sk; next }
  $2 == "png" && !havepng { print "nopng" > sk; next }
  { print $1 "\t" $3 "\t" $2 }' > "$work/plan.tsv"
touch "$work/skipped.txt"

nplan=$(wc -l < "$work/plan.tsv" | tr -d ' ')
nefficient=$(grep -c efficient "$work/skipped.txt"); nsmall=$(grep -c small "$work/skipped.txt"); nnopng=$(grep -c nopng "$work/skipped.txt")
echo "Folder: $src (subfolders included)"
if [ $smaller -eq 1 ]; then echo "Mode:   smaller (JPEGs re-saved at quality $quality; PNGs repacked losslessly)"
else echo "Mode:   lossless (pictures stay pixel-for-pixel identical)"; fi
echo
[ "$nefficient" -gt 0 ] && echo "Skipping $nefficient HEIC/WebP/AVIF image(s): already efficiently compressed."
[ "$nsmall" -gt 0 ]     && echo "Skipping $nsmall image(s) smaller than $min."
[ "$nnopng" -gt 0 ]     && echo "Skipping $nnopng PNG(s): oxipng isn't installed (brew install oxipng)."
[ "$nplan" -gt 0 ] || { echo "No images to compress."; exit 0; }

total=$(awk -F'\t' '{ s += $2 } END { printf "%.0f", s }' "$work/plan.tsv")
echo "Images to compress: $nplan, total size $(human "$total")"
echo "By type:"
awk -F'\t' '{ c[$3]++; s[$3] += $2 } END { for (e in c) printf "%.0f\t%d\t%s\n", s[e], c[e], e }' "$work/plan.tsv" |
  sort -t$'\t' -k1,1nr |
  while IFS=$'\t' read -r b c e; do printf "  %-6s %6d files  %10s\n" "$e" "$c" "$(human "$b")"; done

# --------------------------------------------------------------------------- compress one image
# compress IN OUT KIND: writes the compressed copy to OUT. Returns 1 on failure.
compress() {
  local in="$1" out="$2" kind="$3"
  if [ "$kind" = "png" ]; then
    oxipng -q -o 4 --out "$out" "$in" 2>/dev/null || return 1
    exiftool -q -q -m -overwrite_original -TagsFromFile "$in" -FileModifyDate -FileCreateDate "$out" >/dev/null 2>&1
  elif [ $smaller -eq 1 ]; then
    djpeg "$in" 2>/dev/null | "$CJPEG" -quality "$quality" -optimize -progressive -outfile "$out" 2>/dev/null || return 1
    [ -s "$out" ] || return 1
    # Re-saving drops the metadata: copy it all back, including the colour profile
    # (iPhone photos use Display P3). Orientation is copied too, as djpeg doesn't rotate.
    exiftool -q -q -m -overwrite_original -TagsFromFile "$in" -All:All -ICC_Profile \
      -FileModifyDate -FileCreateDate "$out" >/dev/null 2>&1
  else
    jpegtran -copy all -optimize -progressive -outfile "$out" "$in" 2>/dev/null || return 1
    exiftool -q -q -m -overwrite_original -TagsFromFile "$in" -FileModifyDate -FileCreateDate "$out" >/dev/null 2>&1
  fi
  [ -s "$out" ]
}

# check IN OUT: prints a problem, or nothing if OUT is fine.
check() {
  local in="$1" out="$2"
  if [ $IS_MAC -eq 1 ]; then
    local a b; a=$(sips -g pixelWidth -g pixelHeight "$in" 2>/dev/null | awk '/pixel/ { printf "%s ", $2 }')
    b=$(sips -g pixelWidth -g pixelHeight "$out" 2>/dev/null | awk '/pixel/ { printf "%s ", $2 }')
    [ -n "${b// /}" ] || { echo "the new file doesn't open"; return; }
    [ "$a" = "$b" ] || { echo "the picture size changed ($a vs $b)"; return; }
  fi
  local od nd
  od=$(exiftool -q -q -m -s3 -DateTimeOriginal "$in" 2>/dev/null); nd=$(exiftool -q -q -m -s3 -DateTimeOriginal "$out" 2>/dev/null)
  [ "$od" = "$nd" ] || echo "the date taken didn't carry over ($od vs ${nd:-none})"
}

# Worth keeping? Lossless: at least 2% smaller. Re-saved: at least 10% smaller.
worth() { if [ "$3" = "jpeg" ] && [ $smaller -eq 1 ]; then [ "$2" -lt $(($1 * 9 / 10)) ]; else [ "$2" -lt $(($1 * 98 / 100)) ]; fi; }

# --------------------------------------------------------------------------- estimate
# Compress a few sample images into a temp folder to estimate the saving
nsample=8; [ "$nplan" -lt $nsample ] && nsample=$nplan
awk -v n="$nplan" -v k="$nsample" 'BEGIN { srand(1) } { if (int((NR - 1) * k / n) != int(NR * k / n)) print }' \
  "$work/plan.tsv" > "$work/sample.tsv"
echo
echo "Testing on $nsample sample image(s) to estimate the saving..."
sb=0; sa=0; i=0
while IFS=$'\t' read -r f size kind; do
  i=$((i + 1)); out="$work/sample$i.$kind"
  if compress "$f" "$out" "$kind" && [ -z "$(check "$f" "$out")" ]; then
    ns=$(fsize "$out"); worth "$size" "$ns" "$kind" || ns=$size
  else ns=$size; fi
  sb=$((sb + size)); sa=$((sa + ns)); rm -f "$out"
done < "$work/sample.tsv"
if [ $sb -gt 0 ]; then
  pct=$(( (sb - sa) * 100 / sb ))
  est=$(( total * pct / 100 ))
  echo "  Samples: $(human "$sb") -> $(human "$sa") (-$pct%)"
  echo "  Estimated saving for all $nplan image(s): about $(human "$est") of $(human "$total")"
fi

echo
echo "Biggest images (top 10):"
sort -t$'\t' -k2,2nr "$work/plan.tsv" | head -n 10 | while IFS=$'\t' read -r f s k; do
  printf "  %10s  %s\n" "$(human "$s")" "${f#"$src"/}"
done
mkdir -p "$reports"; stamp=$(date +%Y-%m-%d_%H%M%S)
{ printf 'size\tbytes\tfile\n'; sort -t$'\t' -k2,2nr "$work/plan.tsv" | while IFS=$'\t' read -r f s k; do
  printf '%s\t%s\t%s\n' "$(human "$s")" "$s" "$f"; done; } > "$reports/$stamp-preview.tsv"
echo "  Full list with sizes: $reports/$stamp-preview.tsv"

if [ $go -eq 0 ] || [ $dryrun -eq 1 ]; then
  echo; echo "Dry run: nothing was changed. Run again with --go to compress the images."; exit 0
fi
echo
ask "Compress $nplan image(s) now?" || { echo "Cancelled. Nothing was changed."; exit 0; }

# --------------------------------------------------------------------------- compress all
move_to_trash() {
  if command -v trash >/dev/null 2>&1; then trash "$1"
  elif [ $IS_MAC -eq 1 ]; then
    osascript - "$1" >/dev/null 2>&1 << 'OSA'
on run argv
  tell application "Finder" to delete (POSIX file (item 1 of argv as text))
end run
OSA
  else return 1; fi
}

log="$reports/$stamp.log"
echo -e "# imgcompress log $(date '+%Y-%m-%d %H:%M')\n# original\tnew\told size\tnew size" > "$log"
n=0; ok=0; failed=0; notworth=0; before=0; after=0
while IFS=$'\t' read -r f size kind; do
  n=$((n + 1))
  d=$(dirname "$f"); name=$(basename "$f"); base="${name%.*}"; ext="${name##*.}"
  printf "[%d/%d] %s  (%s) " "$n" "$nplan" "${f#"$src"/}" "$(human "$size")"

  tmpfile="$d/.$base.imgcompress-tmp.$ext"
  if ! compress "$f" "$tmpfile" "$kind"; then
    echo "- failed to compress. Original kept."; rm -f "$tmpfile"; tmpfile=""; failed=$((failed + 1)); continue
  fi
  problem=$(check "$f" "$tmpfile")
  if [ -n "$problem" ]; then
    echo "- problem: $problem. Original kept."; rm -f "$tmpfile"; tmpfile=""; failed=$((failed + 1)); continue
  fi
  newsize=$(fsize "$tmpfile")
  if ! worth "$size" "$newsize" "$kind"; then
    echo "- already well compressed. Kept as is."; rm -f "$tmpfile"; tmpfile=""; notworth=$((notworth + 1)); continue
  fi

  final="$f"
  if [ $keep -eq 1 ]; then
    final="$d/$base (compressed).$ext"
    k=2; while [ -e "$final" ]; do final="$d/$base (compressed $k).$ext"; k=$((k + 1)); done
  elif ! move_to_trash "$f"; then
    final="$d/$base (compressed).$ext"
    echo -n "- could not move the original to the Trash, both kept "
  fi
  mv "$tmpfile" "$final"; tmpfile=""
  echo "-> $(human "$newsize")  (-$(( (size - newsize) * 100 / size ))%)"
  printf '%s\t%s\t%s\t%s\n' "$f" "$final" "$size" "$newsize" >> "$log"
  ok=$((ok + 1)); before=$((before + size)); after=$((after + newsize))
done < "$work/plan.tsv"

echo
echo "Done. Compressed $ok of $nplan image(s): $(human "$before") -> $(human "$after"), saved $(human $((before - after)))."
[ $notworth -gt 0 ] && echo "  $notworth image(s) were already well compressed and were left as they are."
[ $failed -gt 0 ]   && echo "  $failed image(s) had a problem and were left as they are (see messages above)."
if [ $ok -gt 0 ]; then
  if [ $keep -eq 1 ]; then echo "  Originals were kept. Compare them with the \"(compressed)\" files."
  else echo "  Originals are in the Trash. Spot-check a few images, then empty the Trash to free the space."; fi
fi
echo "  Log: $log"
