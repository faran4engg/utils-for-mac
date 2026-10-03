#!/bin/bash
# setdate - give every photo/video in a folder the same date: date taken,
#           Finder Created and Finder Modified.
#
# Usage: setdate DATE [folder] [--go]
#   DATE          e.g. 2018-11-15  or  "2018-11-15 14:30"  (time defaults to 12:00)
#   folder        default: the current folder (subfolders included)
#   --go          actually write the dates (without it you only get a preview)
#   --undo CSV    put the old dates back, using the CSV saved by a --go run
#   -a, --all     include hidden files and folders
#   -h, --help    show this help
#
# Files keep their current order: each one gets 1 second more than the previous,
# ordered by their current date taken, then by name. Needs exiftool.

die() { echo "Error: $*" >&2; exit 1; }
ask() { printf "%s [y/N] " "$1"; local a; read -r a < /dev/tty; case "$a" in y|Y|yes|Yes|YES) return 0 ;; *) return 1 ;; esac; }

date_in=""; dir=""; go=0; undo=""; all=0
while [ $# -gt 0 ]; do
  case "$1" in
    --go)      go=1 ;;
    --undo)    undo="$2"; shift ;;
    -a|--all)  all=1 ;;
    -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)        die "Unknown option: $1 (try -h)" ;;
    *) if [ -z "$date_in" ] && [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2} ]]; then date_in="$1"
       elif [ -z "$dir" ]; then dir="$1"; else die "Too many arguments (try -h)"; fi ;;
  esac
  shift
done
command -v exiftool >/dev/null 2>&1 || die "exiftool is not installed. Run: brew install exiftool"
reports="$HOME/photosort-reports"; mkdir -p "$reports"
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

# --------------------------------------------------------------------------- undo
if [ -n "$undo" ]; then
  [ -f "$undo" ] || die "'$undo' not found."
  list="${undo%.csv}-files.txt"; [ -f "$list" ] || die "The file list '$list' for this CSV is missing."
  echo "This puts back the original dates of $(wc -l < "$list" | tr -d ' ') file(s)."
  ask "Continue?" || { echo "Cancelled. Nothing was changed."; exit 0; }
  exiftool -q -q -m -f -api MissingTagValue= -overwrite_original -api QuickTimeUTC -csv="$undo" -@ "$list"
  echo "Done. The original dates are back."; exit 0
fi

# --------------------------------------------------------------------------- plan
[ -n "$date_in" ] || die "Give the date to set, e.g. setdate 2018-11-15 (try -h)"
if   [[ "$date_in" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})$ ]]; then hh=12; mi=0
elif [[ "$date_in" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})[\ T]([0-9]{1,2}):([0-9]{2})$ ]]; then hh=$((10#${BASH_REMATCH[4]})); mi=$((10#${BASH_REMATCH[5]}))
else die "Date should look like 2018-11-15 or \"2018-11-15 14:30\""; fi
y=${BASH_REMATCH[1]}; mo=$((10#${BASH_REMATCH[2]})); d=$((10#${BASH_REMATCH[3]}))
{ [ $mo -ge 1 ] && [ $mo -le 12 ] && [ $d -ge 1 ] && [ $d -le 31 ] && [ $hh -le 23 ] && [ $mi -le 59 ]; } || die "'$date_in' is not a valid date."

dir="${dir:-.}"; [ -d "$dir" ] || die "'$dir' is not a folder."
src=$(cd "$dir" && pwd -P)
if [ $all -eq 1 ]; then
  find "$src" \( -type d -name '*.photoslibrary' -prune \) -o \( -type f -print \)
else
  find "$src" \( -type d ! -path "$src" \( -name '.*' -o -name '*.photoslibrary' \) -prune \) -o \( -type f ! -name '.*' -print \)
fi 2>/dev/null | awk '
  BEGIN { n = split("jpg jpeg heic heif png gif webp tif tiff dng cr2 cr3 nef arw mov mp4 m4v 3gp", a, " "); for (i = 1; i <= n; i++) M[a[i]] = 1 }
  { k = split($0, p, "/"); e = ""; if (match(p[k], /\.[^.]+$/) && RSTART > 1) e = tolower(substr(p[k], RSTART + 1)); if (e in M) print }' > "$work/files.txt"
nfiles=$(wc -l < "$work/files.txt" | tr -d ' ')
[ "$nfiles" -gt 0 ] || { echo "No photos or videos found in $src."; exit 0; }

# Current date taken (for ordering and the preview), then assign new times 1 second apart
export SD_Y=$y SD_MO=$mo SD_D=$d SD_H=$hh SD_MI=$mi
exiftool -q -q -m -fast -T -api QuickTimeUTC -d '%Y:%m:%d %H:%M:%S' -Directory -FileName \
  -Keys:CreationDate -EXIF:DateTimeOriginal -QuickTime:CreateDate -@ "$work/files.txt" 2>/dev/null |
  awk -F'\t' '{ c = "-"; for (i = 3; i <= 5; i++) if ($i ~ /^[0-9][0-9][0-9][0-9]:/) { c = substr($i, 1, 19); break }
               print (c == "-" ? "9999" : c) "\t" $2 "\t" $1 "/" $2 "\t" c }' |
  sort -t$'\t' -k1,1 -k2,2 |
  awk -F'\t' '{ s = ENVIRON["SD_H"] * 3600 + ENVIRON["SD_MI"] * 60 + NR - 1
      if (s > 86399) s = 86399
      new = sprintf("%04d:%02d:%02d %02d:%02d:%02d", ENVIRON["SD_Y"], ENVIRON["SD_MO"], ENVIRON["SD_D"], int(s / 3600), int(s % 3600 / 60), s % 60)
      print $3 "\t" $4 "\t" new }' > "$work/plan.tsv"

stamp=$(date +%Y-%m-%d_%H%M%S)
first=$(head -1 "$work/plan.tsv" | cut -f3); last=$(tail -1 "$work/plan.tsv" | cut -f3)
echo "Folder: $src (subfolders included)"
echo "Files:  $nfiles photos/videos"
echo "New dates: $first  ...  $last   (date taken, Finder Created and Modified)"
echo
echo "Preview (first 10):        date taken now  ->  new"
awk -F'\t' -v src="$src/" 'NR <= 10 { p = $1; if (index(p, src) == 1) p = substr(p, length(src) + 1)
  printf "  %-40s %-19s  ->  %s\n", p, $2, $3 }' "$work/plan.tsv"
[ "$nfiles" -gt 10 ] && echo "  ...and $((nfiles - 10)) more"

if [ $go -eq 0 ]; then
  echo; echo "This was only a preview. Nothing was changed. Run again with --go to write the dates."; exit 0
fi
echo
ask "Set these dates on $nfiles file(s)?" || { echo "Cancelled. Nothing was changed."; exit 0; }

tags="DateTimeOriginal,CreateDate,ModifyDate,Keys:CreationDate,FileModifyDate,FileCreateDate"
list="$reports/$stamp-setdate-undo-files.txt"; undo_csv="$reports/$stamp-setdate-undo.csv"
cut -f1 "$work/plan.tsv" > "$list"
# -f with an empty MissingTagValue records tags that didn't exist, so undo removes them again
exiftool -q -q -m -f -api MissingTagValue= -api QuickTimeUTC -csv -DateTimeOriginal -CreateDate -ModifyDate -Keys:CreationDate \
  -FileModifyDate -FileCreateDate -@ "$list" > "$undo_csv" 2>/dev/null

awk -F'\t' -v tags="$tags" 'BEGIN { print "SourceFile," tags }
  { p = $1; gsub(/"/, "\"\"", p); printf "\"%s\",%s,%s,%s,%s,%s,%s\n", p, $3, $3, $3, $3, $3, $3 }' "$work/plan.tsv" > "$work/new.csv"
echo "Writing dates..."
exiftool -q -q -m -overwrite_original -api QuickTimeUTC -csv="$work/new.csv" -@ "$list" 2>/dev/null

exiftool -q -q -m -T -api QuickTimeUTC -d '%Y:%m:%d %H:%M:%S' -Directory -FileName -DateTimeOriginal -CreateDate \
  -FileModifyDate -@ "$list" 2>/dev/null > "$work/after.tsv"
ok=$(awk -F'\t' 'FILENAME == ARGV[1] { want[$1] = $3; next }
  { p = $1 "/" $2; t = ($3 != "-") ? $3 : $4; if (substr(t, 1, 19) == want[p] && substr($5, 1, 19) == want[p]) n++ }
  END { print n + 0 }' "$work/plan.tsv" "$work/after.tsv")
echo
echo "Done. $ok of $nfiles file(s) now have the new date."
[ "$ok" -lt "$nfiles" ] && echo "  $((nfiles - ok)) file(s) could not be fully updated (exiftool may not support writing that format)."
echo "  To undo: setdate --undo \"$undo_csv\""
