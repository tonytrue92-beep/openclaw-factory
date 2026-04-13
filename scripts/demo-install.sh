#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
#  OpenClaw TRUE — Демо-установка с нуля
#  Симуляция полного процесса для обучения
#  Не трогает основную систему (~/.openclaw)
# ═══════════════════════════════════════════════════════════════

PROFILE="demo"
DEMO_DIR="$HOME/.openclaw-${PROFILE}"
SPEED=${SPEED:-0.02}

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
#  Финал
# ═══════════════════════════════════════════════════════════════

step_header "✓" "COMPLETE"

# Очистка демо-директории
rm -rf "${DEMO_DIR}"

echo ""
echo -e "${BOLD}${MAGENTA}"
cat << 'DONE'
   ╔════════════════════════════════════════════════════════════════╗
   ║                                                                ║
   ║   🎉  Demo complete — Демонстрация завершена!                  ║
   ║                                                                ║
   ║   Чтобы установить OpenClaw по-настоящему:                     ║
   ║                                                                ║
   ║   1. npm install -g openclaw@latest                            ║
   ║   2. openclaw onboard                                          ║
   ║   3. Создайте бота в Telegram через @BotFather                 ║
   ║   4. openclaw channels add --channel telegram --token ...      ║
   ║   5. Напишите боту — он ответит!                               ║
   ║                                                                ║
   ║   📖 Документация: docs.openclaw.ai                            ║
   ║                                                                ║
   ╚════════════════════════════════════════════════════════════════╝

DONE
echo -e "${NC}"

explain "Демо-файлы удалены. Ваша система чиста." \
  "" \
  "Спасибо за внимание! Теперь вы знаете, как:" \
  "  ✓ Установить OpenClaw" \
  "  ✓ Пройти первоначальную настройку" \
  "  ✓ Подключить Telegram-бота" \
  "  ✓ Создать и настроить AI-агентов" \
  "  ✓ Отправить первое сообщение" \
  "  ✓ Чинить проблемы, если что-то пошло не так" \
  "" \
  "Удачи! 🙌"
echo ""
