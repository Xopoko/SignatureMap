#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PYTHON_BIN="${PYTHON_BIN:-}"
if [[ -z "${PYTHON_BIN}" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    PYTHON_BIN="python3"
  else
    PYTHON_BIN="python"
  fi
fi

ROOT_DIR="${ROOT_DIR}" "${PYTHON_BIN}" - <<'PY'
import os
import re
import json

ROOT = os.environ.get("ROOT_DIR")
if not ROOT:
    raise SystemExit("ROOT_DIR environment variable is required")
ROOT = os.path.abspath(ROOT)

EXCLUDE_DIRS = {
    ".git",
    ".github",
    ".swiftpm",
    ".build",
    "build",
    "DerivedData",
    "Carthage",
    "Pods",
    "RemoteDependencies",
    "B2Core.xcworkspace",
    "Tuist/Dependencies",
    ".idea",
    ".vscode",
}
EXCLUDE_DIRS_LOWER = {d.lower() for d in EXCLUDE_DIRS}

ALLOWED_EXTS = {
    ".swift",
    ".m",
    ".mm",
    ".h",
    ".c",
    ".cc",
    ".cpp",
    ".hpp",
    ".js",
    ".jsx",
    ".ts",
    ".tsx",
    ".py",
    ".rb",
    ".sh",
    ".bash",
    ".zsh",
    ".kt",
    ".kts",
    ".java",
    ".groovy",
}

LANG_BY_EXT = {
    ".swift": "swift",
    ".m": "objc",
    ".mm": "objc",
    ".h": "objc",
    ".c": "c",
    ".cc": "cpp",
    ".cpp": "cpp",
    ".hpp": "cpp",
    ".js": "js",
    ".jsx": "js",
    ".ts": "ts",
    ".tsx": "ts",
    ".py": "py",
    ".rb": "rb",
    ".sh": "sh",
    ".bash": "sh",
    ".zsh": "sh",
    ".kt": "kt",
    ".kts": "kt",
    ".java": "java",
    ".groovy": "java",
}

HASH_COMMENT_LANGS = {"py", "rb", "sh"}
C_LIKE_LANGS = {"swift", "objc", "c", "cpp", "js", "ts", "kt", "java"}

SWIFT_KEYWORDS = re.compile(r"\b(func|init|deinit|subscript)\b")
SWIFT_FUNC_NAME = re.compile(r"\bfunc\b\s*([^\s(<]+)")
SWIFT_INIT_NAME = re.compile(r"\binit\b[!?]?")

OBJC_METHOD_START = re.compile(r"^\s*[-+]\s*\(")

PY_DEF = re.compile(r"^\s*(?:async\s+def|def)\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(")
RB_DEF = re.compile(r"^\s*def\s+([A-Za-z0-9_.!?=]+)")

JS_FUNC_DECL = re.compile(r"^\s*(?:export\s+)?(?:default\s+)?(?:async\s+)?function\s+([A-Za-z0-9_$]+)\s*\(")
JS_FUNC_EXPR = re.compile(r"^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z0-9_$]+)\s*=\s*(?:async\s+)?function\b")
JS_ARROW = re.compile(r"^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z0-9_$]+)\s*=\s*(?:async\s+)?(?:\([^=]*\)|[A-Za-z0-9_$]+)\s*=>")
JS_CLASS_METHOD_INLINE = re.compile(r"^\s*(?:async\s+)?(?:static\s+)?(?:get\s+|set\s+)?([A-Za-z0-9_$]+)\s*\([^)]*\)\s*\{")

KT_FUN = re.compile(r"^\s*(?:@[\w.]+\s+)*(?:public|private|protected|internal|final|open|override|inline|suspend|tailrec|operator|infix|external|abstract|companion|static|\s+)*\s*fun\s+([A-Za-z0-9_<>]+)\s*\(")
JAVA_METHOD = re.compile(r"^\s*(?:@[\w.]+\s+)*(?:public|private|protected|static|final|synchronized|abstract|native|strictfp|\s+)*\s*[\w<>\[\],\s]+\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(")

SH_FUNC = re.compile(r"^\s*(?:function\s+)?([A-Za-z0-9_]+)\s*\(\)\s*(?:\{|$)")

C_FUNC = re.compile(r"^\s*(?!if\b|for\b|while\b|switch\b|catch\b|return\b|typedef\b|struct\b|class\b|enum\b|#|using\b|namespace\b|template\b|static_assert\b)([A-Za-z_][A-Za-z0-9_\s\*\&:<>,\[\]]+?)\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(")

DECORATOR_LINE = re.compile(r"^\s*@")
PREPROCESSOR_LINE = re.compile(r"^\s*#(?:if|elseif|else|endif|define|undef|pragma|warning|error)\b")


def paren_delta(line: str) -> int:
    delta = 0
    in_s = False
    in_d = False
    esc = False
    for ch in line:
        if esc:
            esc = False
            continue
        if ch == "\\":
            esc = True
            continue
        if in_s:
            if ch == "'":
                in_s = False
            continue
        if in_d:
            if ch == '"':
                in_d = False
            continue
        if ch == "'":
            in_s = True
            continue
        if ch == '"':
            in_d = True
            continue
        if ch == "(":
            delta += 1
        elif ch == ")":
            delta -= 1
    return delta


def is_line_comment(line: str, lang: str) -> bool:
    s = line.lstrip()
    if not s:
        return False
    if lang in HASH_COMMENT_LANGS:
        return s.startswith("#")
    if lang in C_LIKE_LANGS:
        return s.startswith("//")
    return False


def is_block_comment_end(line: str, lang: str) -> bool:
    s = line.lstrip()
    if lang in C_LIKE_LANGS:
        return "*/" in s
    if lang == "rb":
        return s.strip() == "=end"
    if lang == "py":
        st = s.strip()
        return (st.startswith('"""') and st.count('"""') >= 2) or (st.startswith("'''") and st.count("'''") >= 2)
    return False


def is_block_comment_start(line: str, lang: str) -> bool:
    s = line.lstrip()
    if lang in C_LIKE_LANGS:
        return "/*" in s
    if lang == "rb":
        return s.strip() == "=begin"
    if lang == "py":
        st = s.strip()
        return st.startswith('"""') or st.startswith("'''")
    return False


def extract_comment(lines, idx, lang):
    i = idx - 1
    while i >= 0 and (DECORATOR_LINE.match(lines[i]) or (lang in C_LIKE_LANGS and PREPROCESSOR_LINE.match(lines[i]))):
        i -= 1
    if i < 0:
        return ""
    if lines[i].strip() == "":
        return ""
    line = lines[i]
    if is_line_comment(line, lang):
        comment_lines = [line.rstrip("\n")]
        i -= 1
        while i >= 0 and is_line_comment(lines[i], lang):
            comment_lines.append(lines[i].rstrip("\n"))
            i -= 1
        comment_lines.reverse()
        return "\n".join(comment_lines)
    if is_block_comment_end(line, lang) or is_block_comment_start(line, lang):
        comment_lines = [line.rstrip("\n")]
        i -= 1
        while i >= 0:
            comment_lines.append(lines[i].rstrip("\n"))
            if is_block_comment_start(lines[i], lang):
                break
            i -= 1
        comment_lines.reverse()
        return "\n".join(comment_lines)
    return ""

def normalize_comment(comment: str, lang: str) -> str:
    if not comment:
        return ""
    lines = comment.splitlines()
    cleaned = []
    for line in lines:
        stripped = line.lstrip()
        if lang in C_LIKE_LANGS:
            if stripped.startswith("//"):
                stripped = stripped[2:]
                if stripped.startswith(" "):
                    stripped = stripped[1:]
            if stripped.startswith("/*"):
                stripped = stripped[2:]
                if stripped.startswith(" "):
                    stripped = stripped[1:]
            if stripped.endswith("*/"):
                stripped = stripped[:-2].rstrip()
            if stripped.startswith("*"):
                stripped = stripped[1:]
                if stripped.startswith(" "):
                    stripped = stripped[1:]
        if lang in HASH_COMMENT_LANGS:
            if stripped.startswith("#"):
                stripped = stripped[1:]
                if stripped.startswith(" "):
                    stripped = stripped[1:]
        cleaned.append(stripped.rstrip())
    collapsed = []
    last_blank = False
    for line in cleaned:
        is_blank = (line.strip() == "")
        if is_blank:
            if not last_blank:
                collapsed.append("")
            last_blank = True
        else:
            collapsed.append(line)
            last_blank = False
    while collapsed and collapsed[0] == "":
        collapsed.pop(0)
    while collapsed and collapsed[-1] == "":
        collapsed.pop()
    return "\n".join(collapsed)

def normalize_signature(signature: str) -> str:
    if not signature:
        return ""
    lines = [ln.rstrip() for ln in signature.splitlines()]
    while lines and lines[0].strip() == "":
        lines.pop(0)
    while lines and lines[-1].strip() == "":
        lines.pop()
    indents = []
    for ln in lines:
        if ln.strip() == "":
            continue
        indent = len(ln) - len(ln.lstrip(" \t"))
        indents.append(indent)
    if indents:
        min_indent = min(indents)
        if min_indent > 0:
            lines = [ln[min_indent:] if len(ln) >= min_indent else ln.lstrip(" \t") for ln in lines]
    collapsed = []
    last_blank = False
    for ln in lines:
        blank = (ln.strip() == "")
        if blank:
            if not last_blank:
                collapsed.append("")
            last_blank = True
        else:
            collapsed.append(ln)
            last_blank = False
    return "\n".join(collapsed)


def collect_signature(lines, start_idx, stop_on_brace=True, stop_on_semicolon=True, allow_continuation=False):
    sig_lines = []
    paren = 0
    found_paren = False
    j = start_idx
    while j < len(lines):
        line = lines[j].rstrip("\n")
        sig_lines.append(line)
        paren += paren_delta(line)
        if "(" in line:
            found_paren = True
        line_has_brace = "{" in line if stop_on_brace else False
        line_has_semicolon = ";" in line if stop_on_semicolon else False
        end = False
        if line_has_brace or line_has_semicolon:
            end = True
        elif found_paren and paren == 0:
            if allow_continuation:
                nxt = lines[j + 1].lstrip() if j + 1 < len(lines) else ""
                if nxt.startswith(("where", "throws", "rethrows", "async", "->")):
                    j += 1
                    continue
            end = True
        if end:
            break
        j += 1
    if sig_lines and sig_lines[-1].strip() == "{" and len(sig_lines) > 1:
        sig_lines = sig_lines[:-1]
        j -= 1
    return "\n".join(sig_lines), j


def extract_objc_name(signature: str) -> str:
    s = re.sub(r"\s+", " ", signature.replace("\n", " ")).strip()
    parts = re.findall(r"([A-Za-z_][A-Za-z0-9_]*)\s*:", s)
    if parts:
        return ":".join(parts) + ":"
    m = re.search(r"\)\s*([A-Za-z_][A-Za-z0-9_]*)", s)
    if m:
        return m.group(1)
    return "unknown"


def should_skip_dir(path):
    lower = path.lower()
    for ex in EXCLUDE_DIRS_LOWER:
        if lower == ex or lower.endswith("/" + ex):
            return True
    return False


def detect_lang_and_ext(path, filename):
    ext = os.path.splitext(filename)[1].lower()
    if ext in ALLOWED_EXTS:
        return LANG_BY_EXT.get(ext, ""), ext
    if ext:
        return "", ext
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            first = f.readline().strip()
    except Exception:
        return "", ext
    if first.startswith("#!"):
        if "python" in first:
            return "py", ext
        if "ruby" in first:
            return "rb", ext
        if "bash" in first or "sh" in first or "zsh" in first:
            return "sh", ext
    return "", ext


def gather_signatures(lines, lang):
    results = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if line.strip() == "" or is_line_comment(line, lang):
            i += 1
            continue
        if lang == "swift":
            if not SWIFT_KEYWORDS.search(line):
                i += 1
                continue
            if not SWIFT_FUNC_NAME.search(line) and not SWIFT_INIT_NAME.search(line) and "deinit" not in line and "subscript" not in line:
                i += 1
                continue
            if "func" in line:
                m = SWIFT_FUNC_NAME.search(line)
                if not m:
                    i += 1
                    continue
                name = m.group(1)
            elif "init" in line:
                m = SWIFT_INIT_NAME.search(line)
                name = m.group(0) if m else "init"
            elif "deinit" in line:
                name = "deinit"
            else:
                name = "subscript"
            sig, end_idx = collect_signature(lines, i, stop_on_brace=True, stop_on_semicolon=True, allow_continuation=True)
            results.append((i, name, sig))
            i = end_idx + 1
            continue
        if lang == "objc":
            if OBJC_METHOD_START.match(line):
                sig, end_idx = collect_signature(lines, i, stop_on_brace=True, stop_on_semicolon=True, allow_continuation=False)
                name = extract_objc_name(sig)
                results.append((i, name, sig))
                i = end_idx + 1
                continue
            if C_FUNC.match(line):
                m = C_FUNC.match(line)
                name = m.group(2)
                sig, end_idx = collect_signature(lines, i, stop_on_brace=True, stop_on_semicolon=True, allow_continuation=False)
                results.append((i, name, sig))
                i = end_idx + 1
                continue
        if lang in {"c", "cpp"}:
            m = C_FUNC.match(line)
            if m:
                name = m.group(2)
                sig, end_idx = collect_signature(lines, i, stop_on_brace=True, stop_on_semicolon=True, allow_continuation=False)
                results.append((i, name, sig))
                i = end_idx + 1
                continue
        if lang in {"js", "ts"}:
            m = JS_FUNC_DECL.match(line) or JS_FUNC_EXPR.match(line) or JS_ARROW.match(line)
            if m:
                name = m.group(1)
                sig, end_idx = collect_signature(lines, i, stop_on_brace=True, stop_on_semicolon=True, allow_continuation=False)
                results.append((i, name, sig))
                i = end_idx + 1
                continue
            m = JS_CLASS_METHOD_INLINE.match(line)
            if m:
                name = m.group(1)
                sig, end_idx = collect_signature(lines, i, stop_on_brace=True, stop_on_semicolon=True, allow_continuation=False)
                results.append((i, name, sig))
                i = end_idx + 1
                continue
        if lang == "py":
            m = PY_DEF.match(line)
            if m:
                name = m.group(1)
                sig, end_idx = collect_signature(lines, i, stop_on_brace=False, stop_on_semicolon=False, allow_continuation=False)
                results.append((i, name, sig))
                i = end_idx + 1
                continue
        if lang == "rb":
            m = RB_DEF.match(line)
            if m:
                name = m.group(1)
                sig, end_idx = collect_signature(lines, i, stop_on_brace=False, stop_on_semicolon=False, allow_continuation=False)
                results.append((i, name, sig))
                i = end_idx + 1
                continue
        if lang == "sh":
            m = SH_FUNC.match(line)
            if m:
                name = m.group(1)
                sig = line.rstrip("\n")
                results.append((i, name, sig))
                i += 1
                continue
        if lang == "kt":
            m = KT_FUN.match(line)
            if m:
                name = m.group(1)
                sig, end_idx = collect_signature(lines, i, stop_on_brace=True, stop_on_semicolon=True, allow_continuation=False)
                results.append((i, name, sig))
                i = end_idx + 1
                continue
        if lang == "java":
            m = JAVA_METHOD.match(line)
            if m:
                name = m.group(1)
                sig, end_idx = collect_signature(lines, i, stop_on_brace=True, stop_on_semicolon=True, allow_continuation=False)
                results.append((i, name, sig))
                i = end_idx + 1
                continue
        i += 1
    return results


entries = []

for root, dirs, files in os.walk(ROOT):
    for d in list(dirs):
        rel = os.path.relpath(os.path.join(root, d), ROOT)
        if should_skip_dir(rel):
            dirs.remove(d)
    for filename in files:
        path = os.path.join(root, filename)
        relpath = os.path.relpath(path, ROOT)
        lang, ext = detect_lang_and_ext(path, filename)
        if not lang:
            if ext not in ALLOWED_EXTS and ext != "":
                continue
            if ext == "" and not lang:
                continue
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as f:
                lines = f.readlines()
        except Exception:
            continue
        results = gather_signatures(lines, lang)
        for (idx, name, sig) in results:
            comment = normalize_comment(extract_comment(lines, idx, lang), lang)
            entry = {
                "path": f"{relpath}::{name}",
                "signature": normalize_signature(sig),
                "comment": comment,
                "line": idx + 1,
            }
            entries.append(entry)

out_path = os.path.join(ROOT, "signatures.json")
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(entries, f, ensure_ascii=True, indent=2)

with open(out_path, "r", encoding="utf-8") as f:
    json.load(f)

print(f"Wrote {len(entries)} signatures to {out_path}")
PY
