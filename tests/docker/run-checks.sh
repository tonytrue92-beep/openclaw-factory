#!/usr/bin/env bash
# Быстрый smoke-прогон внутри Docker-контейнера.
# Отрабатывает ~15-30 секунд.
#
# Scope: синтаксис + non-interactive флаги + preflight + CI-smoke.
# Out-of-scope: полная R1-R6 установка, реальный OpenClaw CLI.

set -euo pipefail

cd /opt/openclaw-factory

pass() { echo "✓ $1"; }
fail() { echo "✗ $1"; exit 1; }

echo "=== Docker smoke for $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"' || uname -s) ==="
echo "    Node: $(node -v), npm: $(npm -v)"
echo ""

# 1. bash -n
for f in scripts/*.sh; do
  bash -n "$f" || fail "bash -n failed on $f"
done
pass "bash -n on all scripts"

# 2. --version
ver=$(bash scripts/demo-install.sh --version 2>&1)
echo "$ver" | grep -qE "OpenClaw Factory Installer v[0-9]{4}\.[0-9]{2}\.[0-9]{2}" || fail "--version output wrong: $ver"
pass "--version: $ver"

# 3. --help
bash scripts/demo-install.sh --help >/dev/null 2>&1 || fail "--help exited with error"
pass "--help runs without error"

# 4. --diagnose-only — ожидаем non-zero exit (OpenClaw не установлен),
#    но НЕ крэш скрипта с синтаксической ошибкой.
diag_output=$(bash scripts/demo-install.sh --diagnose-only 2>&1 || true)
if echo "$diag_output" | grep -q "LIVE ДИАГНОСТИКА"; then
  pass "--diagnose-only runs cleanly (detects missing openclaw as expected)"
else
  fail "--diagnose-only crashed without printing header"
fi

# 5. CI smoke-test script works inside the container too
bash .github/workflows/smoke-test.sh > /tmp/smoke.log 2>&1 || {
  echo "--- smoke-test.sh log ---"
  cat /tmp/smoke.log
  fail "CI smoke-test.sh failed"
}
pass "CI smoke-test.sh passed"

# 5.5. Course-token runtime bootstrap regression test
bash tests/course-token-runtime-test.sh > /tmp/course-token-runtime.log 2>&1 || {
  echo "--- course-token-runtime-test.sh log ---"
  cat /tmp/course-token-runtime.log
  fail "course-token runtime regression test failed"
}
pass "course-token runtime regression test passed"

# 6. security-audit
bash .github/workflows/security-audit.sh > /tmp/sec.log 2>&1 || {
  echo "--- security-audit.sh log ---"
  cat /tmp/sec.log
  fail "security audit failed"
}
pass "security-audit.sh passed"

echo ""
echo "=== All docker smoke checks passed ==="
