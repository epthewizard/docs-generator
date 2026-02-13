# docs-generator

Download documentation, convert to markdown, and feed to AI on demand.

## Usage

```bash
# Download docs
./docs.sh download sqlmodel https://sqlmodel.tiangolo.com/

# List all available docs
./docs.sh list sqlmodel

# Fetch specific doc by keyword
./docs.sh fetch sqlmodel "many-to-many"

# Export all markdown (for AI consumption)
./docs.sh export sqlmodel | pbcopy
```

## View in Browser

```bash
python3 -m http.server 8080
# Open http://localhost:8080/viewer.html
```

## How It Works

- Downloads docs via `llms.txt` if available, otherwise crawls with `wget`
- Converts HTML to markdown
- Stores metadata (paths, titles, URLs) in `manifest.json`
- All commands read from `manifest.json` for fast lookups

## Requirements

- `python3` with `html2text` (auto-installed)
- `wget` (auto-installed on macOS if missing)
# docs-generator
