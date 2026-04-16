# Интеграция токен-проверки в установщик

Небольшой патч к `scripts/demo-install.sh` — после меню выбора пункта, но **до** начала реальной установки.

## Место вставки

После того, как пользователь выбрал пункт `2` (реальная установка), но до `step_header "R1" "SYSTEM CHECK"`.

## Код для вставки

```bash
# ═══════════════════════════════════════════════════════════════
#  ПРОВЕРКА ТОКЕНА КУРСА
# ═══════════════════════════════════════════════════════════════

AUTH_ENDPOINT="${OPENCLAW_AUTH_URL:-https://openclaw-factory-auth.YOUR-ACCOUNT.workers.dev}"

verify_token() {
  local token=""
  local attempts=0
  local max_attempts=3

  echo ""
  echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${BOLD}${CYAN}  🔐 ТОКЕН ДОСТУПА${NC}"
  echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo -e "   ${DIM}Для установки OpenClaw Factory нужен токен курса.${NC}"
  echo -e "   ${DIM}Формат: ${BOLD}OC-XXXX-XXXX-XXXX${NC}"
  echo -e "   ${DIM}Токен пришёл вам на почту после оплаты курса.${NC}"
  echo ""

  while (( attempts < max_attempts )); do
    read -r -p "   Введите токен: " token
    token=$(echo "$token" | tr -d '[:space:]')

    if [[ -z "$token" ]]; then
      echo -e "   ${RED}✗${NC} Пустой токен. Попробуйте ещё раз."
      ((attempts++))
      continue
    fi

    echo ""
    echo -e "   ${DIM}Проверяем токен...${NC}"

    local response
    response=$(curl -fsSL --max-time 10 \
      -H "Content-Type: application/json" \
      -X POST \
      -d "{\"token\":\"$token\"}" \
      "${AUTH_ENDPOINT}/verify" 2>&1 || echo '{"ok":false,"error":"network"}')

    local ok
    ok=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print('yes' if d.get('ok') else 'no')" 2>/dev/null || echo "no")

    if [[ "$ok" == "yes" ]]; then
      local user activations max
      user=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('user','студент'))" 2>/dev/null || echo "студент")
      activations=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('activations','?'))" 2>/dev/null || echo "?")
      max=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('max','?'))" 2>/dev/null || echo "?")

      echo -e "   ${GREEN}✓${NC} Токен принят."
      echo -e "   ${GREEN}✓${NC} Добро пожаловать, ${BOLD}${user}${NC}!"
      echo -e "   ${DIM}   Активация ${activations} из ${max}.${NC}"
      echo ""

      # Сохраняем токен локально, чтобы при повторном запуске не спрашивать
      mkdir -p "$HOME/.openclaw"
      echo "$token" > "$HOME/.openclaw/.course-token"
      chmod 600 "$HOME/.openclaw/.course-token"

      export OPENCLAW_COURSE_TOKEN="$token"
      export OPENCLAW_COURSE_USER="$user"
      return 0
    fi

    # Разбор ошибок
    local err
    err=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('error','unknown'))" 2>/dev/null || echo "unknown")

    case "$err" in
      invalid_token)
        echo -e "   ${RED}✗${NC} Токен не найден. Проверьте правильность (регистр, дефисы)."
        ;;
      expired)
        echo -e "   ${RED}✗${NC} Срок действия токена истёк. Напишите в поддержку."
        return 1
        ;;
      revoked)
        echo -e "   ${RED}✗${NC} Токен отозван. Напишите в поддержку."
        return 1
        ;;
      limit_reached)
        echo -e "   ${RED}✗${NC} Лимит активаций исчерпан. Напишите в поддержку."
        return 1
        ;;
      network)
        echo -e "   ${RED}✗${NC} Не могу проверить токен — проблемы с сетью."
        echo -e "   ${DIM}   Проверьте интернет и попробуйте снова.${NC}"
        ;;
      *)
        echo -e "   ${RED}✗${NC} Ошибка проверки: $err"
        ;;
    esac

    ((attempts++))
    echo -e "   ${DIM}Осталось попыток: $((max_attempts - attempts))${NC}"
    echo ""
  done

  echo -e "   ${RED}✗${NC} Превышено число попыток ввода токена."
  echo -e "   ${DIM}Получить токен: напишите Антону в поддержку.${NC}"
  return 1
}

# Проверяем — если токен уже сохранён локально, используем его
if [[ -f "$HOME/.openclaw/.course-token" ]] && [[ -s "$HOME/.openclaw/.course-token" ]]; then
  SAVED_TOKEN=$(cat "$HOME/.openclaw/.course-token")
  echo ""
  echo -e "   ${DIM}Найден сохранённый токен.${NC}"
  read -r -p "   Использовать его? [Y/n]: " USE_SAVED
  if [[ ! "$USE_SAVED" =~ ^[Nn] ]]; then
    # Перепроверяем — может быть отозван
    RESPONSE=$(curl -fsSL --max-time 10 \
      -H "Content-Type: application/json" \
      -X POST -d "{\"token\":\"$SAVED_TOKEN\"}" \
      "${AUTH_ENDPOINT}/verify" 2>&1 || echo '{"ok":false}')
    if echo "$RESPONSE" | grep -q '"ok":true'; then
      echo -e "   ${GREEN}✓${NC} Сохранённый токен действителен."
      export OPENCLAW_COURSE_TOKEN="$SAVED_TOKEN"
    else
      verify_token || exit 1
    fi
  else
    verify_token || exit 1
  fi
else
  verify_token || exit 1
fi
```

## Почему так

- **3 попытки** на ввод токена — защита от брутфорса без полной блокировки при опечатке
- **Сохранение токена локально** в `~/.openclaw/.course-token` — при повторном запуске установщика не нужно вводить заново (актуально при «3-й активации после переустановки»)
- **`--max-time 10`** — если Worker не отвечает, не виснем навсегда
- **Счётчик активаций** — ученик видит «активация 2/3», понимает, что остаётся запас
- **Фоллбек через `OPENCLAW_AUTH_URL`** — в dev-режиме Антон может указать свой endpoint

## Как выдавать токены (админская часть)

```bash
# Выпустить токен для нового ученика
curl -X POST https://openclaw-factory-auth.YOUR.workers.dev/admin/issue \
  -H "X-Admin-Key: ВАШ_АДМИН_СЕКРЕТ" \
  -H "Content-Type: application/json" \
  -d '{
    "user": "Григорий Конев",
    "email": "gregory@example.com",
    "maxActivations": 3,
    "expiresAt": "2027-04-16T00:00:00Z"
  }'

# Ответ:
# {
#   "ok": true,
#   "token": "OC-A7K2-MQNX-R4PZ",
#   "record": { ... }
# }
```

## Как отозвать токен

```bash
curl -X POST https://openclaw-factory-auth.YOUR.workers.dev/admin/revoke \
  -H "X-Admin-Key: ВАШ_АДМИН_СЕКРЕТ" \
  -H "Content-Type: application/json" \
  -d '{"token": "OC-A7K2-MQNX-R4PZ"}'
```

## Как посмотреть всех учеников

Через Cloudflare Dashboard → Workers → KV → OPENCLAW_TOKENS → видишь все записи в UI.

Или через API:
```bash
wrangler kv:key list --binding OPENCLAW_TOKENS
```

## Итого

- Репозиторий остаётся **публичным** (код любой может читать)
- Установщик сам по себе без токена **не работает** (выходит с ошибкой на этапе верификации)
- Ты полностью контролируешь, кто может устанавливать и сколько раз
- Отозвать можно моментально
- Лимит Cloudflare Workers (100k req/день, 1000 KV writes/день) для тебя — с запасом на годы вперёд

## Порядок интеграции

1. Задеплой Worker (инструкция в `wrangler.toml`)
2. Создай 1 тестовый токен через `/admin/issue`
3. Вставь блок verify_token в `demo-install.sh`
4. Протестируй: с правильным токеном / с неправильным / с отозванным / без интернета
5. Только после успешного теста — продавай курс с этой системой
