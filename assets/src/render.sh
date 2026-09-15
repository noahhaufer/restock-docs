#!/usr/bin/env bash
# Renders assets/architecture-{light,dark}.png from architecture.html.
# Usage: RESTOCK_REPO=~/restock bash assets/src/render.sh
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="${RESTOCK_REPO:?set RESTOCK_REPO to the restock checkout (for the brand mark and wordmark)}"
chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

python3 - "$here/architecture.html" "$repo" "$work/page.html" <<'PY'
import base64, re, sys
src, repo, out = sys.argv[1:]
html = open(src).read()
mark = base64.b64encode(open(f"{repo}/apps/web/public/brand/mark.png", "rb").read()).decode()
word = open(f"{repo}/apps/web/public/brand/wordmark.svg").read()
word = re.sub(r"<\?xml[^>]*>", "", word).strip()
open(out, "w").write(html.replace("{{MARK}}", mark).replace("{{WORDMARK}}", word))
PY

for theme in light dark; do
  cls=""; [ "$theme" = dark ] && cls="dark"
  sed "s/<body>/<body class=\"$cls\">/" "$work/page.html" > "$work/$theme.html"
  "$chrome" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
    --window-size=1600,1040 --virtual-time-budget=4000 \
    --screenshot="$here/../architecture-$theme.png" "file://$work/$theme.html" >/dev/null 2>&1
  echo "wrote assets/architecture-$theme.png"
done
