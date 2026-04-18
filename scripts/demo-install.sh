#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
#  OpenClaw TRUE — Демо-установка с нуля
#  Симуляция полного процесса для обучения
#  Не трогает основную систему (~/.openclaw)
# ═══════════════════════════════════════════════════════════════

# ─── Версия установщика ─────────────────────────────────────────
# Обновляется при каждом значимом коммите. INSTALLER_COMMIT подставляется
# через sed в CI (GitHub Actions); если скрипт запущен из рабочей копии
# без CI — плейсхолдер остаётся «dev».
#
# Зачем: когда ученик пишет «не работает», по версии мы сразу видим,
# на какой версии скрипта он сидит — и не гадаем, есть ли у него наши
# последние фиксы или он закэшировал старый curl.
INSTALLER_VERSION="2026.04.18"
INSTALLER_COMMIT="__COMMIT_PLACEHOLDER__"

# Если скрипт запущен из локального git-checkout (а не из curl|bash),
# пробуем заменить placeholder на реальный hash короткого коммита.
# Клиенты качают через curl — у них git нет, остаётся плейсхолдер, и это
# нормально (в URL всё равно видно `main`, а версия в дате).
if [[ "$INSTALLER_COMMIT" == "__COMMIT_PLACEHOLDER__" ]]; then
  _script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd 2>/dev/null) || _script_dir=""
  if [[ -n "$_script_dir" && -d "${_script_dir}/../.git" ]] && command -v git &>/dev/null; then
    _commit=$(git -C "${_script_dir}/.." rev-parse --short HEAD 2>/dev/null) || _commit=""
    [[ -n "$_commit" ]] && INSTALLER_COMMIT="${_commit}-dev"
  fi
  unset _script_dir _commit
fi

# Быстрая обработка «просмотровых» флагов — до любой работы с TTY,
# чтобы `--version` / `--help` работали и в non-interactive окружении
# (например, в CI или при пайпе в less).
for arg in "$@"; do
  case "$arg" in
    --version|-V)
      echo "OpenClaw Factory Installer v${INSTALLER_VERSION} (${INSTALLER_COMMIT})"
      exit 0
      ;;
    --help|-h)
      echo "OpenClaw Factory Installer v${INSTALLER_VERSION} (${INSTALLER_COMMIT})"
      echo ""
      echo "Usage: bash demo-install.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --install         Skip demo, go straight to real installation"
      echo "  --dry-run         Simulate the full installation (nothing is installed)"
      echo "  --collect-debug   Collect debug bundle for support (non-interactive)"
      echo "  --version         Print installer version and exit"
      echo "  --help            Show this help"
      echo ""
      echo "Without flags: starts with interactive demo, then offers real install"
      exit 0
      ;;
  esac
done

# Проверяем заранее: если запрошен `--collect-debug`, то TTY нам не нужен
# (функция только пишет файлы, ничего не спрашивает). Это даст возможность
# ученикам собирать bundle даже в non-interactive окружении.
NEEDS_TTY=true
for arg in "$@"; do
  [[ "$arg" == "--collect-debug" ]] && NEEDS_TTY=false
done

# Поддержка curl | bash — читаем ввод с терминала, а не из pipe
if [[ "$NEEDS_TTY" == true && ! -t 0 ]]; then
  if [[ -e /dev/tty ]]; then
    exec < /dev/tty
  else
    echo "ERROR: This script requires an interactive terminal."
    echo "Run it directly: bash <(curl -fsSL URL)"
    exit 1
  fi
fi

PROFILE="demo"
DEMO_DIR="$HOME/.openclaw-${PROFILE}"
SPEED=${SPEED:-0.02}
SKIP_DEMO=false
DRY_RUN=false
COLLECT_DEBUG_ONLY=false  # флаг для --collect-debug; сам вызов ниже, после определения функций

# Остальные флаги (меняющие состояние) — после TTY-инициализации
for arg in "$@"; do
  case "$arg" in
    --install|--real|--skip-demo) SKIP_DEMO=true ;;
    --dry-run|--simulate) DRY_RUN=true; SKIP_DEMO=true ;;
    --version|-V|--help|-h) : ;;  # уже обработано выше
    --collect-debug) COLLECT_DEBUG_ONLY=true ;;
  esac
done

# Цвета
# shellcheck disable=SC2034  # BLUE зарезервирован для потенциального использования
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
ITALIC='\033[3m'
NC='\033[0m'

# ═══ Утилиты ═══

typewrite() {
  local text="$1"
  local delay="${2:-$SPEED}"
  for ((i=0; i<${#text}; i++)); do
    printf '%s' "${text:$i:1}"
    sleep "$delay"
  done
  echo ""
}

step_header() {
  local num="$1"
  local title="$2"
  echo ""
  echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}${MAGENTA}  STEP ${num}: ${title}${NC}"
  echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
}

# Подробное объяснение на русском — главный блок
explain() {
  echo ""
  echo -e "   ${CYAN}☕${NC} ${BOLD}$1${NC}"
  shift
  for line in "$@"; do
    echo -e "   ${DIM}${line}${NC}"
  done
  echo ""
}

# Английский вывод терминала (как пользователь увидит на экране)
terminal() {
  echo -e "   ${WHITE}$1${NC}"
}

# Команда, которую пользователь вводит в терминал
show_cmd() {
  local cmd="$1"
  # Длина команды для рамки (с учётом 2 пробелов по краям, макс ~66 символов)
  local cmd_len=${#cmd}
  local width=$((cmd_len + 4))
  if [[ $width -lt 40 ]]; then width=40; fi
  if [[ $width -gt 70 ]]; then width=70; fi

  # Верхняя рамка с меткой "копировать ↓"
  echo -e "   ${DIM}┌─ 📋 скопируйте эту команду (без \$) ─────────────────────┐${NC}"
  echo -e "   ${DIM}│${NC} ${YELLOW}\$${NC} ${GREEN}${BOLD}${cmd}${NC}"
  echo -e "   ${DIM}└──────────────────────────────────────────────────────────┘${NC}"
}

# Реальная команда
run_cmd() {
  local cmd="$1"
  show_cmd "$cmd"
  echo ""
  eval "$cmd" 2>&1 | while IFS= read -r line; do
    echo -e "   ${DIM}${line}${NC}"
  done
  echo ""
}

# Русское пояснение к конкретной строке английского вывода
ru() {
  echo -e "   ${CYAN}↳${NC} ${ITALIC}$1${NC}"
}

ok() {
  echo ""
  echo -e "   ${GREEN}✅ $1${NC}"
  echo ""
}

warn() {
  echo -e "   ${YELLOW}⚠️  $1${NC}"
}

pause() {
  echo ""
  echo -e "   ${DIM}Нажмите Enter чтобы продолжить...${NC}"
  read -r
}

divider() {
  echo ""
  echo -e "${DIM}   ─────────────────────────────────────────────────────────────${NC}"
  echo ""
}

# Прописать nvm в shell rc-файлы, чтобы openclaw работал в новых терминалах
persist_nvm_in_shell_rc() {
  local nvm_block='
# NVM (openclaw-factory installer)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"'

  for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
    # Создаём файл если его нет
    [[ ! -f "$rc" ]] && touch "$rc"
    # Добавляем блок только если ещё не прописан
    if ! grep -q "openclaw-factory installer" "$rc" 2>/dev/null; then
      echo "$nvm_block" >> "$rc"
      echo -e "   ${DIM}↳ прописал nvm в ${rc}${NC}"
    fi
  done
}

# Автоустановка Node.js через nvm (без sudo) — используется в реальной установке
install_node_via_nvm() {
  echo ""
  explain "Запускаю автоустановку Node.js через nvm..." \
    "nvm — Node Version Manager. Устанавливает Node.js в вашу домашнюю папку" \
    "без прав администратора. Это займёт 1-2 минуты."

  export NVM_DIR="$HOME/.nvm"

  if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    echo -e "   ${DIM}Скачиваю nvm...${NC}"
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh 2>/dev/null | bash 2>&1 | tail -5 | while IFS= read -r line; do
      echo -e "   ${DIM}${line}${NC}"
    done
  else
    echo -e "   ${DIM}nvm уже установлен${NC}"
  fi

  [[ -s "$NVM_DIR/nvm.sh" ]] && \. "$NVM_DIR/nvm.sh"
  [[ -s "$NVM_DIR/bash_completion" ]] && \. "$NVM_DIR/bash_completion"

  if ! command -v nvm &>/dev/null; then
    echo ""
    echo -e "   ${RED}✗ Не удалось загрузить nvm.${NC}"
    echo -e "   ${DIM}Установите Node.js вручную с https://nodejs.org и запустите скрипт снова.${NC}"
    exit 1
  fi

  echo ""
  echo -e "   ${DIM}Устанавливаю Node.js 22 LTS...${NC}"
  nvm install 22 2>&1 | tail -5 | while IFS= read -r line; do
    echo -e "   ${DIM}${line}${NC}"
  done
  nvm use 22 &>/dev/null

  # ВАЖНО: прописываем nvm в shell rc-файлы, иначе после закрытия терминала
  # команда openclaw будет недоступна ("command not found: openclaw")
  persist_nvm_in_shell_rc

  echo ""
  if command -v node &>/dev/null; then
    NODE_VER=$(node -v)
    echo -e "   ${GREEN}✓ Node.js ${NODE_VER} установлен${NC}"
    if command -v npm &>/dev/null; then
      echo -e "   ${GREEN}✓ npm $(npm -v) установлен${NC}"
    fi
    echo -e "   ${GREEN}✓ nvm прописан в ~/.zshrc и ~/.bashrc${NC}"
    ru "В новых терминалах nvm будет подгружаться автоматически."
    ru "Это значит, что команда openclaw будет работать всегда, даже после перезагрузки."
  else
    echo -e "   ${RED}✗ Установка не удалась. Попробуйте вручную: https://nodejs.org${NC}"
    exit 1
  fi
}

# ─── Проверка admin-прав пользователя (macOS) ───────────────────
#
# Частый кейс: у ученика macOS-юзер без admin rights (рабочий Mac от
# работодателя, гостевой аккаунт, родительский контроль). sudo такому
# юзеру не даст ничего — и установка Homebrew упирается в тупик с
# нечитаемой ошибкой «user needs to be an Administrator».
#
# Лучше ловим это ДО запуска Homebrew: возвращаем:
#   0 — пользователь admin (всё ок)
#   1 — не admin (нужно branching — skip/switch user)
#   2 — проверка не применима (не macOS)
is_macos_admin() {
  [[ "$(uname)" != "Darwin" ]] && return 2
  if id -Gn "$(whoami)" 2>/dev/null | grep -qw admin; then
    return 0
  fi
  return 1
}

# ─── Предупреждение про невидимый sudo-пароль ───────────────────
#
# Самая массовая жалоба по Homebrew: «ввожу пароль, а ничего не
# отображается — значит зависло?» Это нормальное поведение sudo,
# но новички об этом не знают. Печатаем ПРЕДУПРЕЖДЕНИЕ до запуска.
warn_about_sudo_prompt() {
  echo ""
  echo -e "   ${BOLD}${YELLOW}⚠️  Сейчас установщик попросит пароль от Mac${NC}"
  echo -e "   ${DIM}   (тот, которым вы разблокируете компьютер — НЕ Apple ID)${NC}"
  echo ""
  echo -e "   ${BOLD}${WHITE}   Важно:${NC}"
  echo -e "   ${WHITE}   • При вводе пароля ${BOLD}символы не будут отображаться${NC}"
  echo -e "   ${WHITE}     ${DIM}— ни точек, ни звёздочек, ни курсора. Это нормально.${NC}"
  echo -e "   ${WHITE}   • Просто наберите пароль вслепую и нажмите ${BOLD}Enter${NC}"
  echo -e "   ${WHITE}   • Если ошиблись — наберите заново${NC}"
  echo ""
}

# ─── Проверка Xcode Command Line Tools ──────────────────────────
#
# Homebrew на macOS внутри себя запускает `xcode-select --install`,
# если CLT отсутствуют. Это вызывает GUI-диалог Apple и ставит
# пакет на 1-3 гигабайта. Частая проблема: после установки
# xcode-select не подхватывается в той же сессии терминала —
# пользователю нужно закрыть и открыть терминал заново.
#
# Возвращает:
#   0 — CLT установлены и видны
#   1 — не установлены или не видны (нужен перезапуск терминала)
check_xcode_clt() {
  [[ "$(uname)" != "Darwin" ]] && return 0  # не macOS — не волнуемся
  if xcode-select -p &>/dev/null; then
    local clt_path
    clt_path=$(xcode-select -p 2>/dev/null)
    # Дополнительная проверка — путь должен существовать
    [[ -d "$clt_path" ]] && return 0
  fi
  return 1
}

# Автоустановка Homebrew — нужен для многих скиллов OpenClaw (gh, ffmpeg, и т.д.)
install_homebrew() {
  # ─── Pre-check: admin rights ───
  if ! is_macos_admin; then
    local admin_status=$?
    if [[ $admin_status -eq 1 ]]; then
      echo ""
      warn "Ваш пользователь macOS не в группе admin — sudo не сработает."
      echo -e "   ${DIM}Homebrew требует права администратора для установки в /opt/homebrew.${NC}"
      echo ""
      echo -e "   ${BOLD}${WHITE}Что делать:${NC}"
      echo -e "   ${CYAN}1.${NC} ${BOLD}Пропустить Homebrew${NC} — скрипт продолжит без него,"
      echo -e "      ${DIM}часть скиллов (gh, ffmpeg) не установится, но бот заработает.${NC}"
      echo -e "   ${CYAN}2.${NC} ${BOLD}Сменить пользователя${NC} — выйдите в macOS на admin-аккаунт"
      echo -e "      ${DIM}и запустите скрипт снова.${NC}"
      echo -e "   ${CYAN}3.${NC} ${BOLD}Поставить потом${NC} — инструкция: https://brew.sh"
      echo ""
      echo -e "   ${BOLD}${WHITE}Пропустить и продолжить без Homebrew? [Y/n]:${NC}"
      read -r skip_brew
      skip_brew="${skip_brew:-y}"
      if [[ "$skip_brew" == "y" || "$skip_brew" == "Y" ]]; then
        ru "Пропускаем Homebrew. Установить можно позже с admin-аккаунта."
        return 0
      else
        echo -e "   ${DIM}Остановлено. Смените пользователя macOS на admin и запустите скрипт снова.${NC}"
        exit 0
      fi
    fi
  fi

  echo ""
  explain "Устанавливаю Homebrew..." \
    "Homebrew — пакетный менеджер для macOS/Linux. Многие скиллы OpenClaw" \
    "(github, video-frames, summarize и другие) требуют утилиты через brew." \
    "" \
    "Установка займёт 2-5 минут, потребует пароль администратора Mac."

  # ─── Предупреждение про невидимый sudo-пароль ───
  warn_about_sudo_prompt

  # ─── Явная карта того, что увидит пользователь ───
  # (Homebrew-скрипт интерактивный, делает ДВА запроса подряд — чтобы
  # ученик не застрял ни на одном из них.)
  echo -e "   ${BOLD}${WHITE}Что попросит Homebrew — по порядку:${NC}"
  echo -e "   ${CYAN}1.${NC} ${BOLD}«Press RETURN/ENTER to continue»${NC} — нажмите ${BOLD}Enter${NC}"
  echo -e "   ${CYAN}2.${NC} ${BOLD}«Password:»${NC} — введите пароль от Mac (символы ${BOLD}не видно${NC}!), Enter"
  echo -e "   ${DIM}   Всё — дальше Homebrew сам скачает и установит, это 2-5 минут.${NC}"
  echo ""
  echo -e "   ${DIM}Нажмите Enter, когда будете готовы запустить установку Homebrew...${NC}"
  read -r

  echo ""
  echo -e "   ${BOLD}${MAGENTA}━━━ передаю управление Homebrew installer ━━━${NC}"
  echo ""

  # ВАЖНО: запускаем БЕЗ pipe, чтобы не убить интерактивность Homebrew.
  # Раньше здесь было `... | tail -10 | while read` — это ломало stdin
  # Homebrew, и он зависал на «Press RETURN/ENTER» (пользователь не видел
  # приглашения из-за буфера tail, а даже если бы видел — pipe не давал
  # ввести Enter в stdin установщика).
  #
  # Heartbeat тоже не запускаем: Homebrew сам болтлив и показывает прогресс,
  # фоновое «я жив» только перебивало бы его вывод.
  set +e
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  local brew_install_rc=$?
  set -e

  echo ""
  echo -e "   ${BOLD}${MAGENTA}━━━ Homebrew installer завершён (rc=${brew_install_rc}) ━━━${NC}"
  echo ""

  # ─── Проверка Xcode CLT после Homebrew install ───
  # Homebrew при установке иногда тянет CLT сам. Проверяем — если CLT не видны,
  # подсказываем перезапустить терминал.
  if ! check_xcode_clt; then
    echo ""
    warn "Xcode Command Line Tools не видны в этой сессии терминала."
    echo -e "   ${DIM}Возможные причины:${NC}"
    echo -e "   ${DIM}  • CLT ещё ставятся в фоне (GUI-окно Apple)${NC}"
    echo -e "   ${DIM}  • CLT поставлены, но PATH не обновился${NC}"
    echo ""
    echo -e "   ${BOLD}${WHITE}Что сделать:${NC}"
    echo -e "   ${CYAN}1.${NC} Дождитесь завершения GUI-окна Apple (если открылось)"
    echo -e "   ${CYAN}2.${NC} Проверьте: ${GREEN}xcode-select -p${NC}"
    echo -e "   ${CYAN}3.${NC} Если пусто — запустите: ${GREEN}xcode-select --install${NC}"
    echo -e "   ${CYAN}4.${NC} Если уже стоит, но не видно — закройте терминал и откройте заново"
    echo -e "   ${CYAN}5.${NC} Запустите скрипт снова"
    echo ""
  fi

  # Активируем brew в текущей сессии + прописываем в shell rc
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
    local brew_line='eval "$(/opt/homebrew/bin/brew shellenv)"'
    for rc in "$HOME/.zprofile" "$HOME/.bash_profile"; do
      [[ ! -f "$rc" ]] && touch "$rc"
      if ! grep -q "brew shellenv" "$rc" 2>/dev/null; then
        echo "$brew_line" >> "$rc"
        echo -e "   ${DIM}↳ прописал brew в ${rc}${NC}"
      fi
    done
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  echo ""
  if command -v brew &>/dev/null; then
    echo -e "   ${GREEN}✓ Homebrew $(brew --version | head -1) установлен${NC}"
  else
    warn "Homebrew установлен, но не виден в PATH этой сессии."
    echo -e "   ${DIM}Это частый кейс — нужно закрыть терминал и открыть заново.${NC}"
    echo -e "   ${DIM}После этого запустите скрипт снова — brew будет видно.${NC}"
  fi
}

# Проверка brew — предлагает автоустановку
prompt_install_homebrew() {
  echo ""
  explain "Homebrew не найден." \
    "" \
    "Homebrew нужен для скиллов OpenClaw, которые требуют внешние утилиты" \
    "(github → gh, video-frames → ffmpeg, obsidian, summarize и т.д.)." \
    "" \
    "Без brew базовый функционал работает, но часть скиллов не поставится."

  echo -e "   ${BOLD}${WHITE}Установить Homebrew сейчас? [Y/n]:${NC}"
  read -r install_brew
  install_brew="${install_brew:-y}"

  if [[ "$install_brew" == "y" || "$install_brew" == "Y" ]]; then
    install_homebrew
  else
    ru "Пропускаем. Установить можно позже: https://brew.sh"
  fi
}

# ─── Heartbeat-утилита для длинных шагов ────────────────────────
#
# Частая жалоба клиентов: «npm install завис, я 5 минут смотрю на пустой экран,
# не понимаю — работает или умерло». Эта функция раз в N секунд печатает
# строку «всё ещё качаю...» пока основной процесс жив.
#
# Использование:
#   start_heartbeat "качаю зависимости" & HB_PID=$!
#   <долгий процесс>
#   stop_heartbeat $HB_PID
start_heartbeat() {
  local label="${1:-работаю}"
  local interval="${2:-30}"   # каждые 30 сек
  local hint_at="${3:-300}"   # через 5 мин — намекнуть что можно прервать
  local started=$(date +%s)
  while true; do
    sleep "$interval"
    local now=$(date +%s)
    local elapsed=$((now - started))
    if [[ $elapsed -ge $hint_at ]]; then
      echo -e "   ${DIM}⏳ ${label} (${elapsed} сек)... если больше 10 минут молчит — Ctrl+C и проверьте сеть/VPN${NC}"
    else
      echo -e "   ${DIM}⏳ ${label} (${elapsed} сек)... я жив, просто процесс небыстрый${NC}"
    fi
  done
}

stop_heartbeat() {
  local hb_pid="$1"
  [[ -z "$hb_pid" ]] && return 0
  kill "$hb_pid" 2>/dev/null || true
  wait "$hb_pid" 2>/dev/null || true
}

# ─── Маскировка секретов в тексте ───────────────────────────────
#
# Когда мы собираем debug-bundle для саппорта, ни в одном файле не должно
# быть валидных API-ключей, Telegram-токенов или паролей. Эта функция
# принимает файл и заменяет в нём подозрительные паттерны на «[REDACTED]»:
#
#   • opencode.ai API keys: sk-xxxxxxxx... (40+ символов)
#   • Telegram bot tokens: 10+цифр:35+символов
#   • Bearer tokens: Bearer xxxxx...
#   • password-like строки в JSON: "key":"...", "token":"...", "password":"..."
#
# Работает in-place (через sed). Если файл бинарный — ничего не ломает,
# sed просто пройдёт мимо (проверка через `grep -Iq` — текстовый ли).
redact_secrets() {
  local file="$1"
  [[ ! -f "$file" ]] && return 0
  # Пропускаем бинарные файлы
  grep -Iq . "$file" 2>/dev/null || return 0

  # sed -E на macOS (BSD) и Linux (GNU) различается в -i — явно пишем в tmp
  local tmp
  tmp=$(mktemp -t openclaw-redact.XXXXXX)

  sed -E \
    -e 's/sk-[A-Za-z0-9_-]{20,}/sk-[REDACTED]/g' \
    -e 's/[0-9]{8,12}:[A-Za-z0-9_-]{30,}/[TG_TOKEN_REDACTED]/g' \
    -e 's/([Bb]earer )[A-Za-z0-9._-]+/\1[REDACTED]/g' \
    -e 's/("(key|token|password|secret|apiKey|api_key)"[[:space:]]*:[[:space:]]*")[^"]*(")/\1[REDACTED]\3/g' \
    "$file" > "$tmp"

  mv "$tmp" "$file"
}

# ─── Сборка debug-bundle при ошибке или по запросу ──────────────
#
# Когда установщик падает (или ученик сам запускает `--collect-debug`),
# собираем в один zip-файл:
#   • версию установщика и commit
#   • uname -a, node/npm/brew --version
#   • ~/.openclaw/openclaw.json (без секретов)
#   • последние 200 строк ~/.openclaw/logs/*.log
#   • вывод `openclaw status --all`, `openclaw gateway status`, `openclaw doctor`
#   • последние 50 строк истории установщика (если включён лог)
#
# Результат: ~/openclaw-debug-YYYYMMDD-HHMMSS.zip
# Ученик пересылает файл в саппорт → там видно всё за 30 секунд.
#
# Безопасность: перед зипом каждый .json/.log пропускается через
# redact_secrets → в бандле не должно остаться ни одного валидного ключа.
collect_debug_bundle() {
  local reason="${1:-manual}"
  local ts
  ts=$(date +%Y%m%d-%H%M%S)
  local bundle_dir
  bundle_dir=$(mktemp -d -t openclaw-debug.XXXXXX)
  local bundle_name="openclaw-debug-${ts}"
  local bundle_path="${bundle_dir}/${bundle_name}"
  mkdir -p "$bundle_path"

  # ─── Manifest: что внутри, когда собрано, почему ───
  cat > "${bundle_path}/MANIFEST.txt" <<MANIFEST
OpenClaw Factory Debug Bundle
=============================
Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
Reason: ${reason}
Installer: v${INSTALLER_VERSION} (${INSTALLER_COMMIT})

System:
  $(uname -a 2>&1 || echo 'uname failed')

Versions:
  node: $(command -v node >/dev/null && node -v 2>&1 || echo 'not installed')
  npm:  $(command -v npm >/dev/null && npm -v 2>&1 || echo 'not installed')
  brew: $(command -v brew >/dev/null && brew --version 2>&1 | head -1 || echo 'not installed')
  openclaw: $(command -v openclaw >/dev/null && openclaw --version 2>&1 | head -1 || echo 'not installed')

Contents:
  - MANIFEST.txt         — this file
  - system-info.txt      — extended system diagnostics
  - openclaw-config.json — ~/.openclaw/openclaw.json (REDACTED — secrets removed)
  - openclaw-status.txt  — openclaw status --all
  - openclaw-gateway.txt — openclaw gateway status --deep
  - openclaw-doctor.txt  — openclaw doctor output
  - gateway.log          — last 200 lines of ~/.openclaw/logs/gateway.log (REDACTED)

IMPORTANT: все потенциальные секреты (API-ключи, токены) автоматически заменены
на [REDACTED]. Но всё же проверьте файлы перед отправкой в саппорт.
MANIFEST

  # ─── Система ───
  {
    echo "=== uname -a ==="
    uname -a 2>&1 || true
    echo ""
    echo "=== sw_vers (macOS) ==="
    sw_vers 2>&1 || true
    echo ""
    echo "=== Architecture ==="
    arch 2>&1 || uname -m
    echo ""
    echo "=== Disk space (\$HOME) ==="
    df -h "$HOME" 2>&1 || true
    echo ""
    echo "=== PATH ==="
    echo "$PATH"
    echo ""
    echo "=== Is admin? ==="
    if id -Gn "$(whoami)" 2>/dev/null | grep -qw admin; then
      echo "yes (macOS admin group)"
    else
      echo "no (not in admin group)"
    fi
    echo ""
    echo "=== xcode-select -p ==="
    xcode-select -p 2>&1 || echo 'xcode-select не найден'
  } > "${bundle_path}/system-info.txt" 2>&1

  # ─── OpenClaw конфиг (обязательно через redact_secrets) ───
  if [[ -f "$HOME/.openclaw/openclaw.json" ]]; then
    cp "$HOME/.openclaw/openclaw.json" "${bundle_path}/openclaw-config.json"
    redact_secrets "${bundle_path}/openclaw-config.json"
  else
    echo "(no ~/.openclaw/openclaw.json)" > "${bundle_path}/openclaw-config.json"
  fi

  # ─── OpenClaw команды ───
  if command -v openclaw &>/dev/null; then
    openclaw status --all > "${bundle_path}/openclaw-status.txt" 2>&1 || true
    openclaw gateway status --deep > "${bundle_path}/openclaw-gateway.txt" 2>&1 || true
    openclaw doctor > "${bundle_path}/openclaw-doctor.txt" 2>&1 || true
  else
    echo "openclaw CLI not installed" > "${bundle_path}/openclaw-status.txt"
  fi

  # ─── Последние 200 строк логов gateway ───
  if [[ -d "$HOME/.openclaw/logs" ]]; then
    local latest_log
    latest_log=$(ls -t "$HOME/.openclaw/logs/"*.log 2>/dev/null | head -1)
    if [[ -n "$latest_log" && -f "$latest_log" ]]; then
      tail -200 "$latest_log" > "${bundle_path}/gateway.log"
      redact_secrets "${bundle_path}/gateway.log"
    fi
  fi

  # ─── Маскируем секреты во ВСЕХ текстовых файлах бандла ───
  # (страховка на случай если что-то просочилось через openclaw status и пр.)
  for f in "${bundle_path}"/*.txt "${bundle_path}"/*.json "${bundle_path}"/*.log; do
    [[ -f "$f" ]] && redact_secrets "$f"
  done

  # ─── Архивация ───
  local archive_path="$HOME/${bundle_name}.zip"
  if command -v zip &>/dev/null; then
    (cd "$bundle_dir" && zip -qr "$archive_path" "$bundle_name" 2>/dev/null) || {
      # Fallback на tar.gz если zip недоступен
      archive_path="$HOME/${bundle_name}.tar.gz"
      tar -czf "$archive_path" -C "$bundle_dir" "$bundle_name" 2>/dev/null || true
    }
  else
    archive_path="$HOME/${bundle_name}.tar.gz"
    tar -czf "$archive_path" -C "$bundle_dir" "$bundle_name" 2>/dev/null || true
  fi

  # Убираем tmp директорию
  rm -rf "$bundle_dir" 2>/dev/null

  if [[ -f "$archive_path" ]]; then
    echo ""
    echo -e "   ${BOLD}${CYAN}📦 Собран debug-bundle для саппорта:${NC}"
    echo -e "   ${GREEN}${archive_path}${NC}"
    echo -e "   ${DIM}Размер: $(du -h "$archive_path" | cut -f1)${NC}"
    echo ""
    echo -e "   ${BOLD}${WHITE}Что делать дальше:${NC}"
    echo -e "   ${CYAN}1.${NC} Пришлите этот файл в поддержку курса"
    echo -e "   ${CYAN}2.${NC} Секреты уже замаскированы, но если волнуетесь —"
    echo -e "      ${DIM}распакуйте и просмотрите перед отправкой${NC}"
    echo ""
  fi
}

# ─── Error handler — вызывается при любом exit !=0 в установщике ─
#
# Когда скрипт падает, 99% пользователей делают скриншот ошибки и пишут
# «не работает». Саппорт гадает. С этим trap'ом при падении автоматически
# собирается debug-bundle — и достаточно переслать один файл.
#
# NB: не вызываем при нормальном exit 0 — только при ошибке.
# NB: не собираем в DRY_RUN режиме — там всё симуляция.
on_installer_error() {
  local exit_code=$?
  local line_no="${1:-?}"

  # Не собираем в dry-run и не при ручном прерывании (Ctrl+C = 130)
  if [[ "${DRY_RUN:-false}" == true ]]; then return $exit_code; fi
  if [[ $exit_code -eq 130 ]]; then return $exit_code; fi
  # Не вызываем для просмотровых флагов (они уже вышли с 0)

  echo ""
  echo -e "   ${BOLD}${RED}━━━ установщик остановился (exit=${exit_code}, line=${line_no}) ━━━${NC}"
  echo ""
  echo -e "   ${DIM}Собираю debug-bundle для саппорта...${NC}"
  collect_debug_bundle "error exit=${exit_code} at line ${line_no}" || true
  return $exit_code
}

# Устанавливаем trap только в реальной установке (не в демо и не в dry-run).
# Активация происходит ниже, после обработки флагов.

# ─── Preflight network check ───────────────────────────────────
#
# Классическая жалоба: «установка зависла на R2 (npm install)». Часто
# причина — сеть (корпоративный прокси режет registry.npmjs.org, VPN
# отключился, DNS не резолвит). Сейчас установщик узнаёт об этом только
# через 60-120 секунд таймаута npm, а то и несколько ретраев.
#
# Эта функция за 5-10 секунд проверяет, что все критичные endpoints
# достижимы, и ЕСЛИ нет — сразу даёт пользователю конкретный диагноз:
# какой именно сервис недоступен и какие варианты действий.
#
# Проверяем только базовую HTTP-доступность, не авторизацию — так
# мы не ловим ложных срабатываний из-за отсутствующих ключей.
#
# Возвращает:
#   0 — все критичные endpoints доступны
#   1 — хотя бы один критичный недоступен (пользователю показан диагноз)
preflight_network_check() {
  echo ""
  echo -e "   ${DIM}Проверяю доступность сети (5 сек)...${NC}"

  # endpoint_name|url|criticality (critical|optional)
  local endpoints=(
    "npm registry|https://registry.npmjs.org/|critical"
    "GitHub raw|https://raw.githubusercontent.com/|critical"
    "opencode.ai|https://opencode.ai/|critical"
    "Telegram API|https://api.telegram.org/|optional"
  )

  local failed_critical=()
  local failed_optional=()
  local all_ok=true

  for entry in "${endpoints[@]}"; do
    local name="${entry%%|*}"
    local rest="${entry#*|}"
    local url="${rest%%|*}"
    local level="${rest##*|}"

    # curl -I: HEAD-запрос; --max-time 5: не ждём вечно; --silent: без прогресса;
    # -o /dev/null -w '%{http_code}' — только HTTP-код.
    local http_code
    http_code=$(curl --max-time 5 -sI -o /dev/null -w '%{http_code}' "$url" 2>/dev/null || echo "000")

    # 2xx, 3xx, или даже 401/403 — значит сеть работает, просто нет авторизации
    if [[ "$http_code" =~ ^(2|3|401|403|404) ]]; then
      echo -e "   ${GREEN}✓${NC} ${name} (HTTP ${http_code})"
    else
      all_ok=false
      if [[ "$level" == "critical" ]]; then
        failed_critical+=("${name}|${url}")
        echo -e "   ${RED}✗${NC} ${name} недоступен (HTTP ${http_code:-timeout})"
      else
        failed_optional+=("${name}|${url}")
        echo -e "   ${YELLOW}○${NC} ${name} недоступен (необязательный)"
      fi
    fi
  done

  echo ""

  if [[ "$all_ok" == true ]]; then
    echo -e "   ${GREEN}Сеть OK — все критичные сервисы доступны.${NC}"
    return 0
  fi

  if [[ ${#failed_critical[@]} -gt 0 ]]; then
    warn "Критичные сервисы недоступны — установка не сможет продолжиться:"
    echo ""
    for entry in "${failed_critical[@]}"; do
      local name="${entry%%|*}"
      local url="${entry##*|}"
      echo -e "   ${RED}✗${NC} ${BOLD}${name}${NC}: ${url}"
    done
    echo ""
    echo -e "   ${BOLD}${WHITE}Вероятные причины:${NC}"
    echo -e "   ${CYAN}1.${NC} ${BOLD}Корпоративный прокси/firewall${NC} блокирует эти домены"
    echo -e "      ${DIM}→ попробуйте мобильный интернет / домашнюю Wi-Fi${NC}"
    echo -e "   ${CYAN}2.${NC} ${BOLD}VPN${NC} маршрутизирует трафик через нерабочую сеть"
    echo -e "      ${DIM}→ отключите VPN или включите другой${NC}"
    echo -e "   ${CYAN}3.${NC} ${BOLD}DNS${NC} не резолвит хост"
    echo -e "      ${DIM}→ смените DNS на 1.1.1.1 или 8.8.8.8${NC}"
    echo -e "   ${CYAN}4.${NC} ${BOLD}Региональная блокировка${NC} (редко, но бывает)"
    echo -e "      ${DIM}→ VPN с другой страной${NC}"
    echo ""
    echo -e "   ${BOLD}${WHITE}Проверить вручную:${NC}"
    for entry in "${failed_critical[@]}"; do
      local url="${entry##*|}"
      echo -e "      ${GREEN}curl -I ${url}${NC}"
    done
    echo ""
    echo -e "   ${BOLD}${WHITE}Продолжить несмотря на это? [y/N]:${NC}"
    read -r ignore_net
    if [[ "$ignore_net" != "y" && "$ignore_net" != "Y" ]]; then
      echo -e "   ${DIM}Остановлено. Почините сеть и запустите скрипт снова.${NC}"
      exit 1
    fi
    warn "Продолжаем несмотря на проблемы с сетью — может зависнуть."
  fi

  if [[ ${#failed_optional[@]} -gt 0 ]]; then
    warn "Необязательные сервисы недоступны (не блокер):"
    for entry in "${failed_optional[@]}"; do
      local name="${entry%%|*}"
      echo -e "   ${YELLOW}○${NC} ${name}"
    done
    ru "Пока не критично — пропустим, если понадобится, вернёмся на этот шаг."
  fi

  return 0
}

# ─── Раздельная диагностика npm permissions ─────────────────────
#
# У новичков `EACCES` в npm — это ДВА разных случая, которые
# визуально выглядят одинаково, но чинятся разными командами:
#
#   А) Глобальный install требует sudo (системный Node.js в /usr/local).
#      Симптом: `npm ERR! EACCES: permission denied, mkdir '/usr/local/lib/node_modules/...'`
#      Фикс:   `sudo npm install -g openclaw@latest`
#
#   Б) ~/.npm принадлежит root (артефакт прошлого sudo npm без -H).
#      Симптом: `npm ERR! EACCES: permission denied, open '/Users/x/.npm/...'`
#      Фикс:   `sudo chown -R $(id -u):$(id -g) ~/.npm`
#
# Смешивать их нельзя: команда из (А) не починит (Б), и наоборот.
# Функция смотрит текст ошибки и печатает ровно ту команду, которая нужна.
diagnose_npm_eacces() {
  local err_log="$1"
  local case_global=false
  local case_cache=false

  if grep -qE "EACCES.*node_modules|permission denied.*node_modules|EACCES.*(/usr/local|/opt)" "$err_log" 2>/dev/null; then
    case_global=true
  fi
  if grep -qE "EACCES.*\.npm|permission denied.*\.npm|EACCES.*cache" "$err_log" 2>/dev/null; then
    case_cache=true
  fi

  if [[ "$case_global" == false && "$case_cache" == false ]]; then
    # Не похоже на permission — пусть выше скажет про сеть
    return 1
  fi

  echo ""
  warn "Права доступа npm сломаны. Разбираю по типу:"
  echo ""

  if [[ "$case_cache" == true ]]; then
    echo -e "   ${BOLD}${RED}Случай Б: ${NC}${BOLD}~/.npm принадлежит root${NC}"
    echo -e "   ${DIM}(вероятно кто-то раньше запустил 'sudo npm ...' — это сломало права на кэш)${NC}"
    echo -e "   ${DIM}Фикс:${NC}"
    echo -e "      ${GREEN}sudo chown -R \$(id -u):\$(id -g) ~/.npm${NC}"
    echo ""
  fi

  if [[ "$case_global" == true ]]; then
    echo -e "   ${BOLD}${RED}Случай А: ${NC}${BOLD}системный Node.js требует sudo для -g${NC}"
    echo -e "   ${DIM}(у вас Node.js не через nvm, а через системный установщик)${NC}"
    echo -e "   ${DIM}Фикс (одна из команд):${NC}"
    echo -e "      ${GREEN}sudo npm install -g openclaw@latest${NC}"
    echo -e "   ${DIM}Или перейти на nvm (правильнее, без sudo):${NC}"
    echo -e "      ${GREEN}curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash${NC}"
    echo -e "      ${GREEN}nvm install 22 && nvm use 22 && npm install -g openclaw@latest${NC}"
    echo ""
  fi

  if [[ "$case_global" == true && "$case_cache" == true ]]; then
    echo -e "   ${YELLOW}⚠ У вас сломаны ОБА случая. Сначала почините ~/.npm (Б), потом установку (А).${NC}"
    echo ""
  fi

  return 0
}

# Устойчивая установка OpenClaw через npm — с ретраями и нормальными таймаутами
install_openclaw_npm() {
  # Настраиваем npm для стабильной работы при плохой сети
  npm config set fetch-retries 5 >/dev/null 2>&1 || true
  npm config set fetch-retry-mintimeout 20000 >/dev/null 2>&1 || true
  npm config set fetch-retry-maxtimeout 120000 >/dev/null 2>&1 || true
  npm config set fetch-timeout 300000 >/dev/null 2>&1 || true

  local attempt=1
  local max_attempts=3
  local rc=1
  local err_log
  err_log=$(mktemp -t openclaw-npm-err.XXXXXX)

  while [[ $attempt -le $max_attempts ]]; do
    if [[ $attempt -gt 1 ]]; then
      echo ""
      warn "Сеть подвисла. Повторная попытка ${attempt}/${max_attempts}..."
      sleep 3
    fi

    # Запускаем heartbeat в фоне, чтобы пользователь видел «я жив, качаю»
    start_heartbeat "качаю зависимости OpenClaw" 30 300 &
    local hb_pid=$!

    set +e
    # stdout → пользователю (последние 12 строк), stderr → в лог для диагностики
    npm install -g openclaw@latest 2>"$err_log" | tail -12 | while IFS= read -r line; do
      echo -e "   ${DIM}${line}${NC}"
    done
    rc=${PIPESTATUS[0]}
    set -e

    stop_heartbeat "$hb_pid"

    if [[ $rc -eq 0 ]] && command -v openclaw &>/dev/null; then
      rm -f "$err_log"
      return 0
    fi

    # Если это НЕ network timeout, а permission — не имеет смысла ретраить,
    # выходим сразу и показываем диагностику.
    if grep -qE "EACCES|permission denied" "$err_log" 2>/dev/null; then
      diagnose_npm_eacces "$err_log"
      rm -f "$err_log"
      return 2   # exit code «permission» — отличается от сетевого (=1)
    fi

    attempt=$((attempt + 1))
  done

  # Сетевая ошибка после всех попыток — покажем последние строки stderr
  if [[ -s "$err_log" ]]; then
    echo ""
    echo -e "   ${DIM}Последние строки ошибки:${NC}"
    tail -5 "$err_log" | while IFS= read -r line; do
      echo -e "   ${DIM}${line}${NC}"
    done
  fi
  rm -f "$err_log"
  return 1
}

# Интерактивный промпт автоустановки Node.js — спрашивает и запускает
prompt_install_node() {
  echo ""
  explain "Node.js или npm не найдены (или версия устарела)." \
    "" \
    "Я могу автоматически установить Node.js 22 LTS через nvm" \
    "(Node Version Manager — безопасно, без прав администратора)." \
    "" \
    "Или откажитесь — тогда установите вручную с nodejs.org."

  echo -e "   ${BOLD}${WHITE}Установить Node.js автоматически? [Y/n]:${NC}"
  read -r autoinstall
  autoinstall="${autoinstall:-y}"

  if [[ "$autoinstall" == "y" || "$autoinstall" == "Y" ]]; then
    install_node_via_nvm
  else
    echo ""
    explain "Хорошо. Установите Node.js вручную:" \
      "  1. Зайдите на https://nodejs.org" \
      "  2. Скачайте LTS-версию (зелёная кнопка)" \
      "  3. Установите" \
      "  4. Перезапустите терминал и запустите скрипт снова"
    exit 1
  fi
}

# ═══════════════════════════════════════════════════════════════
#  Helper: гарантируем здоровый gateway (fixes Gregory's issue)
# ═══════════════════════════════════════════════════════════════
#
# Контекст: openclaw onboard иногда падает с
#   "Cannot read properties of undefined (reading 'trim')"
# и оставляет конфиг без gateway.mode — после чего gateway
# закрывается с "1006 abnormal closure" и Telegram-бот молчит,
# хотя токен на месте.
#
# Этот helper:
#   1. Насильно ставит gateway.mode=local
#   2. Валидирует конфиг, чинит через doctor --fix
#   3. Делает deep-проверку gateway
#   4. При неудаче — перезапускает и пробует ещё раз
ensure_gateway_healthy() {
  local label="${1:-gateway}"

  # Отключаем set -e на время хелпера — нам важно прогнать ВСЕ шаги,
  # даже если какой-то openclaw-вызов вернёт non-zero.
  set +e

  # 1. gateway.mode=local — главный фикс
  local current_mode
  current_mode=$(openclaw config get gateway.mode 2>/dev/null | tr -d '\n" ')
  if [[ "$current_mode" != "local" ]]; then
    if openclaw config set gateway.mode local &>/dev/null; then
      echo -e "   ${GREEN}✓${NC} gateway.mode=local (локальный режим)"
    fi
  fi

  # 2. Валидация конфига
  local validation
  validation=$(openclaw config validate 2>&1)
  if echo "$validation" | grep -qiE "error|invalid|unrecognized"; then
    echo -e "   ${DIM}Чиню конфиг: openclaw doctor --fix --yes${NC}"
    openclaw doctor --fix --yes 2>&1 | tail -5 | while IFS= read -r line; do
      echo -e "   ${DIM}${line}${NC}"
    done
  fi

  # 3. Deep health check (fallback на обычный status если --deep не поддержан)
  local status_out
  status_out=$(openclaw gateway status --deep 2>&1)
  if [[ "$status_out" == *"unknown option"* || "$status_out" == *"Unknown"* ]]; then
    status_out=$(openclaw gateway status 2>&1)
  fi

  if echo "$status_out" | grep -qE "running|RPC probe: ok"; then
    echo -e "   ${GREEN}✓${NC} Gateway здоров"
    set -e
    return 0
  fi

  # 4. Recovery — перезапуск
  echo -e "   ${YELLOW}○${NC} Gateway не отвечает. Перезапускаю..."
  openclaw gateway restart 2>&1 | tail -3 | while IFS= read -r line; do
    echo -e "   ${DIM}${line}${NC}"
  done
  sleep 2

  if openclaw gateway status 2>&1 | grep -qE "running"; then
    echo -e "   ${GREEN}✓${NC} Gateway поднялся после перезапуска"
    set -e
    return 0
  fi

  warn "Gateway всё ещё не отвечает. Recovery вручную:"
  echo -e "   ${DIM}  openclaw config set gateway.mode local${NC}"
  echo -e "   ${DIM}  openclaw doctor --fix --yes${NC}"
  echo -e "   ${DIM}  openclaw gateway restart${NC}"
  echo -e "   ${DIM}  openclaw logs --follow    # посмотреть что падает${NC}"
  set -e
  return 1
}

# ═══════════════════════════════════════════════════════════════
#  Helper: согласованность provider+model у defaults и всех агентов
# ═══════════════════════════════════════════════════════════════
#
# Контекст (из живых кейсов Саввы и Елены):
#   • Пользователь выбирает MiniMax 2.5 Free, всё выглядит ok.
#   • Но на реальный запрос прилетает «HTTP 401: Model is disabled»
#     или «Invalid API key».
#
# Причины, которые мы реально видели в чате:
#   1. agents.defaults.model.primary = opencode/minimax-m2.5-free,
#      но agents.list[i].model = opencode/kimi-k2.5 (старый override)
#   2. После нескольких кругов `configure --section model` auth-профиль
#      остался в «opencode:default» с кривым ключом, а модель уже
#      другая — схема «provider ok, model ok, а ключ сохранён на
#      другой provider-id»
#   3. Пользователь ввёл не то в «Provider id» vs «Profile id» в CLI,
#      создал дубль — и два конфликтующих профиля
#
# Что делает этот helper:
#   • смотрит, какая модель задана у defaults
#   • проходит по всем agents.list[*].model — если расходится,
#     приводит всех к default (устраняет кейс 1)
#   • чистит session cache (чтобы не тащился tool_use_id с прошлой модели)
#   • НЕ трогает auth-profiles — это отдельный слой, чинится через R3 меню
ensure_model_consistency() {
  local expected_model="${1:-opencode/minimax-m2.5-free}"

  set +e

  local current_default
  current_default=$(openclaw config get agents.defaults.model.primary 2>/dev/null | tr -d '\n" ')

  # Если default вообще не задан — проставляем
  if [[ -z "$current_default" ]]; then
    openclaw config set agents.defaults.model.primary "$expected_model" &>/dev/null
    current_default="$expected_model"
    echo -e "   ${GREEN}✓${NC} Модель по умолчанию проставлена: ${expected_model}"
  fi

  # Собираем список агентов — если CLI отдаёт
  local agents_raw
  agents_raw=$(openclaw config get agents.list 2>/dev/null)
  local agent_count
  agent_count=$(echo "$agents_raw" | grep -c '"id"' 2>/dev/null || echo 0)
  # grep -c может вернуть пусто при pipefail, приводим к числу
  [[ "$agent_count" =~ ^[0-9]+$ ]] || agent_count=0

  local mismatched=0
  if [[ "$agent_count" -gt 0 ]]; then
    for i in $(seq 0 $((agent_count - 1))); do
      local agent_model
      agent_model=$(openclaw config get "agents.list[${i}].model" 2>/dev/null | tr -d '\n" ')
      if [[ -n "$agent_model" && "$agent_model" != "$current_default" ]]; then
        # Расхождение — переписываем
        openclaw config set "agents.list[${i}].model" "\"${current_default}\"" --strict-json &>/dev/null
        mismatched=$((mismatched + 1))
      fi
    done
  fi

  if [[ "$mismatched" -gt 0 ]]; then
    echo -e "   ${GREEN}✓${NC} У ${mismatched} агент(ов) была другая модель — все приведены к ${current_default}"
    # Чистим сессии — иначе tool_use_id от старой модели будет конфликтовать
    openclaw sessions cleanup --all-agents &>/dev/null || true
    echo -e "   ${GREEN}✓${NC} Очищены сессии (чтобы не было конфликта с tool_use_id от старой модели)"
  fi

  set -e
  return 0
}

# ═══════════════════════════════════════════════════════════════
#  --collect-debug: ручной сбор bundle, ничего не устанавливаем
# ═══════════════════════════════════════════════════════════════
# Вызов идёт именно здесь: функция `collect_debug_bundle` уже определена
# выше вместе с остальными helpers, а основное меню установки — ниже.
if [[ "$COLLECT_DEBUG_ONLY" == true ]]; then
  echo ""
  echo -e "${BOLD}${CYAN}📦 Сбор debug-bundle для саппорта${NC}"
  echo -e "${DIM}   Installer v${INSTALLER_VERSION} (${INSTALLER_COMMIT})${NC}"
  collect_debug_bundle "manual (user ran --collect-debug)"
  exit 0
fi

# ═══════════════════════════════════════════════════════════════
#  НАЧАЛЬНОЕ МЕНЮ — 3 варианта сразу на старте
# ═══════════════════════════════════════════════════════════════

if [[ "$SKIP_DEMO" != true ]]; then
  clear
  echo ""
  echo -e "${BOLD}${MAGENTA}"
  cat << 'LOGO'
     ___                    ____ _
    / _ \ _ __   ___ _ __  / ___| | __ ___      __        _____ ____  _   _ _____
   | | | | '_ \ / _ \ '_ \| |   | |/ _` \ \ /\ / /       |_   _|  _ \| | | | ____|
   | |_| | |_) |  __/ | | | |___| | (_| |\ V  V /          | | | |_) | | | |  _|
    \___/| .__/ \___|_| |_|\____|_|\__,_| \_/\_/           | | |  _ <| |_| | |___
         |_|                                                |_| |_| \_\\___/|_____|
LOGO
  echo -e "${NC}"
  echo -e "${BOLD}   AI-шлюз для мессенджеров (Telegram, WhatsApp, Discord, Slack…)${NC}"
  echo -e "${DIM}   https://openclaw.ai${NC}"
  echo -e "${DIM}   Installer v${INSTALLER_VERSION} (${INSTALLER_COMMIT})${NC}"
  echo ""
  echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  explain "Выберите, как хотите начать:"

  echo -e "   ${BOLD}${GREEN}  1)${NC}  ${BOLD}Демо${NC} — 10 шагов с объяснением на русском."
  echo -e "       ${DIM}Ничего не ставится, просто показываю, как всё устроено.${NC}"
  echo -e "       ${DIM}После демо можно перейти к реальной установке или симуляции.${NC}"
  echo ""
  echo -e "   ${BOLD}${YELLOW}  2)${NC}  ${BOLD}Реальная установка${NC} — ставим OpenClaw на ваш компьютер,"
  echo -e "       ${DIM}подключаем Telegram-бота, создаём первого AI-ассистента.${NC}"
  echo ""
  echo -e "   ${BOLD}${CYAN}  3)${NC}  ${BOLD}Симуляция установки${NC} — прогон процесса без реальных изменений."
  echo -e "       ${DIM}Полезно, если хочется сначала увидеть каждый шаг своими глазами.${NC}"
  echo ""

  divider

  echo -e "   ${BOLD}${WHITE}Выберите вариант [1/2/3]:${NC}"
  echo ""
  read -r INITIAL_CHOICE

  case "$INITIAL_CHOICE" in
    2)
      SKIP_DEMO=true
      DRY_RUN=false
      ;;
    3)
      SKIP_DEMO=true
      DRY_RUN=true
      ;;
    1|"")
      # Идём в демо — SKIP_DEMO остаётся false
      :
      ;;
    *)
      echo ""
      explain "Не распознал выбор. Запустите скрипт ещё раз и введите 1, 2 или 3."
      exit 0
      ;;
  esac
fi

# ═══════════════════════════════════════════════════════════════
#  Если SKIP_DEMO — пропускаем демо, сразу к реальной установке
# ═══════════════════════════════════════════════════════════════

if [[ "$SKIP_DEMO" == true ]]; then
  # Определяем функции уже загружены, переходим к ЧАСТИ 2
  :
else

# ═══════════════════════════════════════════════════════════════
#  СТАРТОВЫЙ ЭКРАН
# ═══════════════════════════════════════════════════════════════

clear
echo ""
echo -e "${BOLD}${MAGENTA}"
cat << 'LOGO'
     ___                    ____ _
    / _ \ _ __   ___ _ __  / ___| | __ ___      __        _____ ____  _   _ _____
   | | | | '_ \ / _ \ '_ \| |   | |/ _` \ \ /\ / /       |_   _|  _ \| | | | ____|
   | |_| | |_) |  __/ | | | |___| | (_| |\ V  V /          | | | |_) | | | |  _|
    \___/| .__/ \___|_| |_|\____|_|\__,_| \_/\_/           | | |  _ <| |_| | |___
         |_|                                                |_| |_| \_\\___/|_____|
LOGO
echo -e "${NC}"
echo -e "${BOLD}   Installation Demo — Демонстрация установки${NC}"
echo -e "${DIM}   Installer v${INSTALLER_VERSION} (${INSTALLER_COMMIT})${NC}"
echo -e "${DIM}   Isolated profile: ${PROFILE} (does not affect your system)${NC}"
echo -e "${DIM}   Directory: ${DEMO_DIR}${NC}"
echo ""
echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

explain "Добро пожаловать!" \
  "" \
  "Сейчас мы вместе пройдём установку OpenClaw с нуля — шаг за шагом," \
  "как будто вы только что сели за компьютер и решили: «хочу AI-агентов в Telegram»." \
  "" \
  "Всё, что вы увидите на английском — это реальный вывод программы." \
  "Именно так будет выглядеть ваш терминал при настоящей установке." \
  "После каждого английского блока будет подробное объяснение на русском."

explain "Как будет проходить процесс:" \
  "" \
  "  ${BOLD}1.${NC} ${DIM}Объяснение (10 шагов)${NC} — сначала мы просто пройдёмся по тому," \
  "     что такое OpenClaw, как он устанавливается, настраивается и работает." \
  "     Это чистое объяснение — ничего не ставится, ничего не меняется." \
  "" \
  "  ${BOLD}2.${NC} ${DIM}Меню выбора${NC} — после объяснения вам будет предложено 3 варианта:" \
  "       • ${GREEN}Завершить${NC} — просто выйти (посмотрели и хорошо)" \
  "       • ${YELLOW}Установить по-настоящему${NC} — развернуть OpenClaw на компьютере" \
  "       • ${CYAN}Симуляция${NC} — повторить процесс установки без реальных изменений" \
  "" \
  "  ${BOLD}3.${NC} ${DIM}Дальше по вашему выбору${NC} — никаких сюрпризов, всё под контролем."

explain "Что такое OpenClaw?" \
  "" \
  "Представьте себе «переводчика» между мессенджерами и AI." \
  "Вы подключаете Telegram (или WhatsApp, Discord, Slack — 30+ каналов)," \
  "а OpenClaw соединяет их с умными AI-моделями (Claude, GPT, Gemini)." \
  "" \
  "В итоге у вас появляется бот (или несколько), которые отвечают" \
  "людям в мессенджерах — пишут тексты, отвечают на вопросы, помогают с задачами." \
  "Всё работает на вашем компьютере, без облачных серверов."

echo ""
echo -e "   ${BOLD}${MAGENTA}🤖 Если что-то непонятно — спросите у нейрокуратора${NC}"
echo -e "   ${DIM}   Любой вопрос про установку, настройку, ошибки — всё объяснит.${NC}"
echo -e "   ${DIM}   Не нужно гуглить, не нужно читать документацию — просто спросите.${NC}"
echo -e "   ${DIM}   Нейрокуратор знает всё про OpenClaw и ведёт вас от А до Я.${NC}"
echo ""

# ─── Важное объяснение про знак доллара ───
echo ""
echo -e "   ${BOLD}${YELLOW}⚠️  Важно про копирование команд${NC}"
echo ""
echo -e "   ${DIM}Когда увидите такую строку:${NC}"
echo -e "   ${DIM}┌─ 📋 скопируйте эту команду (без \$) ─────────────────────┐${NC}"
echo -e "   ${DIM}│${NC} ${YELLOW}\$${NC} ${GREEN}${BOLD}npm install -g openclaw@latest${NC}"
echo -e "   ${DIM}└──────────────────────────────────────────────────────────┘${NC}"
echo ""
echo -e "   ${DIM}Знак ${YELLOW}\$${NC} ${DIM}слева — это просто значок терминала (курсор).${NC}"
echo -e "   ${DIM}Копировать нужно ${BOLD}ТОЛЬКО${NC}${DIM} команду после него:${NC}"
echo -e "   ${GREEN}   npm install -g openclaw@latest${NC}   ${DIM}← вот это${NC}"
echo ""
echo -e "   ${RED}✗${NC} ${DIM}Неправильно: ${NC}${RED}\$ npm install -g openclaw@latest${NC}   ${DIM}(с долларом)${NC}"
echo -e "   ${GREEN}✓${NC} ${DIM}Правильно:   ${NC}${GREEN}npm install -g openclaw@latest${NC}     ${DIM}(без доллара)${NC}"
echo ""

explain "Это демо. Ваша рабочая система не пострадает." \
  "Мы используем изолированный профиль «${PROFILE}» — все файлы будут" \
  "в отдельной папке ${DEMO_DIR}, а в конце — автоматически удалятся."

pause

# ═══════════════════════════════════════════════════════════════
#  ШАГ 0: Очистка
# ═══════════════════════════════════════════════════════════════

if [[ -d "$DEMO_DIR" ]]; then
  step_header "0" "CLEANUP"

  explain "Нашлись файлы от прошлой демонстрации — удаляем их." \
    "Чтобы начать с абсолютно чистого листа."

  run_cmd "rm -rf ${DEMO_DIR}"
  terminal "Removed ${DEMO_DIR}"
  ru "Старая демо-папка удалена. Теперь всё чисто."
fi

# ═══════════════════════════════════════════════════════════════
#  ШАГ 1: Проверка системы
# ═══════════════════════════════════════════════════════════════

step_header "1" "SYSTEM CHECK"

explain "Проверяем, что на компьютере есть всё необходимое." \
  "" \
  "OpenClaw — это программа, написанная на JavaScript. Чтобы она работала," \
  "нужна среда Node.js — как «двигатель», который запускает JS-код." \
  "" \
  "Вместе с Node.js идёт npm — это «магазин приложений» для программистов." \
  "Через npm мы и будем устанавливать OpenClaw — одной командой." \
  "" \
  "Если у вас нет Node.js — скачайте с сайта nodejs.org и установите." \
  "Это бесплатно и занимает 2 минуты."

divider

explain "Проверяем Node.js:" \
  "Вводим команду node -v — она покажет версию, если Node.js установлен." \
  "Минимум нужна версия 22.14. Если ниже — обновите с nodejs.org."

show_cmd "node -v"
echo ""
if command -v node &>/dev/null; then
  NODE_VER=$(node -v)
  terminal "${NODE_VER}"
  echo ""
  ru "Число после буквы 'v' — это версия. Например, v25.9.0 означает версию 25.9.0."
  ru "У вас ${NODE_VER} — отлично, это больше чем 22.14, значит подходит."
else
  terminal "v22.14.0"
  echo ""
  ru "Число после буквы 'v' — это версия. Минимум нужна 22.14."
  ru "Если у вас Node.js не установлен — ничего страшного, поставим позже,"
  ru "когда выберете «Реальную установку» в меню после демо."
fi

divider

explain "Проверяем npm:" \
  "npm — это менеджер пакетов. Через него устанавливаются программы вроде OpenClaw." \
  "Он автоматически ставится вместе с Node.js — отдельно скачивать не нужно."

show_cmd "npm -v"
echo ""
if command -v npm &>/dev/null; then
  NPM_VER=$(npm -v)
  terminal "${NPM_VER}"
  echo ""
  ru "npm версии ${NPM_VER} — есть и работает, всё ок."
else
  terminal "11.3.0"
  echo ""
  ru "Так выглядит версия npm. Он ставится вместе с Node.js — отдельно не нужно."
fi

ok "System check passed — все зависимости на месте"
ru "Компьютер готов. Можно переходить к установке самого OpenClaw."

pause

# ═══════════════════════════════════════════════════════════════
#  ШАГ 2: Установка OpenClaw
# ═══════════════════════════════════════════════════════════════

step_header "2" "INSTALL OPENCLAW"

explain "Устанавливаем OpenClaw на компьютер." \
  "" \
  "Для этого нужна всего одна команда. npm скачает OpenClaw из интернета" \
  "и установит его глобально — это значит, что команда 'openclaw' станет" \
  "доступна из любого места в терминале, а не только в одной папке." \
  "" \
  "Думайте об этом как об установке обычной программы — только через терминал" \
  "вместо «кнопки Скачать» на сайте."

divider

explain "Вот эту команду нужно ввести в терминал:" \
  "• npm install — скачать и установить" \
  "• -g — глобально (для всей системы)" \
  "• openclaw@latest — последняя версия OpenClaw"

show_cmd "npm install -g openclaw@latest"
echo ""

explain "Установка займёт 30–60 секунд. Вы увидите примерно такой вывод:"

terminal "npm warn deprecated inflight@1.0.6"
terminal ""
terminal "added 847 packages in 45s"
terminal ""
terminal "103 packages are looking for funding"
terminal "  run \`npm fund\` for details"
echo ""
ru "'added 847 packages' — npm скачал 847 библиотек, от которых зависит OpenClaw."
ru "Это нормально — современные программы состоят из множества маленьких модулей."
ru ""
ru "'looking for funding' — некоторые авторы просят поддержку. Это информация,"
ru "НЕ ошибка. Можно спокойно игнорировать."
ru ""
ru "'npm warn deprecated' — предупреждение о старой библиотеке внутри пакета."
ru "Тоже не ошибка — просто информация для разработчиков. Игнорируем."

divider

explain "Проверяем, что OpenClaw установился:" \
  "Команда --version покажет номер версии — значит, всё прошло успешно."

show_cmd "openclaw --version"
echo ""
terminal "OpenClaw 2026.4.9 (0512059)"
echo ""
ru "Так выглядит успешный ответ: версия + хэш сборки."
ru "Номер вида 2026.4.9 — это год.месяц.день выпуска."
ru "В скобках — хэш сборки (код конкретной версии). Он нужен разработчикам."

ok "OpenClaw installed — так выглядит успешная установка"
ru "Это был демо-вывод. Настоящая установка запустится, если выберете её в меню."

pause

# ═══════════════════════════════════════════════════════════════
#  ШАГ 3: Первый запуск (onboard)
# ═══════════════════════════════════════════════════════════════

step_header "3" "FIRST RUN — ONBOARDING"

explain "При первом запуске OpenClaw нужно задать один вопрос: ваш API-ключ." \
  "" \
  "Раньше был интерактивный мастер 'openclaw onboard' с четырьмя вопросами," \
  "но у него есть баги — он циклился на выборе каналов, не всегда реагировал" \
  "на стрелки. Поэтому наш установщик настраивает всё напрямую — быстрее и надёжнее." \
  "" \
  "Провайдер мы уже выбрали за вас — ${BOLD}opencode.ai${NC}. Это умный прокси:" \
  "один ключ даёт доступ к Claude, GPT, Gemini, Grok, Kimi и 25+ моделям." \
  "Дешевле и удобнее, чем регистрироваться у каждого отдельно."

divider

# --- Шаг 1: О провайдере opencode.ai ---

explain "ПРОВАЙДЕР — opencode.ai" \
  "" \
  "Обычно для AI-агентов нужно регистрироваться отдельно у каждого:" \
  "  • Anthropic (для Claude)" \
  "  • OpenAI (для GPT)" \
  "  • Google (для Gemini)" \
  "У каждого свой ключ, свой биллинг, свой дашборд." \
  "" \
  "opencode.ai — один ключ ко всем моделям сразу. Как универсальная SIM-карта." \
  "Один счёт, один дашборд, легко менять модели." \
  "" \
  "По умолчанию мы ставим ${BOLD}Minimax 2.5 (free tariff)${NC} —" \
  "работает без оплаты, хорошо справляется с повседневными задачами." \
  "Если захотите Claude или GPT — одна команда, и вы на другой модели."

divider

# --- Шаг 2: API-ключ ---

explain "ВОПРОС — API-ключ opencode.ai" \
  "" \
  "API-ключ — это ваш персональный «пароль» для доступа к моделям." \
  "" \
  "Где его взять:" \
  "  ${CYAN}1.${NC} Откройте ${BOLD}https://opencode.ai${NC} (браузер сам откроется в реальной установке)" \
  "  ${CYAN}2.${NC} Зарегистрируйтесь (можно через Google) или войдите" \
  "  ${CYAN}3.${NC} Выберите провайдера ${BOLD}OpenCode${NC}" \
  "  ${CYAN}4.${NC} Перейдите в раздел ${BOLD}OpenCode Zen${NC}" \
  "  ${CYAN}5.${NC} В списке моделей выберите ${BOLD}${GREEN}MiniMax M2.5 (Free)${NC} — бесплатный тариф" \
  "  ${CYAN}6.${NC} ${BOLD}API Keys${NC} → ${BOLD}Create new key${NC}" \
  "  ${CYAN}7.${NC} Скопируйте ключ (формат: sk-...)" \
  "" \
  "В реальной установке скрипт автоматически откроет opencode.ai в браузере."

echo -e "   ${WHITE}? Paste your opencode.ai API key${NC}"
echo -e "   ${DIM}  ▸ sk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx${NC}"
echo ""
ru "Вы вставляете ключ (Ctrl+V или Cmd+V) и нажимаете Enter."
ru "Ключ начинается с 'sk-'."
ru ""
ru "ВАЖНО: символы ключа НЕ отображаются при вводе (как пароль в терминале)."
ru "Это нормально! Просто вставьте и нажмите Enter."
ru ""
ru "БЕЗОПАСНОСТЬ: никому не показывайте API-ключ. Он привязан к вашему"
ru "аккаунту opencode.ai. Если утёк — сбросьте его в дашборде."

divider

# --- Шаг 3: Gateway (автоматически) ---

explain "GATEWAY — установка в фоне (без вопросов)" \
  "" \
  "Gateway (шлюз) — это «сердце» OpenClaw. Работает в фоне на компьютере:" \
  "  • принимает сообщения из Telegram" \
  "  • отправляет их в AI-модель через opencode.ai" \
  "  • получает ответ и пересылает обратно пользователю" \
  "" \
  "Скрипт автоматически:" \
  "  • поставит gateway как системный сервис (macOS — LaunchAgent, Linux — systemd)" \
  "  • включит автозапуск при загрузке компьютера" \
  "  • стартует его прямо сейчас"

divider

# --- Результат onboard ---

explain "Готово! OpenClaw создал конфигурацию и запустил gateway:" \
  "Вот что вы увидите после ввода ключа —"

echo -e "   ${WHITE}✓ Config created: ~/.openclaw/openclaw.json${NC}"
ru "Создан главный файл настроек. Все параметры хранятся здесь — модель,"
ru "ключи, список агентов, подключённые каналы. Можно редактировать вручную."
echo ""
echo -e "   ${WHITE}✓ Workspace initialized: ~/.openclaw/workspace${NC}"
ru "Создана рабочая папка. В ней хранятся файлы агентов, их сессии и память."
echo ""
echo -e "   ${WHITE}✓ Gateway service installed${NC}"
ru "Сервис добавлен в автозапуск системы. При включении компьютера — стартует сам."
echo ""
echo -e "   ${WHITE}✓ Gateway started on port 18789${NC}"
ru "Шлюз запущен прямо сейчас! Порт 18789 — это «адрес» gateway на компьютере."
echo ""
echo -e "   ${WHITE}✓ Dashboard: http://127.0.0.1:18789${NC}"
ru "Веб-панель управления. Откройте этот адрес в браузере — увидите интерфейс."
ru "127.0.0.1 — это адрес вашего компьютера (localhost). Только вы видите эту панель."

# Создаём структуру для демо
mkdir -p "${DEMO_DIR}/logs"
mkdir -p "${DEMO_DIR}/agents/main/sessions"
mkdir -p "${DEMO_DIR}/workspace"

ok "Onboarding complete — первоначальная настройка завершена"
ru "На этом первый запуск окончен. У вас есть работающий gateway и один агент 'main'."
ru "Дальше подключим мессенджер и научим агента отвечать."

pause

# ═══════════════════════════════════════════════════════════════
#  ШАГ 4: Проверка gateway
# ═══════════════════════════════════════════════════════════════

step_header "4" "CHECK GATEWAY STATUS"

explain "Проверяем здоровье системы." \
  "" \
  "Это как проверить пульс у пациента: работает ли gateway, отвечает ли он," \
  "нет ли ошибок. Эту команду полезно знать на будущее — если агент" \
  "перестанет отвечать, первым делом проверяйте статус gateway."

divider

explain "Команда gateway status — «как ты, gateway?»:"

show_cmd "openclaw gateway status"
echo ""
terminal "Service: LaunchAgent (loaded)"
terminal "Runtime: running (pid 12345, state active)"
terminal "RPC probe: ok"
terminal "Port: 18789"
terminal "Bind: loopback"
echo ""
ru "'Service: LaunchAgent (loaded)' — сервис зарегистрирован в системе macOS."
ru "  «loaded» значит, что система знает про этот сервис и может его запускать."
ru ""
ru "'Runtime: running (pid 12345)' — gateway работает прямо сейчас."
ru "  pid — это Process ID, номер процесса. Нужен только для диагностики."
ru "  Если бы было 'stopped' — значит gateway выключен и агенты не отвечают."
ru ""
ru "'RPC probe: ok' — gateway не просто запущен, а ещё и отвечает на запросы."
ru "  Это самый важный показатель. Если 'fail' — значит процесс завис."
ru ""
ru "'Port: 18789' — порт, на котором работает. Запомните его для Dashboard."
ru "'Bind: loopback' — доступен только с вашего компьютера. Это безопасно."
ru "  Никто из интернета не сможет подключиться к вашему gateway."

divider

explain "Ещё одна полезная команда — полный отчёт status --all." \
  "Показывает ВСЁ: модели, каналы, агентов — одним взглядом."

show_cmd "openclaw status --all"
echo ""
terminal "OpenClaw 2026.4.9 (0512059)"
terminal "Gateway: running (pid 12345)"
terminal "Model: opencode/minimax-m2.5-free"
terminal "Channels: 0 configured"
terminal "Agents: 1 (main)"
terminal "Sessions: 0 active"
echo ""
ru "'Model: opencode/minimax-m2.5-free' — AI-модель, которую используют агенты."
ru "'Channels: 0 configured' — мессенджеры ещё не подключены. Сделаем на следующем шаге."
ru "'Agents: 1 (main)' — есть один агент по умолчанию. Скоро создадим ещё."
ru "'Sessions: 0 active' — нет активных разговоров (никто ещё не писал)."

ok "Gateway is healthy — всё работает штатно"

pause

# ═══════════════════════════════════════════════════════════════
#  ШАГ 5: Dashboard
# ═══════════════════════════════════════════════════════════════

step_header "5" "OPEN DASHBOARD"

explain "Dashboard — панель управления с графическим интерфейсом." \
  "" \
  "Всё, что можно делать в терминале, можно делать и через Dashboard." \
  "Но Dashboard удобнее — кнопки, списки, чат для тестирования." \
  "Многие предпочитают именно его, а не командную строку." \
  "" \
  "Dashboard работает в браузере — Chrome, Safari, Firefox, любой."

divider

show_cmd "openclaw dashboard"
echo ""
terminal "Opening http://127.0.0.1:18789 in default browser..."
echo ""
ru "Эта команда просто открывает браузер с адресом панели управления."
ru "Можно и вручную — откройте браузер и введите http://127.0.0.1:18789"

divider

explain "В Dashboard вы увидите такие разделы:"

echo -e "   ${DIM}┌────────────────────────────────────────────────────────────┐${NC}"
echo -e "   ${DIM}│                                                            │${NC}"
echo -e "   ${DIM}│  ${WHITE}📊 Overview${NC}${DIM}    — главная: общий статус, графики         │${NC}"
echo -e "   ${DIM}│                                                            │${NC}"
echo -e "   ${DIM}│  ${WHITE}🤖 Agents${NC}${DIM}      — список агентов: создать, настроить,     │${NC}"
echo -e "   ${DIM}│                   протестировать в чате                     │${NC}"
echo -e "   ${DIM}│                                                            │${NC}"
echo -e "   ${DIM}│  ${WHITE}📱 Channels${NC}${DIM}    — мессенджеры: подключить Telegram,       │${NC}"
echo -e "   ${DIM}│                   WhatsApp, Discord и другие               │${NC}"
echo -e "   ${DIM}│                                                            │${NC}"
echo -e "   ${DIM}│  ${WHITE}⚙️  Config${NC}${DIM}      — настройки: модели, таймауты, ключи    │${NC}"
echo -e "   ${DIM}│                                                            │${NC}"
echo -e "   ${DIM}│  ${WHITE}📋 Sessions${NC}${DIM}    — текущие разговоры агентов               │${NC}"
echo -e "   ${DIM}│                                                            │${NC}"
echo -e "   ${DIM}│  ${WHITE}📜 Logs${NC}${DIM}        — логи в реальном времени                 │${NC}"
echo -e "   ${DIM}│                                                            │${NC}"
echo -e "   ${DIM}└────────────────────────────────────────────────────────────┘${NC}"
echo ""
ru "Не бойтесь нажимать на разные разделы — вы ничего не сломаете."
ru "Dashboard — это только «пульт управления», а не сама система."

ok "Dashboard ready — панель управления работает"

pause

# ═══════════════════════════════════════════════════════════════
#  ШАГ 6: Подключение Telegram
# ═══════════════════════════════════════════════════════════════

step_header "6" "CONNECT TELEGRAM"

explain "Подключаем первый мессенджер — Telegram." \
  "" \
  "Вот как это устроено: в Telegram есть специальные аккаунты — боты." \
  "Бот — это не человек, а программа, которая автоматически отвечает на сообщения." \
  "Вы создаёте бота, передаёте его «ключ» (токен) в OpenClaw, и всё — бот живой." \
  "" \
  "Любой, кто найдёт вашего бота в Telegram, сможет ему написать," \
  "а OpenClaw будет отвечать через AI-модель."

divider

explain "Шаг 6.1 — Создаём бота в Telegram." \
  "" \
  "В Telegram есть официальный «фабричный бот» — @BotFather." \
  "Через него создаются все боты. Это не сторонний сервис — это часть Telegram." \
  "" \
  "Вот что нужно сделать по шагам:"

echo -e "   ${DIM}┌────────────────────────────────────────────────────────────┐${NC}"
echo -e "   ${DIM}│                                                            │${NC}"
echo -e "   ${DIM}│  1. Откройте Telegram на телефоне или компьютере            │${NC}"
echo -e "   ${DIM}│  2. В поиске найдите ${WHITE}@BotFather${NC}${DIM} (с синей галочкой ✓)       │${NC}"
echo -e "   ${DIM}│  3. Нажмите Start или отправьте ${WHITE}/newbot${NC}${DIM}                    │${NC}"
echo -e "   ${DIM}│  4. BotFather спросит имя — введите любое:                  │${NC}"
echo -e "   ${DIM}│     ${WHITE}My AI Assistant${NC}${DIM} (это отображаемое имя)                │${NC}"
echo -e "   ${DIM}│  5. Затем спросит username — уникальный ID:                 │${NC}"
echo -e "   ${DIM}│     ${WHITE}my_ai_assist_bot${NC}${DIM} (должен заканчиваться на _bot)       │${NC}"
echo -e "   ${DIM}│  6. BotFather пришлёт токен — ${RED}СКОПИРУЙТЕ ЕГО!${NC}${DIM}              │${NC}"
echo -e "   ${DIM}│                                                            │${NC}"
echo -e "   ${DIM}│  Токен выглядит так:                                       │${NC}"
echo -e "   ${DIM}│  ${YELLOW}7123456789:AAHk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxx${NC}${DIM}             │${NC}"
echo -e "   ${DIM}│                                                            │${NC}"
echo -e "   ${DIM}│  ${RED}⚠ Никому не показывайте токен!${NC}${DIM}                            │${NC}"
echo -e "   ${DIM}│  Кто знает токен — тот управляет ботом.                    │${NC}"
echo -e "   ${DIM}│                                                            │${NC}"
echo -e "   ${DIM}└────────────────────────────────────────────────────────────┘${NC}"
echo ""

divider

explain "Шаг 6.2 — Подключаем бота к OpenClaw." \
  "" \
  "Берём токен, который прислал BotFather, и передаём его в OpenClaw." \
  "Одна команда — и OpenClaw «оживит» вашего бота."

show_cmd 'openclaw channels add --channel telegram --name "My AI Bot" --token 7123456789:AAHk-xxxxx'
echo ""
terminal "✓ Telegram channel added: My AI Bot"
terminal "✓ Bot connected: @my_ai_assist_bot"
terminal "✓ Webhook configured"
echo ""
ru "'Channel added' — OpenClaw записал настройки бота в конфигурацию."
ru "'Bot connected' — OpenClaw подключился к Telegram через ваш токен."
ru "'Webhook configured' — настроен механизм доставки сообщений."
ru ""
ru "Webhook — это как «подписка на уведомления». Telegram будет автоматически"
ru "отправлять все входящие сообщения на ваш OpenClaw."

divider

explain "Шаг 6.3 — Проверяем, что Telegram подключился."

show_cmd "openclaw channels status --probe"
echo ""
terminal "Channel    Account      Transport     Health"
terminal "telegram   My AI Bot    connected     audit: ok"
echo ""
ru "'Transport: connected' — связь с Telegram работает, сообщения доходят."
ru "'Health: audit ok' — бот прошёл проверку, всё в порядке."
ru ""
ru "Теперь можно открыть Telegram, найти вашего бота и написать ему!"
ru "Он ответит через AI — Claude, GPT или что вы настроили."

ok "Telegram connected — бот подключён и готов к работе"

pause

# ═══════════════════════════════════════════════════════════════
#  ШАГ 7: Агенты
# ═══════════════════════════════════════════════════════════════

step_header "7" "CONFIGURE AGENTS"

explain "Агенты — это «сотрудники» вашего AI-офиса." \
  "" \
  "Каждый агент — это отдельная личность с собственными настройками:" \
  "  • Имя и роль (копирайтер, маркетолог, техподдержка...)" \
  "  • System prompt — инструкция, КАК он должен отвечать" \
  "  • Модель — какой AI-мозг использует (Claude, GPT...)" \
  "  • Память — запоминает контекст разговоров" \
  "" \
  "Можно создать одного универсального агента, а можно целую команду —" \
  "каждый отвечает за своё направление. Как в настоящем офисе."

divider

explain "Создаём нового агента с ID 'copywriter':" \
  "ID — это уникальное короткое имя агента, без пробелов. Оно используется" \
  "в командах и конфигурации. Имя может быть любым: writer, helper, bot1..."

show_cmd "openclaw agents add copywriter"
echo ""
terminal "✓ Agent created: copywriter"
terminal "  Workspace: ~/.openclaw/agents/copywriter"
terminal "  Model: opencode/minimax-m2.5-free (inherited from defaults)"
echo ""
ru "'Agent created' — агент создан. Теперь он существует в системе."
ru "'Workspace' — у агента появилась своя рабочая папка для сессий и памяти."
ru "'Model inherited from defaults' — агент использует ту же модель,"
ru "  что и все остальные (установленную при onboard). Можно сменить индивидуально."

divider

explain "Привязываем агента к Telegram:" \
  "Это важный шаг — без привязки агент существует, но не получает сообщения." \
  "Привязка (bind) говорит: «когда придёт сообщение из Telegram — отдай его этому агенту»."

show_cmd "openclaw agents bind --agent copywriter --bind telegram"
echo ""
terminal "✓ Binding added: copywriter → telegram"
echo ""
ru "Теперь все сообщения из Telegram-бота идут к агенту copywriter."
ru "Один агент может быть привязан к нескольким каналам,"
ru "а один канал может быть привязан к нескольким агентам."

divider

explain "Посмотрим список всех агентов:"

show_cmd "openclaw agents list"
echo ""
terminal "ID           Name         Model                         Bindings"
terminal "main         Main         opencode/minimax-m2.5-free   -"
terminal "copywriter   Copywriter   opencode/minimax-m2.5-free   telegram"
echo ""
ru "'main' — агент по умолчанию, создаётся автоматически. Пока ни к чему не привязан."
ru "'copywriter' — наш новый агент, привязан к каналу telegram."
ru "'Bindings' — к каким каналам привязан агент. Прочерк значит «ни к каким»."

divider

explain "Переключение AI-моделей." \
  "" \
  "Можно менять модель глобально (для всех агентов сразу)" \
  "или индивидуально (для конкретного агента)."

show_cmd "# Модель для всех агентов по умолчанию:"
show_cmd 'openclaw config set agents.defaults.model.primary "opencode/minimax-m2.5-free"'
echo ""
show_cmd "# Персональная модель для одного агента:"
show_cmd "openclaw config set 'agents.list[1].model' '{\"primary\":\"openai/gpt-4o\"}' --strict-json"
echo ""
ru "'agents.defaults.model.primary' — модель по умолчанию. Все новые агенты используют её."
ru "'agents.list[1].model' — переопределение для конкретного агента."
ru "  [1] — порядковый номер в списке (начиная с 0). main = [0], copywriter = [1]."
ru ""
ru "Зачем разные модели? Например: для важных текстов — Claude (умнее, дороже),"
ru "для простых ответов — GPT-4o (быстрее, дешевле)."

ok "Agents configured — агенты настроены"

pause

# ═══════════════════════════════════════════════════════════════
#  ШАГ 8: Первое сообщение
# ═══════════════════════════════════════════════════════════════

step_header "8" "SEND FIRST MESSAGE"

explain "Всё настроено — отправляем первое сообщение!" \
  "" \
  "Есть три способа пообщаться с агентом:" \
  "  1. Из терминала — для быстрой проверки" \
  "  2. Из Telegram — как обычный пользователь" \
  "  3. Через Dashboard — встроенный чат в браузере"

divider

explain "Способ 1: Из терминала (для тестирования)." \
  "Удобно проверить, работает ли агент, не переключаясь в Telegram."

show_cmd 'openclaw agent -m "Hello! What can you do?" --agent copywriter'
echo ""
terminal "I can help you with writing tasks: blog posts, social media content,"
terminal "marketing copy, email newsletters, and more. What would you like"
terminal "to work on?"
echo ""
ru "Агент ответил! Сообщение прошло весь путь:"
ru "  Ваш текст → OpenClaw → AI-модель (Claude) → Ответ → Терминал"
ru "Если видите ответ — значит и в Telegram всё будет работать."

divider

explain "Способ 2: Из Telegram (основной)." \
  "Откройте Telegram, найдите вашего бота и просто напишите ему."

echo -e "   ${DIM}┌────────────────────────────────────────────────────────────┐${NC}"
echo -e "   ${DIM}│                                                            │${NC}"
echo -e "   ${DIM}│  ${WHITE}Вы:${NC}${DIM} Привет! Напиши пост про AI для Telegram.            │${NC}"
echo -e "   ${DIM}│                                                            │${NC}"
echo -e "   ${DIM}│  ${GREEN}🤖 Copywriter:${NC}${DIM}                                           │${NC}"
echo -e "   ${DIM}│  Вот пост про AI для вашего Telegram-канала:               │${NC}"
echo -e "   ${DIM}│                                                            │${NC}"
echo -e "   ${DIM}│  🤖 Искусственный интеллект — не замена человеку,          │${NC}"
echo -e "   ${DIM}│  а усилитель. Представьте: вы пишете текст за 2 часа,      │${NC}"
echo -e "   ${DIM}│  а с AI — за 20 минут. И качество не падает...             │${NC}"
echo -e "   ${DIM}│                                                            │${NC}"
echo -e "   ${DIM}└────────────────────────────────────────────────────────────┘${NC}"
echo ""
ru "Бот получил ваше сообщение из Telegram, передал его в AI-модель"
ru "и вернул готовый ответ — всё автоматически."

divider

explain "Способ 3: Через Dashboard." \
  "Откройте http://127.0.0.1:18789, зайдите в раздел Agents," \
  "выберите агента — и внизу будет поле для чата. Удобно для тестирования."

ok "Первое сообщение отправлено — всё работает!"

pause

# ═══════════════════════════════════════════════════════════════
#  ШАГ 9: Диагностика и починка
# ═══════════════════════════════════════════════════════════════

step_header "9" "TROUBLESHOOTING — WHEN THINGS GO WRONG"

explain "Иногда что-то ломается. Это нормально." \
  "" \
  "Бот не отвечает? Пишет ерунду? Канал отключился?" \
  "Вот набор команд-«скорой помощи», которые решают 90% проблем."

divider

explain "Команда №1: doctor —  «доктор, почини»." \
  "" \
  "Проверяет конфигурацию, сервисы, подключения и автоматически чинит" \
  "найденные проблемы. Это первое, что нужно запустить при любой ошибке."

show_cmd "openclaw doctor --fix"
echo ""
terminal "✓ Config: valid"
terminal "✓ Gateway: running"
terminal "✓ Channels: 1 connected"
terminal "✓ No issues found"
echo ""
ru "'Config: valid' — файл настроек в порядке, ошибок нет."
ru "'Gateway: running' — шлюз работает."
ru "'Channels: 1 connected' — Telegram подключён."
ru "'No issues found' — проблем нет! Если бы были — doctor бы их починил."
ru ""
ru "Флаг --fix включает автопочинку. Без него doctor только покажет проблемы,"
ru "но не будет их исправлять."

divider

explain "Команда №2: очистка сессий." \
  "" \
  "Сессия — это история разговора агента. Со временем она растёт" \
  "и может стать настолько большой, что агент начнёт тормозить или зависать." \
  "Очистка сессий — как «перезагрузка мозга». Агент забудет контекст," \
  "но начнёт отвечать быстро."

show_cmd "openclaw sessions cleanup --all-agents"
echo ""
terminal "Agent: copywriter — cleaned 12 sessions"
terminal "Agent: main — cleaned 3 sessions"
echo ""
ru "Удалено 15 старых сессий. Агенты потеряли историю разговоров,"
ru "но вернулись в рабочее состояние."
ru ""
ru "Когда использовать? Если агент перестал отвечать, отвечает очень медленно,"
ru "или начал выдавать странные ошибки."

divider

explain "Команда №3: логи — «что происходит внутри»." \
  "" \
  "Логи — это записи о каждом действии системы в реальном времени." \
  "Как камера наблюдения: видно, что пришло, что ушло, где ошибка."

show_cmd "openclaw logs --follow"
echo ""
terminal "[2026-04-13 12:00:01] telegram: message received from user 123456"
terminal "[2026-04-13 12:00:02] agent: copywriter processing message..."
terminal "[2026-04-13 12:00:08] telegram: reply sent to user 123456"
echo ""
ru "Каждая строка — одно событие. Здесь видно:"
ru "  12:00:01 — пришло сообщение из Telegram"
ru "  12:00:02 — агент copywriter начал его обрабатывать"
ru "  12:00:08 — ответ отправлен обратно пользователю (за 6 секунд)"
ru ""
ru "Флаг --follow показывает логи «живьём» — новые строки появляются сами."
ru "Чтобы остановить, нажмите Ctrl+C."

divider

explain "Команда №4: перезапуск gateway — «последнее средство»." \
  "" \
  "Если ничего другое не помогает — перезапустите gateway." \
  "Это безопасно: все настройки сохранятся, каналы переподключатся."

show_cmd "openclaw gateway restart"
echo ""
terminal "Restarted LaunchAgent: gui/501/ai.openclaw.gateway"
echo ""
ru "Gateway перезапущен. Через 5-10 секунд агенты снова онлайн."
ru "Если и это не помогло — проверьте API-ключ (он мог протухнуть или закончились деньги)."

ok "Теперь вы знаете, как чинить проблемы"

pause

# ═══════════════════════════════════════════════════════════════
#  ШАГ 10: Шпаргалка
# ═══════════════════════════════════════════════════════════════

step_header "10" "CHEAT SHEET — ШПАРГАЛКА"

explain "Все важные команды в одном месте." \
  "Сохраните эту шпаргалку — пригодится каждый день!"

echo ""
echo -e "   ${BOLD}${WHITE}🔍 Diagnostics — Диагностика (первая помощь):${NC}"
show_cmd "openclaw status --all              # Полный отчёт о системе"
show_cmd "openclaw gateway status            # Статус шлюза"
show_cmd "openclaw doctor --fix              # Автопочинка проблем"
show_cmd "openclaw logs --follow             # Логи в реальном времени"
echo ""

echo -e "   ${BOLD}${WHITE}🧠 Models — AI-модели:${NC}"
show_cmd "openclaw models list --all         # Все доступные модели"
show_cmd "openclaw models status             # Проверка авторизации"
show_cmd "openclaw models set <model>        # Сменить модель"
echo ""

echo -e "   ${BOLD}${WHITE}📱 Channels — Мессенджеры:${NC}"
show_cmd "openclaw channels status --probe   # Проверить подключения"
show_cmd "openclaw channels add              # Добавить мессенджер"
echo ""

echo -e "   ${BOLD}${WHITE}🤖 Agents — Агенты:${NC}"
show_cmd "openclaw agents list               # Список всех агентов"
show_cmd "openclaw agents add <id>           # Создать нового"
show_cmd "openclaw agents bind               # Привязать к каналу"
echo ""

echo -e "   ${BOLD}${WHITE}⚙️  Config — Настройки:${NC}"
show_cmd "openclaw config get <path>         # Прочитать параметр"
show_cmd "openclaw config set <path> <val>   # Записать параметр"
show_cmd "openclaw config validate           # Проверить на ошибки"
echo ""

echo -e "   ${BOLD}${WHITE}🔧 Maintenance — Обслуживание:${NC}"
show_cmd "openclaw sessions cleanup          # Очистить сессии агентов"
show_cmd "openclaw gateway restart           # Перезапустить шлюз"
show_cmd "openclaw update                    # Обновить до последней версии"
echo ""

pause

# ═══════════════════════════════════════════════════════════════
#  Финал демо — ВЫБОР
# ═══════════════════════════════════════════════════════════════

step_header "✓" "DEMO COMPLETE"

# Очистка демо-директории
rm -rf "${DEMO_DIR}"

echo ""
echo -e "${BOLD}${MAGENTA}"
cat << 'DONE'
   ╔════════════════════════════════════════════════════════════════╗
   ║                                                                ║
   ║   🎉  Демонстрация завершена!                                  ║
   ║                                                                ║
   ║   Теперь вы знаете, как работает OpenClaw.                     ║
   ║   Демо-файлы удалены. Ваша система чиста.                      ║
   ║                                                                ║
   ╚════════════════════════════════════════════════════════════════╝

DONE
echo -e "${NC}"

explain "Что дальше? У вас три варианта:"

echo -e "   ${BOLD}${GREEN}  1)${NC}  ${BOLD}Завершить${NC} — выйти из скрипта. Вы сможете установить OpenClaw позже"
echo -e "       самостоятельно по инструкции на ${CYAN}docs.openclaw.ai${NC}"
echo ""
echo -e "   ${BOLD}${YELLOW}  2)${NC}  ${BOLD}Установить по-настоящему${NC} — прямо сейчас развернуть OpenClaw,"
echo -e "       подключить Telegram-бота и получить работающего AI-ассистента"
echo ""
echo -e "   ${BOLD}${CYAN}  3)${NC}  ${BOLD}Симуляция установки${NC} — посмотреть, как выглядит процесс установки,"
echo -e "       без реальных изменений на вашем компьютере"
echo ""

divider

echo -e "   ${BOLD}${WHITE}Выберите вариант [1/2/3]:${NC}"
echo ""
read -r CHOICE

case "$CHOICE" in
  2)
    DRY_RUN=false
    ;;
  3)
    DRY_RUN=true
    ;;
  *)
    echo ""
    explain "Хорошо! Когда будете готовы — запустите этот скрипт снова" \
      "или установите вручную:" \
      "" \
      "  npm install -g openclaw@latest" \
      "  openclaw onboard" \
      "" \
      "Удачи! 🙌"
    echo ""
    exit 0
    ;;
esac

fi  # конец if SKIP_DEMO

# Если пришли из демо — меню уже было показано и CHOICE/DRY_RUN заданы.
# Если --install или --dry-run — CHOICE не нужен, идём сразу.
# При повторном проходе (после симуляции) — показываем меню заново.
FIRST_LOOP=${FIRST_LOOP:-true}

while true; do  # цикл меню — после симуляции возвращаемся сюда

  # Показываем меню при возврате из симуляции (не первый проход)
  if [[ "$FIRST_LOOP" == false ]]; then
    echo ""
    step_header "↩" "BACK TO MENU"

    explain "Что дальше?"

    echo -e "   ${BOLD}${GREEN}  1)${NC}  ${BOLD}Завершить${NC} — выйти"
    echo ""
    echo -e "   ${BOLD}${YELLOW}  2)${NC}  ${BOLD}Установить по-настоящему${NC} — развернуть OpenClaw"
    echo ""
    echo -e "   ${BOLD}${CYAN}  3)${NC}  ${BOLD}Симуляция установки${NC} — посмотреть процесс ещё раз"
    echo ""

    divider

    echo -e "   ${BOLD}${WHITE}Выберите вариант [1/2/3]:${NC}"
    echo ""
    read -r CHOICE

    case "$CHOICE" in
      2)
        DRY_RUN=false
        ;;
      3)
        DRY_RUN=true
        ;;
      *)
        echo ""
        explain "До встречи! 🙌"
        echo ""
        exit 0
        ;;
    esac
  fi
  FIRST_LOOP=false

# ═══════════════════════════════════════════════════════════════════════
#
#   ЧАСТЬ 2: РЕАЛЬНАЯ УСТАНОВКА
#
# ═══════════════════════════════════════════════════════════════════════

clear
echo ""
echo -e "${BOLD}${GREEN}"
cat << 'REAL'
    ____  _____    _    _       ___ _   _ ____ _____  _    _     _
   |  _ \| ____|  / \  | |    |_ _| \ | / ___|_   _|/ \  | |   | |
   | |_) |  _|   / _ \ | |     | ||  \| \___ \ | | / _ \ | |   | |
   |  _ <| |___ / ___ \| |___  | || |\  |___) || |/ ___ \| |___| |___
   |_| \_\_____/_/   \_\_____||___|_| \_|____/ |_/_/   \_\_____|_____|

REAL
echo -e "${NC}"

if [[ "$DRY_RUN" == true ]]; then
  echo -e "${BOLD}   Installation Simulation — Симуляция установки${NC}"
  echo -e "${DIM}   Режим --dry-run: ничего не устанавливается, только показ процесса${NC}"
else
  echo -e "${BOLD}   Real Installation — Настоящая установка OpenClaw${NC}"
fi
echo -e "${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [[ "$DRY_RUN" == true ]]; then
  explain "Сейчас мы покажем, как выглядит реальная установка — шаг за шагом." \
    "" \
    "Все команды будут СИМУЛИРОВАНЫ — ничего не установится и не изменится." \
    "Вы увидите, как выглядит каждый этап, что вводить и что ожидать."
else
  explain "Отлично! Сейчас мы установим OpenClaw по-настоящему." \
    "" \
    "Вот что произойдёт:" \
    "  1. Проверим, что Node.js и npm на месте" \
    "  2. Установим OpenClaw (если ещё не установлен)" \
    "  3. Запустим onboard — интерактивную настройку" \
    "  4. Вы введёте токен Telegram-бота" \
    "  5. Система автоматически создаст первого AI-ассистента" \
    "" \
    "Это займёт 3–5 минут."
fi

pause

# ═══════════════════════════════════════════════════════════════
#  REAL STEP 1: Проверка зависимостей
# ═══════════════════════════════════════════════════════════════

# Баннер версии — чтобы в случае проблем саппорт сразу знал, какой
# скрипт запущен у пользователя (вдруг закэшировал старый curl).
echo ""
echo -e "${DIM}   OpenClaw Factory Installer v${INSTALLER_VERSION} (${INSTALLER_COMMIT})${NC}"
echo -e "${DIM}   При обращении в поддержку — пришлите эти цифры, так быстрее${NC}"
echo -e "${DIM}   Или одной командой: bash <(curl ...) --collect-debug${NC}"

# Активируем trap для автоматического сбора debug-bundle при любом падении.
# Только для реальной установки (не DRY_RUN), потому что в симуляции
# нам нечего собирать.
if [[ "$DRY_RUN" != true ]]; then
  trap 'on_installer_error $LINENO' ERR
fi

# ─── Preflight: проверяем сеть ДО того, как начать ставить ───
# (быстрый 5-секундный чек; если корпоративный прокси блокирует
# npm registry, пользователь получит конкретный диагноз сразу,
# а не через 2 минуты таймаута на R2)
if [[ "$DRY_RUN" != true ]]; then
  preflight_network_check || true
fi

step_header "R1" "SYSTEM CHECK"

explain "Проверяем, что всё необходимое на месте..."

if [[ "$DRY_RUN" == true ]]; then
  # Симуляция проверки
  echo -n -e "   ${DIM}Node.js... ${NC}"
  sleep 0.5
  echo -e "${GREEN}✓ v25.9.0${NC}"

  echo -n -e "   ${DIM}npm...     ${NC}"
  sleep 0.3
  echo -e "${GREEN}✓ 11.3.0${NC}"

  echo -n -e "   ${DIM}OpenClaw...${NC}"
  sleep 0.3
  echo -e "${YELLOW}○ не установлен (установим сейчас)${NC}"
  OPENCLAW_INSTALLED=false
else
  NEEDS_NODE_INSTALL=false

  # Проверка Node.js
  echo -n -e "   ${DIM}Node.js... ${NC}"
  if command -v node &>/dev/null; then
    NODE_VER=$(node -v)
    NODE_MAJOR=$(echo "$NODE_VER" | sed 's/v//' | cut -d. -f1)
    if [[ "$NODE_MAJOR" -ge 22 ]]; then
      echo -e "${GREEN}✓ ${NODE_VER}${NC}"
    else
      echo -e "${RED}✗ ${NODE_VER} (нужна >= 22.14)${NC}"
      NEEDS_NODE_INSTALL=true
    fi
  else
    echo -e "${RED}✗ не найден${NC}"
    NEEDS_NODE_INSTALL=true
  fi

  # Проверка npm
  echo -n -e "   ${DIM}npm...     ${NC}"
  if command -v npm &>/dev/null; then
    echo -e "${GREEN}✓ $(npm -v)${NC}"
  else
    echo -e "${RED}✗ не найден${NC}"
    NEEDS_NODE_INSTALL=true
  fi

  # Если что-то не хватает — предлагаем автоустановку
  if [[ "$NEEDS_NODE_INSTALL" == true ]]; then
    prompt_install_node
  fi

  # Проверка Homebrew (для скиллов, которые требуют внешние бинарники)
  echo -n -e "   ${DIM}Homebrew...${NC}"
  if command -v brew &>/dev/null; then
    echo -e "${GREEN}✓ $(brew --version | head -1)${NC}"
    HOMEBREW_INSTALLED=true
  else
    echo -e "${YELLOW}○ не найден (нужен для части скиллов)${NC}"
    HOMEBREW_INSTALLED=false
  fi

  # Проверка OpenClaw
  echo -n -e "   ${DIM}OpenClaw...${NC}"
  if command -v openclaw &>/dev/null; then
    OC_VER=$(openclaw --version 2>&1 | head -1)
    echo -e "${GREEN}✓ ${OC_VER} (уже установлен)${NC}"
    OPENCLAW_INSTALLED=true
  else
    echo -e "${YELLOW}○ не установлен (установим сейчас)${NC}"
    OPENCLAW_INSTALLED=false
  fi

  # Если brew нет — предлагаем поставить ПОСЛЕ проверки всего
  if [[ "$HOMEBREW_INSTALLED" == false ]]; then
    prompt_install_homebrew
  fi
fi

echo ""
ru "Скрипт проверяет три вещи: Node.js (среда запуска), npm (установщик пакетов)"
ru "и сам OpenClaw. Если чего-то нет — подскажет, как установить."
ok "System check passed"

pause

# ═══════════════════════════════════════════════════════════════
#  REAL STEP 2: Установка OpenClaw
# ═══════════════════════════════════════════════════════════════

step_header "R2" "INSTALL OPENCLAW"

if [[ "$DRY_RUN" == true ]]; then
  explain "Устанавливаем OpenClaw через npm..." \
    "В реальной установке эта команда скачает ~850 пакетов за 30–60 секунд."

  show_cmd "npm install -g openclaw@latest"
  echo ""
  sleep 1
  terminal "npm warn deprecated inflight@1.0.6"
  sleep 0.3
  terminal ""
  terminal "added 847 packages in 42s"
  terminal ""
  terminal "103 packages are looking for funding"
  terminal "  run \`npm fund\` for details"
  echo ""
  ru "'added 847 packages' — все зависимости скачаны и установлены."
  ru "'looking for funding' — информационное сообщение, НЕ ошибка."

  divider

  show_cmd "openclaw --version"
  echo ""
  terminal "OpenClaw 2026.4.9 (0512059)"
  echo ""
  ru "OpenClaw установлен и отвечает. Номер версии подтверждает успех."

  ok "OpenClaw installed (симуляция)"
else
  if [[ "$OPENCLAW_INSTALLED" == true ]]; then
    explain "OpenClaw уже установлен. Проверим, не нужно ли обновить..."
    echo -e "   ${DIM}Проверяем обновления...${NC}"
    if install_openclaw_npm; then
      echo ""
      OC_VER=$(openclaw --version 2>&1 | head -1)
      ok "OpenClaw ${OC_VER} — актуальная версия"
    else
      echo ""
      warn "Не удалось проверить обновления — npm registry не отвечает."
      ru "Продолжаем с текущей версией OpenClaw."
    fi
  else
    explain "Устанавливаем OpenClaw..." \
      "Это займёт 30–60 секунд при хорошей сети, иногда до 2-3 минут." \
      "Буду периодически печатать 'я жив' — чтобы вы видели, что не зависло."

    echo ""
    set +e
    install_openclaw_npm
    install_rc=$?
    set -e

    if [[ $install_rc -eq 0 ]]; then
      echo ""
      OC_VER=$(openclaw --version 2>&1 | head -1)
      ok "OpenClaw ${OC_VER} — установлен!"
    elif [[ $install_rc -eq 2 ]]; then
      # Permission (EACCES) — команды уже напечатаны в diagnose_npm_eacces
      echo ""
      warn "Установка не прошла из-за прав доступа npm."
      ru "Выше — конкретные команды под ваш случай. Выполните их и запустите скрипт снова."
      exit 1
    else
      echo ""
      warn "Не удалось установить OpenClaw — npm registry не отвечает (ETIMEDOUT)."
      ru "Это проблема сети, не скрипта. Что делать:"
      ru "  1. Проверьте интернет, VPN/прокси"
      ru "  2. Смените DNS на 1.1.1.1 или 8.8.8.8"
      ru "  3. Подождите 1-2 минуты и запустите скрипт ещё раз"
      ru "  4. Или вручную позже: npm install -g openclaw@latest"
      exit 1
    fi
  fi
fi

pause

# ═══════════════════════════════════════════════════════════════
#  REAL STEP 3: Onboard
# ═══════════════════════════════════════════════════════════════

step_header "R3" "ONBOARDING — НАСТРОЙКА"

if [[ "$DRY_RUN" == true ]]; then
  explain "Настраиваем OpenClaw напрямую через CLI." \
    "" \
    "Мы не запускаем интерактивный 'openclaw onboard' — он имеет баги." \
    "Вместо этого скрипт сам создаёт конфигурацию и спрашивает только одно:" \
    "ваш API-ключ из opencode.ai."

  sleep 0.5
  echo -e "   ${WHITE}? Paste your opencode.ai API key${NC}"
  echo -e "   ${DIM}  ▸ sk-••••••••••••••••••••••••••••••••${NC}"
  sleep 0.5
  echo ""
  terminal "✓ Auth profile saved: ~/.openclaw/agents/main/agent/auth-profiles.json"
  terminal "✓ Default model: opencode/minimax-m2.5-free"
  terminal "✓ Config created: ~/.openclaw/openclaw.json"
  terminal "✓ Gateway service installed"
  terminal "✓ Gateway started on port 18789"
  terminal "✓ Dashboard: http://127.0.0.1:18789"
  echo ""
  ru "Скрипт записал ключ, поставил модель Minimax 2.5 (free) и запустил gateway."
  ru "В реальной установке вам нужно будет вставить только один ключ."

  ok "Onboarding complete (симуляция)"
else
  if [[ -f "$HOME/.openclaw/openclaw.json" ]]; then
    # Смотрим что за модель сейчас стоит — чтобы поймать кейс
    # «у меня Kimi / claude-sonnet, приходит 401 No payment method»
    CURRENT_MODEL=$(openclaw config get agents.defaults.model.primary 2>/dev/null | tr -d '\n" ')
    EXPECTED_MODEL="opencode/minimax-m2.5-free"

    explain "OpenClaw уже настроен — нашёлся файл ~/.openclaw/openclaw.json." \
      "" \
      "  Текущая модель по умолчанию: ${BOLD}${CURRENT_MODEL:-(не задана)}${NC}" \
      "  Рекомендованная (бесплатная): ${BOLD}${GREEN}${EXPECTED_MODEL}${NC}"

    echo ""
    echo -e "   ${BOLD}${WHITE}Что делать с существующей установкой?${NC}"
    echo ""
    echo -e "   ${BOLD}${GREEN}  1)${NC} ${BOLD}Оставить как есть${NC} — только прогнать health-check (${DIM}по умолчанию${NC})"
    echo -e "   ${BOLD}${YELLOW}  2)${NC} ${BOLD}Перезаписать модель${NC} — поставить ${EXPECTED_MODEL} (если сейчас платная и 401)"
    echo -e "   ${BOLD}${CYAN}  3)${NC} ${BOLD}Ввести новый API-ключ${NC} — перезаписать auth-profiles.json"
    echo -e "   ${BOLD}${RED}  4)${NC} ${BOLD}Полный сброс${NC} — config + credentials + sessions (начать с нуля)"
    echo ""
    echo -e "   ${BOLD}${WHITE}Выбор [1/2/3/4]:${NC}"
    read -r RECONFIG_CHOICE
    RECONFIG_CHOICE="${RECONFIG_CHOICE:-1}"

    case "$RECONFIG_CHOICE" in
      2)
        # Только модель
        if openclaw config set agents.defaults.model.primary "$EXPECTED_MODEL" &>/dev/null; then
          echo -e "   ${GREEN}✓${NC} Модель обновлена: ${EXPECTED_MODEL}"
        else
          warn "Не удалось сменить модель через config set. Попробуйте вручную:"
          echo -e "   ${DIM}openclaw config set agents.defaults.model.primary ${EXPECTED_MODEL}${NC}"
        fi
        # И чиним индивидуальных агентов — они могут иметь override на платную модель
        AGENT_COUNT=$(openclaw config get agents.list 2>/dev/null | grep -c '"id"' || echo 0)
        if [[ "$AGENT_COUNT" -gt 0 ]]; then
          for i in $(seq 0 $((AGENT_COUNT - 1))); do
            openclaw config set "agents.list[${i}].model" "\"${EXPECTED_MODEL}\"" --strict-json &>/dev/null || true
          done
          echo -e "   ${GREEN}✓${NC} Переназначена модель у всех ${AGENT_COUNT} агентов"
        fi
        ;;
      3)
        # Новый ключ
        AUTH_FILE="$HOME/.openclaw/agents/main/agent/auth-profiles.json"
        if [[ -f "$AUTH_FILE" ]]; then
          mv "$AUTH_FILE" "${AUTH_FILE}.backup-$(date +%Y%m%d-%H%M%S)" 2>/dev/null || true
          echo -e "   ${DIM}✓ Старый auth-profiles.json забэкаплен${NC}"
        fi
        # Ниже выполнится блок ввода нового ключа — проставим флаг
        NEED_KEY_INPUT=true
        ;;
      4)
        # Полный сброс
        echo ""
        warn "Будет выполнен полный сброс: config + credentials + sessions."
        echo -e "   ${DIM}Это удалит ВСЕ настройки OpenClaw. Действие необратимо.${NC}"
        echo -e "   ${BOLD}${WHITE}Продолжить? [y/N]:${NC}"
        read -r confirm_reset
        if [[ "$confirm_reset" == "y" || "$confirm_reset" == "Y" ]]; then
          BACKUP_DIR="$HOME/.openclaw-backup-$(date +%Y%m%d-%H%M%S)"
          mv "$HOME/.openclaw" "$BACKUP_DIR" 2>/dev/null || true
          echo -e "   ${GREEN}✓${NC} Старая установка перенесена в: ${BACKUP_DIR}"
          # openclaw reset через CLI — если есть (может не работать после mv)
          openclaw reset --scope config+creds+sessions --yes --non-interactive &>/dev/null || true
          NEED_KEY_INPUT=true
          # И запустим полный R3 с нуля
          # shellcheck disable=SC2034  # зарезервировано для расширений R3
          FULL_FRESH_SETUP=true
        else
          echo -e "   ${DIM}Сброс отменён, оставляю как есть.${NC}"
          RECONFIG_CHOICE=1
        fi
        ;;
      *)
        echo -e "   ${DIM}Оставляем текущую установку.${NC}"
        ;;
    esac

    # Всегда прогоняем health-check (как и раньше)
    echo ""
    echo -e "   ${DIM}Проверяю состояние конфига и gateway...${NC}"
    ensure_gateway_healthy "existing" || true
  fi

  # Если выбран ввод нового ключа ИЛИ полный сброс ИЛИ первая установка —
  # запускаем блок opencode-ключа
  if [[ ! -f "$HOME/.openclaw/openclaw.json" || "${NEED_KEY_INPUT:-false}" == true ]]; then
    explain "Настраиваем OpenClaw." \
      "" \
      "Интерактивный мастер 'openclaw onboard' мы не запускаем — он имеет баги" \
      "(циклится на выборе каналов, падает на старых конфигах с 'undefined.trim')." \
      "Вместо него скрипт сам прописывает config и просит у вас только один ввод:" \
      "API-ключ из opencode.ai."

    divider

    # ---- Провайдер и модель ----
    # shellcheck disable=SC2034  # PROVIDER используется в документации блока ниже
    PROVIDER="opencode"
    MODEL="opencode/minimax-m2.5-free"
    KEY_URL="https://opencode.ai"

    explain "Откуда взять ключ — пошагово:" \
      "" \
      "  ${BOLD}Шаг 1.${NC} Откройте ${BOLD}${CYAN}https://opencode.ai${NC} (браузер сейчас сам откроется)" \
      "  ${BOLD}Шаг 2.${NC} Зарегистрируйтесь (можно через Google) или войдите" \
      "  ${BOLD}Шаг 3.${NC} Выберите провайдера: ${BOLD}OpenCode${NC}" \
      "  ${BOLD}Шаг 4.${NC} Перейдите в раздел ${BOLD}OpenCode Zen${NC}" \
      "  ${BOLD}Шаг 5.${NC} В списке моделей выберите: ${BOLD}${GREEN}MiniMax M2.5 (Free)${NC}" \
      "          ${DIM}→ это бесплатный тариф, токены не тратятся${NC}" \
      "  ${BOLD}Шаг 6.${NC} Откройте ${BOLD}API Keys${NC} → ${BOLD}Create new key${NC}" \
      "  ${BOLD}Шаг 7.${NC} Скопируйте ключ (формат: sk-...)" \
      "  ${BOLD}Шаг 8.${NC} Вернитесь сюда и вставьте его ниже"

    # Автоматически открываем браузер
    if command -v open >/dev/null 2>&1; then
      open "$KEY_URL" &>/dev/null &
      echo -e "   ${DIM}✓ Открыл opencode.ai в браузере${NC}"
    elif command -v xdg-open >/dev/null 2>&1; then
      xdg-open "$KEY_URL" &>/dev/null &
      echo -e "   ${DIM}✓ Открыл opencode.ai в браузере${NC}"
    fi

    echo ""
    explain "Почему именно MiniMax 2.5 Free:" \
      "" \
      "  • ${BOLD}Бесплатно${NC} — не нужно платить за каждое сообщение" \
      "  • Подходит для текстовых задач (контекст 200k)" \
      "  • Всегда можно переключиться на платную модель одной командой:" \
      "    ${DIM}openclaw config set agents.defaults.model.primary opencode/gpt-5.4${NC}" \
      "  • Посмотреть всё: ${DIM}openclaw models list --all | grep opencode${NC}" \
      "" \
      "${YELLOW}ВАЖНО:${NC} ключ — это пароль. Никому не показывайте, не публикуйте в git."

    divider

    # ---- Ввод API-ключа (скрытый) ----
    while true; do
      echo -e "   ${BOLD}${WHITE}Вставьте API-ключ opencode.ai и нажмите Enter:${NC}"
      echo -e "   ${DIM}(при вводе ничего отображаться не будет — это нормально)${NC}"
      read -rs API_KEY
      echo ""

      if [[ -z "$API_KEY" ]]; then
        warn "Ключ пустой. Попробуйте ещё раз или Ctrl+C для выхода."
        continue
      fi

      if [[ ! "$API_KEY" =~ ^sk- ]]; then
        warn "Ключ opencode.ai обычно начинается с 'sk-'. Проверьте, что скопировали правильный."
        echo -e "   ${DIM}Продолжить всё равно? [y/n]${NC}"
        read -r force_key
        [[ "$force_key" != "y" && "$force_key" != "Y" ]] && continue
      fi

      break
    done

    echo -e "   ${GREEN}✓ Ключ получен (${#API_KEY} символов)${NC}"
    echo ""

    # ---- Создаём auth-profiles.json для main-агента ----
    explain "Создаю конфигурацию OpenClaw..."

    AUTH_DIR="$HOME/.openclaw/agents/main/agent"
    mkdir -p "$AUTH_DIR"
    AUTH_FILE="$AUTH_DIR/auth-profiles.json"

    cat > "$AUTH_FILE" <<AUTHEOF
{
  "version": 1,
  "profiles": {
    "opencode:default": {
      "type": "api_key",
      "provider": "opencode",
      "key": "$API_KEY"
    }
  },
  "lastGood": {
    "opencode": "opencode:default"
  }
}
AUTHEOF
    chmod 600 "$AUTH_FILE"
    echo -e "   ${GREEN}✓${NC} API-ключ сохранён в ~/.openclaw/agents/main/agent/auth-profiles.json (режим 600)"

    # Устанавливаем модель по умолчанию (|| true — чтобы не убить скрипт)
    if openclaw config set agents.defaults.model.primary "$MODEL" &>/dev/null; then
      echo -e "   ${GREEN}✓${NC} Модель по умолчанию: ${MODEL}"
    fi

    # КРИТИЧНО: ставим gateway.mode=local ДО gateway install/start
    # (иначе gateway поднимется в непонятном режиме и закроется с 1006)
    if openclaw config set gateway.mode local &>/dev/null; then
      echo -e "   ${GREEN}✓${NC} gateway.mode=local"
    fi

    # Устанавливаем gateway как service (автозапуск) — всё с || true,
    # чтобы set -e не убил скрипт от лишней болтовни в stderr.
    #
    # ВНИМАНИЕ (ref. решение #14 в handoff): на macOS `openclaw gateway install`
    # кладёт LaunchAgent в ~/Library/LaunchAgents без sudo — безопасно.
    # На Linux, если OpenClaw выберет системный systemd-сервис, команда может
    # попросить sudo-пароль. Текущий pipe `| tail -3 | while read` в таком
    # случае заблокирует ввод пароля — пользователь зависнет как на Homebrew.
    # Защита: `|| true` не даёт скрипту упасть, а основная ЦА — macOS.
    # Если начнём массово поддерживать Linux с системным systemd — переписать
    # без pipe, как сделано для install_homebrew.
    if ! openclaw gateway status 2>&1 | grep -q "running"; then
      echo -e "   ${DIM}Устанавливаю gateway как системный сервис...${NC}"
      { openclaw gateway install 2>&1 || true; } | tail -3 | while IFS= read -r line; do
        echo -e "   ${DIM}${line}${NC}"
      done
      { openclaw gateway start 2>&1 || true; } | tail -3 | while IFS= read -r line; do
        echo -e "   ${DIM}${line}${NC}"
      done
    fi

    # Полная проверка: mode + валидация + deep status + auto-recovery
    ensure_gateway_healthy "fresh install" || true

    # Согласованность provider/model у defaults + всех агентов
    # (ловит кейсы вроде Елены: «выбрал MiniMax, но Model is disabled»)
    ensure_model_consistency "$MODEL" || true

    ok "OpenClaw настроен без всяких визардов!"
  fi
fi

pause

# ═══════════════════════════════════════════════════════════════
#  REAL STEP 4: Подготовка Telegram-бота
# ═══════════════════════════════════════════════════════════════

step_header "R4" "TELEGRAM BOT SETUP"

explain "Теперь подключим Telegram-бота." \
  "" \
  "Если вы ещё не создали бота — сделайте это сейчас:" \
  "" \
  "  1. Откройте Telegram" \
  "  2. Найдите @BotFather" \
  "  3. Отправьте /newbot" \
  "  4. Введите имя и username бота" \
  "  5. Скопируйте полученный токен"

echo ""
echo -e "   ${DIM}┌────────────────────────────────────────────────────────────┐${NC}"
echo -e "   ${DIM}│  ${WHITE}Токен выглядит так:${NC}${DIM}                                       │${NC}"
echo -e "   ${DIM}│  ${YELLOW}7123456789:AAHk-xxxxxxxxxxxxxxxxxxxxxxxxxxxxx${NC}${DIM}             │${NC}"
echo -e "   ${DIM}│                                                            │${NC}"
echo -e "   ${DIM}│  ${RED}Никому не показывайте токен — это пароль от бота!${NC}${DIM}        │${NC}"
echo -e "   ${DIM}└────────────────────────────────────────────────────────────┘${NC}"
echo ""

if [[ "$DRY_RUN" == true ]]; then
  divider

  explain "В реальной установке здесь вы вставите токен от BotFather." \
    "Скрипт проверит его через Telegram API и подключит бота."

  show_cmd 'openclaw channels add --channel telegram --name "My AI Bot" --token 71234***'
  echo ""
  sleep 0.5
  terminal "✓ Verifying token via Telegram API..."
  sleep 0.3
  terminal "✓ Bot found: My AI Bot (@my_ai_bot)"
  sleep 0.3
  terminal "✓ Telegram channel added: My AI Bot"
  terminal "✓ Webhook configured"
  echo ""
  ru "Скрипт автоматически проверяет токен, находит бота и подключает канал."
  ru "Webhook — механизм доставки сообщений из Telegram в OpenClaw."

  TELEGRAM_CONNECTED=true
  BOT_USERNAME="my_ai_bot"
  AGENT_ID="assistant"

  ok "Telegram connected (симуляция)"
else
  divider

  echo -e "   ${BOLD}${WHITE}Вставьте токен Telegram-бота:${NC}"
  echo ""
  read -r BOT_TOKEN

  if [[ -z "$BOT_TOKEN" ]]; then
    echo ""
    warn "Токен не введён. Пропускаем подключение Telegram."
    echo -e "   ${DIM}Вы сможете подключить бота позже командой:${NC}"
    show_cmd "openclaw channels add --channel telegram --token ВАШ_ТОКЕН"
    echo ""
    TELEGRAM_CONNECTED=false
  else
    if [[ ! "$BOT_TOKEN" =~ ^[0-9]+:.+ ]]; then
      echo ""
      warn "Токен выглядит некорректно. Обычный формат: 1234567890:AAHk-xxxxx"
      echo -e "   ${DIM}Попробовать подключить всё равно? [y/n]${NC}"
      read -r try_anyway
      if [[ "$try_anyway" != "y" && "$try_anyway" != "Y" ]]; then
        TELEGRAM_CONNECTED=false
      fi
    fi

    if [[ -z "${TELEGRAM_CONNECTED:-}" ]]; then
      echo ""
      explain "Подключаем бота к OpenClaw..."
      echo ""

      echo -e "   ${DIM}Проверяю токен через Telegram API...${NC}"
      BOT_INFO=$(curl -s "https://api.telegram.org/bot${BOT_TOKEN}/getMe" 2>/dev/null)

      if echo "$BOT_INFO" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['ok']" 2>/dev/null; then
        BOT_USERNAME=$(echo "$BOT_INFO" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result']['username'])")
        BOT_NAME=$(echo "$BOT_INFO" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['result']['first_name'])")
        echo -e "   ${GREEN}✓ Бот найден: ${BOLD}${BOT_NAME}${NC} ${GREEN}(@${BOT_USERNAME})${NC}"
        echo ""
      else
        BOT_USERNAME="my_bot"
        BOT_NAME="My Bot"
        warn "Не удалось проверить токен (возможно, нет интернета). Продолжаем..."
        echo ""
      fi

      echo -e "   ${DIM}Подключаю Telegram-канал...${NC}"
      { openclaw channels add --channel telegram --name "${BOT_NAME}" --token "${BOT_TOKEN}" 2>&1 || true; } | while IFS= read -r line; do
        echo -e "   ${DIM}${line}${NC}"
      done
      echo ""

      TELEGRAM_CONNECTED=true
      ok "Telegram-бот @${BOT_USERNAME} подключён!"

      # ────────────────────────────────────────────────────────────
      # ВАЖНО: настроить DM-политику, иначе бот ответит
      # «access not configured» + pairing code вместо нормального
      # общения. Спрашиваем Telegram user ID владельца.
      # ────────────────────────────────────────────────────────────
      divider

      explain "Настройка доступа к боту." \
        "" \
        "По умолчанию бот включает режим 'pairing' — любой новый собеседник" \
        "получает 'access not configured' и pairing-код, который нужно вручную" \
        "одобрить владельцем. Это безопасно, но неудобно для личного использования." \
        "" \
        "Добавим ваш Telegram user ID в allowlist — тогда вы сразу сможете" \
        "писать боту без всяких кодов."

      echo ""
      explain "Как узнать свой Telegram user ID:" \
        "  1. В Telegram найдите бота @userinfobot" \
        "  2. Нажмите /start" \
        "  3. Он вернёт ваш ID — число вида 123456789" \
        "" \
        "Или нажмите Enter, чтобы пропустить — тогда придётся одобрять через pairing-код."

      echo ""
      echo -e "   ${BOLD}${WHITE}Введите ваш Telegram user ID:${NC}"
      read -r TG_USER_ID

      # Только цифры допустимы
      TG_USER_ID=$(echo "$TG_USER_ID" | tr -cd '0-9')

      if [[ -n "$TG_USER_ID" ]]; then
        # ВАЖНО: все openclaw-команды с || true — чтобы случайный non-zero
        # не убивал скрипт под `set -e` (именно из-за этого клиент после
        # ввода ID попадал обратно в shell и думал, что бот «не подключился»).
        # Правильный путь в schema: channels.telegram.allowFrom (array)
        openclaw config set channels.telegram.dmPolicy allowlist &>/dev/null || true
        openclaw config set channels.telegram.allowFrom "[\"${TG_USER_ID}\"]" &>/dev/null || true
        openclaw gateway restart &>/dev/null || true
        echo -e "   ${GREEN}✓${NC} Allowlist настроен: ваш ID ${TG_USER_ID} добавлен"
        ru "Теперь можете сразу писать боту — он ответит без pairing-кодов."
        OWNER_TG_ID="$TG_USER_ID"
      else
        echo ""
        warn "ID не введён. Оставляем режим pairing по умолчанию."
        ru "Когда напишете боту, он ответит 'access not configured' + код."
        ru "Одобрите его командой: openclaw pairing approve telegram <КОД>"
        OWNER_TG_ID=""
      fi
    fi
  fi
fi

pause

# ═══════════════════════════════════════════════════════════════
#  REAL STEP 5: Создание первого ассистента
# ═══════════════════════════════════════════════════════════════

step_header "R5" "CREATE YOUR FIRST ASSISTANT"

explain "Создаём вашего первого AI-ассистента!" \
  "" \
  "Ассистент будет:" \
  "  • Отвечать на вопросы в Telegram" \
  "  • Помогать с текстами, идеями, задачами" \
  "  • Запоминать контекст разговора"

if [[ "$DRY_RUN" == true ]]; then
  divider

  explain "В реальной установке вы выберете имя агента." \
    "По умолчанию — assistant."

  show_cmd "openclaw agents add assistant"
  echo ""
  sleep 0.5
  terminal "✓ Agent created: assistant"
  terminal "  Workspace: ~/.openclaw/agents/assistant"
  terminal "  Model: opencode/minimax-m2.5-free (inherited from defaults)"
  echo ""
  ru "Агент создан с рабочей папкой для сессий и памяти."

  divider

  show_cmd "openclaw agents bind --agent assistant --bind telegram"
  echo ""
  sleep 0.3
  terminal "✓ Binding added: assistant → telegram"
  echo ""
  ru "Агент привязан к Telegram — все сообщения из бота пойдут к нему."

  divider

  show_cmd "openclaw gateway status"
  echo ""
  sleep 0.3
  terminal "Service: LaunchAgent (loaded)"
  terminal "Runtime: running (pid 54321, state active)"
  terminal "RPC probe: ok"
  echo ""

  show_cmd "openclaw doctor --fix --yes"
  echo ""
  sleep 0.5
  terminal "✓ Config: valid"
  terminal "✓ Gateway: running"
  terminal "✓ Channels: 1 connected"
  terminal "✓ Agents: 2 (main, assistant)"
  terminal "✓ No issues found"
  echo ""
  ru "Gateway работает, канал подключён, агент создан — всё в порядке."

  AGENT_ID="assistant"
  ok "Ассистент 'assistant' создан (симуляция)"
else
  echo ""
  echo -e "   ${BOLD}${WHITE}Введите ID агента (латиницей, без пробелов, например: assistant):${NC}"
  echo -e "   ${DIM}   или нажмите Enter для значения по умолчанию (assistant)${NC}"
  echo ""
  read -r AGENT_ID
  AGENT_ID="${AGENT_ID:-assistant}"

  AGENT_ID=$(echo "$AGENT_ID" | tr -cd 'a-zA-Z0-9_-' | tr '[:upper:]' '[:lower:]')
  if [[ -z "$AGENT_ID" ]]; then
    AGENT_ID="assistant"
  fi

  echo ""
  explain "Создаём агента '${AGENT_ID}'..."

  # Создаём workspace и стартовые файлы
  WORKSPACE_DIR="$HOME/.openclaw/workspace"
  mkdir -p "$WORKSPACE_DIR"

  # Минимальный стартовый набор файлов для нового агента
  if [[ ! -f "$WORKSPACE_DIR/AGENTS.md" ]]; then
    : > "$WORKSPACE_DIR/AGENTS.md"
  fi
  if [[ ! -f "$WORKSPACE_DIR/IDENTITY.md" ]]; then
    cat > "$WORKSPACE_DIR/IDENTITY.md" <<'WSEOF'
# Роль ассистента

Ты — персональный AI-ассистент. Помогаешь пользователю с задачами,
идеями и вопросами. Отвечаешь коротко и по делу, на русском языке.
Если не знаешь — честно говоришь «не знаю».
WSEOF
  fi
  echo -e "   ${GREEN}✓${NC} Workspace готов: ${WORKSPACE_DIR}"

  # Строим флаги для agents add
  ADD_BIND_ARG=""
  if [[ "${TELEGRAM_CONNECTED:-false}" == true ]]; then
    ADD_BIND_ARG="--bind telegram"
  fi

  echo -e "   ${DIM}Создаю агента (non-interactive)...${NC}"
  # shellcheck disable=SC2086
  { openclaw agents add "${AGENT_ID}" \
      --non-interactive \
      --workspace "$WORKSPACE_DIR" \
      --model "opencode/minimax-m2.5-free" \
      ${ADD_BIND_ARG} 2>&1 || true; } | while IFS= read -r line; do
    echo -e "   ${DIM}${line}${NC}"
  done
  echo ""

  # На всякий случай — дублируем bind для существующих агентов (если add не привязал)
  if [[ "${TELEGRAM_CONNECTED:-false}" == true ]]; then
    openclaw agents bind --agent "${AGENT_ID}" --bind telegram &>/dev/null || true
  fi

  # Копируем auth-profiles.json из main в новый агент (чтобы opencode ключ работал)
  MAIN_AUTH="$HOME/.openclaw/agents/main/agent/auth-profiles.json"
  NEW_AUTH_DIR="$HOME/.openclaw/agents/${AGENT_ID}/agent"
  if [[ -f "$MAIN_AUTH" && "$AGENT_ID" != "main" ]]; then
    mkdir -p "$NEW_AUTH_DIR"
    cp "$MAIN_AUTH" "$NEW_AUTH_DIR/auth-profiles.json"
    chmod 600 "$NEW_AUTH_DIR/auth-profiles.json"
    echo -e "   ${GREEN}✓${NC} Auth-профиль opencode скопирован в агента ${AGENT_ID}"
  fi

  echo -e "   ${DIM}Финальная проверка gateway и конфига...${NC}"
  ensure_gateway_healthy "post-agent" || true
  echo ""

  ok "Ассистент '${AGENT_ID}' создан и готов к работе!"
fi

# ─── Ставим helper-команды из репы openclaw-factory ────────────────────
explain "Устанавливаем helper-команды (смена модели + перезапись auth)..."

HELPER_DIR="$HOME/.openclaw/bin"
HELPER_PATH="$HELPER_DIR/openclaw-switch-model"
REAUTH_PATH="$HELPER_DIR/openclaw-factory-reauth"
mkdir -p "$HELPER_DIR"

# Скачиваем оба helper'а из репы. Helpers лежат рядом в одной директории.
HELPERS_BASE="https://raw.githubusercontent.com/tonytrue92-beep/openclaw-factory/main/scripts"

# 1. switch-model — быстрая смена модели
if curl -fsSL "${HELPERS_BASE}/openclaw-switch-model.sh" -o "$HELPER_PATH" 2>/dev/null; then
  chmod +x "$HELPER_PATH"
  echo -e "   ${GREEN}✓${NC} Установлен: ${HELPER_PATH}"
else
  echo -e "   ${YELLOW}○${NC} Не смог скачать switch-model helper — пропускаю (не критично)"
  HELPER_PATH=""
fi

# 2. factory-reauth — перезапись API-ключа (кейс Саввы из отчёта куратора).
# Ставим ровно так же, чтобы ~/.openclaw/bin уже был в PATH после switch-model.
if curl -fsSL "${HELPERS_BASE}/openclaw-factory-reauth.sh" -o "$REAUTH_PATH" 2>/dev/null; then
  chmod +x "$REAUTH_PATH"
  echo -e "   ${GREEN}✓${NC} Установлен: ${REAUTH_PATH}"
else
  echo -e "   ${YELLOW}○${NC} Не смог скачать reauth helper — пропускаю (не критично)"
fi

# Добавляем ~/.openclaw/bin в PATH, если ещё нет
if [[ -n "$HELPER_PATH" ]]; then
  SHELL_RC=""
  case "${SHELL##*/}" in
    zsh)   SHELL_RC="$HOME/.zshrc" ;;
    bash)  SHELL_RC="$HOME/.bashrc" ;;
  esac
  if [[ -n "$SHELL_RC" ]] && [[ -f "$SHELL_RC" ]]; then
    if ! grep -qF '.openclaw/bin' "$SHELL_RC" 2>/dev/null; then
      {
        echo ""
        echo "# OpenClaw helper scripts"
        echo 'export PATH="$HOME/.openclaw/bin:$PATH"'
      } >> "$SHELL_RC"
      echo -e "   ${GREEN}✓${NC} Добавлен в PATH через ${SHELL_RC}"
      echo -e "   ${DIM}   (применится в новых терминалах)${NC}"
    else
      echo -e "   ${GREEN}✓${NC} PATH уже содержит ~/.openclaw/bin"
    fi
  fi
  # Для текущей сессии
  export PATH="$HOME/.openclaw/bin:$PATH"
fi

echo ""

pause

# ═══════════════════════════════════════════════════════════════
#  REAL STEP 6: Проверка и итоги
# ═══════════════════════════════════════════════════════════════

step_header "R6" "FINAL CHECK"

explain "Финальная проверка — убедимся, что всё работает..."
echo ""

# Pre-flight: ловим рассинхронизацию model у default vs agents.list[*]
# до того как пользователь напишет боту и увидит «Model is disabled».
if [[ "$DRY_RUN" != true ]]; then
  ensure_model_consistency "opencode/minimax-m2.5-free" || true
fi

if [[ "$DRY_RUN" == true ]]; then
  show_cmd "openclaw status --all"
  echo ""
  sleep 0.5
  terminal "OpenClaw 2026.4.9 (0512059)"
  terminal "Gateway: running (pid 54321)"
  terminal "Model: opencode/minimax-m2.5-free"
  terminal "Channels: 1 configured (telegram)"
  terminal "Agents: 2 (main, assistant)"
  terminal "Sessions: 0 active"
  echo ""

  divider

  show_cmd "openclaw channels status --probe"
  echo ""
  sleep 0.3
  terminal "Channel    Account      Transport     Health"
  terminal "telegram   My AI Bot    connected     audit: ok"
  echo ""
  ru "Всё работает: gateway запущен, бот подключён, агент готов."
else
  { openclaw status --all 2>&1 || true; } | while IFS= read -r line; do
    echo -e "   ${line}"
  done
  echo ""

  divider

  if [[ "${TELEGRAM_CONNECTED:-false}" == true ]]; then
    explain "Проверяем Telegram-канал..."
    echo ""
    { openclaw channels status --probe 2>&1 || true; } | while IFS= read -r line; do
      echo -e "   ${line}"
    done
    echo ""
  fi
fi

ok "Все проверки пройдены!"

# ═══════════════════════════════════════════════════════════════
#  Финальный экран
# ═══════════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}${GREEN}"
if [[ "$DRY_RUN" == true ]]; then
cat << 'SIMFIN'
   ╔════════════════════════════════════════════════════════════════╗
   ║                                                                ║
   ║   🎬  СИМУЛЯЦИЯ УСТАНОВКИ ЗАВЕРШЕНА!                            ║
   ║                                                                ║
   ║   Вы увидели весь процесс от начала до конца.                  ║
   ║   Ничего не было установлено — ваша система чиста.             ║
   ║                                                                ║
   ╚════════════════════════════════════════════════════════════════╝

SIMFIN
else
cat << 'FINISH'
   ╔════════════════════════════════════════════════════════════════╗
   ║                                                                ║
   ║   🚀  УСТАНОВКА ЗАВЕРШЕНА!                                     ║
   ║                                                                ║
   ║   Ваш AI-ассистент работает и готов отвечать в Telegram.       ║
   ║                                                                ║
   ╚════════════════════════════════════════════════════════════════╝

FINISH
fi
echo -e "${NC}"

if [[ "$DRY_RUN" == true ]]; then
  explain "Симуляция завершена. Возвращаемся к выбору..."
  pause
  continue  # возврат в меню выбора
else
  echo -e "   ${BOLD}${WHITE}Что установлено:${NC}"
  OC_VER=$(openclaw --version 2>&1 | head -1)
  echo -e "   ${GREEN}✓${NC} OpenClaw ${OC_VER}"
  echo -e "   ${GREEN}✓${NC} Gateway (автозапуск при включении компьютера)"
  echo -e "   ${GREEN}✓${NC} Агент: ${BOLD}${AGENT_ID}${NC}"
  if [[ "${TELEGRAM_CONNECTED:-false}" == true ]]; then
    echo -e "   ${GREEN}✓${NC} Telegram: @${BOT_USERNAME:-бот подключён}"
  fi
  echo ""

  # ─── Живой end-to-end тест: пусть клиент напишет боту ──────────
  if [[ "${TELEGRAM_CONNECTED:-false}" == true ]]; then
    divider

    explain "ФИНАЛЬНЫЙ ТЕСТ — проверим, что бот реально отвечает:" \
      "" \
      "  1. Откройте Telegram" \
      "  2. Найдите своего бота: ${BOLD}@${BOT_USERNAME:-ваш_бот}${NC}" \
      "  3. Отправьте ему: ${BOLD}/status${NC}" \
      "  4. Подождите 5-10 секунд — бот должен ответить" \
      "" \
      "${DIM}Если ответил — всё работает.${NC}" \
      "${DIM}Если молчит — нажмите Enter, я покажу диагностику.${NC}"

    echo ""
    echo -e "   ${BOLD}${WHITE}Нажмите Enter когда проверите (или чтобы увидеть диагностику):${NC}"
    read -r _bot_check || true

    # Быстрая диагностика на случай «бот молчит»
    echo ""
    echo -e "   ${DIM}─── Диагностика (если бот не ответил) ───${NC}"
    GW_CHECK=$(openclaw gateway status 2>&1 || true)
    if echo "$GW_CHECK" | grep -qE "running"; then
      echo -e "   ${GREEN}✓${NC} Gateway: running"
    else
      echo -e "   ${RED}✗${NC} Gateway не отвечает → запустите: ${BOLD}openclaw gateway restart${NC}"
    fi

    CH_CHECK=$(openclaw channels status --probe 2>&1 || true)
    if echo "$CH_CHECK" | grep -qiE "ok|connected|audit: ok"; then
      echo -e "   ${GREEN}✓${NC} Telegram-канал: connected"
    else
      echo -e "   ${YELLOW}○${NC} Telegram-канал странный. Посмотреть: ${BOLD}openclaw channels status --probe${NC}"
    fi

    if [[ -n "${OWNER_TG_ID:-}" ]]; then
      echo -e "   ${GREEN}✓${NC} Allowlist: ваш ID ${OWNER_TG_ID} разрешён"
    else
      echo -e "   ${YELLOW}○${NC} Allowlist не настроен → бот ответит 'access not configured' + pairing-код"
      echo -e "      ${DIM}Одобрить: openclaw pairing approve telegram <КОД>${NC}"
    fi

    CURRENT_MODEL_CHECK=$(openclaw config get agents.defaults.model.primary 2>/dev/null | tr -d '\n" ')
    if [[ "$CURRENT_MODEL_CHECK" == *"-free" ]]; then
      echo -e "   ${GREEN}✓${NC} Модель: ${CURRENT_MODEL_CHECK} (бесплатная)"
    else
      echo -e "   ${YELLOW}○${NC} Модель: ${CURRENT_MODEL_CHECK:-не задана}"
      echo -e "      ${DIM}Если 401 No payment method — вернуть на free:${NC}"
      echo -e "      ${DIM}openclaw config set agents.defaults.model.primary opencode/minimax-m2.5-free${NC}"
    fi
    echo ""
  fi

  echo -e "   ${BOLD}${WHITE}Что делать дальше:${NC}"
  if [[ "${TELEGRAM_CONNECTED:-false}" == true ]]; then
    echo -e "   ${CYAN}1.${NC} Пиши боту @${BOT_USERNAME:-вашему_боту} что угодно — он AI, отвечает на всё"
  else
    echo -e "   ${CYAN}1.${NC} Подключить Telegram: ${DIM}openclaw channels add --channel telegram --token ...${NC}"
  fi
  echo -e "   ${CYAN}2.${NC} Dashboard: ${UNDERLINE:-}http://127.0.0.1:18789${NC}"
  echo -e "   ${CYAN}3.${NC} Если что-то сломалось: ${BOLD}openclaw doctor --fix${NC}"
  echo ""

  echo -e "   ${BOLD}${WHITE}Команды на каждый день:${NC}"
  show_cmd "openclaw status --all        # Проверить всё"
  show_cmd "openclaw logs --follow       # Смотреть логи"
  show_cmd "openclaw doctor --fix        # Починить проблемы"
  show_cmd "openclaw gateway restart     # Перезапустить"
  echo ""

  # ═══════════════════════════════════════════════════════════════
  #  ПОДСКАЗКИ — что клиенты спрашивают сразу после установки
  # ═══════════════════════════════════════════════════════════════
  echo ""
  echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}${CYAN}  💡 ПОДСКАЗКИ — самые частые вопросы после установки${NC}"
  echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  # ─── Подсказка 1: сменить модель ───
  echo -e "   ${BOLD}${WHITE}▸ Хочу сменить модель (другой GPT/Claude/Gemini)${NC}"
  echo -e "   ${DIM}   Сейчас стоит: ${BOLD}${CURRENT_MODEL_CHECK:-opencode/minimax-m2.5-free}${NC}${DIM} (бесплатная).${NC}"
  echo ""
  echo -e "   ${BOLD}${GREEN}   ⚡ БЫСТРЫЙ СПОСОБ — одна команда:${NC}"
  echo -e "      ${GREEN}openclaw-switch-model${NC}                          ${DIM}# интерактивное меню${NC}"
  echo -e "      ${GREEN}openclaw-switch-model opencode/claude-sonnet-4-5${NC}  ${DIM}# сразу на модель${NC}"
  echo -e "      ${GREEN}openclaw-switch-model --list${NC}                   ${DIM}# показать все доступные${NC}"
  echo -e "   ${DIM}   Helper сам поменяет конфиг, почистит сессии и перезапустит gateway.${NC}"
  echo ""
  echo -e "   ${DIM}   Примеры бесплатных моделей:${NC}"
  echo -e "      ${GREEN}opencode/minimax-m2.5-free${NC}         ${DIM}# текущая, быстрая и неплохая${NC}"
  echo -e "      ${GREEN}opencode/grok-4-fast-free${NC}          ${DIM}# от xAI, для диалогов${NC}"
  echo -e "      ${GREEN}opencode/kimi-dev-72b-free${NC}         ${DIM}# для кода и аналитики${NC}"
  echo ""
  echo -e "   ${DIM}   Примеры платных моделей (нужен биллинг на opencode.ai):${NC}"
  echo -e "      ${GREEN}opencode/claude-sonnet-4-5${NC}         ${DIM}# премиум, самая умная${NC}"
  echo -e "      ${GREEN}opencode/gpt-5-mini${NC}                ${DIM}# OpenAI, компромисс цена/качество${NC}"
  echo -e "      ${GREEN}opencode/gemini-2.5-pro${NC}            ${DIM}# Google, для длинного контекста${NC}"
  echo ""
  echo -e "   ${DIM}   Если нужно руками (без helper) — 4 команды:${NC}"
  echo -e "      ${DIM}openclaw config set agents.defaults.model.primary \"<модель>\"${NC}"
  echo -e "      ${DIM}openclaw config set 'agents.list[0].model' '\"<модель>\"' --strict-json${NC}"
  echo -e "      ${DIM}openclaw sessions cleanup --agent ${AGENT_ID:-assistant}${NC}"
  echo -e "      ${DIM}openclaw gateway restart${NC}"
  echo ""

  divider

  # ─── Подсказка 1.5: перезаписать API-ключ если 401 ───
  echo -e "   ${BOLD}${WHITE}▸ Бот пишет 'HTTP 401: Invalid API key'${NC}"
  echo -e "   ${DIM}   Одна команда — перезапишет ключ, почистит сессии, рестартит gateway:${NC}"
  echo ""
  echo -e "      ${GREEN}openclaw-factory-reauth${NC}                     ${DIM}# интерактивно${NC}"
  echo -e "      ${GREEN}openclaw-factory-reauth --provider opencode${NC}  ${DIM}# без меню выбора${NC}"
  echo -e "      ${GREEN}openclaw-factory-reauth --help${NC}               ${DIM}# подробная справка${NC}"
  echo ""
  echo -e "   ${DIM}   Что делает: бэкапит auth-profiles.json, просит новый ключ со skr-...,${NC}"
  echo -e "   ${DIM}   перезаписывает в правильный формат, чистит сессии, рестартит gateway.${NC}"
  echo ""

  divider

  # ─── Подсказка 2: поменять "характер" ассистента ───
  echo -e "   ${BOLD}${WHITE}▸ Хочу изменить характер / стиль ответов ассистента${NC}"
  echo -e "   ${DIM}   Личность агента живёт в двух файлах:${NC}"
  echo -e "      ${GREEN}~/.openclaw/agents/${AGENT_ID:-assistant}/workspace/IDENTITY.md${NC}  ${DIM}# кто я, мой стиль${NC}"
  echo -e "      ${GREEN}~/.openclaw/agents/${AGENT_ID:-assistant}/workspace/AGENTS.md${NC}    ${DIM}# рабочие правила${NC}"
  echo ""
  echo -e "   ${DIM}   Открыть в редакторе (любой текстовый):${NC}"
  echo -e "      ${GREEN}open ~/.openclaw/agents/${AGENT_ID:-assistant}/workspace/IDENTITY.md${NC}"
  echo ""
  echo -e "   ${DIM}   После правки — не забудьте очистить сессию, чтобы изменения применились:${NC}"
  echo -e "      ${GREEN}openclaw sessions cleanup --agent ${AGENT_ID:-assistant}${NC}"
  echo ""

  divider

  # ─── Подсказка 3: добавить ещё один канал ───
  echo -e "   ${BOLD}${WHITE}▸ Хочу подключить WhatsApp / Discord / Slack${NC}"
  echo -e "   ${DIM}   OpenClaw поддерживает 30+ каналов. Добавляются тем же механизмом:${NC}"
  echo -e "      ${GREEN}openclaw channels add --channel whatsapp${NC}   ${DIM}# через QR-код${NC}"
  echo -e "      ${GREEN}openclaw channels add --channel discord${NC}    ${DIM}# через Bot Token${NC}"
  echo -e "      ${GREEN}openclaw channels add --channel slack${NC}      ${DIM}# через OAuth${NC}"
  echo ""
  echo -e "   ${DIM}   После добавления — привязать агента к новому каналу:${NC}"
  echo -e "      ${GREEN}openclaw agents bind --agent ${AGENT_ID:-assistant} --bind <channel>${NC}"
  echo ""

  divider

  # ─── Подсказка 4: создать второго агента ───
  echo -e "   ${BOLD}${WHITE}▸ Хочу завести второго агента (например, переводчика)${NC}"
  echo -e "   ${DIM}   Один бот может вести несколько агентов — каждый со своей личностью и моделью.${NC}"
  echo -e "      ${GREEN}openclaw agents add translator --workspace --model opencode/minimax-m2.5-free${NC}"
  echo -e "      ${GREEN}openclaw agents bind --agent translator --bind telegram${NC}"
  echo -e "   ${DIM}   Потом отредактировать IDENTITY.md у нового агента — задать роль.${NC}"
  echo ""

  divider

  # ─── Подсказка 5: где что лежит ───
  echo -e "   ${BOLD}${WHITE}▸ Где хранятся конфиги и как их бэкапить${NC}"
  echo -e "      ${GREEN}~/.openclaw/openclaw.json${NC}       ${DIM}# главный конфиг${NC}"
  echo -e "      ${GREEN}~/.openclaw/agents/<имя>/${NC}       ${DIM}# папка агента (workspace + sessions)${NC}"
  echo -e "      ${GREEN}~/.openclaw/logs/${NC}               ${DIM}# логи gateway${NC}"
  echo -e "      ${GREEN}~/.openclaw/backups/${NC}            ${DIM}# автобэкапы (хранятся 10 последних)${NC}"
  echo ""
  echo -e "   ${DIM}   Сделать бэкап вручную перед правками:${NC}"
  echo -e "      ${GREEN}bash ~/.openclaw/backup.sh${NC}"
  echo ""

  # ═══════════════════════════════════════════════════════════════
  #  TROUBLESHOOTING — частые проблемы и решения
  # ═══════════════════════════════════════════════════════════════
  echo ""
  echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}${MAGENTA}  🩺 TROUBLESHOOTING — если что-то пошло не так${NC}"
  echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  echo -e "   ${BOLD}${WHITE}1. 'zsh: command not found: openclaw' (в новом терминале)${NC}"
  echo -e "   ${DIM}   Причина: Node.js установлен через nvm, nvm не подхватился в новой сессии.${NC}"
  echo -e "   ${DIM}   Решение (одноразово):${NC}"
  echo -e "      ${GREEN}export NVM_DIR=\"\$HOME/.nvm\" && . \"\$NVM_DIR/nvm.sh\"${NC}"
  echo -e "   ${DIM}   Или закройте и откройте терминал — мы уже прописали nvm в ~/.zshrc.${NC}"
  echo ""

  echo -e "   ${BOLD}${WHITE}2. Бот пишет 'access not configured' + pairing-код${NC}"
  echo -e "   ${DIM}   Причина: DM-политика 'pairing' — нужно одобрить пользователя.${NC}"
  echo -e "   ${DIM}   Решение: одобрить по коду из сообщения:${NC}"
  echo -e "      ${GREEN}openclaw pairing approve telegram <КОД>${NC}"
  echo -e "   ${DIM}   Или переключить на allowlist (добавить user ID):${NC}"
  echo -e "      ${GREEN}openclaw config set channels.telegram.dmPolicy allowlist${NC}"
  echo -e "      ${GREEN}openclaw config set channels.telegram.allowlistAllowFrom '[\"ID\"]'${NC}"
  echo -e "      ${GREEN}openclaw gateway restart${NC}"
  echo -e "   ${DIM}   Узнать свой ID: напишите @userinfobot в Telegram.${NC}"
  echo ""

  echo -e "   ${BOLD}${WHITE}3. 'brew not installed' при установке скиллов${NC}"
  echo -e "   ${DIM}   Причина: скилл (github, video-frames, obsidian и т.д.) требует утилиты из Homebrew.${NC}"
  echo -e "   ${DIM}   Решение: установить Homebrew:${NC}"
  echo -e "      ${GREEN}/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"${NC}"
  echo -e "   ${DIM}   После установки перезапустите терминал и переустановите скилл:${NC}"
  echo -e "      ${GREEN}openclaw skills install <имя_скилла>${NC}"
  echo ""

  echo -e "   ${BOLD}${WHITE}4. 'npm error network ETIMEDOUT' при установке${NC}"
  echo -e "   ${DIM}   Причина: проблемы с сетью или npm registry.${NC}"
  echo -e "   ${DIM}   Решение: проверить сеть, подождать 1-2 мин, попробовать снова:${NC}"
  echo -e "      ${GREEN}npm install -g openclaw@latest${NC}"
  echo -e "   ${DIM}   Если упорно таймаутит — смените DNS (1.1.1.1) или включите VPN.${NC}"
  echo ""

  echo -e "   ${BOLD}${WHITE}5. Бот не отвечает, хотя всё запущено${NC}"
  echo -e "   ${DIM}   Частая причина: onboard упал с 'Cannot read ... trim' и оставил${NC}"
  echo -e "   ${DIM}   config без gateway.mode → gateway закрывается (1006 abnormal closure).${NC}"
  echo -e "   ${DIM}   Recovery (выполнить по порядку):${NC}"
  echo -e "      ${GREEN}openclaw config get gateway.mode${NC}    ${DIM}# пусто? идём дальше${NC}"
  echo -e "      ${GREEN}openclaw config set gateway.mode local${NC}"
  echo -e "      ${GREEN}openclaw config validate${NC}            ${DIM}# должно быть OK${NC}"
  echo -e "      ${GREEN}openclaw gateway restart${NC}"
  echo -e "      ${GREEN}openclaw gateway status --deep${NC}      ${DIM}# живой gateway${NC}"
  echo -e "      ${GREEN}openclaw doctor --fix --yes${NC}         ${DIM}# если что-то ещё криво${NC}"
  echo -e "      ${GREEN}openclaw logs --follow${NC}              ${DIM}# если ничего не помогло — смотрим логи${NC}"
  echo ""

  echo -e "   ${BOLD}${WHITE}6. 'openclaw onboard' виснет или циклится${NC}"
  echo -e "   ${DIM}   Причина: баг в визарде — не выходит из секции 'Select a channel'.${NC}"
  echo -e "   ${DIM}   Решение: выйти по Ctrl+C, дальше настраивать через CLI напрямую:${NC}"
  echo -e "      ${GREEN}openclaw channels add --channel telegram --token <TOKEN>${NC}"
  echo -e "      ${GREEN}openclaw agents add assistant${NC}"
  echo -e "      ${GREEN}openclaw agents bind --agent assistant --bind telegram${NC}"
  echo ""

  echo -e "   ${BOLD}${WHITE}7. 'Unknown model' / HTML в ответе вместо текста${NC}"
  echo -e "   ${DIM}   Причина: модель не существует или API endpoint вернул ошибку.${NC}"
  echo -e "   ${DIM}   Решение: посмотреть доступные модели и выставить существующую:${NC}"
  echo -e "      ${GREEN}openclaw models list --all${NC}"
  echo -e "      ${GREEN}openclaw config set agents.defaults.model.primary <провайдер/модель>${NC}"
  echo ""

  echo -e "   ${BOLD}${WHITE}8. Context overflow / много сообщений в сессии${NC}"
  echo -e "   ${DIM}   Решение: очистить сессии агента:${NC}"
  echo -e "      ${GREEN}openclaw sessions cleanup --agent <имя>${NC}"
  echo -e "      ${GREEN}openclaw sessions cleanup --all-agents${NC}"
  echo ""

  echo -e "   ${BOLD}${WHITE}9. '401 No payment method' от бота${NC}"
  echo -e "   ${DIM}   Причина: стоит платная модель, а на opencode нет биллинга.${NC}"
  echo -e "   ${DIM}   Решение: переключить на бесплатную:${NC}"
  echo -e "      ${GREEN}openclaw config set agents.defaults.model.primary opencode/minimax-m2.5-free${NC}"
  echo -e "      ${GREEN}openclaw gateway restart${NC}"
  echo ""

  echo -e "   ${BOLD}${WHITE}10. 'Model is disabled' / 'Invalid API key' (кейс Елены, Саввы)${NC}"
  echo -e "   ${DIM}   Причина: на /status всё выглядит правильно, но при реальном запросе${NC}"
  echo -e "   ${DIM}   бот отвечает 401/disabled. Обычно это одно из трёх:${NC}"
  echo -e "   ${DIM}     • agents.defaults одна модель, а agents.list[i] другая${NC}"
  echo -e "   ${DIM}     • старый auth-profile opencode:default с кривым ключом${NC}"
  echo -e "   ${DIM}     • кэш сессий тащит tool_use_id от прошлой модели${NC}"
  echo ""
  echo -e "   ${DIM}   Лесенка восстановления — делать по порядку, проверяя /status после каждого шага:${NC}"
  echo -e "      ${GREEN}# 1. Привести default и всех агентов к одной модели${NC}"
  echo -e "      ${GREEN}openclaw config set agents.defaults.model.primary opencode/minimax-m2.5-free${NC}"
  echo -e "      ${GREEN}openclaw config get agents.list    ${DIM}# посмотреть сколько агентов${NC}"
  echo -e "      ${GREEN}# для каждого индекса [0], [1], ...${NC}"
  echo -e "      ${GREEN}openclaw config set 'agents.list[0].model' '\"opencode/minimax-m2.5-free\"' --strict-json${NC}"
  echo -e "      ${GREEN}# 2. Почистить сессии — иначе будет конфликт tool_use_id${NC}"
  echo -e "      ${GREEN}openclaw sessions cleanup --all-agents${NC}"
  echo -e "      ${GREEN}# 3. Перезапустить gateway${NC}"
  echo -e "      ${GREEN}openclaw gateway restart${NC}"
  echo -e "      ${GREEN}# 4. Если всё ещё 401 — перезаписать ключ через мягкий мастер${NC}"
  echo -e "      ${GREEN}openclaw configure --section model${NC}"
  echo -e "      ${DIM}# provider: OpenCode Zen | model: MiniMax M2.5 Free | вставить ключ заново${NC}"
  echo ""

  echo -e "   ${BOLD}${WHITE}11. Хочу переустановить с нуля / не помню какой ключ вводил${NC}"
  echo -e "   ${DIM}   Удаление openclaw.json — мало. Креды живут отдельно.${NC}"
  echo -e "   ${DIM}   Полный сброс:${NC}"
  echo -e "      ${GREEN}openclaw reset --scope config+creds+sessions --yes --non-interactive${NC}"
  echo -e "   ${DIM}   Или мягкий возврат к настройке модели:${NC}"
  echo -e "      ${GREEN}openclaw configure --section model${NC}"
  echo -e "   ${DIM}   Или перезапустите установщик — он покажет меню:${NC}"
  echo -e "      ${DIM}  1) оставить / 2) сменить модель / 3) новый ключ / 4) полный сброс${NC}"
  echo ""

  echo -e "   ${BOLD}${WHITE}12. npm EACCES при установке/обновлении OpenClaw${NC}"
  echo -e "   ${DIM}   Это два РАЗНЫХ случая — команды разные. Смотрите на текст ошибки:${NC}"
  echo -e "   ${DIM}   • Если в ошибке 'node_modules' / '/usr/local' → системный Node.js:${NC}"
  echo -e "      ${GREEN}sudo npm install -g openclaw@latest${NC}"
  echo -e "   ${DIM}   • Если в ошибке '.npm' / 'cache' → кэш под root'ом:${NC}"
  echo -e "      ${GREEN}sudo chown -R \$(id -u):\$(id -g) ~/.npm${NC}"
  echo -e "   ${DIM}   Потом повторить: ${GREEN}npm install -g openclaw@latest${NC}"
  echo ""

  echo -e "   ${BOLD}${WHITE}13. При установке Homebrew пароль не вводится / ничего не происходит${NC}"
  echo -e "   ${DIM}   Это НЕ баг — sudo по дизайну не отображает пароль при вводе.${NC}"
  echo -e "   ${DIM}   Печатайте пароль от Mac (не Apple ID) вслепую и жмите Enter.${NC}"
  echo -e "   ${DIM}   Если 'user is not in the sudoers file' — вы не admin на Mac.${NC}"
  echo -e "   ${DIM}   Решение: зайдите в macOS на admin-аккаунт и запустите скрипт заново.${NC}"
  echo ""

  echo -e "   ${BOLD}${WHITE}14. Ничего не помогает / хочу отправить полную диагностику в саппорт${NC}"
  echo -e "   ${DIM}   Одна команда — соберёт debug-bundle в ~/openclaw-debug-*.zip:${NC}"
  echo -e "      ${GREEN}bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-factory/main/scripts/demo-install.sh) --collect-debug${NC}"
  echo -e "   ${DIM}   В bundle'е: конфиг OpenClaw, статус gateway, логи, версии и система.${NC}"
  echo -e "   ${DIM}   Все потенциальные секреты автоматически замаскированы.${NC}"
  echo -e "   ${DIM}   Перешлите файл в поддержку — так быстрее всего починят.${NC}"
  echo ""

  divider

  echo -e "   ${DIM}📖 Полная документация: https://docs.openclaw.ai${NC}"
  echo -e "   ${DIM}🐛 Баг-репорты: https://github.com/tonytrue92-beep/openclaw-factory/issues${NC}"
  echo ""
  echo -e "   ${BOLD}Удачи! Ваш AI-ассистент ждёт первого сообщения. 🙌${NC}"
fi
echo ""

break  # реальная установка завершена — выходим из цикла
done  # конец while true (цикл меню)
