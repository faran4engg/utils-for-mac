#!/bin/bash
# fixdates - fix photo dates in two ways:
#   default:              write the file's Created date into the "date taken" of photos/videos
#                         from one camera model (default: Canon EOS M50), so apps like Ente show it
#   --sync-finder-dates:  set Finder's Created and Modified dates to each photo's date taken
#                         (all cameras except the --model one, whose date taken is wrong)
#
# Usage: fixdates [options] [folder]
#   -m, --model NAME  camera model with the wrong clock (default "Canon EOS M50", case-insensitive)
#   --sync-finder-dates  sync Finder dates to the date taken instead (see above)
#   --go              actually write the dates (without it you only get a preview)
#   --undo CSV        put the old dates back, using the CSV saved by a --go run
#   -a, --all         include hidden files and folders
#   -h, --help        show this help
#
# Scans the folder (default: current folder) and all subfolders.
# The default mode keeps each file's Created and Modified dates. Needs exiftool (brew install exiftool).

die() { echo "Error: $*" >&2; exit 1; }
ask() { printf "%s [y/N] " "$1"; local a; read -r a < /dev/tty; case "$a" in y|Y|yes|Yes|YES) return 0 ;; *) return 1 ;; esac; }

model="Canon EOS M50"; sync=0; go=0; undo=""; all=0; dir=""
while [ $# -gt 0 ]; do
  case "$1" in
    -m|--model) model="$2"; shift ;;
    --go)       go=1 ;;
    --sync-finder-dates) sync=1 ;;
    --undo)     undo="$2"; shift ;;
    -a|--all)   all=1 ;;
    -h|--help)  sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)         die "Unknown option: $1 (try -h)" ;;
    *)          [ -n "$dir" ] && die "Please give one folder at a time."; dir="$1" ;;
  esac
  shift
done
command -v exiftool >/dev/null 2>&1 || die "exiftool is not installed. Run: brew install exiftool"

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
reports="$HOME/photosort-reports"; mkdir -p "$reports"

# --------------------------------------------------------------------------- undo
if [ -n "$undo" ]; then
  [ -f "$undo" ] || die "'$undo' not found."
  n=$(($(wc -l < "$undo") - 1))
  echo "This puts back the original dates of $n file(s) from $undo."
  ask "Continue?" || { echo "Cancelled. Nothing was changed."; exit 0; }
  list="${undo%.csv}-files.txt"
  [ -f "$list" ] || die "The file list '$list' that belongs to this CSV is missing."
  exiftool -q -P -overwrite_original -csv="$undo" -@ "$list"
  echo "Done. The original dates are back."
  exit 0
fi

# --------------------------------------------------------------------------- preview
dir="${dir:-.}"
[ -d "$dir" ] || die "'$dir' is not a folder."
src=$(cd "$dir" && pwd -P)

if [ $all -eq 1 ]; then
  find "$src" \( -type d -name '*.photoslibrary' -prune \) -o \( -type f -print \)
else
  find "$src" \( -type d ! -path "$src" \( -name '.*' -o -name '*.photoslibrary' \) -prune \) -o \( -type f ! -name '.*' -print \)
fi 2>/dev/null | awk '
  BEGIN { n = split("jpg jpeg heic heif png tif tiff dng cr2 cr3 crw mov mp4 m4v", a, " "); for (i = 1; i <= n; i++) M[a[i]] = 1 }
  { k = split($0, p, "/"); e = ""; if (match(p[k], /\.[^.]+$/) && RSTART > 1) e = tolower(substr(p[k], RSTART + 1)); if (e in M) print }' > "$work/files.txt"

nfiles=$(wc -l < "$work/files.txt" | tr -d ' ')
[ "$nfiles" -gt 0 ] || { echo "No photos or videos found in $src."; exit 0; }
echo "Checking $nfiles photos and videos in $src for camera \"$model\"..."

export FD_MODEL="$model" FD_COUNTS="$work/counts"
stamp=$(date +%Y-%m-%d_%H%M%S)

# --------------------------------------------------------------------------- sync Finder dates
if [ $sync -eq 1 ]; then
  echo "(Syncing Finder dates to the date taken. Skipping \"$model\" files.)"
  exiftool -q -q -m -fast -T -api QuickTimeUTC -d '%Y:%m:%d %H:%M:%S' -Directory -FileName -Model \
    -Keys:CreationDate -EXIF:DateTimeOriginal -XMP:DateTimeOriginal -QuickTime:CreateDate -EXIF:CreateDate \
    -FileCreateDate -FileModifyDate -@ "$work/files.txt" 2>/dev/null |
    awk -F'\t' '
      function valid(d,  y) { if (d !~ /^[0-9][0-9][0-9][0-9]:[0-9][0-9]:[0-9][0-9] /) return 0
        y = substr(d, 1, 4) + 0; if (y < 1900) return 0
        if (substr(d, 1, 10) == "1904:01:01" || substr(d, 1, 10) == "1970:01:01") return 0; return 1 }
      tolower($3) == tolower(ENVIRON["FD_MODEL"]) { cam++; next }
      { d = ""; for (i = 4; i <= 8; i++) if (valid($i)) { d = substr($i, 1, 19); break }
        if (d == "") { nodate++; next }
        if (substr($9, 1, 19) == d && substr($10, 1, 19) == d) { same++; next }
        print $1 "/" $2 "\t" substr($9, 1, 19) "\t" substr($10, 1, 19) "\t" d }
      END { print same + 0, nodate + 0, cam + 0 > ENVIRON["FD_COUNTS"] }' > "$work/sync.tsv"

  read same nodate cam < "$work/counts"
  nsync=$(wc -l < "$work/sync.tsv" | tr -d ' ')
  preview="$reports/$stamp-syncdates-preview.txt"
  { echo "# fixdates --sync-finder-dates preview for $src"; echo "# file    Finder Created now  ->  date taken"
    awk -F'\t' '{ printf "%s    %s  ->  %s\n", $1, $2, $4 }' "$work/sync.tsv"; } > "$preview"

  echo
  printf "  %-46s %s\n" "Finder dates will be set to the date taken:" "$nsync"
  [ "$same" -gt 0 ]   && printf "  %-46s %s\n" "Already matching (skipped):" "$same"
  [ "$nodate" -gt 0 ] && printf "  %-46s %s\n" "No date taken (skipped):" "$nodate"
  [ "$cam" -gt 0 ]    && printf "  %-46s %s\n" "$model files (skipped):" "$cam"
  [ "$nsync" -eq 0 ] && { echo "Nothing to do."; exit 0; }
  echo
  echo "Preview (first 10):        Finder Created now  ->  date taken"
  awk -F'\t' -v src="$src/" 'NR <= 10 { p = $1; if (index(p, src) == 1) p = substr(p, length(src) + 1)
    printf "  %-40s %s  ->  %s\n", p, $2, $4 }' "$work/sync.tsv"
  echo "  Full list: $preview"
  if [ $go -eq 0 ]; then
    echo; echo "This was only a preview. Nothing was changed. Run again with --go to update the Finder dates."; exit 0
  fi
  echo
  ask "Set Finder's Created and Modified dates in $nsync file(s)?" || { echo "Cancelled. Nothing was changed."; exit 0; }

  list="$reports/$stamp-syncdates-undo-files.txt"; undo_csv="$reports/$stamp-syncdates-undo.csv"
  cut -f1 "$work/sync.tsv" > "$list"
  exiftool -q -q -csv -FileCreateDate -FileModifyDate -@ "$list" > "$undo_csv" 2>/dev/null

  # New dates go in through a CSV: one fast exiftool run, no file contents are rewritten
  awk -F'\t' 'BEGIN { print "SourceFile,FileModifyDate,FileCreateDate" }
    { p = $1; gsub(/"/, "\"\"", p); printf "\"%s\",%s,%s\n", p, $4, $4 }' "$work/sync.tsv" > "$work/new.csv"
  echo "Updating Finder dates..."
  exiftool -q -q -m -csv="$work/new.csv" -@ "$list" 2>/dev/null

  exiftool -q -q -m -T -d '%Y:%m:%d %H:%M:%S' -Directory -FileName -FileCreateDate -FileModifyDate -@ "$list" 2>/dev/null > "$work/after.tsv"
  read ok mod_only <<< "$(awk -F'\t' 'FILENAME == ARGV[1] { want[$1] = $4; next }
    { p = $1 "/" $2; m = (substr($4, 1, 19) == want[p]); c = (substr($3, 1, 19) == want[p])
      if (m && (c || $3 == "-")) ok++; else if (m) mo++ }
    END { printf "%d %d", ok, mo }' "$work/sync.tsv" "$work/after.tsv")"
  echo
  echo "Done. Finder dates now match the date taken in $ok file(s)."
  [ "$mod_only" -gt 0 ] && echo "  $mod_only file(s) got the new Modified date, but macOS kept their Created date."
  bad=$((nsync - ok - mod_only)); [ $bad -gt 0 ] && echo "  $bad file(s) could not be updated."
  echo "  To undo: fixdates --undo \"$undo_csv\""
  exit 0
fi
exiftool -q -q -m -fast -T -d '%Y:%m:%d %H:%M:%S' -Directory -FileName -Model -DateTimeOriginal -FileCreateDate \
  -@ "$work/files.txt" 2>/dev/null |
  awk -F'\t' '
    tolower($3) == tolower(ENVIRON["FD_MODEL"]) {
      if ($5 !~ /^[0-9][0-9][0-9][0-9]:/) { nocreate++; next }
      new = substr($5, 1, 19)
      if (substr($4, 1, 19) == new) { same++; next }
      print $1 "/" $2 "\t" ($4 == "-" ? "(none)" : $4) "\t" new
    }
    END { print same + 0, nocreate + 0 > ENVIRON["FD_COUNTS"] }' > "$work/plan.tsv"

read same nocreate < "$work/counts"
nfix=$(wc -l < "$work/plan.tsv" | tr -d ' ')
preview="$reports/$stamp-fixdates-preview.txt"
{ echo "# fixdates preview for camera \"$model\" in $src"; echo "# file    date taken now  ->  new date taken (Created date)"
  awk -F'\t' '{ printf "%s    %s  ->  %s\n", $1, $2, $3 }' "$work/plan.tsv"; } > "$preview"

echo
echo "Photos/videos from $model that need fixing: $nfix"
[ "$same" -gt 0 ]     && echo "Already matching their Created date (skipped): $same"
[ "$nocreate" -gt 0 ] && echo "No Created date available (skipped):            $nocreate"
[ "$nfix" -eq 0 ] && { echo "Nothing to do."; exit 0; }
echo
echo "Preview (first 10):"
awk -F'\t' -v src="$src/" 'NR <= 10 { p = $1; if (index(p, src) == 1) p = substr(p, length(src) + 1)
  printf "  %-40s %s  ->  %s\n", p, $2, $3 }' "$work/plan.tsv"
echo "  Full list: $preview"

if [ $go -eq 0 ]; then
  echo
  echo "This was only a preview. Nothing was changed. Run again with --go to write the new dates."
  exit 0
fi

echo
ask "Write the Created date as the date taken in $nfix file(s)?" || { echo "Cancelled. Nothing was changed."; exit 0; }

# Save the current dates so --undo can put them back
cut -f1 "$work/plan.tsv" > "$reports/$stamp-fixdates-undo-files.txt"
undo_csv="$reports/$stamp-fixdates-undo.csv"
exiftool -q -q -csv -DateTimeOriginal -CreateDate -ModifyDate -@ "$reports/$stamp-fixdates-undo-files.txt" > "$undo_csv" 2>/dev/null

echo "Writing dates..."
exiftool -q -q -m -P -overwrite_original -api QuickTimeUTC \
  "-AllDates<FileCreateDate" "-DateTimeOriginal<FileCreateDate" \
  -@ "$reports/$stamp-fixdates-undo-files.txt"

# Check the result: date taken should now equal the Created date we planned
exiftool -q -q -m -T -d '%Y:%m:%d %H:%M:%S' -Directory -FileName -DateTimeOriginal -CreateDate -FileCreateDate \
  -@ "$reports/$stamp-fixdates-undo-files.txt" 2>/dev/null > "$work/after.tsv"
read ok bad created_changed <<< "$(awk -F'\t' '
  FILENAME == ARGV[1] { want[$1] = $3; next }
  { p = $1 "/" $2; got = ($3 != "-") ? substr($3, 1, 19) : substr($4, 1, 19)
    if (got == want[p]) ok++; else bad++
    if (substr($5, 1, 19) != want[p]) cc++ }
  END { printf "%d %d %d", ok, bad, cc }' "$work/plan.tsv" "$work/after.tsv")"

echo
echo "Done. Updated the date taken in $ok file(s)."
[ "$bad" -gt 0 ] && echo "  $bad file(s) could not be updated (exiftool may not support writing that format)."
[ "$created_changed" -gt 0 ] && echo "  Note: macOS changed the Created date of $created_changed file(s) while writing. Their date taken is still correct."
echo "  To undo: fixdates --undo \"$undo_csv\""
