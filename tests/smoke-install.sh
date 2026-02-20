#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALLER="${ROOT_DIR}/install.sh"

TMP_ROOT="$(mktemp -d 2>/dev/null || mktemp -d -t sigmap-smoke-install)"
PROJECT_ROOT="${TMP_ROOT}/project"
mkdir -p "${PROJECT_ROOT}"

cleanup() {
  rm -rf "${TMP_ROOT}"
}
trap cleanup EXIT

assert_file() {
  local f="$1"
  [[ -f "${f}" ]] || {
    echo "ASSERT FAILED: file not found: ${f}" >&2
    exit 1
  }
}

assert_contains() {
  local f="$1"
  local s="$2"
  grep -Fq "${s}" "${f}" || {
    echo "ASSERT FAILED: '${s}' not found in ${f}" >&2
    exit 1
  }
}

echo "[smoke-install] codex global install"
"${INSTALLER}" install --agent codex --scope global --codex-home "${TMP_ROOT}/codex-home"
assert_file "${TMP_ROOT}/codex-home/skills/signature-map/SKILL.md"
assert_file "${TMP_ROOT}/codex-home/skills/signature-map/scripts/sigmap"
assert_file "${TMP_ROOT}/codex-home/skills/signature-map/agents/openai.yaml"
assert_file "${TMP_ROOT}/codex-home/AGENTS.md"
assert_contains "${TMP_ROOT}/codex-home/AGENTS.md" "BEGIN signature-map managed"

echo "[smoke-install] claude global install"
"${INSTALLER}" install --agent claude --scope global --claude-home "${TMP_ROOT}/claude-home"
assert_file "${TMP_ROOT}/claude-home/skills/signature-map/SKILL.md"
assert_file "${TMP_ROOT}/claude-home/skills/signature-map/scripts/sigmap"
if [[ -f "${TMP_ROOT}/claude-home/skills/signature-map/agents/openai.yaml" ]]; then
  echo "ASSERT FAILED: codex-only metadata copied to claude payload" >&2
  exit 1
fi
assert_file "${TMP_ROOT}/claude-home/CLAUDE.md"
assert_contains "${TMP_ROOT}/claude-home/CLAUDE.md" "BEGIN signature-map managed"

echo "[smoke-install] both local install"
"${INSTALLER}" install --agent both --scope local --project-root "${PROJECT_ROOT}"
assert_file "${PROJECT_ROOT}/.codex/skills/signature-map/SKILL.md"
assert_file "${PROJECT_ROOT}/.claude/skills/signature-map/SKILL.md"
assert_file "${PROJECT_ROOT}/AGENTS.md"
assert_file "${PROJECT_ROOT}/CLAUDE.md"
assert_contains "${PROJECT_ROOT}/AGENTS.md" "BEGIN signature-map managed"
assert_contains "${PROJECT_ROOT}/CLAUDE.md" "BEGIN signature-map managed"

echo "[smoke-install] idempotent update"
"${INSTALLER}" update --agent both --scope local --project-root "${PROJECT_ROOT}"
assert_file "${PROJECT_ROOT}/AGENTS.md"
assert_file "${PROJECT_ROOT}/CLAUDE.md"

begin_count="$(grep -c "BEGIN signature-map managed" "${PROJECT_ROOT}/AGENTS.md")"
[[ "${begin_count}" == "1" ]] || {
  echo "ASSERT FAILED: AGENTS managed block duplicated" >&2
  exit 1
}

echo "[smoke-install] uninstall removes managed blocks"
"${INSTALLER}" uninstall --agent both --scope local --project-root "${PROJECT_ROOT}"
if [[ -d "${PROJECT_ROOT}/.codex/skills/signature-map" || -d "${PROJECT_ROOT}/.claude/skills/signature-map" ]]; then
  echo "ASSERT FAILED: local skill dirs were not removed" >&2
  exit 1
fi
if grep -Fq "BEGIN signature-map managed" "${PROJECT_ROOT}/AGENTS.md" 2>/dev/null; then
  echo "ASSERT FAILED: AGENTS managed block not removed" >&2
  exit 1
fi
if grep -Fq "BEGIN signature-map managed" "${PROJECT_ROOT}/CLAUDE.md" 2>/dev/null; then
  echo "ASSERT FAILED: CLAUDE managed block not removed" >&2
  exit 1
fi

echo "[smoke-install] leak scan"
if rg -n --hidden --glob '!.git' --glob '!scripts/.bin/**' --glob '!tests/**' '(/Users/|Projects/Work|B2Broker|B2A|B2Core)' "${ROOT_DIR}"; then
  echo "ASSERT FAILED: sensitive markers detected" >&2
  exit 1
fi

if [[ "${RUN_REMOTE_TEST:-0}" == "1" ]]; then
  echo "[smoke-install] remote bootstrap"
  REMOTE_HOME="${TMP_ROOT}/remote-codex-home"
  "${INSTALLER}" install --source github --repo "${REMOTE_REPO:-Xopoko/SignatureMap}" --ref "${REMOTE_REF:-main}" --agent codex --scope global --codex-home "${REMOTE_HOME}" --force
  assert_file "${REMOTE_HOME}/skills/signature-map/SKILL.md"
fi

echo "[smoke-install] OK"
