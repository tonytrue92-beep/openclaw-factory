#!/usr/bin/env bash
# shellcheck disable=SC2034
# Regression test for token validation on fresh macOS machines without Node.js.
# R0 course-token verification needs Ed25519 crypto. macOS LibreSSL cannot do
# the fallback, so the installer must bootstrap/prompt for Node before trying
# to validate a perfectly valid token.

set -euo pipefail

cd "$(dirname "$0")/.."

FUNCS="${TMPDIR:-/tmp}/openclaw-factory-funcs.$$"
trap 'rm -f "$FUNCS"' EXIT

awk '
  /^typewrite\(\) \{/ { capture=1 }
  /^#  НАЧАЛЬНОЕ МЕНЮ/ { exit }
  capture { print }
' scripts/demo-install.sh > "$FUNCS"

# Stubs consumed by sourced helper functions; shellcheck cannot see those dynamic reads.
# shellcheck disable=SC2034
RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; MAGENTA=''
# shellcheck disable=SC2034
WHITE=''; BOLD=''; DIM=''; ITALIC=''; NC=''
# shellcheck disable=SC2034
INSTALLER_VERSION='test'
# shellcheck disable=SC2034
INSTALLER_COMMIT='test'
# shellcheck disable=SC2034
DRY_RUN=false
# shellcheck disable=SC2034
VPS_MODE=false
# shellcheck disable=SC2034
COLLECT_DEBUG_ONLY=false
# shellcheck disable=SC2034
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
