#!/usr/bin/env bash
# Smoke-test helper functions from demo-install.sh.
# Runs in CI (lint.yml → job `smoke`) and can be run locally:
#   bash .github/workflows/smoke-test.sh
#
# Strategy: we extract everything from the first helper (`typewrite`) down
# to the line before "НАЧАЛЬНОЕ МЕНЮ" (where the main flow starts). Those
# are all the function definitions. Then we source them into a test shell
# with stubbed colors/helpers and exercise the critical ones.

set -euo pipefail

INSTALLER="scripts/demo-install.sh"
FUNCS=/tmp/openclaw-funcs.sh
SMOKE=/tmp/openclaw-smoke-body.sh

# 1. Extract function definitions (from first helper to the last one).
#    We stop at the --collect-debug dispatcher block, which is main-flow code
#    referencing COLLECT_DEBUG_ONLY and must not be sourced in tests.
awk '/^typewrite\(\) \{/{capture=1} /--collect-debug: ручной сбор bundle/{exit} capture' "$INSTALLER" > "$FUNCS"

# 2. Build smoke-test body
cat > "$SMOKE" <<'BODY'
#!/usr/bin/env bash
set -euo pipefail

# Stub UI primitives (color codes are no-ops in CI)
RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; MAGENTA=''
WHITE=''; BOLD=''; DIM=''; ITALIC=''; NC=''
warn() { echo "WARN: $1"; }
ok() { echo "OK: $1"; }
ru() { echo "RU: $1"; }
INSTALLER_VERSION="ci-test"
INSTALLER_COMMIT="ci-test"
DRY_RUN=false

# shellcheck disable=SC1091
source /tmp/openclaw-funcs.sh

fail() { echo "✗ FAIL: $1"; exit 1; }
pass() { echo "✓ PASS: $1"; }

# ─── Test 1: diagnose_npm_eacces — case A (global /usr/local) ───
cat > /tmp/err-a.log <<EOL
npm ERR! code EACCES
npm ERR! Error: EACCES: permission denied, mkdir '/usr/local/lib/node_modules/openclaw'
EOL
if diagnose_npm_eacces /tmp/err-a.log; then
  pass "case A (global EACCES) detected"
else
  fail "case A (global EACCES) NOT detected"
fi

# ─── Test 2: diagnose_npm_eacces — case B (~/.npm cache) ───
cat > /tmp/err-b.log <<EOL
npm ERR! Error: EACCES: permission denied, open '/home/runner/.npm/_cacache/index'
EOL
if diagnose_npm_eacces /tmp/err-b.log; then
  pass "case B (~/.npm cache) detected"
else
  fail "case B (~/.npm cache) NOT detected"
fi

# ─── Test 3: diagnose_npm_eacces — NOT triggered on network errors ───
cat > /tmp/err-net.log <<EOL
npm ERR! network request to https://registry.npmjs.org/openclaw failed
npm ERR! code ETIMEDOUT
EOL
if diagnose_npm_eacces /tmp/err-net.log; then
  fail "false positive on network ETIMEDOUT"
else
  pass "ETIMEDOUT correctly ignored"
fi

# ─── Test 4: redact_secrets masks all common secret patterns ───
cat > /tmp/fake.json <<EOJ
{
  "apiKey": "sk-proj-abcdefghijklmnopqrstuvwxyz0123456789",
  "telegram": {"token": "7123456789:AAGk-abcdefghijklmnopqrstuvwxyzABCDE"},
  "authorization": "Bearer abc.def.xyz789"
}
EOJ
redact_secrets /tmp/fake.json
if grep -qE "sk-proj-[a-z0-9]{20,}|7[0-9]{9}:AAGk" /tmp/fake.json; then
  echo "file after redact:"
  cat /tmp/fake.json
  fail "secrets leaked through redact_secrets"
else
  pass "redact_secrets removed all secret patterns"
fi

# ─── Test 5: is_macos_admin returns an expected code per platform ───
# На macOS: 0 (admin) или 1 (не в admin group). На Linux: 2 (не Darwin).
if is_macos_admin; then
  rc=0
else
  rc=$?
fi
platform=$(uname)
if [[ "$platform" == "Darwin" ]]; then
  if [[ "$rc" == "0" || "$rc" == "1" ]]; then
    pass "is_macos_admin on macOS returned $rc (expected 0 or 1)"
  else
    fail "is_macos_admin on macOS returned $rc"
  fi
else
  if [[ "$rc" == "2" ]]; then
    pass "is_macos_admin on non-Darwin ($platform) returned 2"
  else
    fail "is_macos_admin on $platform returned $rc (expected 2)"
  fi
fi

echo ""
echo "=== All smoke tests passed ==="
BODY

# 3. Run it
bash "$SMOKE"
