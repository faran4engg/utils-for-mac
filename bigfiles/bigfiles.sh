#!/bin/bash
# bigfiles - find the largest files in a folder and all its subfolders.
#
# Usage: bigfiles [options] [folder]
#   -n NUM          how many to list (default 20)
#   -m, --min SIZE  only files at least this big, e.g. 500K, 100M, 1.5G
#   -t, --type TYPE only one type: image, video, audio, pdf, archive, document, other
#   -d, --dirs      show the heaviest subfolders instead of files
#   -a, --all       include hidden files/folders and node_modules
#   -h, --help      show this help
#
# Always scans subfolders. Read-only: never moves or deletes anything.
# Sizes match Finder (1 GB = 1000 MB).

num=20; min=""; type=""; dirs=0; all=0; dir=""
while [ $# -gt 0 ]; do
  case "$1" in
    -n)         num="$2"; shift ;;
    -m|--min)   min="$2"; shift ;;
    -t|--type)  type=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]'); shift ;;
    -d|--dirs)  dirs=1 ;;
    -a|--all)   all=1 ;;
    -h|--help)  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)         echo "Unknown option: $1 (try -h)" >&2; exit 1 ;;
    *)
      if [ -n "$dir" ]; then echo "Please give one folder at a time." >&2; exit 1; fi
      dir="$1" ;;
  esac
  shift
done
dir="${dir:-.}"
[ "$dir" != "/" ] && dir="${dir%/}"

# --- validate input ---
if [ ! -d "$dir" ]; then echo "Error: '$dir' is not a folder." >&2; exit 1; fi
case "$num" in ''|*[!0-9]*) echo "Error: -n needs a number, e.g. -n 50" >&2; exit 1 ;; esac
min_bytes=0
if [ -n "$min" ]; then
  if [[ ! "$min" =~ ^[0-9]+(\.[0-9]+)?[KkMmGgTt]?[Bb]?$ ]]; then
    echo "Error: --min should look like 500K, 100M or 1.5G" >&2; exit 1
  fi
  min_bytes=$(awk -v s="${min%[Bb]}" 'BEGIN {
    u = toupper(substr(s, length(s))); n = s + 0
    if (u == "K") n *= 1e3; else if (u == "M") n *= 1e6
    else if (u == "G") n *= 1e9; else if (u == "T") n *= 1e12
    printf "%.0f", n }')
fi
case "$type" in
  ""|image|video|audio|pdf|archive|document|other) ;;
  *) echo "Error: type must be one of: image, video, audio, pdf, archive, document, other" >&2; exit 1 ;;
esac

data=$(mktemp); matched=$(mktemp); stats=$(mktemp)
trap 'rm -f "$data" "$matched" "$stats"' EXIT

# --- collect "size<TAB>path" for every file ---
if [ "$(uname)" = "Darwin" ]; then stat_args=(-f '%z%t%N'); else stat_args=(-c $'%s\t%n'); fi

# Apple Photos libraries are skipped (manage those inside Photos), always.
if [ $all -eq 1 ]; then
  find "$dir" \( -type d -name '*.photoslibrary' -prune \) -o \( -type f -print0 \)
else
  find "$dir" \( -type d ! -path "$dir" \( -name '.*' -o -name node_modules -o -name '*.photoslibrary' \) -prune \) \
       -o \( -type f ! -name '.*' -print0 \)
fi 2>/dev/null | xargs -0 stat "${stat_args[@]}" > "$data" 2>/dev/null

# --- classify by extension, apply filters ---
awk -F'\t' -v min="$min_bytes" -v want="$type" -v prefix="$dir/" -v stats="$stats" '
  BEGIN {
    split("jpg jpeg png heic heif gif webp tif tiff bmp svg psd raw dng cr2 cr3 nef arw orf rw2 raf", a, " "); for (i in a) cat[a[i]] = "image"
    split("mov mp4 m4v avi mkv webm 3gp mts m2ts wmv flv mpg mpeg", a, " ");                            for (i in a) cat[a[i]] = "video"
    split("mp3 m4a aac wav flac aif aiff ogg opus wma caf", a, " ");                                       for (i in a) cat[a[i]] = "audio"
    split("zip rar 7z tar gz tgz bz2 xz dmg iso pkg xip", a, " ");                                         for (i in a) cat[a[i]] = "archive"
    split("doc docx xls xlsx ppt pptx pages numbers key txt rtf csv md odt ods odp epub", a, " ");        for (i in a) cat[a[i]] = "document"
    cat["pdf"] = "pdf"
  }
  {
    size = $1; path = $2
    scanned++; scanned_bytes += size
    n = split(path, parts, "/"); name = parts[n]; ext = ""
    if (match(name, /\.[^.]+$/) && RSTART > 1) ext = tolower(substr(name, RSTART + 1))
    c = (ext in cat) ? cat[ext] : "other"
    if (size < min) next
    if (want != "" && c != want) next
    if (substr(path, 1, length(prefix)) == prefix) path = substr(path, length(prefix) + 1)
    print size "\t" c "\t" path
  }
  END { print scanned + 0 "\t" scanned_bytes + 0 > stats }' "$data" > "$matched"

# --- helpers for output ---
fmt='function human(b,  u, i) { split("B KB MB GB TB", u, " "); i = 1
       while (b >= 1000 && i < 5) { b /= 1000; i++ }
       return (i == 1) ? sprintf("%d B", b) : sprintf("%.1f %s", b, u[i]) }
     function commas(n,  s) { s = sprintf("%d", n); while (s ~ /[0-9]{4}/) sub(/[0-9][0-9][0-9]($|,)/, ",&", s); return s }'

read scanned scanned_bytes < "$stats"
read m_count m_bytes <<< "$(awk -F'\t' '{ n++; b += $1 } END { printf "%d %.0f", n, b }' "$matched")"

# --- header ---
echo "Folder:   $(cd "$dir" && pwd)"
if [ $all -eq 1 ]; then scope="all subfolders, including hidden ones and node_modules"
else scope="all subfolders (skipping hidden folders and node_modules; -a to include)"; fi
awk -v n="$scanned" -v b="$scanned_bytes" -v s="$scope" "$fmt"' BEGIN { printf "Scanned:  %s files, %s  %s\n", commas(n), human(b), "— " s }'

filters=""
[ -n "$type" ] && filters="$type files only"
[ -n "$min" ] && filters="${filters:+$filters, }at least $min"
if [ -n "$filters" ]; then
  awk -v n="$m_count" -v b="$m_bytes" -v f="$filters" "$fmt"' BEGIN { printf "Matching: %s files, %s  (%s)\n", commas(n), human(b), f }'
fi

find "$dir" -type d -name '*.photoslibrary' -prune 2>/dev/null | while IFS= read -r lib; do
  kb=$(du -sk "$lib" 2>/dev/null | cut -f1)
  awk -v k="${kb:-0}" -v p="$lib" "$fmt"' BEGIN { printf "Skipped:  Photos library %s (%s) — manage it in the Photos app\n", p, human(k * 1024) }'
done

if [ "${m_count:-0}" -eq 0 ]; then echo; echo "No matching files."; exit 0; fi

# --- main list ---
echo
if [ $dirs -eq 1 ]; then
  echo "Heaviest subfolders (top $num)"
  echo "  -------------------------------------------------------"
  awk -F'\t' '{
      n = index($3, "/")
      key = n ? substr($3, 1, n - 1) "/" : "(files directly in this folder)"
      size[key] += $1; cnt[key]++
    } END { for (k in size) printf "%.0f\t%d\t%s\n", size[k], cnt[k], k }' "$matched" |
    sort -t$'\t' -k1,1nr | head -n "$num" |
    awk -F'\t' -v total="$m_bytes" "$fmt"' {
      printf "  %10s  %3d%%  %7s files  %s\n", human($1), total ? $1 * 100 / total : 0, commas($2), $3 }'
  echo
  echo "  Tip: run bigfiles -d on a subfolder to drill down."
else
  echo "Largest files (top $num)"
  echo "  -------------------------------------------------------"
  sort -t$'\t' -k1,1nr "$matched" | head -n "$num" |
    awk -F'\t' -v total="$m_bytes" "$fmt"' {
      printf "  %10s  %-9s %s\n", human($1), $2, $3; shown += $1; n++ }
      END { printf "\n  Shown: %d files, %s (%.0f%% of matching)\n", n, human(shown), total ? shown * 100 / total : 0 }'
fi

# --- by type ---
echo
echo "By type"
echo "  -------------------------------------------------------"
awk -F'\t' '{ size[$2] += $1; cnt[$2]++ } END { for (c in size) printf "%.0f\t%d\t%s\n", size[c], cnt[c], c }' "$matched" |
  sort -t$'\t' -k1,1nr |
  awk -F'\t' "$fmt"' { printf "  %-9s %10s  %7s files\n", $3, human($1), commas($2) }'
