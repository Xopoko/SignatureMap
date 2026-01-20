# SignatureMap

Extract your project’s “API surface” (function/method signatures + nearby doc comments) into a single `signatures.json` file — ready to paste into an LLM/agent context.

This is a lightweight, dependency-free-ish approach: one Bash script that runs an embedded Python parser.

---

## What it does

- Recursively scans your repository (starting from repo root).
- Finds function/method definitions in multiple languages.
- Grabs the closest preceding comment block (doc comment / inline comments).
- Writes everything into a **single JSON** file: `signatures.json`.

Use cases:
- Give an agent quick “map” of your codebase without uploading the whole repo.
- Build retrieval/embeddings on top of a compact API-index.
- Diff API changes by comparing JSON outputs in CI.

---

## Supported languages

Detected mainly by file extension:

- Swift (`.swift`)
- Objective-C (`.m`, `.mm`, `.h`)
- C/C++ (`.c`, `.cc`, `.cpp`, `.hpp`)
- JavaScript/TypeScript (`.js`, `.jsx`, `.ts`, `.tsx`)
- Python (`.py`)
- Ruby (`.rb`)
- Shell (`.sh`, `.bash`, `.zsh`) + shebang detection
- Kotlin (`.kt`, `.kts`)
- Java/Groovy (`.java`, `.groovy`)

> Parsing is heuristic/regex-based (fast and “good enough” for signature extraction, not a full parser).

---

## Excluded directories

Common build/dependency folders are skipped:

- `.git`, `.github`, `.swiftpm`, `.build`, `build`, `DerivedData`
- `Carthage`, `Pods`, `RemoteDependencies`
- `Tuist/Dependencies`
- `.idea`, `.vscode`
- (and a few project-specific entries)

---

## Requirements

- Bash
- Python 3 (preferred) or Python 2/any `python` fallback

You can override the interpreter:

```bash
PYTHON_BIN=python3 ./generate-signatures.sh
````

---

## Installation

Option A — copy the script into your repo (recommended):

```
your-repo/
  scripts/
    generate-signatures.sh
```

The script assumes **repo root is the parent folder** of the script directory (`scripts/..`).

Option B — keep it anywhere, but preserve the same layout (script lives one level below repo root).

---

## Usage

From anywhere:

```bash
./scripts/generate-signatures.sh
```

Output:

* `signatures.json` written to repo root

You should see something like:

```
Wrote 1234 signatures to /path/to/repo/signatures.json
```

---

## Output format

`signatures.json` is an array of entries:

```json
[
  {
    "path": "Sources/Foo/Bar.swift::doWork",
    "signature": "func doWork(x: Int) async throws -> String",
    "comment": "Performs the main job.\n- Parameter x: ...",
    "line": 42
  }
]
```

Fields:

* `path`: `<relative/file/path>::<symbolName>`
* `signature`: extracted signature block (may span multiple lines)
* `comment`: closest preceding comment block (normalized)
* `line`: 1-based line number where signature starts

---

## Typical agent prompt snippet

Use the JSON as “API index”:

> Here is `signatures.json` for the repository. Use it as an authoritative map of available functions/types. When you suggest code changes, reference entries by `path`. If you need implementation details, ask for the specific file.

---

## Limitations / gotchas

* Regex-based: some edge cases will be missed or mis-identified.
* For JS/TS class bodies, method detection is simplified.
* C/C++ parsing is heuristic and may match false positives in tricky macros/templates.
* Comment association is “nearest preceding block” (with basic handling for decorators / preprocessors).

---

## Contributing

PRs welcome:

* Add language patterns
* Improve signature termination logic
* Add optional filtering (by path/glob) or output splitting

---

## Author

GitHub: [https://github.com/Xopoko](https://github.com/Xopoko)
