#!/usr/bin/env bash
# publish.sh — re-render the gallery index, commit, push.
# Contract: see ~/.claude/skills/vivid-html/references/publish-flow.md
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

PAGES_BASE="https://bbbond123.github.io/vivid-html"
TEMPLATE="$REPO_ROOT/_layouts/index-template.html"
COMMIT_NAME="bbbond123"
COMMIT_EMAIL="jamesw@ymail.ne.jp"

err() { printf 'publish.sh: %s\n' "$*" >&2; }

# ---- temp file housekeeping ----------------------------------------
TMPDIR_LOCAL=$(mktemp -d)
trap 'rm -rf "$TMPDIR_LOCAL"' EXIT

# ---- 1. arg parsing -------------------------------------------------
if [[ $# -lt 1 ]]; then
  err "usage: publish.sh <slug>"
  exit 1
fi
SLUG="$1"
SLUG_FILE="$REPO_ROOT/$SLUG/index.html"

# ---- 2. validate slug file ------------------------------------------
if [[ ! -f "$SLUG_FILE" ]]; then
  err "missing artifact: $SLUG_FILE"
  exit 2
fi
if [[ ! -f "$TEMPLATE" ]]; then
  err "missing template: $TEMPLATE"
  exit 2
fi

# ---- 3. metadata extraction (gawk-free, mawk-friendly) --------------
extract_title() {
  python3 -c '
import sys, re
src = open(sys.argv[1]).read()
m = re.search(r"<title>([^<]*)</title>", src, re.I)
print(m.group(1).strip() if m else "")
' "$1"
}

extract_meta() {
  python3 -c '
import sys, re
src = open(sys.argv[1]).read()
name = sys.argv[2]
pat = r"<meta\s+name=\"" + re.escape(name) + r"\"\s+content=\"([^\"]*)\""
m = re.search(pat, src, re.I)
print(m.group(1).strip() if m else "")
' "$1" "$2"
}

T_NEW=$(extract_title "$SLUG_FILE")
D_NEW=$(extract_meta  "$SLUG_FILE" "description")
C_NEW=$(extract_meta  "$SLUG_FILE" "vivid:created")

if [[ -z "$T_NEW" || "$T_NEW" == "Untitled" ]]; then
  err "missing or empty <title> in $SLUG_FILE"; exit 3
fi
if [[ -z "$D_NEW" ]]; then
  err "missing <meta name=\"description\"> in $SLUG_FILE"; exit 3
fi
if [[ ! "$C_NEW" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  err "missing or malformed <meta name=\"vivid:created\"> (need YYYY-MM-DD) in $SLUG_FILE"
  exit 3
fi

# ---- 4. collect all slug dirs ---------------------------------------
LIST_FILE="$TMPDIR_LOCAL/slugs.tsv"
: > "$LIST_FILE"
while IFS= read -r f; do
  d=$(dirname "$f")
  base=$(basename "$d")
  case "$base" in
    _layouts|bin|.git|node_modules) continue;;
  esac
  ti=$(extract_title "$f")
  ds=$(extract_meta  "$f" "description")
  cr=$(extract_meta  "$f" "vivid:created")
  [[ -z "$ti" ]] && ti="$base"
  [[ -z "$ds" ]] && ds="(no description)"
  [[ -z "$cr" ]] && cr="0000-00-00"
  # TAB-separated: created, slug, title, description
  printf '%s\t%s\t%s\t%s\n' "$cr" "$base" "$ti" "$ds" >> "$LIST_FILE"
done < <(find "$REPO_ROOT" -mindepth 2 -maxdepth 2 -name index.html -type f 2>/dev/null)

sort -r "$LIST_FILE" -o "$LIST_FILE"

# ---- 5. render index.html via python --------------------------------
INDEX_OUT="$REPO_ROOT/index.html"
python3 - "$TEMPLATE" "$LIST_FILE" "$INDEX_OUT" <<'PY'
import sys, re, html, pathlib, zlib

tpl_path, list_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]

THUMBS = [
    """<svg viewBox="0 0 120 80">
  <rect class="wh" x="6" y="10" width="48" height="60" rx="5"/>
  <rect class="oa" x="64" y="10" width="48" height="60" rx="5"/>
  <line class="ln" x1="14" y1="24" x2="46" y2="24"/>
  <line class="ln" x1="14" y1="34" x2="40" y2="34"/>
  <line class="lc" x1="72" y1="24" x2="104" y2="24"/>
  <line class="lc" x1="72" y1="34" x2="96" y2="34"/>
  <circle class="cl" cx="88" cy="56" r="6"/>
</svg>""",
    """<svg viewBox="0 0 120 80">
  <rect class="wh" x="44" y="8"  width="32" height="20" rx="4"/>
  <rect class="oa" x="8"  y="52" width="32" height="20" rx="4"/>
  <rect class="cl" x="44" y="52" width="32" height="20" rx="4"/>
  <rect class="wh" x="80" y="52" width="32" height="20" rx="4"/>
  <line class="ln" x1="50" y1="28" x2="26" y2="52"/>
  <line class="lc" x1="60" y1="28" x2="60" y2="52"/>
  <line class="ln" x1="70" y1="28" x2="94" y2="52"/>
</svg>""",
    """<svg viewBox="0 0 120 80">
  <line class="ln" x1="14" y1="12" x2="14" y2="68"/>
  <circle class="cl" cx="14" cy="16" r="5"/>
  <circle class="ol" cx="14" cy="40" r="5"/>
  <circle class="fl" cx="14" cy="64" r="5"/>
  <rect class="fl" x="28" y="12" width="48" height="4" rx="2"/>
  <rect class="fl" x="28" y="36" width="42" height="4" rx="2"/>
  <rect class="fl" x="28" y="60" width="44" height="4" rx="2"/>
  <rect class="oa" x="86" y="12" width="28" height="24" rx="4"/>
  <rect class="wh" x="86" y="44" width="28" height="24" rx="4"/>
</svg>""",
    """<svg viewBox="0 0 120 80">
  <rect class="cl" x="8"  y="10" width="22" height="22" rx="4"/>
  <rect class="ol" x="36" y="10" width="22" height="22" rx="4"/>
  <rect class="oa" x="64" y="10" width="22" height="22" rx="4"/>
  <rect class="sl" x="92" y="10" width="22" height="22" rx="4"/>
  <rect class="fl" x="8" y="42" width="80" height="8" rx="2"/>
  <rect class="fl" x="8" y="56" width="56" height="6" rx="2"/>
  <rect class="fl" x="8" y="68" width="40" height="5" rx="2"/>
</svg>""",
]

def thumb_for(slug: str) -> str:
    return THUMBS[zlib.crc32(slug.encode()) % len(THUMBS)]

rows = []
for line in pathlib.Path(list_path).read_text().splitlines():
    if not line.strip():
        continue
    parts = line.split("\t")
    if len(parts) < 4:
        continue
    cr, slug, ti, ds = parts[0], parts[1], parts[2], parts[3]
    rows.append((cr, slug, ti, ds))

count = len(rows)

if rows:
    cards = []
    for cr, slug, ti, ds in rows:
        thumb = thumb_for(slug)
        cards.append(
            '      <a class="card" href="{slug}/">\n'
            '        <div class="thumb">{thumb}</div>\n'
            '        <div class="body">\n'
            '          <div class="title">{title}</div>\n'
            '          <div class="desc">{desc}</div>\n'
            '          <div class="file"><span>/{slug}/ &middot; {cr}</span><span class="arrow">&rarr;</span></div>\n'
            '        </div>\n'
            '      </a>'.format(
                slug=html.escape(slug, quote=True),
                thumb=thumb,
                title=html.escape(ti),
                desc=html.escape(ds),
                cr=html.escape(cr),
            )
        )
    cards_block = '    <div class="grid">\n' + "\n".join(cards) + "\n    </div>"
else:
    cards_block = (
        '    <div class="empty">No pages yet'
        '<p>Generate one with the <code>vivid-html</code> Claude Code skill.</p>'
        '</div>'
    )

tpl = pathlib.Path(tpl_path).read_text()
tpl = tpl.replace("{{COUNT}}", str(count))
tpl = tpl.replace("{{CARDS}}", cards_block)
pathlib.Path(out_path).write_text(tpl)
PY

# ---- 6. git add / commit / push -------------------------------------
git add -A
if git diff --cached --quiet; then
  err "nothing to commit (slug $SLUG already up to date)"
  printf 'URL: %s/%s/\n' "$PAGES_BASE" "$SLUG"
  exit 4
fi

if ! git -c user.email="$COMMIT_EMAIL" -c user.name="$COMMIT_NAME" \
       commit -m "publish: $SLUG" >/dev/null; then
  err "git commit failed"
  exit 4
fi

# Skip push if no remote yet (bootstrap mode).
if git remote get-url origin >/dev/null 2>&1; then
  if ! git push origin main >/dev/null 2>&1; then
    err "git push failed; check 'gh auth status' (active should be bbbond123)"
    exit 5
  fi
else
  err "no 'origin' remote yet; skipped push"
fi

# ---- 7. emit URL ----------------------------------------------------
printf 'URL: %s/%s/\n' "$PAGES_BASE" "$SLUG"
