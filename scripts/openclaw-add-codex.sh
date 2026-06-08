#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  openclaw-add-codex — умные мозги через ChatGPT (Codex) одной командой
#
#  Что делает (рецепт для OpenClaw 2026.6.x):
#    1. Ставит Codex-плагин (clawhub → npm fallback), включает, обновляет реестр
#    2. Перезапускает gateway (чтобы плагин подхватился)
#    3. Запускает вход в ChatGPT: openclaw models auth login --provider openai
#       (в 2026.6.x именно `openai`; `openai-codex` — legacy-имя)
#    4. Ставит модель по умолчанию (openai/gpt-5.5) + рестарт
#
#  Использование:
#    openclaw-add-codex                      # обычный вход (браузер)
#    openclaw-add-codex --device-code        # вход по коду (VPS / если браузер не открылся)
#    openclaw-add-codex --provider codex      # если на твоей версии провайдер называется иначе
#    openclaw-add-codex openai/gpt-5.5         # явно указать модель
#    openclaw-add-codex --help
#
#  ⚠️ Это ОПЦИОНАЛЬНЫЙ апгрейд. Бесплатная модель (opencode) и так работает.
#     Codex берёт ВСЕ агенты на твой ChatGPT-аккаунт (бесплатного хватает; Plus умнее).
# ═══════════════════════════════════════════════════════════════════════

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'
BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
die()  { echo -e "${RED}✗${NC} $*" >&2; exit 1; }
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}○${NC} $*"; }
info() { echo -e "${CYAN}➜${NC} $*"; }
step() { echo ""; echo -e "${BOLD}${CYAN}━━━ $* ━━━${NC}"; }

PROVIDER="openai"        # 2026.6.x: вход в ChatGPT/Codex через provider `openai`
MODEL="openai/gpt-5.5"   # рекомендованная Codex-модель
DEVICE_CODE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --device-code) DEVICE_CODE="--device-code"; shift ;;
    --provider)
      [[ $# -ge 2 ]] || die "--provider требует значение (например: --provider openai)"
      PROVIDER="$2"; shift 2 ;;
    --provider=*) PROVIDER="${1#*=}"; shift ;;
    --help|-h)
      sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) warn "Неизвестный флаг: $1"; shift ;;
    *) MODEL="$1"; shift ;;   # позиционный аргумент = модель
  esac
done
[[ -n "$PROVIDER" ]] || die "--provider не может быть пустым"
[[ -n "$MODEL" ]] || die "модель не может быть пустой"

command -v openclaw >/dev/null 2>&1 || die "openclaw не найден в PATH. Открой новый терминал (или: source ~/.zshrc) и повтори."

echo -e "${BOLD}🧠 Подключаю умные мозги (ChatGPT / Codex)…${NC}"
echo -e "${DIM}   Опционально. Если что-то пойдёт не так — бесплатная модель остаётся рабочей.${NC}"

# ── 1. Codex-плагин: clawhub → npm fallback (идемпотентно) ──
step "1/4 Ставлю Codex-плагин"
if openclaw plugins install clawhub:@openclaw/codex >/dev/null 2>&1; then
  ok "Плагин установлен (clawhub)"
elif openclaw plugins install @openclaw/codex >/dev/null 2>&1; then
  ok "Плагин установлен (npm)"
else
  warn "Не удалось поставить плагин через install (возможно, уже стоит) — продолжаю."
fi
openclaw plugins enable codex >/dev/null 2>&1 || true
openclaw plugins registry --refresh >/dev/null 2>&1 || true

# ── 2. Рестарт gateway, чтобы плагин подхватился ──
step "2/4 Перезапускаю gateway"
openclaw gateway restart >/dev/null 2>&1 || true
ok "gateway перезапущен"

# ── 3. Вход в ChatGPT ──
step "3/4 Вход в ChatGPT (provider: ${PROVIDER})"
warn "После входа ChatGPT станет моделью по умолчанию для ВСЕХ агентов (шаг 4)."
info "Сейчас откроется ссылка/код для входа — залогинься своим ChatGPT."
# Намеренно БЕЗ --set-default: модель ставим явно на шаге 4 (прозрачно).
if openclaw models auth login --provider "$PROVIDER" $DEVICE_CODE; then
  ok "Вход выполнен"
else
  echo ""
  warn "Вход не завершился — модель НЕ меняю, бесплатная остаётся рабочей."
  echo -e "${DIM}   Можно повторить позже или вручную:${NC}"
  echo -e "   ${GREEN}openclaw models auth login --provider openai --device-code${NC}   ${DIM}# вход по коду${NC}"
  echo -e "   ${GREEN}openclaw models auth login --provider codex${NC}                  ${DIM}# если провайдер называется codex${NC}"
  exit 0   # опциональный апгрейд — не падаем, мягко выходим
fi

# ── 4. Модель по умолчанию + рестарт ──
step "4/4 Ставлю модель ${MODEL}"
if ! openclaw models set "$MODEL" >/dev/null 2>&1; then
  openclaw config set agents.defaults.model.primary "$MODEL" >/dev/null 2>&1 \
    || warn "Не смог выставить модель автоматически — задай вручную: openclaw-switch-model ${MODEL}"
fi
openclaw gateway restart >/dev/null 2>&1 || true
ok "Модель по умолчанию: ${MODEL}"

echo ""
echo -e "${BOLD}${GREEN}Готово.${NC} Напиши боту в Telegram — он теперь на ChatGPT (${MODEL})."
echo -e "${DIM}Вернуть бесплатную модель в любой момент:${NC}"
echo -e "   ${GREEN}openclaw-switch-model opencode/minimax-m2.5-free${NC}"
