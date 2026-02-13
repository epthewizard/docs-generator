#!/bin/bash
# ─────────────────────────────────────────────────────────
# download-docs.sh
# Usage:  ./download-docs.sh <package-name> <docs-url>
# Eg:     ./download-docs.sh fastapi https://fastapi.tiangolo.com/
#
# Run from the folder that also contains viewer.html.
# Then serve with: python3.14 -m http.server 8080
# ─────────────────────────────────────────────────────────
set -e

PACKAGE_NAME="$1"
DOC_URL="$2"
DOCS_DIR="$(pwd)"
PACKAGE_DIR="$DOCS_DIR/$PACKAGE_NAME"

# ── Validate input ──────────────────────────────────────
if [ -z "$PACKAGE_NAME" ] || [ -z "$DOC_URL" ]; then
  echo "Usage: $0 <package-name> <docs-url>"
  echo "  eg: $0 fastapi https://fastapi.tiangolo.com/"
  echo "  eg: $0 pydantic https://docs.pydantic.dev/latest/"
  exit 1
fi

mkdir -p "$PACKAGE_DIR/raw"
mkdir -p "$PACKAGE_DIR/markdown"

# ── Step 1: Try llms.txt first ──────────────────────────
BASE_URL=$(echo "$DOC_URL" | cut -d'/' -f1-3)   # eg: https://python-saleae.readthedocs.io
LLMS_URL="$BASE_URL/llms.txt"

echo ""
echo "━━ $PACKAGE_NAME ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📂 Saving to: $PACKAGE_DIR"
echo "🔍 Checking for llms.txt at $LLMS_URL ..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$LLMS_URL")

if [ "$HTTP_STATUS" = "200" ]; then
  echo "✅ Found llms.txt — downloading single-file docs..."
  curl -s "$LLMS_URL" > "$PACKAGE_DIR/markdown/all-docs.md"
  METHOD="llms.txt"
  RAW_INDEX=""
  echo "📄 Saved: $PACKAGE_DIR/markdown/all-docs.md"

else
  # ── Step 2: Fall back to crawling with wget ────────────
  echo "❌ No llms.txt. Crawling site with wget (may take a while)..."

  if ! command -v wget &>/dev/null; then
    echo "📦 Installing wget via brew..."
    brew install wget
  fi

  if ! python3.14 -c "import html2text" &>/dev/null; then
    echo "📦 Installing html2text..."
    python3.14 -m pip install html2text --quiet --break-system-packages 2>/dev/null || python3.14 -m pip install html2text --quiet
  fi

  wget \
    --recursive \
    --no-parent \
    --convert-links \
    --adjust-extension \
    --no-host-directories \
    --directory-prefix="$PACKAGE_DIR/raw" \
    --reject "*.css,*.js,*.woff,*.woff2,*.ttf,*.eot,*.otf,*.png,*.jpg,*.jpeg,*.svg,*.gif,*.ico,*.xml,*.zip" \
    --quiet --show-progress \
    "$DOC_URL"

  # ── Step 3: Convert HTML → Markdown for Copilot ───────
  echo ""
  echo "🔄 Converting HTML to Markdown for Copilot..."

  find "$PACKAGE_DIR/raw" -name "*.html" | while read -r file; do
    relative="${file#$PACKAGE_DIR/raw/}"
    output="$PACKAGE_DIR/markdown/${relative%.html}.md"
    mkdir -p "$(dirname "$output")"
    python3.14 -c "
import html2text, sys
h = html2text.HTML2Text()
h.ignore_links = False
h.ignore_images = True
h.body_width = 0
try:
  content = open(sys.argv[1]).read()
  print(h.handle(content))
except: pass
" "$file" > "$output" 2>/dev/null || true
  done

  METHOD="wget"

  # ── Work out where wget actually saved the index ───────
  # wget strips the domain but keeps the URL path.
  # We use bash parameter expansion — NOT sed — to avoid BSD sed issues.
  #
  # eg: https://python-saleae.readthedocs.io/en/latest/
  #   step 1 → strip https://   → python-saleae.readthedocs.io/en/latest/
  #   step 2 → strip up to /    → en/latest/
  #   step 3 → append index.html → en/latest/index.html

  URL_NO_PROTO="${DOC_URL#https://}"
  URL_NO_PROTO="${URL_NO_PROTO#http://}"
  URL_PATH="${URL_NO_PROTO#*/}"          # strip domain+first slash

  if [[ "$URL_PATH" == */ ]] || [ -z "$URL_PATH" ]; then
    RAW_INDEX="${URL_PATH}index.html"
  else
    RAW_INDEX="${URL_PATH}.html"
  fi

  echo "📂 Entry point: $PACKAGE_NAME/raw/$RAW_INDEX"
fi

# ── Step 4: Update manifest.json ─────────────────────────
MANIFEST="$DOCS_DIR/manifest.json"
FILE_COUNT=$(find "$PACKAGE_DIR/markdown" -name "*.md" | wc -l | tr -d ' ')

MD_FILES=$(find "$PACKAGE_DIR/markdown" -name "*.md" | sort | python3.14 -c "
import sys, json
files = [line.strip() for line in sys.stdin if line.strip()]
print(json.dumps(files))
")

NEW_ENTRY=$(cat <<ENTRY
{
  "name": "$PACKAGE_NAME",
  "url": "$DOC_URL",
  "method": "$METHOD",
  "raw_index": "$RAW_INDEX",
  "local_raw": "$PACKAGE_DIR/raw",
  "local_markdown": "$PACKAGE_DIR/markdown",
  "markdown_files": $MD_FILES,
  "file_count": $FILE_COUNT
}
ENTRY
)

if command -v jq &>/dev/null; then
  if [ -f "$MANIFEST" ]; then
    jq --argjson entry "$NEW_ENTRY" \
      '.packages = ([.packages[] | select(.name != $entry.name)] + [$entry])' \
      "$MANIFEST" > "$MANIFEST.tmp" && mv "$MANIFEST.tmp" "$MANIFEST"
  else
    echo '{"packages":[]}' | jq --argjson entry "$NEW_ENTRY" \
      '.packages += [$entry]' > "$MANIFEST"
  fi
else
  python3.14 - << EOF
import json, os

manifest_path = "$MANIFEST"
manifest = {"packages": []}

if os.path.exists(manifest_path):
    with open(manifest_path) as f:
        manifest = json.load(f)

manifest["packages"] = [p for p in manifest["packages"] if p["name"] != "$PACKAGE_NAME"]
manifest["packages"].append($NEW_ENTRY)

with open(manifest_path, "w") as f:
    json.dump(manifest, f, indent=2)
EOF
fi

echo "✅ Manifest updated — $FILE_COUNT markdown file(s)"

# ── Done ─────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅  Done! $PACKAGE_NAME → $PACKAGE_DIR"
echo ""
echo "📖  View docs (run from this folder):"
echo "    python3.14 -m http.server 8080"
echo "    open http://localhost:8080/viewer.html"
echo ""
echo "📋  Feed to AI:"
echo "    cat $PACKAGE_DIR/markdown/*.md"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
