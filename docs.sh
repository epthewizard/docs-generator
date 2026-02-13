#!/bin/bash
# ─────────────────────────────────────────────────────────
# docs.sh - Single script for all documentation operations
# ─────────────────────────────────────────────────────────
set -e

COMMAND="$1"

show_help() {
  cat <<'EOF'
docs.sh - Manage documentation

USAGE:
  ./docs.sh <command> [args]

COMMANDS:
  download <name> <url>     Download docs and update manifest
  list <name>               List all docs with titles/URLs
  fetch <name> <keyword>    Fetch specific doc by keyword
  export <name> [file]      Export all markdown for AI
  help                      Show this message

EXAMPLES:
  ./docs.sh download sqlmodel https://sqlmodel.tiangolo.com/
  ./docs.sh list sqlmodel
  ./docs.sh fetch sqlmodel "many-to-many"
  ./docs.sh export sqlmodel | pbcopy
EOF
}

# ─────────────────────────────────────────────────────────
# DOWNLOAD
# ─────────────────────────────────────────────────────────
cmd_download() {
  local name="$1"
  local url="$2"

  if [ -z "$name" ] || [ -z "$url" ]; then
    echo "Usage: $0 download <name> <url>"
    exit 1
  fi

  echo "📥 Downloading $name from $url..."

  local pkg_dir="$name"
  mkdir -p "$pkg_dir/markdown"

  # Try llms.txt first
  if wget -q --timeout=5 -O "$pkg_dir/markdown/all-docs.md" "${url}llms.txt" 2>/dev/null; then
    echo "✅ Downloaded via llms.txt"
    local method="llms.txt"
  else
    # Fall back to web crawling
    echo "🕷️  Crawling website..."
    mkdir -p "$pkg_dir/raw"

    if ! command -v html2text &> /dev/null; then
      echo "📦 Installing html2text..."
      python3 -m pip install html2text >/dev/null 2>&1
    fi

    # Extract domain for wget
    local domain=$(echo "$url" | sed -E 's|^https?://([^/]+).*|\1|')

    # Crawl with wget
    wget -q -r -p -E -k -l 5 -P "$pkg_dir/raw" -np "$url" 2>/dev/null || true

    # Convert HTML to markdown
    find "$pkg_dir/raw" -name "*.html" -type f | while read -r html_file; do
      local rel_path="${html_file#$pkg_dir/raw/$domain/}"
      local md_file="$pkg_dir/markdown/${rel_path%.html}.md"
      local md_dir=$(dirname "$md_file")
      mkdir -p "$md_dir"
      html2text "$html_file" > "$md_file" 2>/dev/null || true
    done

    local method="wget"
    echo "✅ Downloaded via wget"
  fi

  # Update manifest with file metadata
  update_manifest "$name" "$url" "$method"

  echo ""
  echo "📖 View: python3 -m http.server 8080 → http://localhost:8080/viewer.html"
  echo "📋 List: ./docs.sh list $name"
}

# ─────────────────────────────────────────────────────────
# UPDATE MANIFEST
# ─────────────────────────────────────────────────────────
update_manifest() {
  local name="$1"
  local url="$2"
  local method="$3"

  local manifest="manifest.json"

  # Create manifest if missing
  [ ! -f "$manifest" ] && echo '{"packages":[]}' > "$manifest"

  # Build file list with titles and URLs
  python3 <<EOPYTHON
import json
import os
import re

name = "$name"
url = "$url".rstrip("/")
method = "$method"
pkg_dir = f"{name}/markdown"

# Read manifest
with open("manifest.json") as f:
    manifest = json.load(f)

# Remove existing package
manifest["packages"] = [p for p in manifest["packages"] if p["name"] != name]

# Build file list
files = []
for root, _, filenames in os.walk(pkg_dir):
    for filename in filenames:
        if filename.endswith(".md"):
            filepath = os.path.join(root, filename)

            # Skip if this is somehow in a raw directory
            if "/raw/" in filepath:
                continue

            rel_path = filepath.replace(f"{pkg_dir}/", "")

            # Get title from first heading
            title = ""
            try:
                with open(filepath) as f:
                    first_line = f.readline().strip()
                    title = re.sub(r'^#+\s*', '', first_line)
            except:
                pass

            # Derive URL from path (for wget downloads)
            if method == "wget":
                doc_url = url + "/" + rel_path.replace("/index.md", "/").replace(".md", "/")
            else:
                doc_url = url  # llms.txt is single file

            files.append({
                "path": rel_path,
                "title": title,
                "url": doc_url,
                "file": filepath
            })

# Sort files by path
files.sort(key=lambda x: x["path"])

# Add package entry
pkg_entry = {
    "name": name,
    "url": url,
    "method": method,
    "file_count": len(files),
    "files": files
}

# For wget, add raw info
if method == "wget":
    pkg_entry["local_raw"] = f"{name}/raw"
    pkg_entry["raw_index"] = "index.html"

manifest["packages"].append(pkg_entry)

# Write manifest
with open("manifest.json", "w") as f:
    json.dump(manifest, f, indent=2)

print(f"✅ Manifest updated: {len(files)} files indexed")
EOPYTHON
}

# ─────────────────────────────────────────────────────────
# LIST
# ─────────────────────────────────────────────────────────
cmd_list() {
  local name="$1"

  if [ -z "$name" ]; then
    echo "Usage: $0 list <name>"
    exit 1
  fi

  python3 <<EOPYTHON
import json

with open("manifest.json") as f:
    manifest = json.load(f)

pkg = next((p for p in manifest["packages"] if p["name"] == "$name"), None)
if not pkg:
    print(f"❌ Package '$name' not found")
    exit(1)

print(f"📚 {pkg['name']} ({pkg['file_count']} docs)")
print()

for file in pkg["files"]:
    print(f"• {file['path']}")
    if file.get('title'):
        print(f"  {file['title']}")
    print(f"  🔗 {file['url']}")
    print()
EOPYTHON
}

# ─────────────────────────────────────────────────────────
# FETCH
# ─────────────────────────────────────────────────────────
cmd_fetch() {
  local name="$1"
  local keyword="$2"

  if [ -z "$name" ] || [ -z "$keyword" ]; then
    echo "Usage: $0 fetch <name> <keyword>"
    exit 1
  fi

  python3 <<EOPYTHON
import json
import re

with open("manifest.json") as f:
    manifest = json.load(f)

pkg = next((p for p in manifest["packages"] if p["name"] == "$name"), None)
if not pkg:
    print(f"❌ Package '$name' not found")
    exit(1)

keyword = "$keyword".lower()
path_matches = []
title_matches = []
content_matches = []

# Search with priority: path > title > content
for file in pkg["files"]:
    if keyword in file["path"].lower():
        path_matches.append(file)
    elif keyword in file.get("title", "").lower():
        title_matches.append(file)
    else:
        # Search in file content (only first 500 chars to avoid nav menus)
        try:
            with open(file["file"]) as f:
                content = f.read(500).lower()
                if keyword in content:
                    content_matches.append(file)
        except:
            pass

# Combine matches in priority order
matches = path_matches + title_matches + content_matches

if not matches:
    print(f"❌ No matches for '$keyword'")
    exit(1)

if len(matches) > 1:
    print(f"📋 Found {len(matches)} matches (showing most relevant):")
    print()
    for i, m in enumerate(matches[:10], 1):
        print(f"{i}) {m['path']}")
    print()
    print("Showing first match:")
    print()

match = matches[0]
print(f"✅ {match['path']}")
print(f"🔗 {match['url']}")
print()
print("─" * 60)
print()

with open(match["file"]) as f:
    print(f.read())
EOPYTHON
}

# ─────────────────────────────────────────────────────────
# EXPORT
# ─────────────────────────────────────────────────────────
cmd_export() {
  local name="$1"
  local output="$2"

  if [ -z "$name" ]; then
    echo "Usage: $0 export <name> [output-file]"
    exit 1
  fi

  python3 <<EOPYTHON
import json
import sys

with open("manifest.json") as f:
    manifest = json.load(f)

pkg = next((p for p in manifest["packages"] if p["name"] == "$name"), None)
if not pkg:
    print(f"❌ Package '$name' not found", file=sys.stderr)
    exit(1)

output = "$output"

def write_markdown():
    for file in pkg["files"]:
        print(f"<!-- {file['path']} -->")
        print(f"<!-- {file['url']} -->")
        print()
        with open(file["file"]) as f:
            print(f.read())
        print()
        print("---")
        print()

if output:
    with open(output, "w") as f:
        sys.stdout = f
        write_markdown()
    sys.stdout = sys.__stdout__
    print(f"✅ Exported to {output}", file=sys.stderr)
else:
    write_markdown()
EOPYTHON
}

# ─────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────
case "$COMMAND" in
  download) cmd_download "$2" "$3" ;;
  list)     cmd_list "$2" ;;
  fetch)    cmd_fetch "$2" "$3" ;;
  export)   cmd_export "$2" "$3" ;;
  help|'')  show_help ;;
  *)        echo "❌ Unknown: $COMMAND"; echo ""; show_help; exit 1 ;;
esac
