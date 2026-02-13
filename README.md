# docs-generator

Download documentation from any website and convert it to markdown for viewing or feeding to LLMs.

## Quick Start

### 1. Download Documentation

```bash
./download-docs.sh <package-name> <docs-url>
```

Examples:
```bash
./download-docs.sh fastapi https://fastapi.tiangolo.com/
./download-docs.sh pydantic https://docs.pydantic.dev/latest/
```

### 2. View Documentation

Start a local server:
```bash
python3.14 -m http.server 8080
```

Open in browser:
```
http://localhost:8080/viewer.html
```

### 3. Export for LLM

Get all markdown content:
```bash
./export-for-ai.sh <package-name>
```

Examples:
```bash
# Print to terminal
./export-for-ai.sh fastapi

# Save to file
./export-for-ai.sh fastapi fastapi-docs.md

# Copy to clipboard (macOS)
./export-for-ai.sh fastapi | pbcopy

# Copy to clipboard (Linux)
./export-for-ai.sh fastapi | xclip -selection clipboard
```

## Requirements

- `python3.14` with `html2text` package (auto-installed)
- `wget` (auto-installed via brew on macOS if missing)

## How It Works

The downloader tries two methods:
1. **llms.txt**: Checks if the site has a single-file LLM-optimized format
2. **Web crawling**: Falls back to crawling with `wget` and converting HTML to markdown

All documentation is saved as markdown in `<package-name>/markdown/`.
# docs-generator
