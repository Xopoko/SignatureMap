#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGMAP="${ROOT_DIR}/scripts/sigmap"

TMP_REPO="$(mktemp -d 2>/dev/null || mktemp -d -t sigmap-smoke-runtime)"
cleanup() {
  rm -rf "${TMP_REPO}"
}
trap cleanup EXIT

mkdir -p "${TMP_REPO}/src"
cat > "${TMP_REPO}/src/main.swift" <<'SWIFT'
/// Demo type
class DemoType {
    /// Demo callable
    func demoMethod() {}
}
SWIFT

cat > "${TMP_REPO}/src/helper.py" <<'PY'
class Helper:
    def work(self):
        return 1
PY

"${SIGMAP}" refresh --root "${TMP_REPO}"
"${SIGMAP}" doctor --root "${TMP_REPO}" --json >/dev/null

"${SIGMAP}" name DemoType --kind type --root "${TMP_REPO}" --no-refresh >/dev/null
"${SIGMAP}" search "demoMethod" --kind callable --root "${TMP_REPO}" --no-refresh >/dev/null

set +e
"${SIGMAP}" name __missing_symbol__ --root "${TMP_REPO}" --no-refresh >/dev/null 2>&1
rc_empty=$?
"${SIGMAP}" name __missing_symbol__ --root "${TMP_REPO}" --no-refresh --strict-empty >/dev/null 2>&1
rc_strict=$?
set -e

if [[ "${rc_empty}" != "0" ]]; then
  echo "ASSERT FAILED: empty query should return 0" >&2
  exit 1
fi
if [[ "${rc_strict}" != "1" ]]; then
  echo "ASSERT FAILED: --strict-empty should return 1" >&2
  exit 1
fi

echo "[smoke-sigmap] OK"
