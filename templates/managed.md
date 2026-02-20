# Signature Map (managed: {{TARGET_KIND}})

Scope: {{SCOPE_LABEL}}

Use Signature Map as the primary declaration index before broad repo scans.

1) Refresh map:
```bash
{{SIGMAP_CMD}} refresh --root <repo_root>
```

2) Query declarations:
```bash
{{SIGMAP_CMD}} name <SymbolName> --root <repo_root> --no-refresh
{{SIGMAP_CMD}} search "<regex>" --field all --icase --root <repo_root> --no-refresh
{{SIGMAP_CMD}} open "<relative/file/path::symbol>" --root <repo_root> --context 60 --no-refresh
```

3) Fallback:
```bash
{{SIGMAP_CMD}} doctor --root <repo_root>
# then use scoped rg/sed only if needed
```

