# Signature Map

Portable skill package for fast declaration-level code navigation using generated `signatures.json`.

## Why this exists

The main goal is to give coding agents a fast, cheap, high-value context layer before they start expensive repository exploration.

Instead of spending many steps on manual discovery (`ls`, broad `rg`, opening many files), an agent can read a compact declaration map and immediately understand:

- what symbols exist
- where they are located
- what they look like (signature + nearby doc comment)

This reduces context cost and improves task startup speed.  
On top of that, `sigmap` provides syntax sugar over the map (`name/search/open/doctor`) so agents can query and open relevant code directly.

## What it provides

- declaration index with `path::symbol`, signature, nearest comment, line, and `kind`
- canonical runtime commands:
  - `scripts/sigmap`
  - `scripts/generate-signatures.sh`
- installer for Codex/Claude, global or local scope

## Quick start (from checkout)

```bash
./scripts/sigmap refresh --root <repo_root>
./scripts/sigmap name <SymbolName> --root <repo_root> --no-refresh
./scripts/sigmap search "<regex>" --field all --icase --root <repo_root> --no-refresh
./scripts/sigmap open "<relative/file::symbol>" --root <repo_root> --context 60 --no-refresh
```

## One-line install (no clone)

Global auto-detect:

```bash
curl -fsSL https://raw.githubusercontent.com/Xopoko/SignatureMap/main/install.sh | bash -s -- install
```

Local install for both providers into current project:

```bash
curl -fsSL https://raw.githubusercontent.com/Xopoko/SignatureMap/main/install.sh | bash -s -- install --agent both --scope local --project-root "$PWD"
```

Pinned ref:

```bash
curl -fsSL https://raw.githubusercontent.com/Xopoko/SignatureMap/<ref>/install.sh | bash -s -- install --repo Xopoko/SignatureMap --ref <ref>
```

## Installer CLI

```bash
./install.sh [install|update|uninstall|doctor] [options]
```

Main options:

- `--agent codex|claude|both|auto` (default `auto`)
- `--scope global|local` (default `global`)
- `--project-root <path>` (required for custom local root)
- `--with-instructions` / `--without-instructions`
- `--force`
- `--repo <owner/repo>`
- `--ref <git-ref>`
- `--source local|github|auto`
- `--codex-home <path>`
- `--claude-home <path>`
- `--codex-layout auto|codex|agents`
- `--dry-run`

## Install targets

Codex:

- global: `<codex_home>/skills/signature-map`
- local: `<project>/.codex/skills/signature-map` or `<project>/.agents/skills/signature-map`

Claude:

- global: `${CLAUDE_HOME:-$HOME/.claude}/skills/signature-map`
- local: `<project>/.claude/skills/signature-map`

## Managed instructions

Installer manages idempotent blocks in target instruction files:

- Codex: `AGENTS.md`
- Claude: `CLAUDE.md`

Markers:

- `<!-- BEGIN signature-map managed -->`
- `<!-- END signature-map managed -->`

`uninstall` removes managed blocks by default. Use `--keep-instructions` to keep them.

## Policy snippet

Use this if you want to maintain a manual policy block instead of installer-managed instructions:

````md
# Signature Map first

1) Refresh before symbol-level navigation:

```bash
./scripts/sigmap refresh --root <repo_root>
```

2) Query declarations before broad scans:

```bash
./scripts/sigmap name <SymbolName> --root <repo_root> --no-refresh
./scripts/sigmap search "<regex>" --field all --icase --root <repo_root> --no-refresh
./scripts/sigmap open "<relative/file::symbol>" --root <repo_root> --context 60 --no-refresh
```

3) For call-site usage search, use `rg`:

```bash
rg -n "<symbol_or_pattern>" <repo_root>
```

4) Fallback order:

```bash
./scripts/sigmap doctor --root <repo_root>
# then scoped rg/sed scans only if needed
```
````

## Update / uninstall / doctor

```bash
./install.sh update --agent auto --scope global
./install.sh uninstall --agent both --scope local --project-root "$PWD"
./install.sh doctor --agent both --scope local --project-root "$PWD"
```

## Troubleshooting

| Problem | Check |
|---|---|
| `no supported agent environment detected` | run with explicit `--agent` and/or set `--codex-home` / `--claude-home` |
| `destination exists` | rerun with `--force` |
| local path mismatch (`.codex` vs `.agents`) | set `--codex-layout auto|codex|agents` |
| generator build error | ensure `go` is available in `PATH` |

## Security notes

- Prefer pinned refs/tags for remote installs in production workflows.
- Review installer scripts before piping to shell.
- This repo intentionally avoids personal absolute paths.

## Artifact policy

`<repo_root>/signatures.json` is generated. Do not commit unless explicitly requested.
