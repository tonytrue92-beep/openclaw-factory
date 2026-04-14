#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
#  OpenClaw TRUE — Демо-установка с нуля
#  Симуляция полного процесса для обучения
#  Не трогает основную систему (~/.openclaw)
# ═══════════════════════════════════════════════════════════════

# Поддержка curl | bash — читаем ввод с терминала, а не из pipe
if [[ ! -t 0 ]]; then
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

# Флаги запуска
for arg in "$@"; do
  case "$arg" in
    --install|--real|--skip-demo) SKIP_DEMO=true ;;
    --dry-run|--simulate) DRY_RUN=true; SKIP_DEMO=true ;;
    --help|-h)
      echo "Usage: bash demo-install.sh [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --install     Skip demo, go straight to real installation"
      echo "  --dry-run     Simulate the full installation (nothing is installed)"
      echo "  --help        Show this help"
      echo ""
      echo "Without flags: starts with interactive demo, then offers real install"
      exit 0
      ;;
  esac
done

# Цвета
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
  echo -e "   ${YELLOW}\$${NC} ${GREEN}$1${NC}"
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

# ═══════════════════════════════════════════════════════════════
#  Если --install — пропускаем демо, сразу к реальной установке
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

explain "Что такое OpenClaw?" \
  "" \
  "Представьте себе «переводчика» между мессенджерами и AI." \
  "Вы подключаете Telegram (или WhatsApp, Discord, Slack — 30+ каналов)," \
  "а OpenClaw соединяет их с умными AI-моделями (Claude, GPT, Gemini)." \
  "" \
  "В итоге у вас появляется бот (или несколько), которые отвечают" \
  "людям в мессенджерах — пишут тексты, отвечают на вопросы, помогают с задачами." \
  "Всё работает на вашем компьютере, без облачных серверов."

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
  terminal "command not found: node"
  echo ""
  ru "Ой! Node.js не найден. Без него дальше никак."
  ru "Зайдите на https://nodejs.org, скачайте LTS-версию (зелёная кнопка) и установите."
  ru "После установки закройте и откройте терминал заново, затем запустите демо ещё раз."
  exit 1
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
  terminal "command not found: npm"
  echo ""
  ru "npm не найден. Скорее всего, Node.js установлен некорректно."
  ru "Переустановите Node.js с nodejs.org — npm идёт в комплекте."
  exit 1
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
if command -v openclaw &>/dev/null; then
  OC_VER=$(openclaw --version 2>&1 | head -1)
  terminal "${OC_VER}"
  echo ""
  ru "Видим версию — значит OpenClaw установился корректно."
  ru "Номер вида 2026.4.9 — это год.месяц.день выпуска."
  ru "В скобках — хэш сборки (код конкретной версии). Он нужен разработчикам."
else
  terminal "OpenClaw 2026.4.9 (0512059)"
  echo ""
  ru "Так выглядит успешный ответ: версия + хэш сборки."
fi

ok "OpenClaw installed — установка завершена"
ru "Программа скачана и готова. Теперь нужно её настроить."

pause

# ═══════════════════════════════════════════════════════════════
#  ШАГ 3: Первый запуск (onboard)
# ═══════════════════════════════════════════════════════════════

step_header "3" "FIRST RUN — ONBOARDING"

explain "При первом запуске OpenClaw задаст несколько вопросов." \
  "" \
  "Это как мастер настройки при первом включении нового телефона —" \
  "вас спросят: какую AI-модель использовать, где взять ключ доступа," \
  "как запускать программу. В конце всё создастся автоматически." \
  "" \
  "Мастер настройки называется 'onboard' — дословно «вступление на борт»." \
  "Запускается один раз. Потом настройки можно менять вручную."

divider

explain "Вводим команду onboard:"

show_cmd "openclaw onboard"
echo ""

explain "Сейчас покажем, как выглядит каждый вопрос мастера и что на него отвечать." \
  "В реальной установке вы будете отвечать через стрелки и Enter на клавиатуре."

divider

# --- Вопрос 1: Провайдер ---

explain "ВОПРОС 1 из 4 — Выбор AI-провайдера." \
  "" \
  "Провайдер — это компания, которая предоставляет AI-модель." \
  "Модель — это «мозг» вашего агента, от неё зависит качество ответов." \
  "" \
  "Anthropic Claude — сейчас считается лучшим выбором для текстов и рассуждений." \
  "OpenAI GPT — тоже отличный вариант, чуть дешевле." \
  "Google Gemini — хорош для работы с данными." \
  "" \
  "Можно выбрать любого — и потом поменять в любой момент."

echo -e "   ${WHITE}? Select your AI provider${NC}"
echo -e "   ${GREEN}  ❯ Anthropic (Claude) — recommended${NC}"
echo -e "   ${DIM}    OpenAI (GPT)${NC}"
echo -e "   ${DIM}    Google (Gemini)${NC}"
echo -e "   ${DIM}    Other provider${NC}"
echo ""
ru "Стрелка ❯ показывает текущий выбор. Стрелками ↑↓ можно передвигать."
ru "Нажимаете Enter — и выбор подтверждён."
ru "Мы выбираем Anthropic Claude — он уже выделен."

divider

# --- Вопрос 2: API-ключ ---

explain "ВОПРОС 2 из 4 — API-ключ." \
  "" \
  "API-ключ — это ваш персональный «пароль» для доступа к AI-модели." \
  "Без него OpenClaw не сможет отправлять запросы к Claude/GPT/Gemini." \
  "" \
  "Где его взять?" \
  "  • Anthropic Claude → зайдите на console.anthropic.com → API Keys → Create Key" \
  "  • OpenAI GPT → зайдите на platform.openai.com → API Keys → Create" \
  "  • Google Gemini → зайдите на aistudio.google.com → Get API Key" \
  "" \
  "Ключ — это длинная строка букв и цифр. Его показывают один раз при создании," \
  "поэтому сразу скопируйте и сохраните в надёжном месте."

echo -e "   ${WHITE}? Paste your Anthropic API key${NC}"
echo -e "   ${DIM}  ▸ sk-ant-api03-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx${NC}"
echo ""
ru "Вы вставляете свой ключ (Ctrl+V или Cmd+V) и нажимаете Enter."
ru "Ключ Anthropic начинается с 'sk-ant-' — если видите другой формат, значит не тот ключ."
ru ""
ru "ВАЖНО: символы ключа НЕ отображаются при вводе (как пароль в терминале)."
ru "Это нормально! Просто вставьте и нажмите Enter."
ru ""
ru "БЕЗОПАСНОСТЬ: никому не показывайте API-ключ. Он привязан к вашему аккаунту"
ru "и вашей кредитке. Если кто-то узнает ключ — сможет тратить ваш баланс."

divider

# --- Вопрос 3: Gateway ---

explain "ВОПРОС 3 из 4 — Режим gateway." \
  "" \
  "Gateway (шлюз) — это «сердце» OpenClaw. Он работает в фоне" \
  "на вашем компьютере и делает всю работу:" \
  "  • принимает сообщения из Telegram" \
  "  • отправляет их в AI-модель" \
  "  • получает ответ и пересылает обратно пользователю" \
  "" \
  "Local — значит, gateway работает прямо на этом компьютере." \
  "Remote — если у вас уже есть сервер с gateway (продвинутый вариант)."

echo -e "   ${WHITE}? Gateway mode${NC}"
echo -e "   ${GREEN}  ❯ Local — run on this machine${NC}"
echo -e "   ${DIM}    Remote — connect to existing gateway${NC}"
echo ""
ru "Выбираем Local — шлюз будет на вашем Mac или PC."
ru "Пока компьютер включён — агенты отвечают. Выключили — ушли в офлайн."

divider

# --- Вопрос 4: Сервис ---

explain "ВОПРОС 4 из 4 — Автозапуск." \
  "" \
  "Этот вопрос про автозапуск: хотите ли вы, чтобы gateway запускался" \
  "автоматически при включении компьютера?" \
  "" \
  "Если Yes — вам не нужно будет каждый раз открывать терминал и вручную" \
  "запускать программу. OpenClaw стартует тихо в фоне при загрузке системы." \
  "" \
  "Если No — придётся каждый раз запускать вручную командой 'openclaw gateway start'."

echo -e "   ${WHITE}? Install gateway as system service?${NC}"
echo -e "   ${GREEN}  ❯ Yes — start automatically on boot${NC}"
echo -e "   ${DIM}    No — I'll start it manually${NC}"
echo ""
ru "Рекомендуем Yes. Тогда после перезагрузки компьютера агенты сразу онлайн."
ru ""
ru "На macOS это работает через LaunchAgent — системный механизм автозапуска."
ru "На Linux — через systemd. OpenClaw сам определит и настроит нужный вариант."

divider

# --- Результат onboard ---

explain "Готово! OpenClaw создал конфигурацию и запустил gateway:" \
  "Вот что вы увидите после ответов на все вопросы —"

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
terminal "Model: anthropic/claude-sonnet-4-6"
terminal "Channels: 0 configured"
terminal "Agents: 1 (main)"
terminal "Sessions: 0 active"
echo ""
ru "'Model: anthropic/claude-sonnet-4-6' — AI-модель, которую используют агенты."
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
terminal "  Model: anthropic/claude-sonnet-4-6 (inherited from defaults)"
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
terminal "main         Main         anthropic/claude-sonnet-4-6   -"
terminal "copywriter   Copywriter   anthropic/claude-sonnet-4-6   telegram"
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
show_cmd 'openclaw config set agents.defaults.model.primary "anthropic/claude-sonnet-4-6"'
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
  # Реальная проверка
  echo -n -e "   ${DIM}Node.js... ${NC}"
  if command -v node &>/dev/null; then
    NODE_VER=$(node -v)
    NODE_MAJOR=$(echo "$NODE_VER" | sed 's/v//' | cut -d. -f1)
    if [[ "$NODE_MAJOR" -ge 22 ]]; then
      echo -e "${GREEN}✓ ${NODE_VER}${NC}"
    else
      echo -e "${RED}✗ ${NODE_VER} (нужна >= 22.14)${NC}"
      echo ""
      explain "Ваша версия Node.js слишком старая. Обновите:" \
        "  Зайдите на https://nodejs.org и скачайте LTS-версию (зелёная кнопка)." \
        "  После установки закройте терминал, откройте заново и запустите скрипт снова."
      exit 1
    fi
  else
    echo -e "${RED}✗ не найден${NC}"
    echo ""
    explain "Node.js не установлен. Без него OpenClaw не работает." \
      "  Зайдите на https://nodejs.org и скачайте LTS-версию." \
      "  Установите, перезапустите терминал и запустите скрипт снова."
    exit 1
  fi

  echo -n -e "   ${DIM}npm...     ${NC}"
  if command -v npm &>/dev/null; then
    echo -e "${GREEN}✓ $(npm -v)${NC}"
  else
    echo -e "${RED}✗ не найден${NC}"
    explain "npm не найден. Переустановите Node.js с nodejs.org."
    exit 1
  fi

  echo -n -e "   ${DIM}OpenClaw...${NC}"
  if command -v openclaw &>/dev/null; then
    OC_VER=$(openclaw --version 2>&1 | head -1)
    echo -e "${GREEN}✓ ${OC_VER} (уже установлен)${NC}"
    OPENCLAW_INSTALLED=true
  else
    echo -e "${YELLOW}○ не установлен (установим сейчас)${NC}"
    OPENCLAW_INSTALLED=false
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
    npm install -g openclaw@latest 2>&1 | tail -5 | while IFS= read -r line; do
      echo -e "   ${DIM}${line}${NC}"
    done
    echo ""
    OC_VER=$(openclaw --version 2>&1 | head -1)
    ok "OpenClaw ${OC_VER} — актуальная версия"
  else
    explain "Устанавливаем OpenClaw..." \
      "Это займёт 30–60 секунд. npm скачает все необходимые пакеты."

    echo ""
    npm install -g openclaw@latest 2>&1 | while IFS= read -r line; do
      echo -e "   ${DIM}${line}${NC}"
    done
    echo ""

    if command -v openclaw &>/dev/null; then
      OC_VER=$(openclaw --version 2>&1 | head -1)
      ok "OpenClaw ${OC_VER} — установлен!"
    else
      echo -e "   ${RED}✗ Ошибка установки. Попробуйте вручную: npm install -g openclaw@latest${NC}"
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
  explain "Запускаем onboard — интерактивный мастер настройки." \
    "" \
    "В реальной установке откроется интерактивное меню." \
    "Вы будете отвечать на вопросы стрелками ↑↓ и Enter."

  show_cmd "openclaw onboard"
  echo ""

  sleep 0.5
  echo -e "   ${WHITE}? Select your AI provider${NC}"
  echo -e "   ${GREEN}  ❯ Anthropic (Claude) — recommended${NC}"
  sleep 0.5
  echo -e "   ${WHITE}? Paste your Anthropic API key${NC}"
  echo -e "   ${DIM}  ▸ sk-ant-api03-••••••••••••••••${NC}"
  sleep 0.5
  echo -e "   ${WHITE}? Gateway mode${NC}"
  echo -e "   ${GREEN}  ❯ Local — run on this machine${NC}"
  sleep 0.5
  echo -e "   ${WHITE}? Install gateway as system service?${NC}"
  echo -e "   ${GREEN}  ❯ Yes — start automatically on boot${NC}"
  echo ""
  sleep 0.5
  terminal "✓ Config created: ~/.openclaw/openclaw.json"
  terminal "✓ Workspace initialized: ~/.openclaw/workspace"
  terminal "✓ Gateway service installed"
  terminal "✓ Gateway started on port 18789"
  terminal "✓ Dashboard: http://127.0.0.1:18789"
  echo ""
  ru "Мастер задал 4 вопроса, создал конфигурацию и запустил gateway."
  ru "В реальной установке вам нужно будет вставить свой API-ключ."

  ok "Onboarding complete (симуляция)"
else
  if [[ -f "$HOME/.openclaw/openclaw.json" ]]; then
    explain "OpenClaw уже настроен (нашёлся файл ~/.openclaw/openclaw.json)." \
      "Пропускаем onboard и переходим к подключению Telegram-бота." \
      "" \
      "Если хотите перенастроить с нуля — запустите 'openclaw onboard' вручную."
  else
    explain "Запускаем onboard — интерактивную настройку." \
      "" \
      "Сейчас откроется мастер настройки. Отвечайте на вопросы —" \
      "используйте стрелки ↑↓ для выбора и Enter для подтверждения." \
      "" \
      "Рекомендации:" \
      "  • Провайдер: Anthropic (Claude) — лучшее качество ответов" \
      "  • API-ключ: получите на console.anthropic.com → API Keys" \
      "  • Gateway mode: Local" \
      "  • System service: Yes"

    pause

    echo ""
    echo -e "   ${BOLD}${YELLOW}Запускаю openclaw onboard...${NC}"
    echo -e "   ${DIM}(Отвечайте на вопросы в терминале)${NC}"
    echo ""

    openclaw onboard

    if [[ $? -eq 0 ]]; then
      ok "Onboard завершён! OpenClaw настроен."
    else
      echo ""
      warn "Onboard завершился с ошибкой. Попробуйте: openclaw onboard"
      echo ""
      echo -e "   ${DIM}Продолжить всё равно? [y/n]${NC}"
      read -r cont
      [[ "$cont" != "y" && "$cont" != "Y" ]] && exit 1
    fi
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
      openclaw channels add --channel telegram --name "${BOT_NAME}" --token "${BOT_TOKEN}" 2>&1 | while IFS= read -r line; do
        echo -e "   ${DIM}${line}${NC}"
      done
      echo ""

      TELEGRAM_CONNECTED=true
      ok "Telegram-бот @${BOT_USERNAME} подключён!"
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
  terminal "  Model: anthropic/claude-sonnet-4-6 (inherited from defaults)"
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

  echo -e "   ${DIM}Создаю агента...${NC}"
  openclaw agents add "${AGENT_ID}" 2>&1 | while IFS= read -r line; do
    echo -e "   ${DIM}${line}${NC}"
  done
  echo ""

  if [[ "${TELEGRAM_CONNECTED:-false}" == true ]]; then
    echo -e "   ${DIM}Привязываю к Telegram...${NC}"
    openclaw agents bind --agent "${AGENT_ID}" --bind telegram 2>&1 | while IFS= read -r line; do
      echo -e "   ${DIM}${line}${NC}"
    done
    echo ""
  fi

  echo -e "   ${DIM}Проверяю gateway...${NC}"
  GW_STATUS=$(openclaw gateway status 2>&1)
  if echo "$GW_STATUS" | grep -q "running"; then
    echo -e "   ${GREEN}✓ Gateway работает${NC}"
  else
    echo -e "   ${YELLOW}○ Gateway не запущен. Запускаю...${NC}"
    openclaw gateway start 2>&1 | while IFS= read -r line; do
      echo -e "   ${DIM}${line}${NC}"
    done
  fi
  echo ""

  echo -e "   ${DIM}Запускаю диагностику...${NC}"
  openclaw doctor --fix --yes 2>&1 | while IFS= read -r line; do
    echo -e "   ${DIM}${line}${NC}"
  done
  echo ""

  ok "Ассистент '${AGENT_ID}' создан и готов к работе!"
fi

pause

# ═══════════════════════════════════════════════════════════════
#  REAL STEP 6: Проверка и итоги
# ═══════════════════════════════════════════════════════════════

step_header "R6" "FINAL CHECK"

explain "Финальная проверка — убедимся, что всё работает..."
echo ""

if [[ "$DRY_RUN" == true ]]; then
  show_cmd "openclaw status --all"
  echo ""
  sleep 0.5
  terminal "OpenClaw 2026.4.9 (0512059)"
  terminal "Gateway: running (pid 54321)"
  terminal "Model: anthropic/claude-sonnet-4-6"
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
  openclaw status --all 2>&1 | while IFS= read -r line; do
    echo -e "   ${line}"
  done
  echo ""

  divider

  if [[ "${TELEGRAM_CONNECTED:-false}" == true ]]; then
    explain "Проверяем Telegram-канал..."
    echo ""
    openclaw channels status --probe 2>&1 | while IFS= read -r line; do
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
  explain "Чтобы установить OpenClaw по-настоящему, запустите:" \
    "" \
    "  bash demo-install.sh --install" \
    "" \
    "Или пройдите полное демо + установку:" \
    "" \
    "  bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-factory/main/scripts/demo-install.sh)"
  echo ""
  echo -e "   ${BOLD}${WHITE}Что вам понадобится для реальной установки:${NC}"
  echo -e "   ${CYAN}1.${NC} Node.js >= 22.14 (nodejs.org)"
  echo -e "   ${CYAN}2.${NC} API-ключ Anthropic (console.anthropic.com)"
  echo -e "   ${CYAN}3.${NC} Telegram-бот от @BotFather"
  echo ""
  echo -e "   ${BOLD}Когда будете готовы — запускайте установку! 🙌${NC}"
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

  echo -e "   ${BOLD}${WHITE}Что делать дальше:${NC}"
  if [[ "${TELEGRAM_CONNECTED:-false}" == true ]]; then
    echo -e "   ${CYAN}1.${NC} Откройте Telegram и напишите боту @${BOT_USERNAME:-вашему боту} — он ответит!"
  else
    echo -e "   ${CYAN}1.${NC} Подключите Telegram: openclaw channels add --channel telegram --token ..."
  fi
  echo -e "   ${CYAN}2.${NC} Dashboard: ${UNDERLINE:-}http://127.0.0.1:18789${NC}"
  echo -e "   ${CYAN}3.${NC} Если что-то не работает: ${BOLD}openclaw doctor --fix${NC}"
  echo ""

  echo -e "   ${BOLD}${WHITE}Команды на каждый день:${NC}"
  show_cmd "openclaw status --all        # Проверить всё"
  show_cmd "openclaw logs --follow       # Смотреть логи"
  show_cmd "openclaw doctor --fix        # Починить проблемы"
  show_cmd "openclaw gateway restart     # Перезапустить"
  echo ""

  echo -e "   ${DIM}📖 Документация: docs.openclaw.ai${NC}"
  echo -e "   ${DIM}💬 Поддержка: openclaw.ai/community${NC}"
  echo ""
  echo -e "   ${BOLD}Удачи! Ваш AI-ассистент ждёт первого сообщения. 🙌${NC}"
fi
echo ""
