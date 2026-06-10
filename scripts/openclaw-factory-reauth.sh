#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  openclaw-factory-reauth — быстрая перезапись auth-профиля одной командой
#
#  Зачем нужна:
#    Кейс Саввы (из отчёта куратора 2026-04-17): на /status всё выглядит
#    правильно (MiniMax, provider opencode, profile opencode:default),
#    но на реальный запрос бот отвечает 401 Invalid API key. Причина —
#    старый auth-профиль с невалидным ключом, а ученик путается в
#    различии «Provider id» vs «Profile id» в openclaw CLI и создаёт
#    дубликаты вместо замены.
#
#  Что делает (6 шагов):
#    1. Бэкап текущего auth-profiles.json (никакого доверия «я не сломаю»)
#    2. Выбор провайдера (OpenCode Zen по умолчанию)
#    3. Чтение нового ключа (hidden input, начинается с sk-)
#    4. Перезапись auth-profiles.json с правильным provider_id
#    5. Sessions cleanup (иначе tool_use_id от старой модели = конфликт)
#    6. Gateway restart + health check
#
#  Использование:
#    openclaw-factory-reauth                # интерактивно (по умолчанию)
#    openclaw-factory-reauth --provider opencode
#    openclaw-factory-reauth --help
# ═══════════════════════════════════════════════════════════════════════

set -euo pipefail

# ANSI C quoting ($'...'): escape-последовательности интерпретируются
# прямо в значении переменной. Это важно для heredoc <<EOF в usage()
# и сообщениях — там обычный `cat` не умеет печатать \033, а нам нужны
# цветные подсказки.
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
WHITE=$'\033[1;37m'
BOLD=$'\033[1m'
DIM=$'\033[2m'
NC=$'\033[0m'

die()   { echo -e "${RED}✗${NC} $*" >&2; exit 1; }
ok()    { echo -e "${GREEN}✓${NC} $*"; }
warn()  { echo -e "${YELLOW}○${NC} $*"; }
info()  { echo -e "${CYAN}➜${NC} $*"; }
step()  { echo ""; echo -e "${BOLD}${CYAN}━━━ $* ━━━${NC}"; }

usage() {
  cat <<EOF
${BOLD}openclaw-factory-reauth${NC} — перезаписать API-ключ opencode.ai одной командой

${BOLD}Когда это нужно:${NC}
  • Бот отвечает ${RED}'HTTP 401: Invalid API key'${NC}
  • На /status всё выглядит правильно (provider, model), но реальные запросы падают
  • Вы сменили ключ на opencode.ai и хотите обновить в OpenClaw
  • Кто-то (вы или прошлый мастер) сломал auth-profile, и ${DIM}configure --section model${NC} не помогает

${BOLD}Использование:${NC}
  openclaw-factory-reauth                       ${DIM}# интерактивно (рекомендуется)${NC}
  openclaw-factory-reauth --provider opencode   ${DIM}# без меню выбора провайдера${NC}
  openclaw-factory-reauth --help                ${DIM}# эту справку${NC}

${BOLD}Что произойдёт (6 шагов, ~30 секунд):${NC}
  1. Бэкап текущего ${DIM}~/.openclaw/agents/main/agent/auth-profiles.json${NC}
  2. Выбор провайдера (по умолчанию ${BOLD}opencode${NC} = OpenCode Zen)
  3. Вы вставляете новый API-ключ (символы не отображаются — это нормально)
  4. Перезапись auth-profiles.json с правильной структурой
  5. Очистка сессий (${DIM}openclaw sessions cleanup --all-agents${NC})
  6. Перезапуск gateway и проверка здоровья

${BOLD}Безопасность:${NC}
  • Старый профиль сохраняется в auth-profiles.json.backup-YYYYMMDD-HHMMSS
  • Ключ вводится скрыто (без эха)
  • Файл создаётся с правами 600 (только владельцу)
EOF
}

# ─── Аргументы ──────────────────────────────────────────────────────────
PROVIDER=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --provider)
      PROVIDER="${2:-}"
      [[ -z "$PROVIDER" ]] && die "--provider требует значение (например: opencode)"
      shift 2
      ;;
    *)
      die "Неизвестный аргумент: $1 (см. --help)"
      ;;
  esac
done

# ─── Pre-check: openclaw установлен ─────────────────────────────────────
command -v openclaw >/dev/null || die "openclaw не найден в PATH. Сначала запустите установщик."

# ─── Pre-check: есть ли хоть какой-то существующий конфиг ───────────────
if [[ ! -f "$HOME/.openclaw/openclaw.json" ]]; then
  die "OpenClaw ещё не настроен (нет ~/.openclaw/openclaw.json).
Запустите основной установщик сначала:
  bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-factory/main/scripts/demo-install.sh)"
fi

# ─── Шаг 2: выбор провайдера ────────────────────────────────────────────
step "ШАГ 1/6: провайдер"

if [[ -z "$PROVIDER" ]]; then
  echo ""
  echo -e "${BOLD}Какой провайдер используете?${NC}"
  echo ""
  echo -e "  ${CYAN}1${NC}) ${GREEN}opencode${NC}    ${DIM}(OpenCode Zen — по умолчанию в курсе Антона)${NC}"
  echo -e "  ${CYAN}2${NC}) ${GREEN}openrouter${NC}  ${DIM}(OpenRouter — если самостоятельно настроили)${NC}"
  echo -e "  ${CYAN}3${NC}) ${GREEN}другой${NC}     ${DIM}(ввести вручную)${NC}"
  echo ""
  echo -e "${BOLD}Выбор [1/2/3, Enter = 1]:${NC}"
  read -r choice
  case "${choice:-1}" in
    1|"") PROVIDER="opencode-go" ;;
    2)    PROVIDER="openrouter" ;;
    3)
      echo -e "${BOLD}Введите id провайдера (строка без пробелов):${NC}"
      read -r PROVIDER
      [[ -z "$PROVIDER" ]] && die "Пустое значение"
      ;;
    *) die "Неправильный выбор: $choice" ;;
  esac
fi

info "Провайдер: ${BOLD}${PROVIDER}${NC}"

# ─── Шаг 1: бэкап старого auth-profiles.json ────────────────────────────
step "ШАГ 2/6: бэкап старого auth-профиля"

AUTH_FILE="$HOME/.openclaw/agents/main/agent/auth-profiles.json"
AUTH_DIR="$(dirname "$AUTH_FILE")"
mkdir -p "$AUTH_DIR"

if [[ -f "$AUTH_FILE" ]]; then
  TS=$(date +%Y%m%d-%H%M%S)
  BACKUP="${AUTH_FILE}.backup-${TS}"
  cp "$AUTH_FILE" "$BACKUP"
  chmod 600 "$BACKUP"
  ok "Бэкап: ${BACKUP}"
else
  warn "Текущего auth-profiles.json не существует — создадим новый."
fi

# ─── Шаг 3: получаем новый ключ ──────────────────────────────────────────
step "ШАГ 3/6: новый API-ключ"

echo ""
echo -e "${BOLD}Куда идти за ключом:${NC}"
case "$PROVIDER" in
  opencode)
    echo -e "  1. Откройте ${CYAN}https://opencode.ai${NC}"
    echo -e "  2. Логин / регистрация"
    echo -e "  3. ${BOLD}OpenCode Zen${NC} → API Keys → Create new key"
    echo -e "  4. Скопируйте ключ (формат: ${DIM}sk-...${NC})"
    ;;
  openrouter)
    echo -e "  1. Откройте ${CYAN}https://openrouter.ai/keys${NC}"
    echo -e "  2. Create Key → скопируйте"
    ;;
  *)
    echo -e "  Проверьте документацию провайдера ${BOLD}${PROVIDER}${NC} — где взять API-ключ."
    ;;
esac
echo ""

while true; do
  echo -e "${BOLD}Вставьте API-ключ и нажмите Enter:${NC}"
  echo -e "${DIM}(при вводе ничего отображаться не будет — это нормально)${NC}"
  read -rs API_KEY
  echo ""

  if [[ -z "$API_KEY" ]]; then
    warn "Ключ пустой, попробуйте ещё раз (или Ctrl+C для выхода)"
    continue
  fi

  if [[ "$PROVIDER" == "opencode-go" && ! "$API_KEY" =~ ^sk- ]]; then
    warn "Ключ opencode.ai обычно начинается с 'sk-'. Точно вставили правильный?"
    echo -e "${BOLD}Продолжить с этим значением? [y/N]:${NC}"
    read -r force_key
    [[ "$force_key" != "y" && "$force_key" != "Y" ]] && continue
  fi

  break
done

ok "Ключ получен (${#API_KEY} символов)"

# ─── Шаг 4: перезапись auth-profiles.json ────────────────────────────────
step "ШАГ 4/6: перезапись auth-profiles.json"

# Сохраняем как `<provider>:default` — это дефолтный profile_id, с которым
# дружит openclaw CLI. Если в будущем понадобится несколько ключей под
# одного провайдера — просто добавляйте второй профиль руками.
cat > "$AUTH_FILE" <<EOF
{
  "version": 1,
  "profiles": {
    "${PROVIDER}:default": {
      "type": "api_key",
      "provider": "${PROVIDER}",
      "key": "${API_KEY}"
    }
  },
  "lastGood": {
    "${PROVIDER}": "${PROVIDER}:default"
  }
}
EOF
chmod 600 "$AUTH_FILE"
ok "Новый auth-profiles.json сохранён (режим 600)"

# Забываем ключ из переменных окружения сразу после записи.
unset API_KEY

# ─── Шаг 5: чистим сессии ────────────────────────────────────────────────
step "ШАГ 5/6: очистка сессий"

# Это важно! Если оставить старые сессии, первый же запрос к новой модели
# может упасть с «No tool call found for toolu_XXX» — потому что tool_use_id
# в кэше ссылаются на предыдущую auth + модель + provider.
openclaw sessions cleanup --all-agents >/dev/null 2>&1 || true
ok "Сессии очищены у всех агентов"

# ─── Шаг 6: рестарт gateway + проверка ──────────────────────────────────
step "ШАГ 6/6: перезапуск gateway"

openclaw gateway restart 2>&1 | tail -3 | while IFS= read -r line; do
  echo -e "  ${DIM}${line}${NC}"
done

# Даём gateway'ю секунду на подъём, потом проверяем
sleep 1

GATEWAY_OK=false
if openclaw gateway status 2>&1 | grep -qE "running"; then
  GATEWAY_OK=true
  ok "Gateway: running"
else
  warn "Gateway не поднялся после рестарта — проверьте: openclaw gateway status --deep"
fi

# ─── Итог ───────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}━━━ Готово! ━━━${NC}"
echo ""
if [[ "$GATEWAY_OK" == true ]]; then
  echo -e "Auth-профиль для провайдера ${BOLD}${PROVIDER}${NC} перезаписан."
  echo -e "Gateway живой, сессии чистые."
  echo ""
  echo -e "${BOLD}Проверьте бота:${NC}"
  echo -e "  1. Откройте Telegram, напишите боту ${BOLD}/status${NC}"
  echo -e "  2. Потом — любое сообщение (например: ${DIM}«привет»${NC})"
  echo -e "  3. Если бот ответил нормально — авторизация починена."
  echo ""
  echo -e "${BOLD}Если всё ещё 401:${NC}"
  echo -e "  • проверьте, что ключ действителен на ${CYAN}https://opencode.ai${NC}"
  echo -e "  • посмотрите логи: ${GREEN}openclaw logs --follow${NC}"
  echo -e "  • соберите debug-bundle: ${GREEN}bash <(curl ...) --collect-debug${NC}"
else
  echo -e "${YELLOW}Auth-профиль перезаписан, но gateway не отвечает.${NC}"
  echo -e "Проверьте:"
  echo -e "  ${GREEN}openclaw gateway status --deep${NC}"
  echo -e "  ${GREEN}openclaw logs --follow${NC}"
fi
echo ""
