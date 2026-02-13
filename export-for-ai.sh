#!/bin/bash
# ─────────────────────────────────────────────────────────
# export-for-ai.sh
# Usage:  ./export-for-ai.sh <package-name> [output-file]
# Eg:     ./export-for-ai.sh fastapi fastapi-docs.md
#         ./export-for-ai.sh pydantic | pbcopy
# ─────────────────────────────────────────────────────────
set -e

PACKAGE_NAME="$1"
OUTPUT_FILE="$2"

if [ -z "$PACKAGE_NAME" ]; then
  echo "Usage: $0 <package-name> [output-file]"
  echo ""
  echo "Examples:"
  echo "  $0 fastapi                    # Print to stdout"
  echo "  $0 fastapi fastapi.md         # Save to file"
  echo "  $0 fastapi | pbcopy           # Copy to clipboard (macOS)"
  echo "  $0 fastapi | xclip -selection clipboard  # Copy to clipboard (Linux)"
  exit 1
fi

PACKAGE_DIR="$(pwd)/$PACKAGE_NAME"

if [ ! -d "$PACKAGE_DIR/markdown" ]; then
  echo "Error: Package '$PACKAGE_NAME' not found."
  echo "Run: ./download-docs.sh $PACKAGE_NAME <docs-url>"
  exit 1
fi

# Function to output markdown
output_markdown() {
  # If there's an all-docs.md (from llms.txt), use that
  if [ -f "$PACKAGE_DIR/markdown/all-docs.md" ]; then
    cat "$PACKAGE_DIR/markdown/all-docs.md"
  else
    # Otherwise, concatenate all markdown files
    find "$PACKAGE_DIR/markdown" -name "*.md" -type f | sort | while read -r file; do
      echo "<!-- File: ${file#$PACKAGE_DIR/markdown/} -->"
      echo ""
      cat "$file"
      echo ""
      echo "---"
      echo ""
    done
  fi
}

# Output to file or stdout
if [ -n "$OUTPUT_FILE" ]; then
  output_markdown > "$OUTPUT_FILE"
  echo "✅ Exported to: $OUTPUT_FILE"
else
  output_markdown
fi
