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

# OPENCLAW_VERSION (пин движка) объявлен на верхнем уровне ВЫШЕ typewrite() —
# awk его не захватывает. Инжектим реальную декларацию из установщика, иначе
# функции с `openclaw@${OPENCLAW_VERSION}` падают под set -u в тестах.
grep -m1 '^OPENCLAW_VERSION=' "$INSTALLER" >> "$FUNCS"

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

# ─── Static checks: объединённый установщик (Phase A) ───
echo ""
echo "=== Static checks (unified installer) ==="
grep -q 'ENGINE_ONLY=false' "$INSTALLER" \
  || { echo "✗ FAIL: нет дефолта ENGINE_ONLY=false"; exit 1; }
grep -qE '^[[:space:]]*--engine-only\)' "$INSTALLER" \
  || { echo "✗ FAIL: нет кейса --engine-only"; exit 1; }
grep -q 'ENGINE_ONLY=true' "$INSTALLER" \
  || { echo "✗ FAIL: --engine-only не ставит ENGINE_ONLY=true"; exit 1; }
grep -q 'install-agents-bundled.sh' "$INSTALLER" \
  || { echo "✗ FAIL: нет чейна на install-agents-bundled.sh"; exit 1; }
grep -Fq '"${COURSE_TIER:-}" == "STD" || "${COURSE_TIER:-}" == "VIP"' "$INSTALLER" \
  || { echo "✗ FAIL: чейн не обусловлен STD/VIP"; exit 1; }
grep -q 'ENGINE_ONLY:-false' "$INSTALLER" \
  || { echo "✗ FAIL: чейн не уважает --engine-only"; exit 1; }
echo "✓ PASS: unified installer (--engine-only + чейн STD/VIP) на месте"

# ─── Static checks: устойчивая дотяжка агентов (обход 504) ───
grep -q '_fetch_agents_installer()' "$INSTALLER" \
  || { echo "✗ FAIL: нет хелпера _fetch_agents_installer"; exit 1; }
grep -q 'releases/download/' "$INSTALLER" \
  || { echo "✗ FAIL: нет фоллбэка на прямой тег (releases/download/)"; exit 1; }
# git-clone fallback УБРАН (приватные репо → git просит GitHub-логин = фишинг-вид).
# Доставка: gateway (block 0) → releases/latest → прямой тег. Без git clone.
if grep -q 'git clone --depth 1' "$INSTALLER"; then
  echo "✗ FAIL: вернулся git-clone fallback — на приватном репо просит GitHub-логин"; exit 1
fi
echo "✓ PASS: устойчивая дотяжка агентов (gateway → latest → тег; без git clone)"

# ─── Static checks: хелпер openclaw-add-codex ───
[[ -f scripts/openclaw-add-codex.sh ]] \
  || { echo "✗ FAIL: нет scripts/openclaw-add-codex.sh"; exit 1; }
bash -n scripts/openclaw-add-codex.sh \
  || { echo "✗ FAIL: синтаксис openclaw-add-codex.sh"; exit 1; }
grep -q 'models auth login --provider "$PROVIDER"' scripts/openclaw-add-codex.sh \
  || { echo "✗ FAIL: add-codex не логинит через provider"; exit 1; }
grep -q 'openclaw-add-codex.sh' "$INSTALLER" \
  || { echo "✗ FAIL: установщик не ставит openclaw-add-codex"; exit 1; }
echo "✓ PASS: хелпер openclaw-add-codex (ChatGPT мозги) на месте + ставится"

# ─── Static checks: аудит R2 ───
grep -q '_agents_run --vps' "$INSTALLER" \
  || { echo "✗ FAIL: чейн не пробрасывает --vps"; exit 1; }
grep -q 'plugins.entries.bonjour.enabled false' "$INSTALLER" \
  || { echo "✗ FAIL: factory не отключает bonjour на VPS"; exit 1; }
grep -q '_chain_fail' "$INSTALLER" \
  || { echo "✗ FAIL: нет раздельной диагностики чейна (fetch vs child)"; exit 1; }
grep -q 'HRM-\*' "$INSTALLER" \
  || { echo "✗ FAIL: нет целевого сообщения для HRM-токена"; exit 1; }
grep -q '_tok_tg' "$INSTALLER" \
  || { echo "✗ FAIL: TG ID не префиллится из токена"; exit 1; }
grep -q '{80,120}' "$INSTALLER" \
  && { echo "✗ FAIL: остался regex {80,120} (должен быть {80,100})"; exit 1; }
echo "✓ PASS: аудит R2 (--vps чейн, bonjour, диагностика, HRM, TG-префилл)"

# ─── Хотфикс по саппорту 2026-06-10: opencode-go ───
grep -q 'opencode-go/deepseek-v4-flash' scripts/demo-install.sh \
  || { echo "FAIL: дефолт-модель не opencode-go/deepseek-v4-flash"; exit 1; }
grep -q 'opencode/minimax-m2.5-free' scripts/demo-install.sh \
  && { echo "FAIL: остался мёртвый opencode/minimax-m2.5-free"; exit 1; }
grep -q 'Вставьте API-ключ opencode.ai и нажмите Enter' scripts/demo-install.sh \
  && { echo "FAIL: шаг ввода ключа вернулся в установку"; exit 1; }
grep -q 'Никаких ключей и моделей на этом шаге' scripts/demo-install.sh \
  || { echo "FAIL: R3 не безключевой"; exit 1; }
grep -q 'Остался один шаг — выбрать модель' scripts/demo-install.sh \
  || { echo "FAIL: в финале нет рекомендации выбрать модель"; exit 1; }
grep -q 'NODE_MAJOR" -eq 22' scripts/demo-install.sh \
  || { echo "FAIL: нет гейта «ровно Node 22»"; exit 1; }
echo "OK: hotfix 2026-06-10 (opencode-go + node22 gate)"

# ─── Скип R4/R5 при готовой установке (живой прогон 2026-06-10) ───
grep -q 'TG_ALREADY_CONFIGURED=true' scripts/demo-install.sh \
  || { echo "FAIL: нет R4-гейта Telegram-уже-подключён"; exit 1; }
grep -q 'AGENT_ALREADY_EXISTS=true' scripts/demo-install.sh \
  || { echo "FAIL: нет R5-гейта агент-уже-есть"; exit 1; }
grep -q 'fi  # TG_ALREADY_CONFIGURED' scripts/demo-install.sh \
  || { echo "FAIL: R4-гейт не закрыт перед R5"; exit 1; }
grep -q 'fi  # AGENT_ALREADY_EXISTS' scripts/demo-install.sh \
  || { echo "FAIL: R5-гейт не закрыт перед R6"; exit 1; }
grep -q 'TELEGRAM_CONNECTED=true' scripts/demo-install.sh \
  || { echo "FAIL: скип-ветка не проставляет TELEGRAM_CONNECTED"; exit 1; }
echo "OK: повторный запуск поверх готовой установки не просит токен/агента заново"

# ─── Меню из 3 боевых пунктов (решение Антона 2026-06-11) ───
grep -q 'Установить AI-команду агентов' scripts/demo-install.sh \
  || { echo "FAIL: нет пункта «Установить AI-команду агентов»"; exit 1; }
grep -q 'Выберите вариант \[1/2/3, Enter = 1\]' scripts/demo-install.sh \
  || { echo "FAIL: меню не [1/2/3, Enter = 1]"; exit 1; }
grep -qE '^\s+echo -e .*Демо.*— посмотреть процесс' scripts/demo-install.sh \
  && { echo "FAIL: пункт «Демо» всё ещё в меню"; exit 1; }
echo "OK: главное меню — 3 пункта (установка / агенты / VPS)"

# ─── IP-gated доставка (2026-06-14) ───
grep -q 'ip_dl()' scripts/demo-install.sh || { echo "FAIL: ip_dl нет в factory"; exit 1; }
grep -q 'IP_BASE="${IP_BASE:-}"; \[\[ -n "$IP_BASE" \]\] && export IP_BASE' scripts/demo-install.sh || { echo "FAIL: IP_BASE не экспортится в чейн"; exit 1; }
grep -q 'installers/agents.sh" -o "$tmp"' scripts/demo-install.sh || { echo "FAIL: agents-fetch без gateway-ветки"; exit 1; }
grep -qF 'curl -fsSL --connect-timeout 10 --max-time 25 "$2" -o "$3"' scripts/demo-install.sh || { echo "FAIL: github-ветка ip_dl не чистая"; exit 1; }
grep -q 'for _try in 1 2 3' scripts/demo-install.sh || { echo "FAIL: ip_dl без ретраев — блип сети потеряет хелпер/файл"; exit 1; }
echo "OK: factory ip_dl шов + ретраи + чейн наследует IP_BASE + agents через gateway"

# ─── VPS-команда и fallback'ы не должны быть мёртвыми raw/release (private) ───
# busybox grep (alpine CI) не поддерживает context-флаг -A → пустой блок → ложный
# FAIL (хронически красная alpine-джоба). Тело функции извлекаем через awk
# (портабельно gawk/busybox-awk/BSD-awk), матчим через awk index() — без grep
# regex/локали на строке с кириллицей ВАШ_ТОКЕН.
_vps_body=$(awk '/^show_vps_guide\(\)/{c=1} c&&c++<=61' scripts/demo-install.sh)
printf '%s\n' "$_vps_body" | awk 'index($0,"raw.githubusercontent")&&index($0,"demo-install"){exit 1}' \
  || { echo "FAIL: show_vps_guide печатает мёртвую raw-команду"; exit 1; }
printf '%s\n' "$_vps_body" | awk 'index($0,"IP_BASE=https://api.tonytrue.pro/ip"){f=1} END{exit !f}' \
  || { echo "FAIL: VPS-гайд без gateway-команды"; exit 1; }
grep -qE 'echo.*releases/latest/download/install-agents-bundled' scripts/demo-install.sh \
  && { echo "FAIL: остался печатаемый мёртвый release-fallback"; exit 1; }
echo "OK: VPS-команда и fallback'ы — через gateway/бота (не мёртвый raw)"

# ─── Плейсхолдер токена без угловых скобок (иначе gateway 401) ───
grep -qE 'COURSE_TOKEN=<' scripts/demo-install.sh && { echo "FAIL: <ТОКЕН> в скобках — клиент оставит скобки → 401"; exit 1; }
echo "OK: плейсхолдер токена без угловых скобок"

# ─── R4 Telegram-валидация: ретраи + честный фейл (2026-06-16) ───
grep -q 'for _tg_try in 1 2 3' scripts/demo-install.sh || { echo "FAIL: getMe без ретраев"; exit 1; }
grep -q "error_code')==401" scripts/demo-install.sh || { echo "FAIL: нет ветки «неверный токен 401»"; exit 1; }
grep -q 'TG_TOKEN_VERIFIED' scripts/demo-install.sh || { echo "FAIL: нет флага верификации"; exit 1; }
grep -q 'BOT_USERNAME="my_bot"' scripts/demo-install.sh && { echo "FAIL: осталась заглушка @my_bot"; exit 1; }
echo "OK: R4 — ретраи getMe, отказ на неверный токен, честное сообщение при сбое сети"

# ─── IP_BASE объявлен ДО _fetch_agents_installer (set -u, 2026-06-16) ───
_dl=$(grep -n 'IP_BASE="\${IP_BASE:-}"' scripts/demo-install.sh | head -1 | cut -d: -f1)
_fl=$(grep -n '_fetch_agents_installer()' scripts/demo-install.sh | head -1 | cut -d: -f1)
[ -n "$_dl" ] && [ "$_dl" -lt "$_fl" ] || { echo "FAIL: IP_BASE не объявлен до _fetch_agents_installer (set -u unbound)"; exit 1; }
echo "OK: IP_BASE объявлен рано (строка $_dl < $_fl) — нет unbound в чейне"

# ─── gateway.auth.mode none на loopback (OpenClaw 2026.6.6 device-identity) ───
grep -q 'gateway.auth.mode none' scripts/demo-install.sh || { echo "FAIL: не выключаем gateway auth (device identity required)"; exit 1; }
# должно стоять и в ensure_gateway_healthy, и в R2 (>=2 раза)
[ "$(grep -c 'gateway.auth.mode none' scripts/demo-install.sh)" -ge 2 ] || { echo "FAIL: auth=none не во всех путях gateway-setup"; exit 1; }
echo "OK: gateway.auth.mode none на loopback (фикс device identity required 2026.6.6)"

# ─── COURSE_TOKEN экспортируется → чейн agents.sh наследует токен (2026-06-16) ───
# Без export дочерний `eval "bash /tmp/agents.sh"` не видит токен через env;
# при «Полном сбросе» кэш ~/.openclaw/course-token снесён → _ip_token пуст →
# gateway 401 → ложная ошибка «не смог скачать lib/ui.sh с GitHub raw».
grep -q '^export COURSE_TOKEN' scripts/demo-install.sh || { echo "FAIL: COURSE_TOKEN не экспортирован — чейн agents.sh не получит токен после полного сброса"; exit 1; }
# grep -m1: останавливаемся на первом матче. БЕЗ -m1 `eval "$_agents_run"` (2 шт)
# + `| head -1` рвёт пайп → grep ловит SIGPIPE → под pipefail+set -e тихий abort
# (busybox/Linux; на macOS BSD grep успевает дозаписать). -F: фикс-строка с $.
_ex=$(grep -nm1 '^export COURSE_TOKEN' scripts/demo-install.sh | cut -d: -f1)
_ch=$(grep -nFm1 'eval "$_agents_run"' scripts/demo-install.sh | cut -d: -f1)
[ -n "$_ex" ] && [ -n "$_ch" ] && [ "$_ex" -lt "$_ch" ] || { echo "FAIL: export COURSE_TOKEN после запуска чейна — токен не успеет пробросится"; exit 1; }
echo "OK: COURSE_TOKEN экспортирован (строка $_ex < $_ch) — чейн agents.sh наследует токен даже после полного сброса"

# ─── ПИН версии OpenClaw: НЕ @latest (2026-06-16) ───
# Апстрим @latest ломал клиентов (2026.6.6 device-identity; opencode-go rename).
# Ставим конкретную версию из OPENCLAW_VERSION; бамп — вручную.
grep -q '^OPENCLAW_VERSION=' scripts/demo-install.sh || { echo "FAIL: нет пина OPENCLAW_VERSION — вернулись на плавающую версию"; exit 1; }
grep -q 'npm install -g openclaw@latest' scripts/demo-install.sh && { echo "FAIL: остался openclaw@latest — апстрим снова будет ломать клиентов"; exit 1; }
grep -qF 'npm install -g openclaw@${OPENCLAW_VERSION}' scripts/demo-install.sh || { echo "FAIL: реальная установка не через пин OPENCLAW_VERSION"; exit 1; }
echo "OK: OpenClaw запинен ($(grep -m1 '^OPENCLAW_VERSION=' scripts/demo-install.sh)) — не @latest"

# ─── git НИКОГДА не спрашивает GitHub-логин (2026-06-16) ───
# После приватизации git clone/любой git к приватному репо → интерактивный
# «Username for github.com» (клиенты принимают за фишинг). GIT_TERMINAL_PROMPT=0
# + удалён git-clone fallback.
grep -q '^export GIT_TERMINAL_PROMPT=0' scripts/demo-install.sh || { echo "FAIL: нет GIT_TERMINAL_PROMPT=0 — git может спросить GitHub-логин у клиента"; exit 1; }
if grep -qE 'git clone .*github\.com/tonytrue92-beep' scripts/demo-install.sh; then
  echo "FAIL: остался git clone приватного репо — git попросит GitHub-логин (фишинг-вид)"; exit 1
fi
echo "OK: git не спросит GitHub-логин (GIT_TERMINAL_PROMPT=0 + нет git-clone приватного репо)"

