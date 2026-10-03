#!/bin/bash
# filesummary - count files in a folder by extension and by actual content type.
#
# Usage: filesummary [options] [folder]
#   -r, --recursive   include all subfolders
#   -a, --all         also count hidden files/folders (.git, .env...) and node_modules
#   -h, --help        show this help
#
# Options can go before or after the folder, e.g. "filesummary ~/code -r".
# With no folder, the current folder is used.

recursive=0
all=0
dir=""
for arg in "$@"; do
  case "$arg" in
    -r|--recursive) recursive=1 ;;
    -a|--all)       all=1 ;;
    -ra|-ar)        recursive=1; all=1 ;;
    -h|--help)      sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)             echo "Unknown option: $arg (try -h)" >&2; exit 1 ;;
    *)
      if [ -n "$dir" ]; then echo "Please give one folder at a time." >&2; exit 1; fi
      dir="$arg" ;;
  esac
done
dir="${dir:-.}"

if [ ! -d "$dir" ]; then
  echo "Error: '$dir' is not a folder." >&2
  exit 1
fi

list=$(mktemp); mimes=$(mktemp)
trap 'rm -f "$list" "$mimes"' EXIT

# 1. Build the list of files
if [ $recursive -eq 0 ]; then
  if [ $all -eq 1 ]; then
    find "$dir" -maxdepth 1 -type f > "$list"
  else
    find "$dir" -maxdepth 1 -type f ! -name '.*' > "$list"
  fi
elif [ $all -eq 1 ]; then
  find "$dir" -type f > "$list"
else
  # Skip hidden folders (.git, .next...) and node_modules, which would flood the counts
  find "$dir" \( -type d ! -path "$dir" \( -name '.*' -o -name node_modules \) -prune \) \
       -o \( -type f ! -name '.*' -print \) > "$list"
fi

total=$(wc -l < "$list" | tr -d ' ')

# 2. Detect real types in one batch (much faster than one call per file)
if [ "$total" -gt 0 ]; then
  file --mime-type -b -f "$list" > "$mimes" 2>/dev/null
fi

# 3. Header
echo "Folder: $(cd "$dir" && pwd)"
if [ $recursive -eq 1 ]; then
  if [ $all -eq 1 ]; then echo "Scope:  all subfolders, including hidden ones and node_modules"
  else echo "Scope:  all subfolders (skipping hidden folders and node_modules; add -a to include)"; fi
else
  echo "Scope:  this folder only"
fi
echo "Total files: $total"

if [ $recursive -eq 0 ]; then
  subs=$(find "$dir" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | wc -l | tr -d ' ')
  if [ "$subs" -gt 0 ]; then
    echo "Note: $subs subfolder(s) were not scanned. Add -r to include them."
  fi
fi

[ "$total" -eq 0 ] && exit 0

# 4. Pair each file's extension with its category
paste "$list" "$mimes" | awk -F'\t' '
  {
    n = split($1, parts, "/"); name = parts[n]; mime = $2
    ext = "(no extension)"
    if (match(name, /\.[^.]*$/) && RSTART > 1 && RLENGTH > 1) ext = tolower(substr(name, RSTART + 1))

    if (ext == "svg" && mime ~ /svg|xml|plain|html/)                     cat = "Image"
    else if (mime ~ /^image\//)                                           cat = "Image"
    else if (mime ~ /^video\//)                                           cat = "Video"
    else if (mime ~ /^audio\//)                                           cat = "Audio"
    else if (mime == "application/pdf")                                   cat = "PDF"
    else if (mime ~ /^text\// || mime ~ /javascript|json|xml|x-sh|ecmascript|typescript/) cat = "Text / Code"
    else if (mime ~ /zip|gzip|x-tar|bzip2|x-xz|7z|rar/)                   cat = "Archive"
    else if (mime ~ /msword|vnd\.ms-|openxmlformats|opendocument|rtf/)    cat = "Document"
    else if (mime ~ /font/)                                               cat = "Font"
    else if (mime == "inode/x-empty")                                     cat = "Empty file"
    else                                                                  cat = "Other (" mime ")"
    print ext "\t" cat
  }' > "$mimes.pairs"
trap 'rm -f "$list" "$mimes" "$mimes.pairs"' EXIT

print_table() {
  cut -f"$1" "$mimes.pairs" | sort | uniq -c | sort -rn |
    awk '{ n=$1; $1=""; sub(/^ /, ""); printf "  %-28s %6d\n", $0, n }'
}

echo
echo "By extension"
echo "  ----------------------------------"
print_table 1
echo
echo "By actual type (detected from file contents)"
echo "  ----------------------------------"
print_table 2
