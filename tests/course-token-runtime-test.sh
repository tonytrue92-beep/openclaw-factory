#!/usr/bin/env bash
# Regression test for token validation on fresh macOS machines without Node.js.
# R0 course-token verification needs Ed25519 crypto. macOS LibreSSL cannot do
# the fallback, so the installer must bootstrap/prompt for Node before trying
# to validate a perfectly valid token.

set -euo pipefail

cd "$(dirname "$0")/.."

FUNCS="${TMPDIR:-/tmp}/openclaw-factory-funcs.$$"
trap 'rm -f "$FUNCS"' EXIT

python3 - <<'PY' > "$FUNCS"
from pathlib import Path
text = Path('scripts/demo-install.sh').read_text()
start = text.index('typewrite() {')
end = text.index('# ═══════════════════════════════════════════════════════════════\n#  НАЧАЛЬНОЕ МЕНЮ')
print(text[start:end])
PY

RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; MAGENTA=''
WHITE=''; BOLD=''; DIM=''; ITALIC=''; NC=''
INSTALLER_VERSION='test'
INSTALLER_COMMIT='test'
DRY_RUN=false
VPS_MODE=false
COLLECT_DEBUG_ONLY=false
DIAGNOSE_ONLY=false
warn() { echo "WARN: $1"; }
ok() { echo "OK: $1"; }
ru() { echo "RU: $1"; }
explain() { :; }
pause() { :; }

# shellcheck disable=SC1090
source "$FUNCS"

fail() { echo "✗ $1"; exit 1; }
pass() { echo "✓ $1"; }

# The helper must exist; before the fix this test fails here.
declare -F ensure_course_token_crypto_runtime >/dev/null \
  || fail "ensure_course_token_crypto_runtime is missing"
declare -F course_token_crypto_runtime_available >/dev/null \
  || fail "course_token_crypto_runtime_available is missing"

# Simulate a fresh machine: crypto runtime unavailable until Node bootstrap runs.
install_called=0
course_token_crypto_runtime_available() {
  [[ "$install_called" == "1" ]]
}
prompt_install_node() {
  install_called=1
}

ensure_course_token_crypto_runtime
[[ "$install_called" == "1" ]] \
  || fail "ensure_course_token_crypto_runtime did not bootstrap Node when crypto runtime was missing"
pass "course-token runtime bootstrap triggers Node install when crypto runtime is missing"

# If a crypto runtime is already present, it must not prompt/install again.
install_called=0
course_token_crypto_runtime_available() {
  return 0
}
prompt_install_node() {
  fail "prompt_install_node should not run when crypto runtime is already available"
}

ensure_course_token_crypto_runtime
[[ "$install_called" == "0" ]] \
  || fail "unexpected install call when crypto runtime is available"
pass "course-token runtime bootstrap is skipped when crypto runtime is available"
