---
name: signature-map
description: Generate and use a codebase signature map JSON (signatures.json) for fast project navigation. Use when asked to create or refresh a signature map, inspect functions or methods across languages, or build a lightweight index of project APIs without manually scanning files. Works in repos that include scripts/generate-signatures.sh (for example B2Broker).
---

# Signature Map

## Overview
Generate a JSON index of function and method signatures (plus comments and line numbers) so an agent can navigate the codebase quickly without reading files manually.

## Quick start (preferred)
1. From the repo root, run the generator:
```bash
./scripts/generate-signatures.sh
```
This writes `signatures.json` in the repo root.

2. Confirm output:
```bash
ls -lh signatures.json
```

## Output schema
Each entry is an object with:
- `path`: `relative/file/path::symbolName`
- `signature`: normalized declaration line(s)
- `comment`: nearest preceding doc or line comment (if any)
- `line`: 1-based line number of the signature start

## Use the map
Use these patterns to search and filter:

- Find all signatures by name:
```bash
rg -n "\"path\": \".*::MySymbol\"|\"signature\": \".*MySymbol" signatures.json
```

- Filter by path prefix (with `jq`):
```bash
jq '.[] | select(.path | startswith("L0/B2Core/"))' signatures.json
```

- List Swift symbols:
```bash
jq -r '.[] | select(.path | test("\\.swift::")) | .path' signatures.json | head
```

- Jump to source:
Use the `path` and `line` fields to open the file directly.

## Refresh the map
Re-run the generator after code changes:
```bash
./scripts/generate-signatures.sh
```

## Troubleshooting
- Set a specific Python binary:
```bash
PYTHON_BIN=python3 ./scripts/generate-signatures.sh
```
- Use `jq` or `rg` filters instead of opening the whole JSON in an editor.
- Treat `signatures.json` as a regenerated local artifact unless explicitly asked to commit it.
