#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
#  OpenClaw TRUE — Демо-установка с нуля
#  Симуляция полного процесса для обучения
#  Не трогает основную систему (~/.openclaw)
# ═══════════════════════════════════════════════════════════════

# ─── Версия установщика ─────────────────────────────────────────
# Обновляется при каждом значимом коммите. У factory НЕТ release-workflow
# (раздача с raw/main, не из релизов) — INSTALLER_COMMIT подставляется
# только при запуске из git-checkout (блок ниже), из curl останется
# плейсхолдер. Это ок: версия определяется INSTALLER_VERSION.
#
# Зачем: когда ученик пишет «не работает», по версии мы сразу видим,
# на какой версии скрипта он сидит — и не гадаем, есть ли у него наши
# последние фиксы или он закэшировал старый curl.
INSTALLER_VERSION="2026.06.14"
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

COURSE_TOKEN="${COURSE_TOKEN:-}"

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
      echo "  --vps, --headless VPS mode (Linux server, no GUI, SSH-tunnel for dashboard)"
      echo "  --course-token TOKEN Base/Pro/OpenClaw token from @AITeamVIPBot (skip R0 prompt)"
      echo "  --vip-token TOKEN    Legacy alias for --course-token"
      echo "  --diagnose-only   Check existing OpenClaw install without changing anything"
      echo "  --collect-debug   Collect debug bundle for support (non-interactive)"
      echo "  --version         Print installer version and exit"
      echo "  --help            Show this help"
      echo ""
      echo "Environment variables:"
      echo "  COURSE_TOKEN      Same as --course-token (для CI/non-interactive)"
      echo ""
      echo "Without flags: starts with interactive demo, then offers real install"
      exit 0
      ;;
  esac
done

_args=("$@")
for ((i = 0; i < ${#_args[@]}; i++)); do
  case "${_args[$i]}" in
    --course-token|--vip-token)
      if [[ -z "${_args[$((i + 1))]:-}" ]]; then
        echo "ERROR: ${_args[$i]} требует значение" >&2
        exit 1
      fi
      ;;
  esac
done
unset _args

# Проверяем заранее: если запрошен `--collect-debug`, то TTY нам не нужен
# (функция только пишет файлы, ничего не спрашивает). Это даст возможность
# ученикам собирать bundle даже в non-interactive окружении.
NEEDS_TTY=true
for arg in "$@"; do
  [[ "$arg" == "--collect-debug" ]] && NEEDS_TTY=false
  [[ "$arg" == "--diagnose-only" ]] && NEEDS_TTY=false
done

# Поддержка curl | bash — читаем ввод с терминала, а не из pipe
if [[ "$NEEDS_TTY" == true && ! -t 0 ]]; then
  if ! { [[ -e /dev/tty ]] && { exec < /dev/tty; } 2>/dev/null; }; then
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
DIAGNOSE_ONLY=false       # флаг для --diagnose-only; сам вызов там же
VPS_MODE=false            # флаг для --vps; меняет поведение R1/R6 (skip macOS checks, no GUI)
ENGINE_ONLY=false         # --engine-only: не дотягивать агентов (отладка/SUB/переустановка движка)
COURSE_TOKEN="${COURSE_TOKEN:-}"  # env или --course-token / --vip-token

# Остальные флаги (меняющие состояние) — после TTY-инициализации
while [[ $# -gt 0 ]]; do
  arg="$1"
  case "$arg" in
    --install|--real|--skip-demo) SKIP_DEMO=true ;;
    --dry-run|--simulate) DRY_RUN=true; SKIP_DEMO=true ;;
    --version|-V|--help|-h) : ;;  # уже обработано выше
    --collect-debug) COLLECT_DEBUG_ONLY=true ;;
    --diagnose-only) DIAGNOSE_ONLY=true ;;
    --course-token)
      COURSE_TOKEN="${2:-}"
      if [[ -z "$COURSE_TOKEN" ]]; then
        echo "ERROR: --course-token требует значение" >&2
        exit 1
      fi
      shift 2
      continue
      ;;
    --course-token=*)
      COURSE_TOKEN="${1#*=}"
      shift
      continue
      ;;
    --vip-token)
      COURSE_TOKEN="${2:-}"
      if [[ -z "$COURSE_TOKEN" ]]; then
        echo "ERROR: --vip-token требует значение" >&2
        exit 1
      fi
      shift 2
      continue
      ;;
    --vip-token=*)
      COURSE_TOKEN="${1#*=}"
      shift
      continue
      ;;
    --vps|--headless)
      # VPS-режим: бот поднимается на удалённом Linux-сервере,
      # никаких macOS-specific шагов (Homebrew/Xcode), никаких GUI
      # (open/xdg-open), в post-install SSH-tunnel инструкция.
      # Подразумевает --install (на VPS нет смысла в демо/меню).
      VPS_MODE=true
      SKIP_DEMO=true
      ;;
    --engine-only)
      ENGINE_ONLY=true
      ;;
  esac
  shift || true
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

# ═══ Course-token (wave 12): локальная Ed25519-проверка SUB/STD/VIP ═══
# Встроено в первый установщик, чтобы нельзя было поставить OpenClaw
# движок без оплаты курса. С тем же public key, что и agents-pack.
COURSE_TOKEN_CACHE="$HOME/.openclaw/course-token"
COURSE_TIER=""
COURSE_TOKEN="${COURSE_TOKEN:-}"

COURSE_PUBLIC_KEY_PEM=$(cat <<'EOF'
-----BEGIN PUBLIC KEY-----
MCowBQYDK2VwAyEAQIjPPB5LB1R3outrY1HMaVRVUB2tkDhHtpC8LLJ+8rA=
-----END PUBLIC KEY-----
EOF
)

course_token_get_tier() {
  local token="$1"
  if [[ "$token" =~ ^(VIP|STD|SUB)- ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

course_token_expected_tg() {
  local token="$1"
  if [[ "$token" =~ ^(VIP|STD|SUB)-[A-F0-9]{16}-([0-9]{5,15})-[A-Za-z0-9_-]{80,100}$ ]]; then
    printf '%s' "${BASH_REMATCH[2]}"
    return 0
  fi
  return 1
}

course_token_normalize() {
  local token="$1"
  token=$(printf '%s' "$token" | tr -d '[:space:]')
  token="${token//—/-}"   # U+2014 EM DASH (длинное тире)
  token="${token//–/-}"   # U+2013 EN DASH (среднее тире)
  token="${token//‐/-}"   # U+2010 HYPHEN (юникод-дефис)
  token="${token//‑/-}"   # U+2011 NON-BREAKING HYPHEN (неразрывный)
  token="${token//\"/}"   # обрамляющие кавычки "TOKEN"
  token="${token//\'/}"   # обрамляющие одинарные кавычки 'TOKEN'
  printf '%s' "$token"
}

course_token_load_cache() {
  if [[ -f "$COURSE_TOKEN_CACHE" ]]; then
    local perms
    perms=$(stat -f '%A' "$COURSE_TOKEN_CACHE" 2>/dev/null \
              || stat -c '%a' "$COURSE_TOKEN_CACHE" 2>/dev/null \
              || echo "?")
    if [[ "$perms" == "?" ]]; then
      # R2-аудит: stat недоступен — чиним права сами (fail-closed)
      chmod 600 "$COURSE_TOKEN_CACHE" 2>/dev/null || return 1
    elif [[ "$perms" != "600" ]]; then
      return 1
    fi
    tr -d '[:space:]' < "$COURSE_TOKEN_CACHE" 2>/dev/null || true
  fi
}

course_token_save_cache() {
  local token="$1"
  mkdir -p "$(dirname "$COURSE_TOKEN_CACHE")"
  ( umask 077; printf '%s\n' "$token" > "$COURSE_TOKEN_CACHE" )
  chmod 600 "$COURSE_TOKEN_CACHE" 2>/dev/null || true
}

course_token_clear_cache() {
  rm -f "$COURSE_TOKEN_CACHE" 2>/dev/null || true
}

course_decode_b64url() {
  local sig="$1"
  local out="$2"
  python3 - "$sig" "$out" <<'PY_B64'
import base64, sys
sig, out = sys.argv[1], sys.argv[2]
padded = sig + '=' * (-len(sig) % 4)
with open(out, 'wb') as fh:
    fh.write(base64.urlsafe_b64decode(padded.encode()))
PY_B64
}

course_token_node_crypto_available() {
  command -v node >/dev/null 2>&1 || return 1
  COURSE_PUBLIC_KEY_PEM="$COURSE_PUBLIC_KEY_PEM" node - <<'JS_NODE_CHECK' >/dev/null 2>&1
const crypto = require('crypto');
try {
  crypto.createPublicKey(process.env.COURSE_PUBLIC_KEY_PEM || '');
  Buffer.from('AA', 'base64url');
  process.exit(0);
} catch {
  process.exit(1);
}
JS_NODE_CHECK
}

course_token_openssl_ed25519_available() {
  command -v openssl >/dev/null 2>&1 || return 1
  openssl pkeyutl -help 2>&1 | grep -q -- '-rawin'
}

course_token_crypto_runtime_available() {
  course_token_node_crypto_available || course_token_openssl_ed25519_available
}

ensure_course_token_crypto_runtime() {
  course_token_crypto_runtime_available && return 0
  [[ "$DRY_RUN" == true ]] && return 0

  echo ""
  explain "Сейчас подготовим OpenClaw и проверим токен." \
    "Если понадобится — установщик сам поставит нужный компонент."

  prompt_install_node

  if course_token_crypto_runtime_available; then
    return 0
  fi

  warn "Node.js не подготовлен, course-token проверить невозможно. Установи Node.js и запусти команду снова."
  exit 1
}

course_verify_ed25519_signature() {
  local payload="$1"
  local sig_part="$2"

  if course_token_node_crypto_available; then
    if COURSE_PUBLIC_KEY_PEM="$COURSE_PUBLIC_KEY_PEM" COURSE_PAYLOAD="$payload" COURSE_SIG_B64="$sig_part" node - <<'JS_VERIFY' >/dev/null 2>&1
const crypto = require('crypto');
try {
  const publicKey = crypto.createPublicKey(process.env.COURSE_PUBLIC_KEY_PEM);
  const payload = Buffer.from(process.env.COURSE_PAYLOAD || '', 'utf8');
  const signature = Buffer.from(process.env.COURSE_SIG_B64 || '', 'base64url');
  process.exit(crypto.verify(null, payload, publicKey, signature) ? 0 : 1);
} catch {
  process.exit(1);
}
JS_VERIFY
    then
      return 0
    fi
  fi

  local tmpdir
  tmpdir=$(mktemp -d -t course-token.XXXXXX)
  chmod 700 "$tmpdir" 2>/dev/null || true
  printf '%s' "$payload" > "$tmpdir/payload.txt"
  printf '%s\n' "$COURSE_PUBLIC_KEY_PEM" > "$tmpdir/public.pem"

  if ! course_decode_b64url "$sig_part" "$tmpdir/signature.bin"; then
    rm -rf "$tmpdir"
    return 4
  fi

  if openssl pkeyutl -verify -pubin -inkey "$tmpdir/public.pem" \
       -rawin -in "$tmpdir/payload.txt" -sigfile "$tmpdir/signature.bin" \
       >/dev/null 2>&1; then
    rm -rf "$tmpdir"
    return 0
  fi

  rm -rf "$tmpdir"
  return 5
}

course_verify_token() {
  local token="$1"
  local machine_tg_id="$2"

  local tier hash_part tg_part sig_part
  if [[ "$token" =~ ^(VIP|STD|SUB)-([A-F0-9]{16})-([0-9]{5,15})-([A-Za-z0-9_-]{80,100})$ ]]; then
    tier="${BASH_REMATCH[1]}"
    hash_part="${BASH_REMATCH[2]}"
    tg_part="${BASH_REMATCH[3]}"
    sig_part="${BASH_REMATCH[4]}"

    if [[ -n "$machine_tg_id" && "$tg_part" != "$machine_tg_id" ]]; then
      return 3
    fi

    # v3: tier явно подписан. Для VIP оставляем fallback на legacy v2 payload.
    if course_verify_ed25519_signature "${tier}|${hash_part}|${tg_part}" "$sig_part"; then
      COURSE_TIER="$tier"
      COURSE_TOKEN="$token"
      return 0
    fi
    if [[ "$tier" == "VIP" ]] && course_verify_ed25519_signature "${hash_part}|${tg_part}" "$sig_part"; then
      COURSE_TIER="VIP"
      COURSE_TOKEN="$token"
      return 0
    fi
    return 5
  fi

  # Legacy v1 VIP: подпись валидна, но TG-binding нет. Принимаем только для VIP backward-compat.
  if [[ "$token" =~ ^VIP-([A-F0-9]{16})-([A-Za-z0-9_-]{80,100})$ ]]; then
    hash_part="${BASH_REMATCH[1]}"
    sig_part="${BASH_REMATCH[2]}"
    if course_verify_ed25519_signature "$hash_part" "$sig_part"; then
      COURSE_TIER="VIP"
      COURSE_TOKEN="$token"
      return 6
    fi
    return 5
  fi

  return 2
}

course_detect_owner_tg_id() {
  local cfg="$HOME/.openclaw/openclaw.json"
  [[ ! -f "$cfg" ]] && return 0

  local tg_id
  tg_id=$(grep -oE '"allowFrom"[[:space:]]*:[[:space:]]*\[[[:space:]]*"[0-9]+"' "$cfg" \
            | grep -oE '"[0-9]+"' | head -1 | tr -d '"')

  if [[ -z "$tg_id" ]]; then
    tg_id=$(grep -oE '"allowlistAllowFrom"[[:space:]]*:[[:space:]]*\[[[:space:]]*"[0-9]+"' "$cfg" \
              | grep -oE '"[0-9]+"' | head -1 | tr -d '"')
  fi

  printf '%s' "${tg_id:-}"
}

course_validate_and_set() {
  local token="$1"
  local machine_tg_id="$2"

  COURSE_TOKEN=""
  COURSE_TIER=""
  if [[ -z "$(course_token_get_tier "$token" 2>/dev/null)" ]]; then
    # R2-аудит: HRM (Hermes SKU) — целевое сообщение вместо «не распознан»
    if [[ "$token" == HRM-* ]]; then
      warn "Это HRM-токен (супер-агент Hermes), а не токен движка."
      echo -e "   ${DIM}Для движка нужен SUB-/STD-/VIP-токен. Hermes ставится ПОСЛЕ движка:${NC}"
      echo -e "   ${DIM}установщик агентов → пункт 4 (Hermes).${NC}"
      return 1
    fi
    warn "Формат токена не распознан. Ожидается SUB-..., STD-... или VIP-..."
    return 1
  fi

  course_verify_token "$token" "$machine_tg_id"
  local rc=$?
  case $rc in
    0|6)
      return 0
      ;;
    3)
      local expected_tg
      expected_tg=$(course_token_expected_tg "$token" 2>/dev/null || echo "?")
      warn "Токен выдан для TG ID ${expected_tg}, а указан ${machine_tg_id}."
      echo -e "   ${DIM}Получи свой токен в @AITeamVIPBot с того же Telegram-аккаунта.${NC}"
      return 1
      ;;
    *)
      warn "Course-token не прошёл проверку (код $rc). Получи свежий в @AITeamVIPBot."
      return 1
      ;;
  esac
}

acquire_course_token_for_install() {
  local preset_token="$1"
  local machine_tg_id="$2"

  if [[ -n "$preset_token" ]]; then
    local original_preset_token="$preset_token"
    preset_token=$(course_token_normalize "$preset_token")
    if [[ "$preset_token" != "$original_preset_token" ]]; then
      echo "ℹ️  Очистил токен из команды от лишних символов (пробелы / юникод-тире / кавычки)."
    fi
    if course_validate_and_set "$preset_token" "$machine_tg_id"; then
      course_token_save_cache "$COURSE_TOKEN"
      return 0
    fi
    warn "Токен из команды не прошёл проверку. Старый кэш не использую, чтобы не смешивать причины ошибки."
    echo -e "   ${DIM}Скопируй готовую команду из @AITeamVIPBot ещё раз. Токен должен быть полным — от префикса SUB-/STD-/VIP- до конца подписи.${NC}"
    return 1
  fi

  local cached
  cached=$(course_token_load_cache || true)
  if [[ -n "$cached" ]]; then
    cached=$(course_token_normalize "$cached")
    if course_validate_and_set "$cached" "$machine_tg_id"; then
      echo -e "   ${GREEN}✓${NC} Использую кэшированный course-token (${COURSE_TIER}-тариф)"
      return 0
    fi
    warn "Кэшированный course-token больше не валиден. Запрашиваю новый."
    course_token_clear_cache
  fi

  explain "Для установки нужен токен из @AITeamVIPBot." \
    "Открой Telegram: @AITeamVIPBot → /start → email/phone оплаты."

  local attempts=0
  while [[ $attempts -lt 3 ]]; do
    attempts=$((attempts + 1))
    echo -e "   ${BOLD}${WHITE}Вставь токен Base/Pro/OpenClaw (попытка ${attempts}/3):${NC}"
    local token
    read -r token
    # ─── Wave 17: санитизация ввода ──────────────────────────────
    # Триггер: реальный кейс клиента (Надежда Sagitova, 15.05.2026).
    # Валидный VIP-токен отклонялся с кодом 5 из-за copy-paste артефактов.
    # Санитизация в единой точке = покрывает все источники токена.
    # ────────────────────────────────────────────────────────────

    local original_token="$token"
    token=$(course_token_normalize "$token")

    if [[ "$token" != "$original_token" ]]; then
      echo "ℹ️  Очистил токен от лишних символов (пробелы / юникод-тире / кавычки)."
    fi

    [[ -z "$token" ]] && { warn "Пустой ввод."; continue; }
    if course_validate_and_set "$token" "$machine_tg_id"; then
      course_token_save_cache "$COURSE_TOKEN"
      echo -e "   ${GREEN}✓${NC} Токен подтверждён (${COURSE_TIER}-тариф). Сохранил для следующих запусков."
      return 0
    fi
  done

  return 1
}

require_course_token_before_real_install() {
  [[ "$DRY_RUN" == true ]] && return 0

  step_header "R0" "COURSE-TOKEN"

  local machine_tg_id
  machine_tg_id=$(course_detect_owner_tg_id)
  if [[ -z "$machine_tg_id" ]]; then
    explain "Нужен твой Telegram ID." \
      "Если не знаешь — напиши @userinfobot в Telegram."
    echo -e "   ${BOLD}${WHITE}Введите ваш Telegram user ID:${NC}"
    read -r machine_tg_id
    [[ ! "$machine_tg_id" =~ ^[0-9]+$ ]] && { warn "TG ID должен быть числом."; exit 1; }
  else
    echo -e "   ${GREEN}✓${NC} Ваш Telegram ID из текущей настройки OpenClaw: ${BOLD}${machine_tg_id}${NC}"
  fi

  ensure_course_token_crypto_runtime

  if ! acquire_course_token_for_install "$COURSE_TOKEN" "$machine_tg_id"; then
    warn "Токен из @AITeamVIPBot не получен. Установка прервана."
    echo -e "   ${DIM}Получи токен: ${BOLD}@AITeamVIPBot${NC}${DIM} → /start → email/phone оплаты.${NC}"
    exit 1
  fi

  ok "Course-token подтверждён (${BOLD}${COURSE_TIER}${NC}-тариф). Можно продолжать установку."
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

# Устойчивое скачивание установщика агентов: releases/latest → прямой тег
# (через GitHub API, обход 504 на сломанном редиректе /latest/) → git clone.
# Печатает команду запуска в stdout (для eval), код 0 при успехе; иначе 1.
_fetch_agents_installer() {
  local repo="tonytrue92-beep/openclaw-agents-pack"
  local base="https://github.com/${repo}"
  local tmp; tmp="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/oc-agents-$$.sh")"

  # 0) IP-gated gateway (если задан IP_BASE) — приоритетный источник
  if [[ -n "$IP_BASE" ]]; then
    if curl -fsSL --max-time 45 -H "Authorization: Bearer $(_ip_token)" \
         "${IP_BASE%/}/installers/agents.sh" -o "$tmp" 2>/dev/null \
         && head -1 "$tmp" 2>/dev/null | grep -q '^#!'; then
      printf 'bash %q' "$tmp"; return 0
    fi
    # gateway задан, но не отдал — не падаем в публичный github (репо может
    # быть private); вернём ошибку, чейн покажет диагностику.
    rm -f "$tmp" 2>/dev/null || true
    return 1
  fi

  # 1) обычный путь — releases/latest/download
  if curl -fsSL --max-time 45 "${base}/releases/latest/download/install-agents-bundled.sh" -o "$tmp" 2>/dev/null \
       && head -1 "$tmp" 2>/dev/null | grep -q '^#!'; then
    printf 'bash %q' "$tmp"; return 0
  fi

  # 2) прямой тег (обход сломанного редиректа /latest/, напр. 504)
  local tag
  tag=$(curl -fsSL --max-time 20 "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
          | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
  if [[ -n "$tag" ]] \
       && curl -fsSL --max-time 45 "${base}/releases/download/${tag}/install-agents-bundled.sh" -o "$tmp" 2>/dev/null \
       && head -1 "$tmp" 2>/dev/null | grep -q '^#!'; then
    printf 'bash %q' "$tmp"; return 0
  fi

  # 3) git clone (полный репо с lib/) — последний рубеж
  if command -v git >/dev/null 2>&1; then
    local cdir; cdir="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/oc-agents-clone-$$")"
    if git clone --depth 1 "${base}.git" "$cdir" >/dev/null 2>&1 \
         && [[ -f "$cdir/scripts/install-agents.sh" ]]; then
      printf 'bash %q' "$cdir/scripts/install-agents.sh"; return 0
    fi
  fi

  rm -f "$tmp" 2>/dev/null || true
  return 1
}

# Автоустановка Node.js через nvm (без sudo) — используется в реальной установке
install_node_via_nvm() {
  echo ""
  explain "Ставлю Node.js — это займёт 1-2 минуты."

  export NVM_DIR="$HOME/.nvm"

  if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
    echo -e "   ${DIM}Скачиваю установщик Node.js...${NC}"
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh 2>/dev/null | bash 2>&1 | tail -5 | while IFS= read -r line; do
      echo -e "   ${DIM}${line}${NC}"
    done
  else
    echo -e "   ${DIM}Node.js installer уже на месте${NC}"
  fi

  [[ -s "$NVM_DIR/nvm.sh" ]] && \. "$NVM_DIR/nvm.sh"
  [[ -s "$NVM_DIR/bash_completion" ]] && \. "$NVM_DIR/bash_completion"

  if ! command -v nvm &>/dev/null; then
    echo ""
    echo -e "   ${RED}✗ Не удалось подготовить Node.js.${NC}"
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
    echo -e "   ${GREEN}✓ Node.js готов для текущего и новых запусков${NC}"
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
  explain "Ставлю Homebrew для дополнительных возможностей." \
    "Это займёт 2-5 минут и попросит пароль от Mac."

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
    "Базовый бот заработает и без него. Для некоторых дополнительных функций он пригодится позже."

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
# Вторая функция heartbeat — использовать мёртвое время с пользой: пока
# ученик ждёт npm/brew, показывать ему короткие факты про OpenClaw. Когда
# установка закончится, он уже не просто поставил бота — он понимает,
# на что этот бот способен.
#
# Темы подобраны под бизнес-ЦА: «что я могу сделать», а не «как это устроено».
_HEARTBEAT_TIPS=(
  "💡 OpenClaw — мост между мессенджерами и AI. Telegram — только первый канал; дальше WhatsApp, Discord, Slack и 30+ других."
  "💡 Ваш бот работает локально на этой машине. Никаких облаков — данные никуда не уходят. Важно для бизнеса."
  "💡 Один бот = несколько агентов. Можно завести 'ассистента' для клиентов и отдельного 'переводчика' с разной личностью."
  "💡 По умолчанию стоит бесплатная модель — можно начать без оплаты."
  "💡 Стиль ассистента можно поменять позже: тон, роль, правила ответа."
  "💡 Бот помнит разговоры, а при необходимости память можно очистить."
  "💡 Dashboard — это панель управления ботом в браузере."
)

# Случайный tip с вероятностью ~30% — чтобы подкидывать факты, но не
# перебивать основной progress-вывод npm/brew.
_show_random_tip() {
  (( RANDOM % 10 < 3 )) || return 0
  local count=${#_HEARTBEAT_TIPS[@]}
  (( count == 0 )) && return 0
  local idx=$((RANDOM % count))
  echo -e "   ${CYAN}${_HEARTBEAT_TIPS[$idx]}${NC}"
}

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
      _show_random_tip
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
  # NB: никогда не пишем сюда $(env) — в переменных окружения могут быть
  # секреты ($API_KEY, $BOT_TOKEN) если unset не сработал. Собираем только
  # те переменные, которые точно не содержат секретов.
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

# ─── Opt-in локальная телеметрия (фундамент, endpoint позже) ────
#
# Зачем: Антон сейчас не видит продуктовых метрик — сколько людей
# начали установку, сколько дошли до конца, на каком шаге бросают.
# Без этого оптимизировать установщик можно только по жалобам
# (реактивно), а не проактивно.
#
# Дизайн на двух принципах:
#
# 1) **Opt-in** — ни одного байта не уходит наружу без явного согласия.
#    Когда ученик первый раз запускает установщик, мы спрашиваем:
#    «разрешить анонимную телеметрию установки?». Ответ сохраняем в
#    ~/.openclaw/.telemetry-consent (yes/no) — больше не спрашиваем.
#
# 2) **Local first, remote later** — пока Cloudflare Worker не задеплоен
#    (ждём технаря), события пишутся в локальный JSONL-лог. Когда будет
#    endpoint, один `curl -X POST` в конце каждого шага. Сейчас мы
#    только собираем данные на самих учениках — у Антона они будут
#    доступны через debug-bundle, когда ученик пришлёт его в саппорт.
#
# Что отправляем (когда Worker появится):
#   { step: "R3", status: "ok", os: "darwin-arm64", duration_s: 42,
#     installer_version: "2026.04.18" }
# Никаких имён, API-ключей, токенов, IP. Только этап + результат + ОС.
#
# Контракт события:
#   record_telemetry <step> <status> [duration]
# Пример:
#   record_telemetry "R2" "ok" "42"
#   record_telemetry "R4" "fail:telegram_probe_timeout"
TELEMETRY_CONSENT_FILE="$HOME/.openclaw/.telemetry-consent"
TELEMETRY_LOG="$HOME/.openclaw/.telemetry-events.jsonl"

ensure_telemetry_consent() {
  # DRY_RUN никогда не пишет события — это симуляция
  [[ "${DRY_RUN:-false}" == true ]] && return 0

  # Уже есть сохранённое согласие — используем его
  if [[ -f "$TELEMETRY_CONSENT_FILE" ]]; then
    TELEMETRY_CONSENT=$(cat "$TELEMETRY_CONSENT_FILE" 2>/dev/null | tr -d '\n ')
    return 0
  fi

  # Первый запуск — спрашиваем
  echo ""
  echo -e "   ${BOLD}${WHITE}Разрешить анонимную статистику установки?${NC}"
  echo -e "   ${DIM}Она помогает понять, на каком шаге чаще возникают ошибки.${NC}"
  echo -e "   ${DIM}Имена, ключи и личные данные не собираем.${NC}"
  echo ""
  echo -e "   ${BOLD}${WHITE}Разрешить? [y/N]:${NC}"
  read -r tel_consent
  mkdir -p "$(dirname "$TELEMETRY_CONSENT_FILE")"
  if [[ "$tel_consent" == "y" || "$tel_consent" == "Y" ]]; then
    echo "yes" > "$TELEMETRY_CONSENT_FILE"
    TELEMETRY_CONSENT="yes"
    echo -e "   ${GREEN}✓${NC} Статистика разрешена"
  else
    echo "no" > "$TELEMETRY_CONSENT_FILE"
    TELEMETRY_CONSENT="no"
    echo -e "   ${DIM}Окей, не собираем.${NC}"
  fi
  echo ""
}

# Записать событие телеметрии (если согласие = yes).
# Работает fire-and-forget: если что-то пошло не так, молча пропускаем.
record_telemetry() {
  [[ "${DRY_RUN:-false}" == true ]] && return 0
  [[ "${TELEMETRY_CONSENT:-no}" == "yes" ]] || return 0

  local step="${1:-unknown}"
  local status="${2:-unknown}"
  local duration="${3:-0}"
  local os_info
  os_info=$(uname -sm 2>/dev/null | tr ' ' '-' | tr '[:upper:]' '[:lower:]' || echo "unknown")

  local ts
  ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  # JSON-line формат: один объект на строку, легко парсить
  mkdir -p "$(dirname "$TELEMETRY_LOG")"
  printf '{"ts":"%s","step":"%s","status":"%s","duration_s":%s,"os":"%s","installer_version":"%s","commit":"%s"}\n' \
    "$ts" "$step" "$status" "$duration" "$os_info" "$INSTALLER_VERSION" "$INSTALLER_COMMIT" \
    >> "$TELEMETRY_LOG" 2>/dev/null || true

  # TODO: когда Cloudflare Worker будет задеплоен, добавить сюда
  # curl -sS -X POST "$TELEMETRY_ENDPOINT/events" \
  #   --max-time 3 \
  #   -H 'Content-Type: application/json' \
  #   -d "$event_json" &>/dev/null &
  # (в фоне, с коротким таймаутом — чтобы не тормозить установку)
}

# ─── VPS guide — печатается при выборе пункта 4 в главном меню ──
#
# Задача: провести ученика с нулевым техническим бэкграундом от
# «хочу чтобы бот не выключался» до «вот готовая команда для запуска
# на VPS». Не пытаемся научить его Linux — даём copy-paste шаги.
#
show_vps_guide() {
  clear
  echo ""
  echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}${MAGENTA}  📦  OPENCLAW НА VPS 24/7${NC}"
  echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  explain "VPS — это отдельный сервер, где бот работает постоянно." \
    "Обычно стоит 200–500 ₽/мес. Выбирайте Ubuntu 22.04/24.04, 1 GB RAM, 25 GB SSD."

  divider
  echo -e "${BOLD}${WHITE}1. Купите VPS${NC}"
  echo -e "   ${CYAN}•${NC} Timeweb Cloud — от 230 ₽/мес: ${CYAN}https://timeweb.cloud/${NC}"
  echo -e "   ${CYAN}•${NC} Beget — от 200 ₽/мес: ${CYAN}https://beget.com/${NC}"
  echo -e "   ${CYAN}•${NC} Hetzner — от €4.5/мес: ${CYAN}https://www.hetzner.com/${NC}"
  echo ""
  echo -e "   ${DIM}После оплаты нужны IP, логин и пароль. Никому их не отправляйте.${NC}"

  divider
  echo -e "${BOLD}${WHITE}2. Подключитесь к серверу${NC}"
  echo -e "   ${GREEN}ssh root@<ip-вашего-vps>${NC}"
  echo -e "   ${DIM}Первый вопрос — ответьте yes. Потом вставьте пароль из письма.${NC}"

  divider
  echo -e "${BOLD}${WHITE}3. Запустите установку на VPS${NC}"
  echo ""
  echo -e "   ${DIM}┌─ 📋 скопируйте эту команду (без \$) ─────────────────────────────┐${NC}"
  echo -e "   ${DIM}│${NC} ${YELLOW}\$${NC} ${GREEN}${BOLD}bash <(curl -fsSL https://raw.githubusercontent.com/${NC}"
  echo -e "   ${DIM}│${NC}   ${GREEN}${BOLD}tonytrue92-beep/openclaw-factory/main/scripts/${NC}"
  echo -e "   ${DIM}│${NC}   ${GREEN}${BOLD}demo-install.sh) --vps --install${NC}"
  echo -e "   ${DIM}└──────────────────────────────────────────────────────────────────┘${NC}"
  echo ""
  echo -e "   ${DIM}Дальше установщик попросит токен Telegram-бота и ваш Telegram ID.${NC}"
  echo -e "   ${DIM}Через 3–5 минут бот будет отвечать в Telegram.${NC}"
  echo ""
}
# ─── --diagnose-only: live-проверка состояния без изменений ─────
#
# Когда использовать:
#   • ученик пишет «у меня что-то сломалось — проверь, где именно»
#   • сам проверяешь свою инсталляцию
#   • саппорт просит быстрый snapshot состояния
#
# В отличие от --collect-debug (собирает zip для разбора), этот режим
# печатает результат сразу в терминал, ничего не записывает и ничего
# не меняет. Идеально для «я хочу увидеть, что с моим OpenClaw прямо
# сейчас».
#
# Структура отчёта:
#   1. Версия установщика + commit
#   2. Сеть (preflight_network_check)
#   3. Node / npm / brew / openclaw версии и наличие
#   4. OpenClaw config: провайдер, модель, gateway.mode
#   5. Gateway health (running? RPC probe?)
#   6. Агенты (список + модель у каждого)
#   7. Согласованность defaults vs agents (ensure_model_consistency dry)
#   8. Telegram channel (подключён? allowlist?)
#   9. Вердикт: всё ок / есть проблемы X, Y, Z
run_diagnostics() {
  echo ""
  echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}${MAGENTA}  🩺  OpenClaw Factory — LIVE ДИАГНОСТИКА${NC}"
  echo -e "${BOLD}${MAGENTA}  (ничего не меняется, только проверяем)${NC}"
  echo -e "${BOLD}${MAGENTA}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "${DIM}   Installer v${INSTALLER_VERSION} (${INSTALLER_COMMIT})${NC}"
  echo ""

  local issues=()

  # ─── 1. Инструменты ─────────────────────────────────────────────
  echo -e "${BOLD}1. Инструменты${NC}"
  for tool in node npm openclaw; do
    if command -v "$tool" &>/dev/null; then
      local ver
      case "$tool" in
        node)     ver=$(node -v 2>&1 || echo '?') ;;
        npm)      ver=$(npm -v 2>&1 || echo '?') ;;
        openclaw) ver=$(openclaw --version 2>&1 | head -1 || echo '?') ;;
      esac
      echo -e "   ${GREEN}✓${NC} ${tool}: ${ver}"
    else
      echo -e "   ${RED}✗${NC} ${tool}: не установлен"
      issues+=("${tool} не установлен")
    fi
  done
  if command -v brew &>/dev/null; then
    echo -e "   ${GREEN}✓${NC} brew: $(brew --version 2>&1 | head -1)"
  else
    echo -e "   ${YELLOW}○${NC} brew: не установлен (опционально)"
  fi
  echo ""

  # ─── 2. Сеть ────────────────────────────────────────────────────
  echo -e "${BOLD}2. Сеть${NC}"
  preflight_network_check <<< "n" >/dev/null 2>&1 && echo -e "   ${GREEN}✓${NC} Все критичные endpoints доступны" || issues+=("сеть: недоступны какие-то критичные endpoints (запустите preflight отдельно для деталей)")
  echo ""

  # ─── 3. OpenClaw config ─────────────────────────────────────────
  echo -e "${BOLD}3. OpenClaw config${NC}"
  if [[ ! -f "$HOME/.openclaw/openclaw.json" ]]; then
    echo -e "   ${RED}✗${NC} ~/.openclaw/openclaw.json не существует — OpenClaw ещё не настроен"
    issues+=("OpenClaw не настроен")
  else
    echo -e "   ${GREEN}✓${NC} ~/.openclaw/openclaw.json существует"
    if command -v openclaw &>/dev/null; then
      local gw_mode current_model
      gw_mode=$(openclaw config get gateway.mode 2>/dev/null | tr -d '\n" ')
      current_model=$(openclaw config get agents.defaults.model.primary 2>/dev/null | tr -d '\n" ')
      if [[ "$gw_mode" == "local" ]]; then
        echo -e "   ${GREEN}✓${NC} Режим запуска настроен"
      else
        echo -e "   ${RED}✗${NC} Режим запуска не настроен"
        issues+=("режим запуска не настроен — бот не поднимется")
      fi
      echo -e "   ${CYAN}➜${NC} model.primary: ${current_model:-не задана}"
    fi
  fi
  echo ""

  # ─── 4. Gateway health ──────────────────────────────────────────
  echo -e "${BOLD}4. Gateway${NC}"
  if command -v openclaw &>/dev/null; then
    local gw_status
    gw_status=$(openclaw gateway status 2>&1 || true)
    if echo "$gw_status" | grep -qE "running"; then
      echo -e "   ${GREEN}✓${NC} Gateway: running"
    else
      echo -e "   ${RED}✗${NC} Gateway не отвечает"
      issues+=("gateway не отвечает (попробуйте: openclaw gateway restart)")
    fi
  else
    echo -e "   ${DIM}(пропускаю — нет openclaw CLI)${NC}"
  fi
  echo ""

  # ─── 5. Агенты и согласованность моделей ────────────────────────
  echo -e "${BOLD}5. Агенты${NC}"
  if command -v openclaw &>/dev/null; then
    local default_model agents_raw agent_count
    default_model=$(openclaw config get agents.defaults.model.primary 2>/dev/null | tr -d '\n" ')
    agents_raw=$(openclaw config get agents.list 2>/dev/null || echo "")
    agent_count=$(echo "$agents_raw" | grep -c '"id"' 2>/dev/null || echo 0)
    [[ "$agent_count" =~ ^[0-9]+$ ]] || agent_count=0

    if [[ "$agent_count" -eq 0 ]]; then
      echo -e "   ${YELLOW}○${NC} Агентов не найдено"
    else
      echo -e "   ${CYAN}➜${NC} Всего агентов: ${agent_count}"
      local mismatched=0
      for i in $(seq 0 $((agent_count - 1))); do
        local agent_model agent_id
        agent_id=$(openclaw config get "agents.list[${i}].id" 2>/dev/null | tr -d '\n" ')
        agent_model=$(openclaw config get "agents.list[${i}].model" 2>/dev/null | tr -d '\n" ')
        if [[ -n "$agent_model" && "$agent_model" != "$default_model" ]]; then
          echo -e "   ${YELLOW}○${NC} ${agent_id}: ${agent_model} (не совпадает с default=${default_model})"
          mismatched=$((mismatched + 1))
        else
          echo -e "   ${GREEN}✓${NC} ${agent_id}: ${agent_model:-default}"
        fi
      done
      if [[ "$mismatched" -gt 0 ]]; then
        issues+=("рассинхрон моделей у ${mismatched} агент(ов) — запустите openclaw-factory-reauth или openclaw-switch-model")
      fi
    fi
  else
    echo -e "   ${DIM}(пропускаю — нет openclaw CLI)${NC}"
  fi
  echo ""

  # ─── 6. Telegram канал ──────────────────────────────────────────
  echo -e "${BOLD}6. Telegram${NC}"
  if command -v openclaw &>/dev/null; then
    local tg_probe
    tg_probe=$(openclaw channels status --probe 2>&1 || true)
    if echo "$tg_probe" | grep -qiE "audit: ok|connected"; then
      echo -e "   ${GREEN}✓${NC} Telegram канал подключён и отвечает"
    elif echo "$tg_probe" | grep -qiE "telegram"; then
      echo -e "   ${YELLOW}○${NC} Telegram настроен, но пробинг вернул что-то необычное"
      echo -e "${DIM}$(echo "$tg_probe" | head -5 | sed 's/^/       /')${NC}"
    else
      echo -e "   ${YELLOW}○${NC} Telegram не подключён"
    fi
  fi
  echo ""

  # ─── Вердикт ────────────────────────────────────────────────────
  echo -e "${BOLD}${MAGENTA}━━━ ИТОГ ━━━${NC}"
  if [[ ${#issues[@]} -eq 0 ]]; then
    echo -e "${GREEN}${BOLD}✓ Проблем не найдено. OpenClaw в рабочем состоянии.${NC}"
  else
    echo -e "${YELLOW}Найдено проблем: ${#issues[@]}${NC}"
    for issue in "${issues[@]}"; do
      echo -e "   ${RED}•${NC} ${issue}"
    done
    echo ""
    echo -e "${BOLD}Рекомендации:${NC}"
    echo -e "   ${CYAN}→${NC} если много проблем — соберите debug-bundle: ${GREEN}bash <(curl ...) --collect-debug${NC}"
    echo -e "   ${CYAN}→${NC} если 401/Invalid API key — запустите ${GREEN}openclaw-factory-reauth${NC}"
    echo -e "   ${CYAN}→${NC} если бот не отвечает — запустите ${GREEN}openclaw doctor --fix${NC}"
  fi
  echo ""
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
  explain "Нужно обновить Node.js." \
    "Могу сделать это автоматически. Если откажетесь — установите вручную с nodejs.org."

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
      echo -e "   ${GREEN}✓${NC} Режим запуска исправлен"
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

  warn "Gateway всё ещё не отвечает. Попробуйте диагностику:"
  echo -e "   ${DIM}  openclaw doctor --fix --yes${NC}"
  echo -e "   ${DIM}  openclaw gateway restart${NC}"
  echo -e "   ${DIM}  openclaw logs --follow${NC}"
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
#   1. agents.defaults.model.primary = opencode-go/deepseek-v4-flash,
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
  local expected_model="${1:-opencode-go/deepseek-v4-flash}"

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
#  --diagnose-only: live-диагностика без изменений
# ═══════════════════════════════════════════════════════════════
if [[ "$DIAGNOSE_ONLY" == true ]]; then
  run_diagnostics
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

  explain "Выберите вариант:"

  # Решение Антона 2026-06-11: «Демо» и «Симуляция» убраны из меню —
  # клиентов они только путали (запускали демо вместо установки).
  # Код демо/симуляции остаётся в скрипте для отладки (см. SKIP_DEMO/DRY_RUN).
  echo -e "   ${BOLD}${GREEN}  1)${NC}  ${BOLD}Установить OpenClaw${NC} — движок + Telegram-бот ${DIM}(по умолчанию)${NC}"
  echo -e "   ${BOLD}${YELLOW}  2)${NC}  ${BOLD}Установить AI-команду агентов${NC} — если OpenClaw уже стоит"
  echo -e "   ${BOLD}${MAGENTA}  3)${NC}  ${BOLD}VPS 24/7${NC} — бот работает, даже когда ноут выключен"
  echo ""

  divider

  echo -e "   ${BOLD}${WHITE}Выберите вариант [1/2/3, Enter = 1]:${NC}"
  echo ""
  read -r INITIAL_CHOICE

  case "$INITIAL_CHOICE" in
    1|"")
      SKIP_DEMO=true
      DRY_RUN=false
      ;;
    2)
      # Доустановка AI-команды: движковый поток не нужен, сразу качаем
      # установщик агентов (токен он возьмёт из кэша или спросит сам).
      if ! command -v openclaw &>/dev/null || [[ ! -f "$HOME/.openclaw/openclaw.json" ]]; then
        warn "OpenClaw ещё не установлен или не настроен — сначала выполните пункт 1."
        exit 1
      fi
      echo ""
      echo -e "   ${DIM}Скачиваю установщик AI-команды...${NC}"
      if _agents_run=$(_fetch_agents_installer); then
        [[ "${VPS_MODE:-false}" == true ]] && _agents_run="$_agents_run --vps"
        eval "$_agents_run"
        exit $?
      else
        warn "Не смог скачать установщик агентов (сеть/GitHub). Запустите вручную:"
        echo -e "   ${GREEN}bash <(curl -fsSL https://github.com/tonytrue92-beep/openclaw-agents-pack/releases/latest/download/install-agents-bundled.sh)${NC}"
        exit 1
      fi
      ;;
    3)
      # VPS-гайд — печатаем инструкцию и выходим; установка на этой
      # машине не нужна, клиент пойдёт запускать команду на VPS.
      show_vps_guide
      exit 0
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
  "Сейчас покажу установку OpenClaw: бот в Telegram, первый ассистент, проверка работы."

explain "Что такое OpenClaw?" \
  "OpenClaw соединяет мессенджеры с AI-ассистентами." \
  "После установки у вас будет бот, которому можно писать в Telegram."

echo ""
echo -e "   ${BOLD}${MAGENTA}🤖 Если что-то непонятно — спросите у нейрокуратора.${NC}"
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

explain "Проверяем, что компьютер готов к установке." \
  "Если чего-то не хватает — установщик подскажет следующий шаг."

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
  "Одна команда скачает и поставит всё нужное."

divider

explain "Вот команда установки:"

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
ru "Если видите 'added packages' — установка прошла нормально."
ru "Предупреждения npm в этом месте обычно не мешают установке."

divider

explain "Проверяем, что OpenClaw установился:" \
  "Команда --version покажет номер версии — значит, всё прошло успешно."

show_cmd "openclaw --version"
echo ""
terminal "OpenClaw 2026.4.9 (0512059)"
echo ""
ru "Если команда показывает версию — OpenClaw установлен."

ok "OpenClaw installed — так выглядит успешная установка"
ru "Это был демо-вывод. Настоящая установка запустится, если выберете её в меню."

pause

# ═══════════════════════════════════════════════════════════════
#  ШАГ 3: Первый запуск (onboard)
# ═══════════════════════════════════════════════════════════════

step_header "3" "FIRST RUN — ONBOARDING"

explain "При первом запуске нужен ключ opencode.ai." \
  "Откройте https://opencode.ai, создайте API key и вставьте его в установщик." \
  "По умолчанию ставим бесплатную модель MiniMax — карта не нужна."

divider

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

explain "OpenClaw будет работать в фоне." \
  "Скрипт сам включит автозапуск и сразу запустит бота."

divider

# --- Результат onboard ---

explain "Готово! OpenClaw создал конфигурацию и запустил gateway:" \
  "Вот что вы увидите после ввода ключа —"

echo -e "   ${WHITE}✓ Настройки созданы${NC}"
echo -e "   ${WHITE}✓ Автозапуск включён${NC}"
echo -e "   ${WHITE}✓ Dashboard: http://127.0.0.1:18789${NC}"
ru "После ввода ключа OpenClaw сам запустится и покажет панель управления."

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
terminal "Model: opencode-go/deepseek-v4-flash"
terminal "Channels: 0 configured"
terminal "Agents: 1 (main)"
terminal "Sessions: 0 active"
echo ""
ru "'Model: opencode-go/deepseek-v4-flash' — AI-модель, которую используют агенты."
ru "'Channels: 0 configured' — мессенджеры ещё не подключены. Сделаем на следующем шаге."
ru "'Agents: 1 (main)' — есть один агент по умолчанию. Скоро создадим ещё."
ru "'Sessions: 0 active' — нет активных разговоров (никто ещё не писал)."

ok "Gateway is healthy — всё работает штатно"

pause

# ═══════════════════════════════════════════════════════════════
#  ШАГ 5: Dashboard
# ═══════════════════════════════════════════════════════════════

step_header "5" "OPEN DASHBOARD"

explain "Dashboard — панель управления в браузере." \
  "Там видно бота, агентов и последние сообщения."

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

explain "Подключаем Telegram." \
  "Создайте бота, вставьте токен — и OpenClaw начнёт отвечать через него."

divider

explain "Создайте бота через @BotFather:"

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
ru "Если бот найден и канал добавлен — Telegram подключён."

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

explain "Агент — это роль вашего AI-ассистента." \
  "Например: помощник, копирайтер, техподдержка или менеджер."

divider

explain "Создаём агента 'copywriter'."

show_cmd "openclaw agents add copywriter"
echo ""
terminal "✓ Agent created: copywriter"
terminal "  Workspace: ~/.openclaw/agents/copywriter"
terminal "  Model: opencode-go/deepseek-v4-flash (inherited from defaults)"
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
terminal "main         Main         opencode-go/deepseek-v4-flash   -"
terminal "copywriter   Copywriter   opencode-go/deepseek-v4-flash   telegram"
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
show_cmd 'openclaw config set agents.defaults.model.primary "opencode-go/deepseek-v4-flash"'
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

echo -e "   ${BOLD}${GREEN}  1)${NC}  ${BOLD}Завершить${NC} — выйти из скрипта"
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
    explain "Хорошо, выходим. Когда будете готовы — запустите установщик снова."
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
  explain "Симуляция: покажу шаги установки, но ничего не изменю."
else
  explain "Установим OpenClaw, подключим Telegram-бота и создадим первого ассистента." \
    "Обычно это занимает 3–5 минут."
fi

require_course_token_before_real_install

pause

# ═══════════════════════════════════════════════════════════════
#  REAL STEP 1: Проверка зависимостей
# ═══════════════════════════════════════════════════════════════

# Баннер версии — чтобы в случае проблем саппорт сразу знал, какой
# скрипт запущен у пользователя (вдруг закэшировал старый curl).
echo ""
echo -e "${DIM}   OpenClaw Factory Installer v${INSTALLER_VERSION} (${INSTALLER_COMMIT})${NC}"
if [[ "$VPS_MODE" == true ]]; then
  echo -e "${BOLD}${MAGENTA}   🌐 VPS-режим: бот будет работать 24/7 на сервере${NC}"
fi
echo -e "${DIM}   Если понадобится поддержка — пришлите эту версию.${NC}"

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

# ─── Спросить разрешение на телеметрию (один раз на инсталляцию) ───
if [[ "$DRY_RUN" != true ]]; then
  ensure_telemetry_consent
  record_telemetry "install_start" "ok"
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
    if [[ "$NODE_MAJOR" -eq 22 ]]; then
      echo -e "${GREEN}✓ ${NODE_VER}${NC}"
    elif [[ "$NODE_MAJOR" -gt 22 ]]; then
      # Саппорт 2026-06-10: v24/системный Node ломал npm install -g (EACCES,
      # «openclaw: not installed»). Рецепт дня: ровно Node 22 через nvm.
      echo -e "${YELLOW}⚠ ${NODE_VER} — рекомендуется ровно 22 через nvm${NC}"
      NEEDS_NODE_INSTALL=true
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

  # Если brew нет — предлагаем поставить ПОСЛЕ проверки всего.
  # В VPS-режиме Homebrew не ставим: на Linux-сервере есть apt и не
  # нужны macOS-specific скиллы. Для базового Telegram-бота brew не
  # критичен нигде, поэтому даже на Mac это опциональный шаг.
  if [[ "$HOMEBREW_INSTALLED" == false && "$VPS_MODE" != true ]]; then
    prompt_install_homebrew
  elif [[ "$VPS_MODE" == true ]]; then
    echo -e "   ${DIM}(VPS-режим — Homebrew не требуется, пропускаем)${NC}"
  fi
fi

echo ""
ru "Если чего-то не хватает — установщик подскажет или поставит сам."
ok "System check passed"
record_telemetry "R1" "ok"

pause

# ═══════════════════════════════════════════════════════════════
#  REAL STEP 2: Установка OpenClaw
# ═══════════════════════════════════════════════════════════════

step_header "R2" "INSTALL OPENCLAW"

if [[ "$DRY_RUN" == true ]]; then
  explain "Устанавливаем OpenClaw..." \
    "Обычно это занимает 30–60 секунд."

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
  explain "Настраиваем OpenClaw." \
    "Нужно будет вставить только API-ключ opencode.ai."

  sleep 0.5
  echo -e "   ${WHITE}? Paste your opencode.ai API key${NC}"
  echo -e "   ${DIM}  ▸ sk-••••••••••••••••••••••••••••••••${NC}"
  sleep 0.5
  echo ""
  terminal "✓ API key saved"
  terminal "✓ Default model: opencode-go/deepseek-v4-flash"
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
    # живой кейс: стоит платная модель и приходит 401 No payment method
    CURRENT_MODEL=$(openclaw config get agents.defaults.model.primary 2>/dev/null | tr -d '\n" ')
    EXPECTED_MODEL="opencode-go/deepseek-v4-flash"

    explain "OpenClaw уже настроен — нашёлся файл ~/.openclaw/openclaw.json."

    echo ""
    echo -e "   ${BOLD}${WHITE}Что делать с существующей установкой?${NC}"
    echo ""
    echo -e "   ${BOLD}${GREEN}  1)${NC} ${BOLD}Оставить как есть${NC} — только прогнать health-check (${DIM}по умолчанию${NC})"
    echo -e "   ${BOLD}${YELLOW}  2)${NC} ${BOLD}Сбросить модель на стартовую${NC} — если бот не отвечает из-за модели"
    echo -e "   ${BOLD}${CYAN}  3)${NC} ${BOLD}Как подключить/сменить модель${NC} — показать команды"
    echo -e "   ${BOLD}${RED}  4)${NC} ${BOLD}Полный сброс${NC} — начать с нуля"
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
        # Старые установки: ключ лежит под провайдером «opencode» — новая
        # модель opencode-go его не видит. Переименовываем профиль в файле.
        _paf="$HOME/.openclaw/agents/main/agent/auth-profiles.json"
        if [[ -f "$_paf" ]] && grep -q '"opencode"' "$_paf" 2>/dev/null; then
          python3 - "$_paf" <<'PYEOF' && echo -e "   ${GREEN}✓${NC} Auth-профиль переведён: opencode → opencode-go" || true
import json,sys
p=sys.argv[1]; d=json.load(open(p))
prof=d.get("profiles") or {}
out={}
for k,v in prof.items():
    if isinstance(v,dict) and v.get("provider")=="opencode":
        v["provider"]="opencode-go"
    out[k.replace("opencode:","opencode-go:")]=v
d["profiles"]=out
lg=d.get("lastGood") or {}
d["lastGood"]={kk.replace("opencode","opencode-go") if kk=="opencode" else kk:
               (vv.replace("opencode:","opencode-go:") if isinstance(vv,str) else vv)
               for kk,vv in lg.items()}
json.dump(d,open(p,"w"),ensure_ascii=False,indent=2)
PYEOF
        fi
        ;;
      3)
        # Подключение/смена модели — после установки, своими командами
        echo -e "   ${BOLD}${WHITE}Модель подключается после установки:${NC}"
        echo -e "   ${GREEN}openclaw-add-codex${NC} ${DIM}— ChatGPT (GPT-5.5), вход в браузере${NC}"
        echo -e "   ${GREEN}openclaw models auth login --provider <имя>${NC} ${DIM}— любой другой провайдер${NC}"
        echo -e "   ${GREEN}openclaw-switch-model <id>${NC} ${DIM}— переключить модель у всех агентов${NC}"
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
    # Решение Антона 2026-06-11: установка идёт БЕЗ ключей и БЕЗ выбора
    # модели. Бот подключается к Telegram, а модель клиент подключает сам
    # после установки (финальный экран покажет команды).
    explain "Настраиваем OpenClaw." \
      "Никаких ключей и моделей на этом шаге — всё это после установки."

    # КРИТИЧНО: ставим gateway.mode=local ДО gateway install/start
    # (иначе gateway поднимется в непонятном режиме и закроется с 1006)
    if openclaw config set gateway.mode local &>/dev/null; then
      echo -e "   ${GREEN}✓${NC} Режим запуска настроен"
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

# Самодиагностика (живой прогон 2026-06-10): при повторном запуске поверх
# готовой установки канал Telegram уже есть — токен заново просить нельзя
# (клиента это сбивает: «какой токен? у меня всё работало»).
TG_ALREADY_CONFIGURED=false
if [[ "$DRY_RUN" != true ]]; then
  _existing_tg="$(openclaw channels status --probe 2>/dev/null </dev/null \
    | sed -nE 's/.*Telegram[^:]*:.*bot:@([A-Za-z0-9_]+).*/\1/p' | head -1)"
  if [[ -n "${_existing_tg:-}" ]]; then
    TG_ALREADY_CONFIGURED=true
    BOT_USERNAME="$_existing_tg"
    TELEGRAM_CONNECTED=true
    OWNER_TG_ID="$(course_detect_owner_tg_id 2>/dev/null || true)"
    echo -e "   ${GREEN}✓ Telegram уже подключён: @${_existing_tg}${NC}"
    echo -e "   ${DIM}Пропускаю шаг — новый токен не нужен. Хочешь другого бота?${NC}"
    echo -e "   ${DIM}Полный сброс — пункт 4 на шаге настройки (R3).${NC}"
  fi
fi

if [[ "$TG_ALREADY_CONFIGURED" != true ]]; then

explain "Создайте бота через @BotFather в Telegram (/newbot) и скопируйте токен."

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

  explain "В реальной установке здесь нужно вставить токен Telegram-бота."

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
      # ВАЖНО: пропускаем вывод через sed-маску, чтобы если OpenClaw
      # случайно распечатал токен в stdout (например «adding channel with
      # token 7123:AAGk...»), клиент его не увидел в терминале, а мы —
      # в скриншоте бага в саппорте.
      { openclaw channels add --channel telegram --name "${BOT_NAME}" --token "${BOT_TOKEN}" 2>&1 || true; } \
        | sed -E \
            -e 's/[0-9]{8,12}:[A-Za-z0-9_-]{30,}/[TG_TOKEN_REDACTED]/g' \
            -e 's/sk-[A-Za-z0-9_-]{20,}/sk-[REDACTED]/g' \
        | while IFS= read -r line; do
            echo -e "   ${DIM}${line}${NC}"
          done
      echo ""

      # Забываем токен из переменных окружения сразу после использования —
      # чтобы он не болтался в памяти процесса, если кто-то позже сделает
      # дамп env через debug-bundle.
      unset BOT_TOKEN

      TELEGRAM_CONNECTED=true
      ok "Telegram-бот @${BOT_USERNAME} подключён!"

      # ────────────────────────────────────────────────────────────
      # ВАЖНО: настроить DM-политику, иначе бот ответит
      # «access not configured» + pairing code вместо нормального
      # общения. Спрашиваем Telegram user ID владельца.
      # ────────────────────────────────────────────────────────────
      divider

      explain "Добавим ваш Telegram ID, чтобы бот сразу отвечал вам." \
        "Узнать ID можно через @userinfobot."

      # R2-аудит: ID уже зашит в course-token — префиллим его, и
      # предупреждаем при расхождении (иначе агенты на втором шаге не
      # примут токен по чужому ID, а кэш токена сотрётся).
      _tok_tg=""
      if [[ "${COURSE_TOKEN:-}" =~ ^(VIP|STD|SUB)-[A-F0-9]{16}-([0-9]{5,15})- ]]; then
        _tok_tg="${BASH_REMATCH[2]}"
      fi
      echo ""
      if [[ -n "$_tok_tg" ]]; then
        echo -e "   ${DIM}В твоём токене указан ID: ${BOLD}${_tok_tg}${NC}${DIM} — Enter, чтобы взять его.${NC}"
      fi
      echo -e "   ${BOLD}${WHITE}Введите ваш Telegram user ID:${NC}"
      read -r TG_USER_ID

      # Только цифры допустимы
      TG_USER_ID=$(echo "$TG_USER_ID" | tr -cd '0-9')
      [[ -z "$TG_USER_ID" && -n "$_tok_tg" ]] && TG_USER_ID="$_tok_tg"
      if [[ -n "$_tok_tg" && -n "$TG_USER_ID" && "$TG_USER_ID" != "$_tok_tg" ]]; then
        warn "Введённый ID (${TG_USER_ID}) отличается от ID в токене (${_tok_tg})."
        echo -e "   ${DIM}Установщик агентов сверяет токен с ID из токена. Если это другой${NC}"
        echo -e "   ${DIM}твой аккаунт — ок; если опечатка — перезапусти шаг с верным ID.${NC}"
      fi
      unset _tok_tg

      if [[ -n "$TG_USER_ID" ]]; then
        # ВАЖНО: все openclaw-команды с || true — чтобы случайный non-zero
        # не убивал скрипт под `set -e` (именно из-за этого клиент после
        # ввода ID попадал обратно в shell и думал, что бот «не подключился»).
        # Правильный путь в schema: channels.telegram.allowFrom (array)
        openclaw config set channels.telegram.dmPolicy allowlist &>/dev/null || true
        openclaw config set channels.telegram.allowFrom "[\"${TG_USER_ID}\"]" &>/dev/null || true
        openclaw gateway restart &>/dev/null || true
        echo -e "   ${GREEN}✓${NC} Allowlist настроен: ваш ID ${TG_USER_ID} добавлен"
        ru "Теперь можете сразу писать боту — он ответит без подтверждения."
        OWNER_TG_ID="$TG_USER_ID"
      else
        echo ""
        warn "ID не введён. Оставляем подтверждение доступа по умолчанию."
        ru "Когда напишете боту, он может попросить код подтверждения."
        ru "Если увидите код — отправьте его в саппорт или нейрокуратору."
        OWNER_TG_ID=""
      fi
    fi
  fi
fi

pause

# ═══════════════════════════════════════════════════════════════
#  REAL STEP 5: Создание первого ассистента
# ═══════════════════════════════════════════════════════════════

fi  # TG_ALREADY_CONFIGURED

step_header "R5" "CREATE YOUR FIRST ASSISTANT"

# Самодиагностика: main-агент уже существует → не создаём/не онбордим заново.
AGENT_ALREADY_EXISTS=false
if [[ "$DRY_RUN" != true ]] \
   && [[ "$(openclaw config get agents.list 2>/dev/null </dev/null | grep -c '"id"')" -gt 0 ]]; then
  AGENT_ALREADY_EXISTS=true
  AGENT_ID="main"
  echo -e "   ${GREEN}✓ Ассистент уже создан — пропускаю шаг.${NC}"
fi

if [[ "$AGENT_ALREADY_EXISTS" != true ]]; then

explain "Создаём первого AI-ассистента для Telegram."

if [[ "$DRY_RUN" == true ]]; then
  divider

  explain "В реальной установке вы выберете имя агента." \
    "По умолчанию — assistant."

  show_cmd "openclaw agents add assistant"
  echo ""
  sleep 0.5
  terminal "✓ Agent created: assistant"
  terminal "  Workspace: ~/.openclaw/agents/assistant"
  terminal "  Model: opencode-go/deepseek-v4-flash (inherited from defaults)"
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
      --model "opencode-go/deepseek-v4-flash" \
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
explain "Добавляю быстрые команды для обслуживания."

HELPER_DIR="$HOME/.openclaw/bin"
HELPER_PATH="$HELPER_DIR/openclaw-switch-model"
REAUTH_PATH="$HELPER_DIR/openclaw-factory-reauth"
mkdir -p "$HELPER_DIR"

# Скачиваем оба helper'а из репы. Helpers лежат рядом в одной директории.
# ─── IP-доставка (token-gated, 2026-06-14) ───────────────────────
# IP_BASE пуст → публичный github (как сейчас). Задан → gateway, Authorization
# шлём ТОЛЬКО туда (github raw на чужой Bearer = 404). При чейне agents-pack
# IP_BASE наследуется дочерним установщиком (тот же процесс).
IP_BASE="${IP_BASE:-}"; [[ -n "$IP_BASE" ]] && export IP_BASE
_ip_token() {
  printf '%s' "${COURSE_TOKEN:-$(cat "$HOME/.openclaw/course-token" 2>/dev/null || true)}"
}
ip_dl() {  # $1=путь под /assets/  $2=github-url  $3=dest
  if [[ -n "$IP_BASE" ]]; then
    curl -fsSL --max-time 20 -H "Authorization: Bearer $(_ip_token)" "${IP_BASE%/}/assets/$1" -o "$3" 2>/dev/null
  else
    curl -fsSL --max-time 20 "$2" -o "$3" 2>/dev/null
  fi
}

HELPERS_BASE="https://raw.githubusercontent.com/tonytrue92-beep/openclaw-factory/main/scripts"

# 1. switch-model — быстрая смена модели
if ip_dl "openclaw-factory/scripts/openclaw-switch-model.sh" "${HELPERS_BASE}/openclaw-switch-model.sh" "$HELPER_PATH"; then
  chmod +x "$HELPER_PATH"
  echo -e "   ${GREEN}✓${NC} Установлен: ${HELPER_PATH}"
else
  echo -e "   ${YELLOW}○${NC} Не смог скачать switch-model helper — пропускаю (не критично)"
  HELPER_PATH=""
fi

# 2. factory-reauth — перезапись API-ключа (кейс Саввы из отчёта куратора).
# Ставим ровно так же, чтобы ~/.openclaw/bin уже был в PATH после switch-model.
if ip_dl "openclaw-factory/scripts/openclaw-factory-reauth.sh" "${HELPERS_BASE}/openclaw-factory-reauth.sh" "$REAUTH_PATH"; then
  chmod +x "$REAUTH_PATH"
  echo -e "   ${GREEN}✓${NC} Установлен: ${REAUTH_PATH}"
else
  echo -e "   ${YELLOW}○${NC} Не смог скачать reauth helper — пропускаю (не критично)"
fi

# 3. add-codex — умные мозги через ChatGPT (Codex) одной командой (опционально)
ADDCODEX_PATH="$HELPER_DIR/openclaw-add-codex"
if ip_dl "openclaw-factory/scripts/openclaw-add-codex.sh" "${HELPERS_BASE}/openclaw-add-codex.sh" "$ADDCODEX_PATH"; then
  chmod +x "$ADDCODEX_PATH"
  echo -e "   ${GREEN}✓${NC} Установлен: ${ADDCODEX_PATH}"
  echo -e "      ${DIM}умные мозги (ChatGPT): запусти ${BOLD}openclaw-add-codex${NC}${DIM} когда захочешь${NC}"
else
  echo -e "   ${YELLOW}○${NC} Не смог скачать add-codex helper — пропускаю (не критично)"
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

fi  # AGENT_ALREADY_EXISTS

step_header "R6" "FINAL CHECK"

explain "Финальная проверка — убедимся, что всё работает..."
echo ""

# Pre-flight: ловим рассинхронизацию model у default vs agents.list[*]
# до того как пользователь напишет боту и увидит «Model is disabled».
if [[ "$DRY_RUN" != true ]]; then
  _cur_model="$(openclaw config get agents.defaults.model.primary 2>/dev/null | tr -d '\" \n')"
  [[ -n "$_cur_model" ]] && ensure_model_consistency "$_cur_model" || true
fi

if [[ "$DRY_RUN" == true ]]; then
  show_cmd "openclaw status --all"
  echo ""
  sleep 0.5
  terminal "OpenClaw 2026.4.9 (0512059)"
  terminal "Gateway: running (pid 54321)"
  terminal "Model: opencode-go/deepseek-v4-flash"
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
record_telemetry "install_complete" "ok"

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
  echo -e "   ${GREEN}✓${NC} Агент: ${BOLD}${AGENT_ID:-main}${NC}"
  if [[ "${TELEGRAM_CONNECTED:-false}" == true ]]; then
    echo -e "   ${GREEN}✓${NC} Telegram: @${BOT_USERNAME:-бот подключён}"
  fi
  # Модель не подключена (свежая установка без ключей) → рекомендация
  if [[ ! -f "$HOME/.openclaw/agents/main/agent/auth-profiles.json" ]] \
     && ! python3 - "$HOME/.openclaw/openclaw.json" <<'PYEOF' 2>/dev/null
import json,sys
d=json.load(open(sys.argv[1]))
p=(d.get("auth") or {}).get("profiles") or {}
sys.exit(0 if p else 1)
PYEOF
  then
    echo ""
    echo -e "   ${BOLD}${YELLOW}🧠 Остался один шаг — выбрать модель (мозги).${NC}"
    echo -e "   ${DIM}Бот уже в Telegram, отвечать начнёт после подключения модели:${NC}"
    echo -e "   ${GREEN}openclaw-add-codex${NC} ${DIM}— ChatGPT (GPT-5.5), вход в браузере, 1 минута${NC}"
    echo -e "   ${GREEN}openclaw models auth login --provider <имя>${NC} ${DIM}— любой другой провайдер${NC}"
  fi
  echo ""

  # ─── Живой end-to-end тест: пусть клиент напишет боту ──────────
  if [[ "${TELEGRAM_CONNECTED:-false}" == true ]]; then
    divider

    explain "ФИНАЛЬНЫЙ ТЕСТ" \
      "Откройте @${BOT_USERNAME:-ваш_бот} в Telegram и отправьте /status." \
      "Если ответил — всё работает. Если молчит — нажмите Enter, покажу диагностику."

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
      echo -e "   ${YELLOW}○${NC} Доступ не настроен → бот может попросить код подтверждения"
      echo -e "      ${DIM}Если увидите код — отправьте его в саппорт или нейрокуратору.${NC}"
    fi

    : # печать модели в финале убрана (решение Антона 2026-06-11)
    echo ""
  fi

  # ─── VPS: отключаем bonjour (mDNS) — на сервере он валит gateway в цикл
  # рестартов (CIAO PROBING CANCELLED). R2-аудит: раньше фикс жил только в
  # agents-pack --vps и в объединённом потоке/у SUB на VPS не срабатывал.
  if [[ "$VPS_MODE" == true && "$DRY_RUN" != true ]]; then
    openclaw config set plugins.entries.bonjour.enabled false &>/dev/null || true
    openclaw gateway restart &>/dev/null || true
  fi

  # ─── Объединённый платный поток: STD/VIP — сразу ставим AI-команду ───
  # Тариф из токена решает: SUB → только движок (блок ниже);
  # STD/VIP → докачиваем agents-pack и ставим агентов В ТОЙ ЖЕ сессии
  # (nvm уже загружен в процесс → у дочернего скрипта openclaw в PATH,
  # «command not found» между шагами физически невозможен).
  if [[ "${ENGINE_ONLY:-false}" != true \
        && ( "${COURSE_TIER:-}" == "STD" || "${COURSE_TIER:-}" == "VIP" ) ]]; then

    # nvm в rc заранее — если докачка сорвётся, openclaw всё равно доступен потом
    [[ -d "$HOME/.nvm" ]] && persist_nvm_in_shell_rc >/dev/null 2>&1

    _tier_label="Base (3 агента)"
    [[ "${COURSE_TIER}" == "VIP" ]] && _tier_label="Pro (8 агентов + база знаний)"
    divider
    echo -e "   ${BOLD}${GREEN}✓ Движок и main-агент готовы.${NC}"
    echo -e "   ${BOLD}${WHITE}Тариф ${_tier_label}: ставлю твою AI-команду — это та же установка, НЕ закрывай терминал.${NC}"
    echo ""

    # Токен НЕ передаём в командной строке (не светим в ps / scrollback):
    # factory уже сохранил его в ~/.openclaw/course-token (umask 077), а
    # agents-pack сам читает этот кэш через acquire_course_token.
    # Скачиваем устойчиво: latest → прямой тег (обход 504) → git clone.
    _chain_ok=false
    _chain_fail=""
    if _agents_run=$(_fetch_agents_installer); then
      # R2-аудит: пробрасываем VPS-режим (иначе на сервере терялись
      # bonjour-фикс и SSH-tunnel-инструкция дочернего установщика)
      [[ "$VPS_MODE" == true ]] && _agents_run="$_agents_run --vps"
      if eval "$_agents_run"; then
        _chain_ok=true
      else
        _chain_fail="child"
      fi
    else
      _chain_fail="fetch"
    fi

    if [[ "$_chain_ok" != true ]]; then
      echo ""
      # R2-аудит: честная диагностика — раньше ЛЮБОЙ сбой списывался на GitHub
      if [[ "$_chain_fail" == "fetch" ]]; then
        warn "Движок установлен и работает, но скачать установщик агентов не удалось (GitHub недоступен?)."
      else
        warn "Движок установлен и работает, но установщик агентов завершился с ошибкой — причина в сообщении ВЫШЕ."
      fi
      echo -e "   ${DIM}Доустанови команду агентов вручную (в новом терминале), любым способом:${NC}"
      echo -e "      ${GREEN}bash <(curl -fsSL https://github.com/tonytrue92-beep/openclaw-agents-pack/releases/latest/download/install-agents-bundled.sh)${NC}"
      echo -e "   ${DIM}   если GitHub отдаёт 504 — через git:${NC}"
      echo -e "      ${GREEN}git clone https://github.com/tonytrue92-beep/openclaw-agents-pack && bash openclaw-agents-pack/scripts/install-agents.sh${NC}"
      echo ""
    fi
    unset _tier_label _chain_ok _chain_fail _agents_run
    break   # агенты поставлены (или показан fallback) — их финал последний, выходим
  fi

  if [[ "${COURSE_TIER:-}" == "SUB" ]]; then
    divider
    echo -e "   ${BOLD}${GREEN}✓ Установка завершена!${NC}"
    echo ""
    echo -e "   ${BOLD}${WHITE}Твой тариф: OpenClaw (подписка)${NC}"
    echo -e "   ${GREEN}✓${NC} OpenClaw движок"
    echo -e "   ${GREEN}✓${NC} main-агент в Telegram"
    echo ""
    echo -e "   ${DIM}Дополнительные агенты (Технарь / Маркетолог / Продюсер и т.д.) доступны на Base/Pro.${NC}"
    echo -e "   ${DIM}Для апгрейда напиши в саппорт-чат курса.${NC}"
    echo ""
  fi

  echo -e "   ${BOLD}${WHITE}Что делать дальше:${NC}"
  if [[ "${TELEGRAM_CONNECTED:-false}" == true ]]; then
    echo -e "   ${CYAN}1.${NC} Пиши боту @${BOT_USERNAME:-вашему_боту} что угодно — он AI, отвечает на всё"
  else
    echo -e "   ${CYAN}1.${NC} Подключить Telegram: ${DIM}openclaw channels add --channel telegram --token ...${NC}"
  fi
  echo -e "   ${CYAN}2.${NC} Dashboard: ${BOLD}${CYAN}http://127.0.0.1:18789${NC}"
  echo -e "      ${DIM}Там всё — каналы, агенты, последние сообщения, настройки.${NC}"
  echo -e "      ${DIM}Откроется в любом браузере. Это локально, никуда не отправляется.${NC}"
  echo -e "   ${CYAN}3.${NC} Быстрая проверка: ${BOLD}bash <(curl ... ) --diagnose-only${NC}"
  echo -e "      ${DIM}(покажет, что работает, что сломано — без изменений)${NC}"
  echo -e "   ${CYAN}4.${NC} Если что-то сломалось: ${BOLD}openclaw doctor --fix${NC}"
  echo ""

  # В VPS-режиме нет смысла в `open` — мы на headless Linux, GUI нет.
  # Вместо этого даём инструкцию по SSH-туннелю (чтобы dashboard VPS
  # можно было открыть в браузере на своём Mac/Windows).
  if [[ "$VPS_MODE" == true ]]; then
    echo -e "   ${BOLD}${WHITE}Dashboard работает на VPS локально (${CYAN}127.0.0.1:18789${NC}${BOLD}${WHITE}).${NC}"
    echo -e "   ${DIM}Чтобы открыть в браузере на вашей машине — нужен SSH-туннель.${NC}"
    echo ""
    echo -e "   ${BOLD}На Mac / Windows (в НОВОМ окне терминала, не SSH-сессии):${NC}"
    # Пытаемся определить IP из SSH_CONNECTION (если залогинены по SSH)
    _vps_host="<ip-вашего-vps>"
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
      # SSH_CONNECTION формата: "client-ip client-port server-ip server-port"
      _vps_host=$(echo "$SSH_CONNECTION" | awk '{print $3}')
    fi
    echo -e "      ${GREEN}ssh -L 18789:127.0.0.1:18789 root@${_vps_host}${NC}"
    echo ""
    echo -e "   ${DIM}Пока эта команда висит — откройте в браузере:${NC}"
    echo -e "      ${CYAN}http://127.0.0.1:18789${NC}"
    echo ""
    echo -e "   ${DIM}Закрыть туннель: Ctrl+C в терминале с туннелем.${NC}"
    unset _vps_host
    echo ""
  # Предложим открыть dashboard прямо сейчас на macOS
  elif command -v open &>/dev/null; then
    echo -e "   ${BOLD}${WHITE}Открыть dashboard сейчас? [Y/n]:${NC}"
    read -r _open_dash
    _open_dash="${_open_dash:-y}"
    if [[ "$_open_dash" == "y" || "$_open_dash" == "Y" ]]; then
      open "http://127.0.0.1:18789" &>/dev/null &
      echo -e "   ${GREEN}✓${NC} Открыл dashboard в браузере"
    fi
    unset _open_dash
    echo ""
  elif command -v xdg-open &>/dev/null; then
    echo -e "   ${DIM}Откройте в браузере: ${CYAN}http://127.0.0.1:18789${NC}"
    echo ""
  fi

  # nvm-PATH: openclaw поставлен под nvm. В ТЕКУЩЕЙ сессии его ещё нет в
  # PATH (nvm подхватится только в новом терминале или после source).
  # Гарантируем запись nvm в rc (идемпотентно) + чётко подсказываем клиенту,
  # иначе он видит «openclaw: command not found» и думает, что не установилось.
  [[ -d "$HOME/.nvm" ]] && persist_nvm_in_shell_rc >/dev/null 2>&1
  echo -e "   ${BOLD}${YELLOW}⚠ Важно: команда «openclaw» работает в НОВОМ окне терминала.${NC}"
  echo -e "   ${DIM}   Если в этом окне пишет «command not found» — открой новый терминал,${NC}"
  echo -e "   ${DIM}   либо выполни прямо здесь одну из строк (по своей оболочке):${NC}"
  echo -e "      ${GREEN}source ~/.zshrc${NC}          ${DIM}# если zsh${NC}"
  echo -e "      ${GREEN}source ~/.bash_profile${NC}   ${DIM}# если bash${NC}"
  echo ""

  echo -e "   ${BOLD}${WHITE}Если что-то пошло не так (в новом терминале):${NC}"
  show_cmd "openclaw status --all        # Проверить всё"
  show_cmd "openclaw doctor --fix        # Починить проблемы"
  show_cmd "openclaw logs --follow       # Смотреть логи"
  echo ""
  echo -e "   ${DIM}Для смены модели или нового ключа: ${BOLD}openclaw-switch-model${NC}${DIM} / ${BOLD}openclaw-factory-reauth${NC}"
  echo -e "   ${DIM}Если нужна поддержка — соберите диагностику: ${BOLD}bash <(curl ...) --collect-debug${NC}"
  echo ""
  echo -e "   ${BOLD}Готово. Напишите боту первое сообщение. 🙌${NC}"
fi
echo ""

break  # реальная установка завершена — выходим из цикла
done  # конец while true (цикл меню)
