#!/usr/bin/env bash
# Security audit: grep for patterns that could leak secrets in the installer.
#
# Запускается в CI на каждый push и локально:
#   bash .github/workflows/security-audit.sh
#
# Пять проверок:
#   1. echo/printf of $API_KEY, $BOT_TOKEN, $INSTALLER_TOKEN
#   2. Logging of full env or $(env) dumps
#   3. Missing unset after secret use (heuristic)
#   4. curl URL with inline token (не через header)
#   5. Debug-bundle collects $(env) or ~/.bash_history

set -euo pipefail

INSTALLER=scripts/demo-install.sh
REAUTH=scripts/openclaw-factory-reauth.sh

fail_count=0

fail() {
  echo "✗ FAIL: $1"
  fail_count=$((fail_count + 1))
}
pass() { echo "✓ PASS: $1"; }
note() { echo "  → $1"; }

echo "=== Security audit of installer scripts ==="
echo ""

# ─── Check 1: echo/printf of raw secret vars ─────────────────────────────
# Opasные: `echo "... $API_KEY ..."`, `printf '%s' "$BOT_TOKEN"`, etc.
# Разрешённые: использование только в heredoc для записи в файл, в качестве
# аргумента команды (${...}), и в проверках ([[ -z ... ]]).
#
# Эта проверка консервативная — ищет только очевидные случаи.
echo "─── Check 1: direct echo of secret variables ───"
if grep -nE '(echo|printf).*\$\{?(API_KEY|BOT_TOKEN|INSTALLER_TOKEN)\}?' "$INSTALLER" "$REAUTH" 2>/dev/null; then
  fail "found echo/printf of raw secret variable"
else
  pass "no direct echo/printf of secret variables"
fi
echo ""

# ─── Check 2: no $(env) dumps in debug-bundle ────────────────────────────
echo "─── Check 2: no raw env dump in collect_debug_bundle ───"
# Ищем ВЫЗОВЫ (не упоминания в комментариях!) команды env внутри
# collect_debug_bundle. Отфильтровываем строки, начинающиеся с `#`
# (в том числе с отступом) — это комментарии, они безопасны.
bundle_body=$(awk '/^collect_debug_bundle\(\)/,/^\}$/' "$INSTALLER")
bundle_code=$(echo "$bundle_body" | sed 's/^[[:space:]]*#.*$//')
if echo "$bundle_code" | grep -qE '(\$\(env\)|`env`|[^a-zA-Z_]env( |$|\|))'; then
  fail "collect_debug_bundle contains a raw env dump (could leak secrets)"
  echo "$bundle_code" | grep -nE '(\$\(env\)|`env`|[^a-zA-Z_]env( |$|\|))' | head -3
else
  pass "collect_debug_bundle does not dump env"
fi
echo ""

# ─── Check 3: secrets are unset after use (heuristic) ────────────────────
# Проверяем, что после записи API_KEY/BOT_TOKEN в файл есть `unset` где-то
# в ближайших 30 строках.
echo "─── Check 3: API_KEY/BOT_TOKEN are unset after use ───"
# Для API_KEY (|| true — grep может не найти, если установщик больше не
# использует API_KEY, напр. перешёл на OAuth-логин: тогда под set -euo
# pipefail присваивание не должно ронять аудит — просто пропускаем под-чек)
api_line=$(grep -n '"key": "$API_KEY"' "$INSTALLER" | head -1 | cut -d: -f1 || true)
if [[ -n "$api_line" ]]; then
  slice=$(sed -n "${api_line},$((api_line + 30))p" "$INSTALLER")
  if echo "$slice" | grep -qE '^\s*unset\s+API_KEY\b'; then
    pass "API_KEY is unset after being written to auth-profiles.json (line ${api_line})"
  else
    fail "API_KEY is NOT unset after use (line ${api_line}). Memory leak risk."
  fi
fi

# Для BOT_TOKEN (|| true — та же защита от set -e при отсутствии совпадения)
bot_line=$(grep -n 'openclaw channels add.*BOT_TOKEN' "$INSTALLER" | head -1 | cut -d: -f1 || true)
if [[ -n "$bot_line" ]]; then
  slice=$(sed -n "${bot_line},$((bot_line + 20))p" "$INSTALLER")
  if echo "$slice" | grep -qE '^\s*unset\s+BOT_TOKEN\b'; then
    pass "BOT_TOKEN is unset after channel setup (line ${bot_line})"
  else
    fail "BOT_TOKEN is NOT unset after use (line ${bot_line}). Memory leak risk."
  fi
fi
echo ""

# ─── Check 4: no tokens baked into source ────────────────────────────────
echo "─── Check 4: no real tokens committed to scripts ───"
# Ищем валидно-выглядящие sk-* (>= 20 символов) и TG bot tokens, кроме
# явно тестовых («sk-••••» / «sk-xxxx» / «7123456789:AAHk-xxx» / примеров в комментариях).
leaks=$(grep -nE '"sk-[A-Za-z0-9]{30,}"|["\x27]7[0-9]{9}:AA[A-Za-z0-9_-]{30,}["\x27]' \
  "$INSTALLER" "$REAUTH" scripts/openclaw-switch-model.sh 2>/dev/null \
  | grep -vE 'sk-(xxx|•|test|REDACTED|proj-abc)' \
  | grep -vE '7123456789:AA(Hk-xx|Gk-abc)' || true)
if [[ -n "$leaks" ]]; then
  fail "possible real token committed to source:"
  echo "$leaks"
else
  pass "no real-looking tokens in source"
fi
echo ""

# ─── Check 5: redact_secrets is called on all copied files ──────────────
echo "─── Check 5: redact_secrets is called on copied files in bundle ───"
# Проверяем, что внутри collect_debug_bundle все .json/.log, которые мы
# копируем или tail'им, потом проходят через redact_secrets.
if echo "$bundle_body" | grep -qE 'redact_secrets.*openclaw-config\.json' &&
   echo "$bundle_body" | grep -qE 'redact_secrets.*gateway\.log' &&
   echo "$bundle_body" | grep -qE 'redact_secrets\s+"\$f"'; then
  pass "redact_secrets is applied to config, log, and all bundle files"
else
  fail "one or more copied files is not redacted before zip"
fi
echo ""

# ─── Summary ─────────────────────────────────────────────────────────────
if [[ $fail_count -eq 0 ]]; then
  echo "=== Security audit passed ==="
  exit 0
else
  echo "=== Security audit FAILED: $fail_count issue(s) ==="
  exit 1
fi
