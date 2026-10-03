#!/bin/bash
# photosort - sort photos and videos into date folders (like 2023/08-August) by the date they were taken.
#
# Usage: photosort [options] [SOURCE] [DEST]
#   SOURCE          folder to sort (default: the current folder)
#   DEST            where the dated folders go (default: "SOURCE (sorted)", next to SOURCE)
#   --go            actually move the files (without it you only get a preview)
#   --copy          copy instead of move, so the originals stay where they are
#   --by LAYOUT     month = 2023/08-August (default), day = 2023/08-August/14, year = 2023
#   --strict        files with no date taken go to an "Unknown date" folder
#                   (default: use the file's Created date for those)
#   --ignore-camera NAME  don't trust the date taken from this camera model; use the
#                   Created date instead (repeatable; Canon EOS M50 is always included)
#   --min-year YEAR use the Created date when the date taken is before YEAR (off by default)
#   -a, --all       include hidden files and folders
#   --undo LOG      move everything back, using the log from an earlier --go run
#   -h, --help      show this help
#
# Reads the real date taken with exiftool (brew install exiftool). Scans all subfolders.
# Live Photo videos and .AAE / .XMP sidecar files follow their photo. Never overwrites a file.

IS_MAC=0; [ "$(uname)" = "Darwin" ] && IS_MAC=1
die() { echo "Error: $*" >&2; exit 1; }
n_comma() { awk -v n="$1" 'BEGIN { s = sprintf("%d", n); while (s ~ /[0-9][0-9][0-9][0-9]/) sub(/[0-9][0-9][0-9]($|,)/, ",&", s); print s }'; }
abspath() { local p="$1"; case "$p" in /*) ;; *) p="$PWD/$p" ;; esac; if [ -d "$p" ]; then (cd "$p" && pwd -P); else echo "${p%/}"; fi; }
ask() { printf "%s [y/N] " "$1"; local a; read -r a < /dev/tty; case "$a" in y|Y|yes|Yes|YES) return 0 ;; *) return 1 ;; esac; }

# Cameras whose clock can't be trusted: their photos are dated by the file's Created date.
# Match is on the camera model name, ignoring upper/lower case.
IGNORE_CAMERAS=("Canon EOS M50")

minyear=0; go=0; copy=0; by=month; fallback=1; all=0; undo=""; args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --go)        go=1 ;;
    --copy)      copy=1 ;;
    --by)        by="$2"; shift ;;
    --strict)    fallback=0 ;;
    --min-year)  minyear="$2"; shift ;;
    --ignore-camera) IGNORE_CAMERAS+=("$2"); shift ;;
    --fallback)  fallback=1 ;;   # old flag, now the default
    -a|--all)    all=1 ;;
    --undo)      undo="$2"; shift ;;
    -h|--help)   sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)          die "Unknown option: $1 (try -h)" ;;
    *)           args+=("$1") ;;
  esac
  shift
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
reports="$HOME/photosort-reports"

# --------------------------------------------------------------------------- undo
if [ -n "$undo" ]; then
  [ -f "$undo" ] || die "'$undo' not found."
  head -1 "$undo" | grep -q '^# photosort move log' || {
    head -1 "$undo" | grep -q '^# photosort copy log' &&
      die "That log is from a --copy run, so the originals were never moved. Just delete the copies if you don't want them."
    die "'$undo' doesn't look like a photosort log."
  }
  dest=$(sed -n 's/^# dest: //p' "$undo" | head -1)
  grep -v '^#' "$undo" | awk '{ l[NR] = $0 } END { for (i = NR; i >= 1; i--) print l[i] }' > "$work/undo.tsv"
  total=$(wc -l < "$work/undo.tsv" | tr -d ' ')
  echo "This puts $(n_comma "$total") file(s) back where they were before the sort."
  ask "Continue?" || { echo "Cancelled. Nothing was moved."; exit 0; }
  ok=0; skip=0
  while IFS=$'\t' read -r from to; do
    if [ -e "$to" ] && [ ! -e "$from" ] && mkdir -p "$(dirname "$from")" && mv -n "$to" "$from" && [ -e "$from" ]; then
      ok=$((ok + 1))
    else
      skip=$((skip + 1)); echo "  Skipped: $to" >&2
    fi
  done < "$work/undo.tsv"
  [ -n "$dest" ] && [ -d "$dest" ] && find "$dest" -depth -type d -empty -delete 2>/dev/null
  echo "Moved $(n_comma $ok) file(s) back.$([ $skip -gt 0 ] && echo " Skipped $skip (already moved or missing).")"
  exit 0
fi

# --------------------------------------------------------------------------- sort
command -v exiftool >/dev/null 2>&1 || die "exiftool is not installed. Run: brew install exiftool"
[ ${#args[@]} -ge 1 ] || args=(.)   # no folder given: sort the current folder
[ ${#args[@]} -le 2 ] || die "Too many folders. Usage: photosort [options] [SOURCE] [DEST]"
case "$by" in month|day|year) ;; *) die "--by must be month, day or year" ;; esac
case "$minyear" in 0|[12][0-9][0-9][0-9]) ;; *) die "--min-year needs a year, e.g. --min-year 2005" ;; esac
export PS_CAMERAS="$(printf '%s\n' "${IGNORE_CAMERAS[@]}")"

[ -d "${args[0]}" ] || die "'${args[0]}' is not a folder."
src=$(abspath "${args[0]}")
[ "$src" = "/" ] && die "Please pick a more specific folder than /."
if [ ${#args[@]} -eq 2 ]; then dest=$(abspath "${args[1]}"); else dest="$src (sorted)"; fi
case "$src/" in "$dest/"?*) die "DEST can't be a folder that contains SOURCE." ;; esac

# Prune hidden folders, Photos libraries, and DEST if it sits inside SOURCE
prune=( -name '*.photoslibrary' )
[ $all -eq 0 ] && prune+=( -o -name '.*' )
[ "$dest" != "$src" ] && prune+=( -o -path "$dest" )
if [ $all -eq 1 ]; then hidden=(); else hidden=( ! -name '.*' ); fi

find "$src" \( -type d ! -path "$src" \( "${prune[@]}" \) -prune \) -o \( -type f "${hidden[@]}" -print \) 2>/dev/null |
  awk -v media="$work/media.txt" -v side="$work/side.txt" '
    BEGIN {
      n = split("jpg jpeg heic heif png gif webp tif tiff bmp avif dng raw cr2 cr3 nef arw orf rw2 raf srw pef mov mp4 m4v 3gp avi mts m2ts mkv wmv mpg mpeg", a, " ")
      for (i = 1; i <= n; i++) M[a[i]] = 1
      S["aae"] = 1; S["xmp"] = 1
    }
    { k = split($0, p, "/"); name = p[k]; ext = ""
      if (match(name, /\.[^.]+$/) && RSTART > 1) ext = tolower(substr(name, RSTART + 1))
      if (ext in M) print > media; else if (ext in S) print > side; else other++ }
    END { print other + 0 }' > "$work/other.count"
touch "$work/media.txt" "$work/side.txt"
nmedia=$(wc -l < "$work/media.txt" | tr -d ' ')
nside=$(wc -l < "$work/side.txt" | tr -d ' ')
nother=$(cat "$work/other.count")

echo "Source:       $src"
echo "Destination:  $dest/"
echo
if [ "$nmedia" -eq 0 ]; then echo "No photos or videos found."; exit 0; fi
echo "Reading the date taken from $(n_comma "$nmedia") photos and videos..."

exiftool -q -q -m -fast -T -api QuickTimeUTC -d '%Y-%m-%d %H:%M:%S' \
  -Directory -FileName \
  -Keys:CreationDate -EXIF:DateTimeOriginal -XMP:DateTimeOriginal \
  -QuickTime:CreateDate -EXIF:CreateDate -XMP:DateCreated \
  -FileModifyDate -FileCreateDate -Model \
  -@ "$work/media.txt" 2>/dev/null |
  awk -v total="$nmedia" '{ print; if (NR % 25 == 0 || NR == total) printf "\r  %d / %d", NR, total > "/dev/stderr" }
    END { if (NR) printf "\n" > "/dev/stderr" }' > "$work/exif.tsv"

# Build the plan: path <TAB> folder <TAB> how the date was found <TAB> date
export PS_MAXYEAR=$(( $(date +%Y) + 1 )) PS_ORPHAN="$work/orphan.count"
awk -F'\t' -v by="$by" -v fallback="$fallback" -v minyear="$minyear" '
  function valid(d,  y) {
    if (d !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] /) return 0
    y = substr(d, 1, 4) + 0
    if (y < 1900 || y > ENVIRON["PS_MAXYEAR"] + 0) return 0
    if (substr(d, 1, 10) == "1904-01-01" || substr(d, 1, 10) == "1970-01-01") return 0
    return 1
  }
  function folder(d,  mm) {
    if (d == "") return "Unknown date"
    if (by == "year") return substr(d, 1, 4)
    mm = substr(d, 6, 2) "-" MONTH[substr(d, 6, 2) + 0]
    if (by == "day")  return substr(d, 1, 4) "/" mm "/" substr(d, 9, 2)
    return substr(d, 1, 4) "/" mm
  }
  function keyof(p,  k) { k = p; sub(/\.[^.\/]*$/, "", k); return tolower(k) }
  function ext(p,  e) { e = ""; if (match(p, /\.[^.\/]+$/)) e = tolower(substr(p, RSTART + 1)); return e }
  BEGIN {
    label[3] = "Apple creation date"; label[4] = "EXIF date taken"; label[5] = "XMP date taken"
    label[6] = "video creation date"; label[7] = "EXIF create date"; label[8] = "XMP date created"
    split("mov mp4 m4v 3gp", v, " "); for (i in v) VID[v[i]] = 1
    nc = split(ENVIRON["PS_CAMERAS"], cams, "\n"); for (i = 1; i <= nc; i++) if (cams[i] != "") IGNORECAM[tolower(cams[i])] = 1
    split("January February March April May June July August September October November December", MONTH, " ")
  }
  FILENAME == ARGV[1] {
    p = $1 "/" $2; d = ""; how = ""; why = "no date taken"
    if (tolower($11) in IGNORECAM) {
      why = $11 ", date taken ignored"                             # untrusted camera
    } else {
      for (i = 3; i <= 8; i++) if (valid($i)) {
        if (substr($i, 1, 4) + 0 < minyear) { why = "date taken before " minyear; continue }
        d = substr($i, 1, 19); how = label[i]; break
      }
    }
    if (d == "") WHY[p] = why
    if (d == "" && fallback) {
      if (valid($10))     { d = substr($10, 1, 19); how = "file Created date (" why ")" }
      else if (valid($9)) { d = substr($9, 1, 19);  how = "file Modified date (" why ")" }
    }
    D[p] = d; H[p] = how; next
  }
  FILENAME == ARGV[2] {
    n++; mp[n] = $0
    if (!($0 in D)) { D[$0] = ""; H[$0] = "" }
    if (!(ext($0) in VID) && D[$0] != "") photo[keyof($0)] = $0
    next
  }
  { sp[++ns] = $0 }
  END {
    for (i = 1; i <= n; i++) {
      p = mp[i]; k = keyof(p)
      if ((ext(p) in VID) && (k in photo)) { D[p] = D[photo[k]]; H[p] = "Live Photo, follows its photo" }
      f = folder(D[p]); if (!(k in F)) F[k] = f
      print p "\t" f "\t" (H[p] != "" ? H[p] : (p in WHY) ? WHY[p] : "no date taken") "\t" D[p]
    }
    for (i = 1; i <= ns; i++) {
      k = keyof(sp[i])
      if (k in F) print sp[i] "\t" F[k] "\t" "sidecar, follows its photo" "\t"
      else orphan++
    }
    print orphan + 0 > ENVIRON["PS_ORPHAN"]
  }' "$work/exif.tsv" "$work/media.txt" "$work/side.txt" > "$work/plan.tsv"

# --------------------------------------------------------------------------- preview
norphan=$(cat "$work/orphan.count" 2>/dev/null || echo 0)
nother=$((nother + norphan))
mkdir -p "$reports" || die "Could not create $reports"
stamp=$(date +%Y-%m-%d_%H%M%S)
preview="$reports/$stamp-preview.txt"

export PS_SRC="$src" PS_DEST="$dest"
awk -F'\t' '
  BEGIN { src = ENVIRON["PS_SRC"] "/"; print "# photosort preview. Source: " ENVIRON["PS_SRC"] "  Destination: " ENVIRON["PS_DEST"] }
  { p = $1; if (index(p, src) == 1) p = substr(p, length(src) + 1)
    printf "%-18s <- %s   (%s%s)\n", $2 "/", p, $3, ($4 != "" ? ", " $4 : "") }' "$work/plan.tsv" > "$preview"

read n_taken n_live n_fall n_unknown n_side <<< "$(awk -F'\t' '
  $3 ~ /^sidecar/ { s++; next } $3 ~ /^Live Photo/ { l++; next } $3 ~ /^file (Created|Modified) date/ { f++; next }
  $3 == "no date taken" || $3 ~ /^date taken before|date taken ignored$/ { u++; next } { t++ }
  END { printf "%d %d %d %d %d", t, l, f, u, s }' "$work/plan.tsv")"

echo
echo "Found $(n_comma "$nmedia") photos and videos$([ "$n_side" -gt 0 ] && echo " (+ $n_side sidecar files)")."
printf "  %-34s %7s\n" "Date taken found" "$(n_comma "$n_taken")"
[ "$n_live" -gt 0 ]    && printf "  %-34s %7s\n" "Live Photo videos (follow photo)" "$(n_comma "$n_live")"
[ "$n_fall" -gt 0 ]    && printf "  %-34s %7s\n" "Used Created date instead" "$(n_comma "$n_fall")"
[ "$n_unknown" -gt 0 ] && printf "  %-34s %7s   -> \"Unknown date\" folder\n" "No date taken" "$(n_comma "$n_unknown")"
[ "$nother" -gt 0 ]    && printf "  %-34s %7s   (left where they are)\n" "Other files, not photos/videos" "$(n_comma "$nother")"

echo
echo "By year:"
cut -f2 "$work/plan.tsv" | cut -d/ -f1 | sort | uniq -c |
  awk '{ n = $1; $1 = ""; sub(/^ /, ""); printf "  %-14s %7d\n", $0, n }'

echo
echo "Preview (first 10):"
grep -v '^#' "$preview" | head -n 10 | sed 's/^/  /'
echo "  Full list: $preview"

if [ "$n_unknown" -gt 0 ] && [ $fallback -eq 0 ]; then
  echo
  echo "Tip: run without --strict to date the $(n_comma "$n_unknown") undated file(s) by their Created date instead."
fi

if [ $go -eq 0 ]; then
  echo
  echo "This was only a preview. Nothing was moved."
  echo "To do it, run the same command with --go$([ $copy -eq 0 ] && echo " (or --go --copy to keep the originals)")."
  exit 0
fi

# --------------------------------------------------------------------------- execute
verb=Move; [ $copy -eq 1 ] && verb=Copy
total=$(wc -l < "$work/plan.tsv" | tr -d ' ')
echo
ask "$verb $(n_comma "$total") files into $dest/ ?" || { echo "Cancelled. Nothing was changed."; exit 0; }

log="$reports/$stamp-$( [ $copy -eq 1 ] && echo copy || echo move ).log"
{ echo "# photosort $( [ $copy -eq 1 ] && echo copy || echo move ) log, $(date '+%Y-%m-%d %H:%M')"
  echo "# source: $src"; echo "# dest: $dest"; } > "$log"

done_n=0; same=0; renamed=0; inplace=0; failed=0
: > "$work/identical.txt"
while IFS=$'\t' read -r path folder how date; do
  tdir="$dest/$folder"; name="${path##*/}"; target="$tdir/$name"
  if [ "$path" = "$target" ]; then inplace=$((inplace + 1)); continue; fi
  mkdir -p "$tdir" || { failed=$((failed + 1)); continue; }
  if [ -e "$target" ]; then
    if cmp -s "$path" "$target"; then same=$((same + 1)); echo "$path" >> "$work/identical.txt"; continue; fi
    base="${name%.*}"; ext="${name##*.}"; [ "$base" = "$name" ] && ext=""
    i=2; while [ -e "$tdir/$base ($i)${ext:+.$ext}" ]; do i=$((i + 1)); done
    target="$tdir/$base ($i)${ext:+.$ext}"; renamed=$((renamed + 1))
  fi
  if [ $copy -eq 1 ]; then cp -p "$path" "$target"; else mv -n "$path" "$target"; fi
  if [ -e "$target" ] && { [ $copy -eq 1 ] || [ ! -e "$path" ]; }; then
    printf '%s\t%s\n' "$path" "$target" >> "$log"; done_n=$((done_n + 1))
  else
    failed=$((failed + 1)); echo "  Could not $verb: $path" >&2
  fi
  [ $((done_n % 25)) -eq 0 ] && printf "\r  %sd %d / %d" "$( [ $copy -eq 1 ] && echo Copie || echo Move )" "$done_n" "$total"
done < "$work/plan.tsv"
printf "\r  %sd %d / %d\n" "$( [ $copy -eq 1 ] && echo Copie || echo Move )" "$done_n" "$total"

echo
echo "Done. $( [ $copy -eq 1 ] && echo Copied || echo Moved ) $(n_comma $done_n) file(s) into $dest/"
[ $renamed -gt 0 ] && echo "  $renamed file(s) had a different file with the same name already there, so they got a number, like \"IMG_1234 (2).jpg\"."
[ $inplace -gt 0 ] && echo "  $inplace file(s) were already in the right folder."
if [ $same -gt 0 ]; then
  cp "$work/identical.txt" "$reports/$stamp-identical.txt"
  echo "  $same file(s) were left in place because an identical copy is already in the destination."
  echo "    List: $reports/$stamp-identical.txt  (dupfinder can clean these up)"
fi
[ $failed -gt 0 ] && echo "  $failed could not be $( [ $copy -eq 1 ] && echo copied || echo moved ). See the messages above."
echo "  Log: $log"
[ $copy -eq 0 ] && echo "  To undo: photosort --undo \"$log\""

# Offer to remove source folders that are now empty (or only hold .DS_Store)
if [ $copy -eq 0 ]; then
  # A folder counts as empty if it only holds .DS_Store and folders that are themselves empty
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
    if ask "$nempty source folder(s) are now empty. Remove them?"; then
      while IFS= read -r d; do rm -f "$d/.DS_Store"; rmdir "$d" 2>/dev/null; done < "$work/empty.txt"
      echo "Removed the empty folders."
    fi
  fi
fi
