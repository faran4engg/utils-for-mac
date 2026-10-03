#!/bin/bash
# vidshrink - make videos smaller by re-encoding them to HEVC (H.265), keeping their
#             date taken, location and other metadata.
#
# Usage: vidshrink [options] [folder]
#   --go             actually shrink (without it you only get a preview)
#   --keep           keep the original and save the new file next to it as "name (shrunk).mp4"
#                    (default: the original goes to the Trash once the new file checks out)
#   --max-height N   also shrink the picture, e.g. 1080 turns 4K into 1080p (default: keep size)
#   --crf N          quality: lower = better and bigger (default 24, sensible range 20-28)
#   --fast           use the Mac's hardware encoder: much faster, files somewhat bigger
#   --min SIZE       skip videos smaller than this (default 50M)
#   --force          also re-encode videos that are already HEVC
#   -a, --all        include hidden files and folders
#   -h, --help       show this help
#
# Scans the folder (default: current folder) and all subfolders. Needs ffmpeg and exiftool.
# Each new file is checked (plays, same length, same date taken, really smaller)
# before the original is touched.

IS_MAC=0; [ "$(uname)" = "Darwin" ] && IS_MAC=1
die() { echo "Error: $*" >&2; exit 1; }
ask() { printf "%s [y/N] " "$1"; local a; read -r a < /dev/tty; case "$a" in y|Y|yes|Yes|YES) return 0 ;; *) return 1 ;; esac; }
human() { awk -v b="$1" 'BEGIN { split("B KB MB GB TB", u, " "); i = 1; while (b >= 1000 && i < 5) { b /= 1000; i++ }
  if (i == 1) printf "%d B", b; else printf "%.1f %s", b, u[i] }'; }
fsize() { if [ $IS_MAC -eq 1 ]; then stat -f %z "$1"; else stat -c %s "$1"; fi; }

go=0; keep=0; maxh=0; crf=24; fast=0; min="50M"; force=0; all=0; dir=""
while [ $# -gt 0 ]; do
  case "$1" in
    --go)         go=1 ;;
    --keep)       keep=1 ;;
    --max-height) maxh="$2"; shift ;;
    --crf)        crf="$2"; shift ;;
    --fast)       fast=1 ;;
    --min)        min="$2"; shift ;;
    --force)      force=1 ;;
    -a|--all)     all=1 ;;
    -h|--help)    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)           die "Unknown option: $1 (try -h)" ;;
    *)            [ -n "$dir" ] && die "Please give one folder at a time."; dir="$1" ;;
  esac
  shift
done

command -v ffmpeg >/dev/null 2>&1 && command -v ffprobe >/dev/null 2>&1 || die "ffmpeg is not installed. Run: brew install ffmpeg"
command -v exiftool >/dev/null 2>&1 || die "exiftool is not installed. Run: brew install exiftool"
case "$maxh" in ''|*[!0-9]*) die "--max-height needs a number, e.g. 1080" ;; esac
case "$crf"  in ''|*[!0-9]*) die "--crf needs a number, e.g. 24" ;; esac
[[ "$min" =~ ^[0-9]+(\.[0-9]+)?[KkMmGg]?[Bb]?$ ]] || die "--min should look like 50M or 1G"
min_bytes=$(awk -v s="${min%[Bb]}" 'BEGIN { u = toupper(substr(s, length(s))); n = s + 0
  if (u == "K") n *= 1e3; else if (u == "M") n *= 1e6; else if (u == "G") n *= 1e9; printf "%.0f", n }')
if [ $fast -eq 1 ]; then
  ffmpeg -hide_banner -encoders 2>/dev/null | grep -q hevc_videotoolbox || die "--fast needs the Mac hardware encoder (hevc_videotoolbox), which this ffmpeg doesn't have."
else
  ffmpeg -hide_banner -encoders 2>/dev/null | grep -q libx265 || die "This ffmpeg has no HEVC encoder (libx265). Try: brew reinstall ffmpeg"
fi

dir="${dir:-.}"; [ -d "$dir" ] || die "'$dir' is not a folder."
src=$(cd "$dir" && pwd -P)
work=$(mktemp -d); tmpfile=""
cleanup() { [ -n "$tmpfile" ] && rm -f "$tmpfile"; rm -rf "$work"; }
trap cleanup EXIT
trap 'echo; echo "Stopped. The video being worked on was left untouched."; exit 130' INT
reports="$HOME/vidshrink-reports"

# --------------------------------------------------------------------------- find + inspect
if [ $all -eq 1 ]; then
  find "$src" \( -type d -name '*.photoslibrary' -prune \) -o \( -type f -print \)
else
  find "$src" \( -type d ! -path "$src" \( -name '.*' -o -name '*.photoslibrary' \) -prune \) -o \( -type f ! -name '.*' -print \)
fi 2>/dev/null | awk '
  BEGIN { n = split("mov mp4 m4v avi mkv mts m2ts 3gp wmv mpg mpeg flv webm", a, " "); for (i = 1; i <= n; i++) V[a[i]] = 1 }
  { k = split($0, p, "/"); e = ""; if (match(p[k], /\.[^.]+$/) && RSTART > 1) e = tolower(substr(p[k], RSTART + 1)); if (e in V) print }' > "$work/videos.txt"

nvid=$(wc -l < "$work/videos.txt" | tr -d ' ')
[ "$nvid" -gt 0 ] || { echo "No videos found in $src."; exit 0; }
echo "Inspecting $nvid video(s) in $src (subfolders included)..."

: > "$work/plan.tsv"; small=0; already=0; broken=0; i=0
while IFS= read -r f; do
  i=$((i + 1)); printf "\r  %d / %d" "$i" "$nvid" >&2
  size=$(fsize "$f"); [ "$size" -lt "$min_bytes" ] && { small=$((small + 1)); continue; }
  info=$(ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,width,height,pix_fmt \
         -show_entries format=duration -of default=nw=1 "$f" 2>/dev/null)
  codec=$(sed -n 's/^codec_name=//p' <<< "$info" | head -1); w=$(sed -n 's/^width=//p' <<< "$info" | head -1)
  h=$(sed -n 's/^height=//p' <<< "$info" | head -1); pix=$(sed -n 's/^pix_fmt=//p' <<< "$info" | head -1)
  dur=$(sed -n 's/^duration=//p' <<< "$info" | head -1)
  if [ -z "$codec" ] || [ -z "$w" ] || [ -z "$h" ]; then broken=$((broken + 1)); continue; fi
  short=$w; [ "$h" -lt "$w" ] && short=$h
  scale=0; [ "$maxh" -gt 0 ] && [ "$short" -gt "$maxh" ] && scale=1
  if [ "$codec" = "hevc" ] && [ $scale -eq 0 ] && [ $force -eq 0 ]; then already=$((already + 1)); continue; fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$f" "$size" "$codec" "$w" "$h" "${pix:-yuv420p}" "${dur:-0}" "$scale" >> "$work/plan.tsv"
done < "$work/videos.txt"
printf "\n" >&2

label() {   # "4K H.264" style description: label WIDTH HEIGHT CODEC
  local s=$1; [ "$2" -lt "$s" ] && s=$2
  local r="${s}p"; [ "$s" -ge 2000 ] && r="4K"
  local c; case "$3" in h264) c="H.264" ;; hevc) c="HEVC" ;; mpeg4) c="MPEG-4" ;; prores) c="ProRes" ;; *) c="$3" ;; esac
  echo "$r $c"
}

nplan=$(wc -l < "$work/plan.tsv" | tr -d ' ')
total=$(awk -F'\t' '{ s += $2 } END { printf "%.0f", s }' "$work/plan.tsv")
echo
echo "Videos to shrink: $nplan ($(human "$total") in total)"
[ "$already" -gt 0 ] && echo "Already HEVC, skipped:   $already  (use --force to include, or --max-height to downsize)"
[ "$small" -gt 0 ]   && echo "Smaller than $min, skipped: $small"
[ "$broken" -gt 0 ]  && echo "Unreadable, skipped:     $broken"
[ "$nplan" -eq 0 ] && { echo "Nothing to do."; exit 0; }

echo
echo "Plan:"
while IFS=$'\t' read -r f size codec w h pix dur scale; do
  to="HEVC"; [ "$scale" -eq 1 ] && to="${maxh}p HEVC"
  rel="${f#"$src"/}"
  printf "  %9s  %-12s -> %-11s %s\n" "$(human "$size")" "$(label "$w" "$h" "$codec")" "$to" "$rel"
done < <(sort -t$'\t' -k2,2nr "$work/plan.tsv" | head -n 15)
[ "$nplan" -gt 15 ] && echo "  ...and $((nplan - 15)) more"
echo
echo "Encoder: $( [ $fast -eq 1 ] && echo "Mac hardware HEVC (fast)" || echo "x265, quality $crf (slower, smallest files)" )"
echo "Afterwards: $( [ $keep -eq 1 ] && echo "originals are kept; new files are saved as \"name (shrunk)\"" || echo "each original goes to the Trash once its new file checks out" )"

if [ $go -eq 0 ]; then
  echo
  echo "This was only a preview. Nothing was changed."
  echo "Tip: try one folder with --keep first and compare a few videos before shrinking everything."
  echo "Run again with --go to start."
  exit 0
fi
echo
ask "Shrink $nplan video(s) now? This can take a while." || { echo "Cancelled. Nothing was changed."; exit 0; }

# --------------------------------------------------------------------------- encode
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

date_of() {   # first available creation date, as local time
  exiftool -q -q -m -T -api QuickTimeUTC -d '%Y:%m:%d %H:%M:%S' -Keys:CreationDate -QuickTime:CreateDate "$1" 2>/dev/null |
    awk -F'\t' '{ for (i = 1; i <= NF; i++) if ($i ~ /^[12][0-9][0-9][0-9]:/ && $i !~ /^1904:01:01|^1970:01:01/) { print substr($i, 1, 19); exit } }'
}

mkdir -p "$reports"; log="$reports/$(date +%Y-%m-%d_%H%M%S).log"
echo -e "# vidshrink log $(date '+%Y-%m-%d %H:%M')\n# original\tnew\told size\tnew size" > "$log"
n=0; ok=0; failed=0; notworth=0; before=0; after=0
while IFS=$'\t' read -r f size codec w h pix dur scale; do
  n=$((n + 1))
  d=$(dirname "$f"); name=$(basename "$f"); base="${name%.*}"; ext="${name##*.}"
  case "$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')" in mov|mp4|m4v) outext="$ext" ;; *) outext="mp4" ;; esac
  echo
  echo "[$n/$nplan] ${f#"$src"/}  ($(human "$size"), $(label "$w" "$h" "$codec"))"

  tmpfile="$d/.$base.vidshrink-tmp.$outext"
  venc=(); vf=()
  ten=0; case "$pix" in *10*) ten=1 ;; esac
  if [ $fast -eq 1 ]; then
    tgt=$h; [ "$w" -lt "$tgt" ] && tgt=$w; [ "$scale" -eq 1 ] && tgt=$maxh
    if   [ "$tgt" -ge 2000 ]; then br=16M; elif [ "$tgt" -ge 1400 ]; then br=10M
    elif [ "$tgt" -ge 1000 ]; then br=6M;  elif [ "$tgt" -ge 700 ];  then br=3500k; else br=2M; fi
    venc=(-c:v hevc_videotoolbox -b:v "$br")
    [ $ten -eq 1 ] && venc+=(-profile:v main10 -pix_fmt p010le)
  else
    venc=(-c:v libx265 -crf "$crf" -preset medium -x265-params log-level=error)
    if [ $ten -eq 1 ]; then venc+=(-pix_fmt yuv420p10le); else venc+=(-pix_fmt yuv420p); fi
  fi
  [ "$scale" -eq 1 ] && vf=(-vf "scale=w='if(gt(iw,ih),-2,$maxh)':h='if(gt(iw,ih),$maxh,-2)'")
  acodec=$(ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$f" 2>/dev/null | head -1)
  if [ "$acodec" = "aac" ]; then aenc=(-c:a copy); else aenc=(-c:a aac -b:a 160k); fi

  if ! ffmpeg -nostdin -hide_banner -loglevel error -stats -i "$f" -map 0:v:0 -map '0:a?' \
        -map_metadata 0 -movflags +use_metadata_tags+faststart "${vf[@]}" "${venc[@]}" "${aenc[@]}" \
        -tag:v hvc1 -y "$tmpfile"; then
    echo "  Failed to encode. Original kept."; rm -f "$tmpfile"; tmpfile=""; failed=$((failed + 1)); continue
  fi

  # Copy all metadata (date, location, camera...) and Finder dates from the original.
  # Rotation is left out: ffmpeg already turned the picture the right way up.
  exiftool -q -q -m -overwrite_original -TagsFromFile "$f" -All:All --Rotation \
    -FileModifyDate -FileCreateDate "$tmpfile" >/dev/null 2>&1

  # Checks: plays, same length, same date taken, really smaller
  newsize=$(fsize "$tmpfile")
  ndur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$tmpfile" 2>/dev/null)
  problem=""
  if [ -z "$ndur" ]; then problem="the new file doesn't play"
  elif awk -v a="$dur" -v b="$ndur" 'BEGIN { d = a - b; if (d < 0) d = -d; t = a * 0.01; if (t < 1) t = 1; exit !(d > t) }'; then
    problem="the new file has a different length ($ndur s vs $dur s)"
  else
    od=$(date_of "$f"); nd=$(date_of "$tmpfile")
    [ -n "$od" ] && [ "$od" != "$nd" ] && problem="the date taken didn't carry over ($od vs ${nd:-none})"
  fi
  if [ -n "$problem" ]; then
    echo "  Problem: $problem. Original kept, new file discarded."
    rm -f "$tmpfile"; tmpfile=""; failed=$((failed + 1)); continue
  fi
  if [ "$newsize" -ge $((size * 9 / 10)) ]; then
    echo "  Only $(human "$size") -> $(human "$newsize"), not worth it. Original kept."
    rm -f "$tmpfile"; tmpfile=""; notworth=$((notworth + 1)); continue
  fi

  final="$d/$base.$outext"
  if [ $keep -eq 1 ] || [ "$final" != "$f" -a -e "$final" ]; then
    final="$d/$base (shrunk).$outext"
    k=2; while [ -e "$final" ]; do final="$d/$base (shrunk $k).$outext"; k=$((k + 1)); done
  elif ! move_to_trash "$f"; then
    final="$d/$base (shrunk).$outext"
    echo "  Could not move the original to the Trash, so both are kept."
  fi
  mv "$tmpfile" "$final"; tmpfile=""
  pct=$(( (size - newsize) * 100 / size ))
  echo "  $(human "$size") -> $(human "$newsize")  (-$pct%)  OK"
  printf '%s\t%s\t%s\t%s\n' "$f" "$final" "$size" "$newsize" >> "$log"
  ok=$((ok + 1)); before=$((before + size)); after=$((after + newsize))
done < "$work/plan.tsv"

echo
echo "Done. Shrunk $ok of $nplan video(s): $(human "$before") -> $(human "$after"), saved $(human $((before - after)))."
[ $notworth -gt 0 ] && echo "  $notworth video(s) wouldn't get meaningfully smaller and were left as they are."
[ $failed -gt 0 ]   && echo "  $failed video(s) had a problem and were left as they are (see messages above)."
if [ $ok -gt 0 ]; then
  if [ $keep -eq 1 ]; then echo "  Originals were kept. Compare them with the \"(shrunk)\" files."
  else echo "  Originals are in the Trash. Spot-check a few videos, then empty the Trash to free the space."; fi
fi
echo "  Log: $log"
