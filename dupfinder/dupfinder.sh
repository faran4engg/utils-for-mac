#!/bin/bash
# dupfinder - find exact duplicate files, review them, then move the extras to the Trash.
#
# 1) Scan:    dupfinder [options] [folder ...]
#      -m, --min SIZE    ignore files smaller than this, e.g. 100K or 1M
#      -p, --prefer DIR  when suggesting which copy to keep, prefer copies inside DIR
#      -o, --out DIR     where to save reports (default: ~/dupfinder-reports)
#      -a, --all         include hidden files/folders and node_modules
#      --no-open         don't open the review page automatically
# 2) Review:  use review.html (opens in Safari) and click "Download decisions",
#             or edit report.txt and change KEEP / REMOVE by hand.
# 3) Apply:   dupfinder --apply FILE [-y]
#      Re-checks every file, then moves the ones marked REMOVE to the Trash.
#      Asks before doing anything (-y skips the question).
#
# Scans all subfolders. Never deletes permanently. Apple Photos libraries are skipped.

IS_MAC=0; [ "$(uname)" = "Darwin" ] && IS_MAC=1

FMT='function human(b,  u, i) { split("B KB MB GB TB", u, " "); i = 1
       while (b >= 1000 && i < 5) { b /= 1000; i++ }
       return (i == 1) ? sprintf("%d B", b) : sprintf("%.1f %s", b, u[i]) }
     function commas(n,  s) { s = sprintf("%d", n)
       while (s ~ /[0-9][0-9][0-9][0-9]/) sub(/[0-9][0-9][0-9]($|,)/, ",&", s); return s }'

die()     { echo "Error: $*" >&2; exit 1; }
n_human() { awk -v n="$1" "$FMT"' BEGIN { print human(n) }'; }
n_comma() { awk -v n="$1" "$FMT"' BEGIN { print commas(n) }'; }

# Reads NUL-separated paths, prints "md5<TAB>path"
hash_files() {
  if [ $IS_MAC -eq 1 ]; then
    xargs -0 md5 -r 2>/dev/null | awk '{ print substr($0, 1, 32) "\t" substr($0, 34) }'
  else
    xargs -0 md5sum 2>/dev/null | awk '{ print substr($0, 1, 32) "\t" substr($0, 35) }'
  fi
}

# Passes lines through, showing "label N / total" on the terminal
progress() {
  awk -v total="$1" -v label="$2" '{ print
      if (NR % 20 == 0 || NR == total) printf "\r  %s %d / %d files", label, NR, total > "/dev/stderr" }
    END { if (NR) printf "\n" > "/dev/stderr" }'
}

file_size() {
  if [ $IS_MAC -eq 1 ]; then stat -f '%z' "$@"; else stat -c '%s' "$@"; fi
}

# --------------------------------------------------------------------------- args
mode=scan; report=""; yes=0; min=""; prefer=""; out="$HOME/dupfinder-reports"; all=0; open=1; dirs=()
while [ $# -gt 0 ]; do
  case "$1" in
    --apply)      mode=apply; report="$2"; shift ;;
    -y|--yes)     yes=1 ;;
    -m|--min)     min="$2"; shift ;;
    -p|--prefer)  prefer="$2"; shift ;;
    -o|--out)     out="$2"; shift ;;
    -a|--all)     all=1 ;;
    --no-open)    open=0 ;;
    -h|--help)    sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)           die "Unknown option: $1 (try -h)" ;;
    *)            dirs+=("$1") ;;
  esac
  shift
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# --------------------------------------------------------------------------- scan
scan() {
  [ ${#dirs[@]} -eq 0 ] && dirs=(.)
  local abs=() d
  for d in "${dirs[@]}"; do
    [ -d "$d" ] || die "'$d' is not a folder."
    abs+=("$(cd "$d" && pwd -P)")
  done

  export DF_PREFER=""
  if [ -n "$prefer" ]; then
    [ -d "$prefer" ] || die "--prefer: '$prefer' is not a folder."
    DF_PREFER=$(cd "$prefer" && pwd -P)
  fi

  local min_bytes=1
  if [ -n "$min" ]; then
    [[ "$min" =~ ^[0-9]+(\.[0-9]+)?[KkMmGgTt]?[Bb]?$ ]] || die "--min should look like 100K, 5M or 1G"
    min_bytes=$(awk -v s="${min%[Bb]}" 'BEGIN { u = toupper(substr(s, length(s))); n = s + 0
      if (u == "K") n *= 1e3; else if (u == "M") n *= 1e6; else if (u == "G") n *= 1e9; else if (u == "T") n *= 1e12
      if (n < 1) n = 1; printf "%.0f", n }')
  fi

  local stat_args
  if [ $IS_MAC -eq 1 ]; then stat_args=(-f '%z%t%B%t%m%t%N'); else stat_args=(-c $'%s\t%W\t%Y\t%n'); fi

  echo "Scanning ${#abs[@]} folder(s), including all subfolders..."
  for d in "${abs[@]}"; do
    if [ $all -eq 1 ]; then
      find "$d" \( -type d -name '*.photoslibrary' -prune \) -o \( -type f -print0 \)
    else
      find "$d" \( -type d ! -path "$d" \( -name '.*' -o -name node_modules -o -name '*.photoslibrary' \) -prune \) \
           -o \( -type f ! -name '.*' -print0 \)
    fi
  done 2>/dev/null | xargs -0 stat "${stat_args[@]}" 2>/dev/null |
    awk -F'\t' '{ p = $4; for (i = 5; i <= NF; i++) p = p "\t" $i } !seen[p]++' > "$work/all.tsv"

  local scanned ncand
  scanned=$(wc -l < "$work/all.tsv" | tr -d ' ')
  awk -F'\t' -v min="$min_bytes" '$1 + 0 >= min + 0' "$work/all.tsv" > "$work/sized.tsv"
  awk -F'\t' 'NR == FNR { c[$1]++; next } c[$1] > 1' "$work/sized.tsv" "$work/sized.tsv" > "$work/cand.tsv"
  ncand=$(wc -l < "$work/cand.tsv" | tr -d ' ')

  echo "Scanned $(n_comma "$scanned") files. $(n_comma "$ncand") have the same size as another file, comparing their contents..."
  if [ "$ncand" -eq 0 ]; then echo "No duplicates found."; exit 0; fi

  awk -F'\t' '{ p = $4; for (i = 5; i <= NF; i++) p = p "\t" $i; print p }' "$work/cand.tsv" |
    tr '\n' '\0' | hash_files | progress "$ncand" "Comparing" > "$work/hash.tsv"

  # Group identical files and suggest which copy to keep:
  #   1. inside --prefer folder   2. name doesn't look like a copy ("x copy", "x (1)")
  #   3. oldest file              4. shortest path
  awk -F'\t' '
    function penalty(p,  n, parts, base, pen) {
      pen = 0
      if (ENVIRON["DF_PREFER"] != "" && index(p, ENVIRON["DF_PREFER"] "/") != 1) pen += 100
      n = split(p, parts, "/"); base = tolower(parts[n]); sub(/\.[^.]*$/, "", base)
      if (base ~ / copy( [0-9]+)?$/ || base ~ /\([0-9]+\)$/ || base ~ /^copy of /) pen += 10
      return pen
    }
    function better(k, a, b,  pa, pb) {
      pa = penalty(mp[k, a]); pb = penalty(mp[k, b])
      if (pa != pb) return pa < pb
      if (mb[k, a] != mb[k, b]) return mb[k, a] < mb[k, b]
      if (length(mp[k, a]) != length(mp[k, b])) return length(mp[k, a]) < length(mp[k, b])
      return mp[k, a] < mp[k, b]
    }
    FILENAME == ARGV[1] { h[substr($0, 34)] = substr($0, 1, 32); next }
    {
      p = $4; for (i = 5; i <= NF; i++) p = p "\t" $i
      if (!(p in h)) next
      key = h[p] SUBSEP $1
      n = ++cnt[key]; mp[key, n] = p; mm[key, n] = $3 + 0
      mb[key, n] = ($2 + 0 > 0) ? $2 + 0 : $3 + 0
      sz[key] = $1 + 0; hh[key] = h[p]
    }
    END {
      for (key in cnt) {
        if (cnt[key] < 2) continue
        best = 1
        for (i = 2; i <= cnt[key]; i++) if (better(key, i, best)) best = i
        for (i = 1; i <= cnt[key]; i++)
          printf "%.0f\t%s\t%.0f\t%d\t%s\t%d\t%s\n", sz[key] * (cnt[key] - 1), hh[key], sz[key], cnt[key],
                 (i == best ? "KEEP" : "REMOVE"), mm[key, i], mp[key, i]
      }
    }' "$work/hash.tsv" "$work/cand.tsv" | sort -t$'\t' -k1,1nr -k2,2 -k5,5 -k7 > "$work/groups.tsv"

  if [ ! -s "$work/groups.tsv" ]; then echo "No duplicates found."; exit 0; fi

  local ngroups nextra freed
  read ngroups nextra freed <<< "$(awk -F'\t' '!g[$2]++ { n++ } $5 == "REMOVE" { e++; b += $3 }
    END { printf "%d %d %.0f", n, e, b }' "$work/groups.tsv")"

  local outdir
  outdir="$out/$(date +%Y-%m-%d_%H%M%S)"
  mkdir -p "$outdir" || die "Could not create '$outdir'."
  outdir=$(cd "$outdir" && pwd -P)

  export DF_REPORT="$outdir/report.txt" DF_DATA="$work/data.txt" DF_CREATED="$(date '+%Y-%m-%d %H:%M')"
  export DF_DIRS="$(printf '%s\n' "${abs[@]}")" DF_HOME="$HOME"
  export DF_SUMMARY="$ngroups duplicate groups, $nextra extra copies, $(n_human "$freed") can be freed"

  awk -F'\t' "$FMT"'
    function enc(s) { gsub(/%/, "%25", s); gsub(/</, "%3C", s); return s }
    BEGIN {
      rep = ENVIRON["DF_REPORT"]; dat = ENVIRON["DF_DATA"]
      nd = split(ENVIRON["DF_DIRS"], dirs, "\n"); list = ""
      for (i = 1; i <= nd; i++) if (dirs[i] != "") { list = list (list == "" ? "" : ", ") dirs[i]; print "D\t" enc(dirs[i]) > dat }
      print "M\tcreated\t" ENVIRON["DF_CREATED"] > dat
      print "M\thome\t" enc(ENVIRON["DF_HOME"]) > dat
      print "M\treport\t" enc(rep) > dat
      print "# dupfinder report, created " ENVIRON["DF_CREATED"] > rep
      print "# Scanned: " list > rep
      print "# " ENVIRON["DF_SUMMARY"] > rep
      print "#" > rep
      print "# Change KEEP / REMOVE below as you like. Every group must keep at least one file." > rep
      print "# Then run:" > rep
      print "#   dupfinder --apply \"" rep "\"" > rep
      print "# Files marked REMOVE are moved to the Trash (not deleted) after a safety re-check." > rep
    }
    {
      p = $7; for (i = 8; i <= NF; i++) p = p "\t" $i
      if ($2 != last) {
        last = $2; g++
        printf "\n## Group %d: %d copies, %s each, md5 %s\n", g, $4, human($3), $2 > rep
        print "G\t" g "\t" $2 "\t" $3 "\t" $4 > dat
      }
      printf "%-7s %s\n", $5, p > rep
      print "F\t" $5 "\t" $6 "\t" enc(p) > dat
    }' "$work/groups.tsv"

  write_html "$outdir/review.html"

  echo
  echo "Found $DF_SUMMARY."
  echo
  echo "Biggest groups:"
  awk -F'\t' "$FMT"' $5 == "KEEP" && n < 5 { n++; k = split($7, parts, "/")
      printf "  %10s to free   %d copies of %s\n", human($1), $4, parts[k] }' "$work/groups.tsv"
  echo
  echo "Report:       $outdir/report.txt"
  echo "Review page:  $outdir/review.html"
  echo
  echo "Next: review the suggestions, then run ONE of these:"
  echo "  dupfinder --apply ~/Downloads/dupfinder-decisions.txt   # if you used the review page"
  echo "  dupfinder --apply \"$outdir/report.txt\"   # if you edited the text report"

  if [ $open -eq 1 ] && [ $IS_MAC -eq 1 ]; then
    open -a Safari "$outdir/review.html" 2>/dev/null || open "$outdir/review.html"
  fi
}

# --------------------------------------------------------------------------- review page
write_html() {
  {
cat << 'HTML1'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Duplicate review</title>
<style>
:root {
  --bg: #d9dad6; --panel: #f4f4f1; --frame: #ffffff; --ink: #1d1f22; --muted: #5b5f64;
  --line: #b7b9b3; --keep: #0e6b66; --remove: #a8233f;
  font-family: "Avenir Next", Avenir, "Segoe UI", system-ui, sans-serif;
  color: var(--ink); background: var(--bg);
}
@media (prefers-color-scheme: dark) {
  :root { --bg: #2b2c2e; --panel: #35373a; --frame: #3e4044; --ink: #ecebe6; --muted: #a6a9ad;
          --line: #4c4f53; --keep: #4fb3aa; --remove: #e5677f; }
}
body { margin: 0; }
.bar { position: sticky; top: 0; z-index: 5; display: flex; flex-wrap: wrap; align-items: center;
       justify-content: space-between; gap: 12px 24px; padding: 12px 24px;
       background: var(--panel); border-bottom: 1px solid var(--line); }
.bar h1 { margin: 0; font-size: 1.125rem; font-weight: 600; }
.status { margin: 2px 0 0; color: var(--muted); font-size: .875rem; font-variant-numeric: tabular-nums; }
.status b { color: var(--remove); font-weight: 600; }
.actions { display: flex; gap: 8px; flex-wrap: wrap; }
button { font: inherit; font-size: .875rem; cursor: pointer; padding: 7px 14px; border-radius: 6px;
         border: 1px solid var(--line); background: transparent; color: var(--ink); }
button.primary { background: var(--ink); color: var(--panel); border-color: var(--ink); }
button:focus-visible, a:focus-visible { outline: 2px solid var(--keep); outline-offset: 2px; }
main { max-width: 1280px; margin: 0 auto; padding: 24px; }
.howto { max-width: 72ch; margin: 0 0 32px; line-height: 1.5; }
.howto ol { margin: 0; padding-left: 1.25rem; }
.next { display: none; margin: 0 0 32px; padding: 14px 16px; border-left: 4px solid var(--keep);
        background: var(--panel); line-height: 1.6; }
.next.show { display: block; }
code { font-family: ui-monospace, Menlo, monospace; font-size: .8125rem; background: var(--panel);
       padding: 2px 6px; border-radius: 4px; word-break: break-all; }
.next code { background: var(--bg); }
.group { margin: 0 0 40px; }
.group h2 { margin: 0 0 2px; font-size: 1rem; font-weight: 600; word-break: break-all; }
.group > p { margin: 0 0 12px; color: var(--muted); font-size: .875rem; }
.frames { display: grid; grid-template-columns: repeat(auto-fill, minmax(220px, 1fr)); gap: 16px; }
.frame { margin: 0; display: flex; flex-direction: column; gap: 8px; padding: 10px 10px 12px;
         background: var(--frame); border-top: 4px solid var(--keep); border-radius: 2px; }
.frame.remove { border-top-color: var(--remove); }
.frame.remove .thumb > * { filter: grayscale(1); opacity: .4; }
.thumb { position: relative; display: grid; place-items: center; aspect-ratio: 4 / 3; overflow: hidden;
         color: var(--muted); text-decoration: none;
         background: repeating-conic-gradient(#8881 0 25%, transparent 0 50%) 0 0 / 16px 16px; }
.thumb img, .thumb video { width: 100%; height: 100%; object-fit: contain; }
.thumb.video::after { content: "▶"; position: absolute; right: 8px; bottom: 6px; font-size: .75rem;
                      color: #fff; background: #0008; padding: 2px 6px; border-radius: 3px; }
.ext { font-size: 1.5rem; font-weight: 600; }
.nopreview { font-size: .75rem; padding: 0 12px; text-align: center; }
figcaption { font-family: "Avenir Next Condensed", "Avenir Next", sans-serif; font-size: .8125rem;
             line-height: 1.35; word-break: break-all; }
.dir { color: var(--muted); }
.name { font-weight: 600; }
.date { display: block; margin-top: 2px; color: var(--muted); }
.choice { display: grid; grid-template-columns: 1fr 1fr; margin-top: auto; border: 1px solid var(--line);
          border-radius: 6px; overflow: hidden; }
.choice button { border: 0; border-radius: 0; padding: 6px; }
.choice button[aria-pressed="true"][data-a="KEEP"] { background: var(--keep); color: #fff; }
.choice button[aria-pressed="true"][data-a="REMOVE"] { background: var(--remove); color: #fff; }
.toast { position: fixed; left: 50%; bottom: 24px; transform: translateX(-50%); max-width: 90vw;
         padding: 10px 16px; border-radius: 6px; background: var(--ink); color: var(--panel);
         opacity: 0; transition: opacity .2s; pointer-events: none; }
.toast.show { opacity: 1; }
@media (prefers-reduced-motion: reduce) { .toast { transition: none; } }
@media (max-width: 600px) { .bar, main { padding-left: 14px; padding-right: 14px; } }
</style>
</head>
<body>
<header class="bar">
  <div>
    <h1 id="title">Duplicate review</h1>
    <p class="status" id="status"></p>
  </div>
  <div class="actions">
    <button type="button" id="reset">Reset to suggestions</button>
    <button type="button" class="primary" id="download">Download decisions</button>
  </div>
</header>
<main>
  <section class="howto">
    <ol>
      <li>Check each group below. Each card is an identical copy of the same file. Green means keep, red means move to the Trash.</li>
      <li>Click <b>Download decisions</b> when you're happy with your choices.</li>
      <li>In Terminal, run <code>dupfinder --apply ~/Downloads/dupfinder-decisions.txt</code>. It re-checks every file and asks before moving anything.</li>
    </ol>
  </section>
  <section class="next" id="next">
    Saved <b>dupfinder-decisions.txt</b> to your Downloads folder. Now run this in Terminal:<br>
    <code id="cmd">dupfinder --apply ~/Downloads/dupfinder-decisions.txt</code>
    <button type="button" id="copy">Copy command</button><br>
    If Safari renamed the file (for example <i>dupfinder-decisions-2.txt</i>), use that name instead.
  </section>
  <div id="groups"></div>
</main>
<div class="toast" id="toast" role="status" aria-live="polite"></div>
<script type="text/plain" id="dupdata">
HTML1
cat "$DF_DATA"
cat << 'HTML2'
</script>
<script>
(() => {
  const dec = s => decodeURIComponent(s);
  const meta = { dirs: [] }, groups = [];
  let cur = null;
  for (const line of document.getElementById('dupdata').textContent.split('\n')) {
    if (!line) continue;
    const f = line.split('\t');
    if (f[0] === 'M') meta[f[1]] = f.slice(2).join('\t');
    else if (f[0] === 'D') meta.dirs.push(dec(f.slice(1).join('\t')));
    else if (f[0] === 'G') { cur = { num: +f[1], hash: f[2], size: +f[3], files: [] }; groups.push(cur); }
    else if (f[0] === 'F' && cur) cur.files.push({ suggested: f[1], action: f[1], mtime: +f[2], path: dec(f.slice(3).join('\t')) });
  }
  const home = meta.home ? dec(meta.home) : '';

  const IMG = new Set(['jpg','jpeg','png','gif','webp','heic','heif','tif','tiff','bmp','svg','avif']);
  const VID = new Set(['mov','mp4','m4v','webm','3gp']);
  const human = b => { const u = ['B','KB','MB','GB','TB']; let i = 0; while (b >= 1000 && i < 4) { b /= 1000; i++; } return i ? b.toFixed(1) + ' ' + u[i] : b + ' B'; };
  const ext = p => { const n = p.split('/').pop(); const i = n.lastIndexOf('.'); return i > 0 ? n.slice(i + 1).toLowerCase() : ''; };
  const pretty = p => home && p.startsWith(home + '/') ? '~' + p.slice(home.length) : p;
  const fileURL = p => 'file://' + p.split('/').map(encodeURIComponent).join('/');
  const el = (tag, cls, text) => { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; };

  const names = meta.dirs.map(d => d.split('/').pop() || d);
  document.getElementById('title').textContent = 'Duplicates in ' + names.join(', ');
  document.title = 'Duplicate review: ' + names.join(', ');

  const toast = document.getElementById('toast');
  let toastTimer;
  const say = msg => { toast.textContent = msg; toast.classList.add('show'); clearTimeout(toastTimer); toastTimer = setTimeout(() => toast.classList.remove('show'), 3200); };

  const io = new IntersectionObserver(entries => {
    for (const e of entries) if (e.isIntersecting) { const m = e.target; m.src = m.dataset.src; io.unobserve(m); }
  }, { rootMargin: '800px' });

  function updateStatus() {
    let n = 0, bytes = 0;
    for (const g of groups) for (const f of g.files) if (f.action === 'REMOVE') { n++; bytes += g.size; }
    const s = document.getElementById('status');
    s.innerHTML = '';
    s.append(groups.length + ' groups. Marked for the Trash: ');
    s.append(el('b', null, n + ' files, ' + human(bytes)));
  }

  function setAction(g, f, card, action) {
    if (action === 'REMOVE' && f.action === 'KEEP' && g.files.filter(x => x.action === 'KEEP').length === 1) {
      say('Each group needs at least one kept copy. Mark another copy Keep first.');
      return;
    }
    f.action = action;
    card.classList.toggle('remove', action === 'REMOVE');
    for (const b of card.querySelectorAll('.choice button')) b.setAttribute('aria-pressed', String(b.dataset.a === action));
    updateStatus();
  }

  const host = document.getElementById('groups');
  const cards = [];
  for (const g of groups) {
    const sec = el('section', 'group');
    const first = g.files[0].path.split('/').pop();
    sec.append(el('h2', null, first));
    sec.append(el('p', null, g.files.length + ' identical copies of ' + human(g.size) + '. Removing the extras frees ' + human(g.size * (g.files.length - 1)) + '.'));
    const grid = el('div', 'frames');
    for (const f of g.files) {
      const card = el('figure', 'frame' + (f.action === 'REMOVE' ? ' remove' : ''));
      const x = ext(f.path);
      const thumb = el('a', 'thumb');
      thumb.href = fileURL(f.path); thumb.target = '_blank'; thumb.title = 'Open ' + f.path;
      if (IMG.has(x) || VID.has(x)) {
        const m = document.createElement(IMG.has(x) ? 'img' : 'video');
        m.dataset.src = fileURL(f.path) + (VID.has(x) ? '#t=0.1' : '');
        if (VID.has(x)) { m.muted = true; m.preload = 'metadata'; m.playsInline = true; thumb.classList.add('video'); }
        else { m.alt = ''; m.decoding = 'async'; }
        m.addEventListener('error', () => { m.replaceWith(el('span', 'nopreview', 'No preview in this browser. Open this page in Safari.')); thumb.classList.remove('video'); });
        thumb.append(m); io.observe(m);
      } else {
        thumb.append(el('span', 'ext', x ? '.' + x : 'file'));
      }
      const cap = el('figcaption');
      const p = pretty(f.path), cut = p.lastIndexOf('/') + 1;
      cap.append(el('span', 'dir', p.slice(0, cut)), el('span', 'name', p.slice(cut)));
      cap.append(el('span', 'date', 'Modified ' + new Date(f.mtime * 1000).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' })));
      const choice = el('div', 'choice'); choice.setAttribute('role', 'group'); choice.setAttribute('aria-label', 'Keep or remove');
      for (const [a, label] of [['KEEP', 'Keep'], ['REMOVE', 'Remove']]) {
        const b = el('button', null, label); b.type = 'button'; b.dataset.a = a; b.setAttribute('aria-pressed', String(f.action === a));
        b.addEventListener('click', () => setAction(g, f, card, a));
        choice.append(b);
      }
      card.append(thumb, cap, choice);
      grid.append(card);
      cards.push([g, f, card]);
    }
    sec.append(grid);
    host.append(sec);
  }
  updateStatus();

  document.getElementById('reset').addEventListener('click', () => {
    for (const [g, f, card] of cards) { f.action = 'KEEP'; }
    for (const [g, f, card] of cards) setAction(g, f, card, f.suggested);
    say('Back to the suggested choices.');
  });

  document.getElementById('download').addEventListener('click', () => {
    let t = '# dupfinder decisions, exported from the review page on ' + new Date().toLocaleString() + '\n'
          + '# Scanned: ' + meta.dirs.join(', ') + '\n#\n'
          + '# Apply with:  dupfinder --apply ~/Downloads/dupfinder-decisions.txt\n'
          + '# Files marked REMOVE are moved to the Trash (not deleted) after a safety re-check.\n';
    for (const g of groups) {
      t += '\n## Group ' + g.num + ': ' + g.files.length + ' copies, ' + human(g.size) + ' each, md5 ' + g.hash + '\n';
      for (const f of g.files) t += f.action.padEnd(7) + ' ' + f.path + '\n';
    }
    const a = document.createElement('a');
    a.href = URL.createObjectURL(new Blob([t], { type: 'text/plain' }));
    a.download = 'dupfinder-decisions.txt';
    document.body.append(a); a.click(); a.remove();
    document.getElementById('next').classList.add('show');
    document.getElementById('next').scrollIntoView({ block: 'nearest' });
  });

  document.getElementById('copy').addEventListener('click', async () => {
    const text = document.getElementById('cmd').textContent;
    try { await navigator.clipboard.writeText(text); say('Command copied.'); }
    catch { const r = document.createRange(); r.selectNodeContents(document.getElementById('cmd'));
            const s = getSelection(); s.removeAllRanges(); s.addRange(r); say('Press Cmd+C to copy the selected command.'); }
  });
})();
</script>
</body>
</html>
HTML2
  } > "$1"
}

# --------------------------------------------------------------------------- apply
move_to_trash() {
  if command -v trash >/dev/null 2>&1; then
    trash "$@"
  elif [ $IS_MAC -eq 1 ]; then
    osascript - "$@" >/dev/null << 'OSA'
on run argv
  set fileList to {}
  repeat with p in argv
    set end of fileList to (POSIX file (p as text))
  end repeat
  tell application "Finder" to delete fileList
end run
OSA
  else
    echo "No way to move files to the Trash on this system." >&2; return 1
  fi
}

apply() {
  [ -n "$report" ] || die "--apply needs a report file, e.g. dupfinder --apply ~/Downloads/dupfinder-decisions.txt"
  [ -f "$report" ] || die "'$report' not found."
  local report_dir; report_dir=$(cd "$(dirname "$report")" && pwd -P)

  # group <TAB> md5 <TAB> ACTION <TAB> path
  awk '
    /^## Group/ { g++; h = ""; if (match($0, /md5 [0-9a-f]+/)) h = substr($0, RSTART + 4, RLENGTH - 4); next }
    /^(KEEP|REMOVE)[ \t]+\// { a = $1; p = $0; sub(/^(KEEP|REMOVE)[ \t]+/, "", p); print g + 0 "\t" h "\t" a "\t" p }
  ' "$report" > "$work/plan.tsv"

  [ -s "$work/plan.tsv" ] || die "No KEEP / REMOVE lines found in '$report'."
  if ! grep -q $'\tREMOVE\t' "$work/plan.tsv"; then echo "Nothing is marked REMOVE, so there's nothing to do."; exit 0; fi

  awk -F'\t' '{ p = $4; for (i = 5; i <= NF; i++) p = p "\t" $i; if (!seen[p]++) print p }' "$work/plan.tsv" |
    while IFS= read -r p; do [ -f "$p" ] && [ ! -L "$p" ] && printf '%s\n' "$p"; done > "$work/exist.txt"
  local nexist; nexist=$(wc -l < "$work/exist.txt" | tr -d ' ')

  echo "Re-checking files before moving anything..."
  : > "$work/actual.tsv"
  if [ "$nexist" -gt 0 ]; then
    tr '\n' '\0' < "$work/exist.txt" | hash_files | progress "$nexist" "Verifying" > "$work/actual.tsv"
  fi

  export DF_TRASH="$work/trash.txt" DF_SKIP="$work/skip.tsv"
  : > "$DF_TRASH"; : > "$DF_SKIP"
  awk -F'\t' '
    FILENAME == ARGV[1] { act[substr($0, 34)] = substr($0, 1, 32); next }
    {
      g = $1; h = $2; a = $3; p = $4; for (i = 5; i <= NF; i++) p = p "\t" $i
      if (a == "KEEP") { keep[p] = 1; if (h != "" && (p in act) && act[p] == h) keepok[g] = 1 }
      else { n++; rg[n] = g; rh[n] = h; rp[n] = p }
    }
    END {
      for (i = 1; i <= n; i++) {
        p = rp[i]
        if (rh[i] == "")           reason = "its group has no md5 line"
        else if (p in done)        reason = "listed twice"
        else if (p in keep)        reason = "also marked KEEP"
        else if (!(p in act))      reason = "file no longer exists"
        else if (act[p] != rh[i])  reason = "file changed since the scan"
        else if (!keepok[rg[i]])   reason = "no kept copy in its group still exists unchanged"
        else { done[p] = 1; print p > ENVIRON["DF_TRASH"]; continue }
        print reason "\t" p > ENVIRON["DF_SKIP"]
      }
    }' "$work/actual.tsv" "$work/plan.tsv"

  local ntrash nskip bytes=0
  ntrash=$(wc -l < "$DF_TRASH" | tr -d ' ')
  nskip=$(wc -l < "$DF_SKIP" | tr -d ' ')
  if [ "$ntrash" -gt 0 ]; then
    bytes=$(tr '\n' '\0' < "$DF_TRASH" | xargs -0 sh -c 'if [ "$(uname)" = Darwin ]; then stat -f %z "$@"; else stat -c %s "$@"; fi' sh |
            awk '{ s += $1 } END { printf "%.0f", s }')
  fi

  echo
  if [ "$nskip" -gt 0 ]; then
    echo "Skipping $nskip file(s) to stay safe:"
    head -n 15 "$DF_SKIP" | awk -F'\t' '{ p = $2; for (i = 3; i <= NF; i++) p = p "\t" $i; printf "  %s  (%s)\n", p, $1 }'
    [ "$nskip" -gt 15 ] && echo "  ...and $((nskip - 15)) more"
    echo
  fi
  if [ "$ntrash" -eq 0 ]; then echo "Nothing left to move."; exit 0; fi

  echo "Ready to move $ntrash file(s), $(n_human "$bytes"), to the Trash:"
  head -n 15 "$DF_TRASH" | sed 's/^/  /'
  [ "$ntrash" -gt 15 ] && echo "  ...and $((ntrash - 15)) more"
  echo

  if [ $yes -ne 1 ]; then
    printf "Move these to the Trash? [y/N] "
    read -r ans < /dev/tty
    case "$ans" in y|Y|yes|YES|Yes) ;; *) echo "Cancelled. Nothing was moved."; exit 0 ;; esac
  fi

  local log="$report_dir/trashed-$(date +%Y-%m-%d_%H%M%S).log"
  { echo "# dupfinder: moved to the Trash on $(date '+%Y-%m-%d %H:%M') from report $report"; } > "$log"

  local batch=() moved=0 p
  while IFS= read -r p; do
    batch+=("$p")
    if [ ${#batch[@]} -ge 100 ]; then
      if ! move_to_trash "${batch[@]}"; then break; fi
      printf '%s\n' "${batch[@]}" >> "$log"; moved=$((moved + ${#batch[@]})); batch=()
      printf "\r  Moved %d / %d" "$moved" "$ntrash"
    fi
  done < "$DF_TRASH"
  if [ ${#batch[@]} -gt 0 ] && move_to_trash "${batch[@]}"; then
    printf '%s\n' "${batch[@]}" >> "$log"; moved=$((moved + ${#batch[@]})); batch=()
  fi
  printf "\r  Moved %d / %d\n" "$moved" "$ntrash"

  echo
  if [ "$moved" -lt "$ntrash" ]; then
    echo "Stopped early: $moved of $ntrash files were moved."
    echo "If macOS asked whether Terminal may control Finder, allow it (System Settings > Privacy & Security > Automation) and run the same command again."
  else
    echo "Done. Moved $moved file(s), $(n_human "$bytes"), to the Trash."
  fi
  echo "To undo, open the Trash, select the files, and choose Put Back."
  echo "Log: $log"
}

if [ "$mode" = "apply" ]; then apply; else scan; fi
