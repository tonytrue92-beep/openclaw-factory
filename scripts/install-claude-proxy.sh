#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
#  Claude Code → OpenClaw Proxy Installer
#  Устанавливает proxy-acpx-x как OpenAI-совместимый мост
#  между подпиской Claude Code и OpenClaw
# ═══════════════════════════════════════════════════════════════

VERSION="1.0.0"
PORT=52088
PROVIDER_NAME="claude-local"
MODEL_ID="claude-code-proxy"
LABEL="ai.openclaw.claude-proxy"

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log()   { echo -e "${GREEN}✅${NC} $1"; }
warn()  { echo -e "${YELLOW}⚠️${NC}  $1"; }
err()   { echo -e "${RED}❌${NC} $1"; }
info()  { echo -e "${BLUE}ℹ️${NC}  $1"; }
step()  { echo -e "\n${BOLD}═══ $1 ═══${NC}"; }

DRY_RUN=false
SKIP_PATCH=false
FORCE=false

usage() {
  cat <<EOF
Claude Code → OpenClaw Proxy Installer v${VERSION}

Usage: $0 [options]

Options:
  --dry-run       Показать что будет сделано, без изменений
  --skip-patch    Не патчить tool labels (оставить 🔧 Read: в ответах)
  --force         Переустановить даже если уже установлено
  --uninstall     Удалить прокси и провайдер
  --port PORT     Порт прокси (по умолчанию: 52088)
  -h, --help      Показать справку
EOF
  exit 0
}

UNINSTALL=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)     DRY_RUN=true; shift ;;
    --skip-patch)  SKIP_PATCH=true; shift ;;
    --force)       FORCE=true; shift ;;
    --uninstall)   UNINSTALL=true; shift ;;
    --port)        PORT="$2"; shift 2 ;;
    -h|--help)     usage ;;
    *)             err "Неизвестный флаг: $1"; usage ;;
  esac
done

# ═══ Определение ОС ═══
detect_os() {
  case "$(uname -s)" in
    Darwin) OS="macos" ;;
    Linux)
      if command -v systemctl &>/dev/null; then
        OS="linux-systemd"
      else
        err "Linux без systemd не поддерживается"
        exit 1
      fi
      ;;
    *) err "Неподдерживаемая ОС: $(uname -s)"; exit 1 ;;
  esac
}

# ═══ Проверка зависимостей ═══
check_deps() {
  step "Проверка зависимостей"

  # Node.js
  if ! command -v node &>/dev/null; then
    err "Node.js не найден. Установите: https://nodejs.org"
    exit 1
  fi
  NODE_VER=$(node -v | sed 's/v//')
  NODE_MAJOR=$(echo "$NODE_VER" | cut -d. -f1)
  NODE_MINOR=$(echo "$NODE_VER" | cut -d. -f2)
  if [[ $NODE_MAJOR -lt 22 ]] || { [[ $NODE_MAJOR -eq 22 ]] && [[ $NODE_MINOR -lt 14 ]]; }; then
    err "Node.js >= 22.14 required (текущая: $NODE_VER)"
    exit 1
  fi
  log "Node.js $NODE_VER"

  # npm
  if ! command -v npm &>/dev/null; then
    err "npm не найден"
    exit 1
  fi
  log "npm $(npm -v)"

  # OpenClaw
  if ! command -v openclaw &>/dev/null; then
    err "OpenClaw CLI не найден. Установите: npm install -g openclaw"
    exit 1
  fi
  log "OpenClaw $(openclaw --version 2>&1 | head -1)"

  # Claude CLI
  if ! command -v claude &>/dev/null; then
    err "Claude Code CLI не найден. Установите: npm install -g @anthropic-ai/claude-code"
    exit 1
  fi
  log "Claude CLI $(claude --version 2>&1 | head -1)"

  # Claude auth
  if ! claude auth status &>/dev/null 2>&1; then
    warn "Claude CLI не залогинен. Запустите: claude auth login"
  else
    log "Claude CLI авторизован"
  fi
}

# ═══ Установка proxy-acpx-x ═══
install_proxy() {
  step "Установка proxy-acpx-x"

  if npm list -g proxy-acpx-x &>/dev/null && [[ "$FORCE" == false ]]; then
    CURRENT_VER=$(npm list -g proxy-acpx-x --depth=0 2>/dev/null | grep proxy-acpx-x | sed 's/.*@//')
    log "proxy-acpx-x@$CURRENT_VER уже установлен (--force для переустановки)"
  else
    if [[ "$DRY_RUN" == true ]]; then
      info "[dry-run] npm install -g proxy-acpx-x"
    else
      npm install -g proxy-acpx-x
      log "proxy-acpx-x установлен"
    fi
  fi

  NODE_PATH=$(which node)
  PROXY_PATH="$(npm root -g)/proxy-acpx-x/dist/http-server.js"

  if [[ ! -f "$PROXY_PATH" ]]; then
    err "Файл прокси не найден: $PROXY_PATH"
    exit 1
  fi
  log "Node: $NODE_PATH"
  log "Proxy: $PROXY_PATH"
}

# ═══ Создание сервиса ═══
create_service() {
  step "Создание сервиса ($OS)"

  if [[ "$OS" == "macos" ]]; then
    create_launchagent
  else
    create_systemd
  fi
}

create_launchagent() {
  PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"

  if [[ -f "$PLIST" ]] && [[ "$FORCE" == false ]]; then
    log "LaunchAgent уже существует (--force для пересоздания)"
    return
  fi

  mkdir -p "$HOME/.openclaw/logs"

  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] Создание $PLIST"
    return
  fi

  # Выгрузить если уже загружен
  launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true

  cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${NODE_PATH}</string>
        <string>${PROXY_PATH}</string>
        <string>--port</string>
        <string>${PORT}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>5</integer>
    <key>EnvironmentVariables</key>
    <dict>
        <key>HOME</key>
        <string>${HOME}</string>
        <key>PATH</key>
        <string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin</string>
    </dict>
    <key>StandardOutPath</key>
    <string>${HOME}/.openclaw/logs/claude-proxy.log</string>
    <key>StandardErrorPath</key>
    <string>${HOME}/.openclaw/logs/claude-proxy.err.log</string>
</dict>
</plist>
PLIST_EOF

  launchctl load "$PLIST"
  log "LaunchAgent создан и загружен"
}

create_systemd() {
  UNIT_DIR="$HOME/.config/systemd/user"
  UNIT_FILE="$UNIT_DIR/claude-proxy.service"

  if [[ -f "$UNIT_FILE" ]] && [[ "$FORCE" == false ]]; then
    log "systemd unit уже существует (--force для пересоздания)"
    return
  fi

  mkdir -p "$UNIT_DIR"
  mkdir -p "$HOME/.openclaw/logs"

  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] Создание $UNIT_FILE"
    return
  fi

  cat > "$UNIT_FILE" <<UNIT_EOF
[Unit]
Description=Claude Code Proxy for OpenClaw
After=network.target

[Service]
ExecStart=${NODE_PATH} ${PROXY_PATH} --port ${PORT}
Restart=always
RestartSec=5
Environment=HOME=${HOME}
Environment=PATH=/usr/local/bin:/usr/bin:/bin
StandardOutput=append:${HOME}/.openclaw/logs/claude-proxy.log
StandardError=append:${HOME}/.openclaw/logs/claude-proxy.err.log

[Install]
WantedBy=default.target
UNIT_EOF

  systemctl --user daemon-reload
  systemctl --user enable --now claude-proxy
  log "systemd unit создан и запущен"
}

# ═══ Проверка прокси ═══
verify_proxy() {
  step "Проверка прокси"

  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] curl http://127.0.0.1:${PORT}/v1/models"
    return
  fi

  sleep 3

  for i in 1 2 3 4 5; do
    if curl -sS "http://127.0.0.1:${PORT}/v1/models" 2>/dev/null | grep -q "claude-code-proxy"; then
      log "Прокси отвечает на порту ${PORT}"
      return
    fi
    info "Ожидание запуска прокси... (попытка $i/5)"
    sleep 3
  done

  err "Прокси не отвечает на порту ${PORT}"
  info "Проверьте логи: tail -f ~/.openclaw/logs/claude-proxy.err.log"
  exit 1
}

# ═══ Патч tool labels ═══
patch_tool_labels() {
  step "Патч tool labels"

  if [[ "$SKIP_PATCH" == true ]]; then
    info "Пропущен (--skip-patch)"
    return
  fi

  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] Патч $PROXY_PATH"
    return
  fi

  # Бэкап
  if [[ ! -f "${PROXY_PATH}.orig" ]]; then
    cp "$PROXY_PATH" "${PROXY_PATH}.orig"
    log "Бэкап: ${PROXY_PATH}.orig"
  fi

  # Правка 1: content_block_stop — убрать sseChunk(toolLabel)
  if grep -q 'currentRes.write(sseChunk(toolLabel, currentModel))' "$PROXY_PATH"; then
    sed -i.bak '
      /Tool call finished/,/currentToolInput = ""/ {
        s/toolCallsSummary.push(toolLabel);/\/\/ toolCallsSummary.push(toolLabel); \/\/ PATCHED/
        s/currentRes.write(sseChunk(toolLabel, currentModel));/log(`Tool done (hidden from client): ${toolLabel}`); \/\/ PATCHED/
        s/hasStreamedText = true;/\/\/ hasStreamedText = true; \/\/ PATCHED/
      }
    ' "$PROXY_PATH"
    log "Правка 1: tool labels скрыты из стрима"
  else
    info "Правка 1: уже применена или формат изменился"
  fi

  # Правка 2: убрать разделитель ---
  if grep -q 'sseChunk("\\n\\n---\\n\\n"' "$PROXY_PATH"; then
    sed -i.bak '
      /toolCallsSummary.length > 0 && !hasStreamedText/,/}/ {
        s/^/\/\/ PATCHED: /
      }
    ' "$PROXY_PATH"
    log "Правка 2: разделитель --- убран"
  else
    info "Правка 2: уже применена"
  fi

  # Правка 3: fallback path
  if grep -q 'toolCallsSummary.push(toolLabel);' "$PROXY_PATH" 2>/dev/null; then
    sed -i.bak '
      /Fallback.*assistant/,/}$/ {
        s/toolCallsSummary.push(toolLabel);/\/\/ PATCHED: toolCallsSummary.push(toolLabel);/
        s/currentRes.write(sseChunk(toolLabel, currentModel));/log(`Tool (fallback, hidden): ${toolLabel}`); \/\/ PATCHED/
        /hasStreamedText = true;/ {
          /tool_use/,/}/ s/hasStreamedText = true;/\/\/ PATCHED: hasStreamedText = true;/
        }
      }
    ' "$PROXY_PATH"
    log "Правка 3: fallback tool labels скрыты"
  else
    info "Правка 3: уже применена"
  fi

  rm -f "${PROXY_PATH}.bak"

  # Перезапуск
  if [[ "$OS" == "macos" ]]; then
    launchctl kickstart -k "gui/$(id -u)/${LABEL}"
  else
    systemctl --user restart claude-proxy
  fi
  sleep 2
  log "Прокси перезапущен с патчем"
}

# ═══ Регистрация провайдера ═══
register_provider() {
  step "Регистрация провайдера в OpenClaw"

  if openclaw models list --all 2>/dev/null | grep -q "${PROVIDER_NAME}/${MODEL_ID}"; then
    if [[ "$FORCE" == false ]]; then
      log "Провайдер ${PROVIDER_NAME}/${MODEL_ID} уже зарегистрирован"
      return
    fi
  fi

  if [[ "$DRY_RUN" == true ]]; then
    info "[dry-run] openclaw config set models.providers.${PROVIDER_NAME} ..."
    return
  fi

  # Бэкап
  openclaw backup create 2>/dev/null || bash ~/.openclaw/backup.sh 2>/dev/null || true

  openclaw config set "models.providers.${PROVIDER_NAME}" "{
    \"baseUrl\": \"http://127.0.0.1:${PORT}/v1\",
    \"apiKey\": \"sk-dummy-key\",
    \"api\": \"openai-completions\",
    \"models\": [{
      \"id\": \"${MODEL_ID}\",
      \"name\": \"Claude Code (subscription)\",
      \"api\": \"openai-completions\",
      \"reasoning\": true,
      \"input\": [\"text\", \"image\"],
      \"output\": [\"text\"],
      \"contextWindow\": 200000,
      \"maxOutput\": 128000
    }]
  }" --strict-json 2>&1

  log "Провайдер ${PROVIDER_NAME}/${MODEL_ID} зарегистрирован"
}

# ═══ Таймаут ═══
set_timeout() {
  step "Настройка таймаута LLM"

  CURRENT=$(openclaw config get agents.defaults.llm.idleTimeoutSeconds 2>/dev/null || echo "not set")
  if [[ "$CURRENT" == "not set" ]] || [[ "$CURRENT" -lt 60 ]]; then
    if [[ "$DRY_RUN" == true ]]; then
      info "[dry-run] openclaw config set agents.defaults.llm.idleTimeoutSeconds 60"
    else
      openclaw config set agents.defaults.llm.idleTimeoutSeconds 60 2>&1
      log "idleTimeoutSeconds = 60"
    fi
  else
    log "idleTimeoutSeconds = $CURRENT (уже достаточно)"
  fi
}

# ═══ Деинсталляция ═══
uninstall() {
  step "Удаление Claude Code Proxy"

  if [[ "$OS" == "macos" ]]; then
    PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
    if [[ -f "$PLIST" ]]; then
      launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
      rm -f "$PLIST"
      log "LaunchAgent удалён"
    else
      info "LaunchAgent не найден"
    fi
  else
    if systemctl --user is-enabled claude-proxy &>/dev/null; then
      systemctl --user disable --now claude-proxy
      rm -f "$HOME/.config/systemd/user/claude-proxy.service"
      systemctl --user daemon-reload
      log "systemd unit удалён"
    else
      info "systemd unit не найден"
    fi
  fi

  # Убрать провайдер из OpenClaw
  if openclaw config get "models.providers.${PROVIDER_NAME}" &>/dev/null; then
    openclaw config unset "models.providers.${PROVIDER_NAME}" 2>&1
    log "Провайдер ${PROVIDER_NAME} удалён из OpenClaw"
  fi

  # Восстановить оригинал прокси
  PROXY_PATH="$(npm root -g)/proxy-acpx-x/dist/http-server.js"
  if [[ -f "${PROXY_PATH}.orig" ]]; then
    cp "${PROXY_PATH}.orig" "$PROXY_PATH"
    log "http-server.js восстановлен из .orig"
  fi

  openclaw gateway restart 2>&1 | tail -1
  log "Готово. Прокси удалён."
  exit 0
}

# ═══ Итог ═══
summary() {
  step "Готово!"

  echo ""
  echo -e "  ${BOLD}Провайдер:${NC}  ${PROVIDER_NAME}/${MODEL_ID}"
  echo -e "  ${BOLD}Порт:${NC}       ${PORT}"
  echo -e "  ${BOLD}Сервис:${NC}     ${LABEL}"
  echo -e "  ${BOLD}Логи:${NC}       ~/.openclaw/logs/claude-proxy.err.log"
  echo ""
  echo -e "  ${BOLD}Использование:${NC}"
  echo -e "    • Как default:    ${BLUE}openclaw config set agents.defaults.model.primary \"${PROVIDER_NAME}/${MODEL_ID}\"${NC}"
  echo -e "    • Как fallback:   ${BLUE}openclaw models fallbacks add ${PROVIDER_NAME}/${MODEL_ID}${NC}"
  echo -e "    • Per-agent:      ${BLUE}openclaw config set 'agents.list[N].model' '{\"primary\":\"${PROVIDER_NAME}/${MODEL_ID}\"}' --strict-json${NC}"
  echo ""
  echo -e "  ${BOLD}Диагностика:${NC}"
  echo -e "    ${BLUE}curl http://127.0.0.1:${PORT}/v1/models${NC}"
  echo -e "    ${BLUE}tail -f ~/.openclaw/logs/claude-proxy.err.log${NC}"
  echo ""
  warn "npm update -g proxy-acpx-x перезапишет патч — запустите установщик с --force"
  echo ""
}

# ═══ Main ═══
main() {
  echo ""
  echo -e "${BOLD}  Claude Code → OpenClaw Proxy Installer v${VERSION}${NC}"
  echo ""

  detect_os

  if [[ "$DRY_RUN" == true ]]; then
    warn "Режим dry-run — изменения не будут применены"
  fi

  if [[ "$UNINSTALL" == true ]]; then
    uninstall
  fi

  check_deps
  install_proxy
  create_service
  verify_proxy
  patch_tool_labels
  register_provider
  set_timeout
  summary
}

main
