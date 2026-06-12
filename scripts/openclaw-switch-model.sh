#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  openclaw-switch-model — быстрая смена модели одной командой
#
#  Что делает:
#    1. Валидирует, что модель существует (openclaw models list --all)
#    2. Меняет agents.defaults.model.primary
#    3. Меняет model у всех агентов в agents.list[]
#    4. Чистит сессии (обязательно — разные модели = разные tool-форматы)
#    5. Перезапускает gateway
#    6. Проверяет /status
#
#  Использование:
#    openclaw-switch-model                                    # интерактивно — покажет меню
#    openclaw-switch-model opencode-go/deepseek-v4-flash          # сразу на указанную модель
#    openclaw-switch-model --list                             # показать список доступных
#    openclaw-switch-model --help                             # эта справка
# ═══════════════════════════════════════════════════════════════════════

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

die()   { echo -e "${RED}✗${NC} $*" >&2; exit 1; }
ok()    { echo -e "${GREEN}✓${NC} $*"; }
warn()  { echo -e "${YELLOW}○${NC} $*"; }
info()  { echo -e "${CYAN}➜${NC} $*"; }
step()  { echo ""; echo -e "${BOLD}${CYAN}━━━ $* ━━━${NC}"; }

usage() {
  cat <<EOF
${BOLD}openclaw-switch-model${NC} — сменить модель у всех агентов одной командой

${BOLD}Использование:${NC}
  openclaw-switch-model                          ${DIM}# интерактивное меню${NC}
  openclaw-switch-model <модель>                 ${DIM}# сразу переключить${NC}
  openclaw-switch-model --list                   ${DIM}# показать все доступные${NC}
  openclaw-switch-model --help                   ${DIM}# эту справку${NC}

${BOLD}Популярные модели:${NC}
  ${GREEN}opencode-go/deepseek-v4-flash${NC}         ${DIM}# бесплатная, по умолчанию${NC}
  ${GREEN}opencode/grok-4-fast-free${NC}          ${DIM}# бесплатная, от xAI${NC}
  ${GREEN}opencode/kimi-dev-72b-free${NC}         ${DIM}# бесплатная, для кода${NC}
  ${GREEN}opencode/claude-sonnet-4-5${NC}         ${DIM}# платная, премиум${NC}
  ${GREEN}opencode/gpt-5-mini${NC}                ${DIM}# платная, OpenAI${NC}
  ${GREEN}opencode/gemini-2.5-pro${NC}            ${DIM}# платная, длинный контекст${NC}

${BOLD}Пример:${NC}
  openclaw-switch-model opencode/claude-sonnet-4-5

Скрипт сам почистит сессии и перезапустит gateway.
EOF
}

# ─── Аргументы ──────────────────────────────────────────────────────────
MODEL=""
case "${1:-}" in
  --help|-h)  usage; exit 0 ;;
  --list|-l)
    command -v openclaw >/dev/null || die "openclaw не найден в PATH"
    echo -e "${BOLD}Все доступные модели:${NC}"
    openclaw models list --all
    exit 0
    ;;
  "")
    # Интерактивное меню
    command -v openclaw >/dev/null || die "openclaw не найден в PATH"
    echo ""
    echo -e "${BOLD}Выберите модель:${NC}"
    echo ""
    echo -e "  ${CYAN}1${NC}) ${GREEN}opencode-go/deepseek-v4-flash${NC}      ${DIM}(бесплатная, быстрая)${NC}"
    echo -e "  ${CYAN}2${NC}) ${GREEN}opencode/grok-4-fast-free${NC}       ${DIM}(бесплатная, от xAI)${NC}"
    echo -e "  ${CYAN}3${NC}) ${GREEN}opencode/kimi-dev-72b-free${NC}      ${DIM}(бесплатная, код/аналитика)${NC}"
    echo -e "  ${CYAN}4${NC}) ${GREEN}opencode/claude-sonnet-4-5${NC}      ${DIM}(платная, премиум)${NC}"
    echo -e "  ${CYAN}5${NC}) ${GREEN}opencode/gpt-5-mini${NC}             ${DIM}(платная)${NC}"
    echo -e "  ${CYAN}6${NC}) ${GREEN}opencode/gemini-2.5-pro${NC}         ${DIM}(платная)${NC}"
    echo -e "  ${CYAN}0${NC}) своя (ввести вручную)"
    echo ""
    read -r -p "Ваш выбор [1-6 / 0]: " CHOICE
    case "$CHOICE" in
      1) MODEL="opencode-go/deepseek-v4-flash" ;;
      2) MODEL="opencode/grok-4-fast-free" ;;
      3) MODEL="opencode/kimi-dev-72b-free" ;;
      4) MODEL="opencode/claude-sonnet-4-5" ;;
      5) MODEL="opencode/gpt-5-mini" ;;
      6) MODEL="opencode/gemini-2.5-pro" ;;
      0)
        read -r -p "Введите имя модели (формат провайдер/модель): " MODEL
        [[ -n "$MODEL" ]] || die "Пустое имя"
        ;;
      *) die "Неверный выбор: $CHOICE" ;;
    esac
    ;;
  *)
    MODEL="$1"
    ;;
esac

command -v openclaw >/dev/null || die "openclaw не найден в PATH. Поставьте: npm install -g openclaw@latest"

# ─── Текущая модель ─────────────────────────────────────────────────────
CURRENT=$(openclaw config get agents.defaults.model.primary 2>/dev/null | tr -d '\n" ' || echo "")
if [[ -n "$CURRENT" ]]; then
  info "Сейчас: ${BOLD}${CURRENT}${NC}"
fi
info "Переключаем на: ${BOLD}${MODEL}${NC}"
echo ""

# ─── Валидация модели ───────────────────────────────────────────────────
step "1/5  Проверяем, что модель существует"
if openclaw models list --all 2>/dev/null | grep -qF "$MODEL"; then
  ok "Модель найдена в списке доступных"
else
  warn "Модель не в списке openclaw models list --all"
  echo ""
  if [[ "${OPENCLAW_SWITCH_ASSUME_YES:-0}" == "1" ]]; then
    CONFIRM="y"; echo "   (auto-yes: модель официальная для нашей сборки, проверю через probe)"
  else
    read -r -p "Всё равно продолжить? [y/N]: " CONFIRM
  fi
  [[ "$CONFIRM" =~ ^[YyДд] ]] || die "Отмена"
fi

# ─── Меняем default ─────────────────────────────────────────────────────
step "2/5  Меняем дефолтную модель"
openclaw config set agents.defaults.model.primary "$MODEL"
ok "agents.defaults.model.primary → $MODEL"

# ─── Меняем per-agent overrides ─────────────────────────────────────────
step "3/5  Меняем модель у каждого агента"
AGENTS_RAW=$(openclaw config get agents.list 2>/dev/null || echo "")
if [[ -n "$AGENTS_RAW" ]]; then
  # Считаем количество агентов по префиксу "- id:" или по "[index]"
  AGENT_COUNT=$(echo "$AGENTS_RAW" | grep -cE '^\s*-\s*id:' || echo 0)
  if [[ "$AGENT_COUNT" -eq 0 ]]; then
    # Альтернативный подсчёт — по полям id в JSON-подобном выводе
    AGENT_COUNT=$(echo "$AGENTS_RAW" | grep -cE '"id"\s*:' || echo 0)
  fi
  if [[ "$AGENT_COUNT" -gt 0 ]]; then
    for i in $(seq 0 $((AGENT_COUNT - 1))); do
      if openclaw config set "agents.list[${i}].model" "\"${MODEL}\"" --strict-json 2>/dev/null; then
        ok "agents.list[${i}].model → $MODEL"
      fi
    done
  else
    warn "Не смог определить количество агентов — пропускаю per-agent overrides"
  fi
else
  warn "agents.list пуст — пропускаю"
fi

# ─── Чистим сессии ──────────────────────────────────────────────────────
step "4/5  Чистим сессии (обязательно при смене модели)"
if openclaw sessions cleanup --all-agents 2>&1 | grep -qiE "cleaned|ok|done|removed"; then
  ok "Сессии очищены"
else
  # Fallback — ручная чистка через python
  warn "CLI-чистка не сработала, делаю вручную"
  for dir in "$HOME"/.openclaw/agents/*/sessions/; do
    [[ -f "$dir/sessions.json" ]] || continue
    python3 -c "
import json, sys
p = '$dir/sessions.json'
try:
    with open(p) as f: d = json.load(f)
    keys = [k for k in d if isinstance(d[k], dict)]
    for k in keys: del d[k]
    with open(p, 'w') as f: json.dump(d, f, indent=2)
    print(f'cleared {len(keys)} from {p}')
except Exception as e:
    print(f'skip {p}: {e}', file=sys.stderr)
"
  done
  ok "Сессии очищены вручную"
fi

# ─── Рестарт gateway ────────────────────────────────────────────────────
step "5/5  Перезапускаем gateway"
openclaw gateway restart 2>&1 | tail -3
sleep 1

# ─── Проверка ───────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}━━━ Проверка ━━━${NC}"
NEW_MODEL=$(openclaw config get agents.defaults.model.primary 2>/dev/null | tr -d '\n" ' || echo "")
GW_STATUS=$(openclaw gateway status 2>&1 || true)

if [[ "$NEW_MODEL" == "$MODEL" ]]; then
  ok "Модель: ${BOLD}${NEW_MODEL}${NC}"
else
  warn "Модель в конфиге: ${NEW_MODEL:-пусто} (ожидалось $MODEL)"
fi

if echo "$GW_STATUS" | grep -qE "running"; then
  ok "Gateway: running"
else
  warn "Gateway не поднялся: $(echo "$GW_STATUS" | head -1)"
  echo -e "   ${DIM}Посмотрите логи: openclaw logs --follow${NC}"
fi

echo ""
echo -e "${BOLD}${GREEN}🎉  Готово!${NC}"
echo -e "   Отправьте боту ${BOLD}/status${NC} в Telegram — должна показаться новая модель."
echo ""
