# OpenClaw Factory — Token Gateway

Cloudflare Worker для проверки токенов курса перед установкой OpenClaw.

## Архитектура

```
Клиент запускает install.sh
        │
        ▼
Скрипт просит токен курса (например: OC-A7K2-MQNX-R4PZ)
        │
        ▼
POST https://auth.openclaw.ai/verify  ──► Cloudflare Worker
        │                                        │
        │                                        ▼
        │                                 KV: OPENCLAW_TOKENS
        │                                 ищет по токену
        │                                        │
        │  {ok:true, user:"Григорий"} ◄──────────┘
        │
        ▼
Установка идёт дальше
```

## Что внутри

| Файл | Назначение |
|------|-----------|
| `worker.js` | Код Worker (verify + admin/issue + admin/revoke) |
| `wrangler.toml` | Конфиг для деплоя через wrangler |
| `installer-integration.md` | Как встроить проверку в demo-install.sh |
| `README.md` | Этот файл |

## Быстрый деплой

```bash
# 1. Поставить wrangler
npm install -g wrangler

# 2. Залогиниться в Cloudflare
wrangler login

# 3. Создать KV namespace для хранения токенов
wrangler kv:namespace create OPENCLAW_TOKENS
# → получишь id, вставить в wrangler.toml

# 4. Задать секрет для админки
wrangler secret put ADMIN_SECRET
# → ввести длинную случайную строку (минимум 32 символа)

# 5. Задеплоить
wrangler deploy
```

После деплоя Worker доступен по адресу типа:
`https://openclaw-factory-auth.<аккаунт>.workers.dev`

## Выпуск первого токена

```bash
export ADMIN_SECRET="тот-секрет-что-ввёл-на-шаге-4"
export WORKER_URL="https://openclaw-factory-auth.<аккаунт>.workers.dev"

curl -X POST "$WORKER_URL/admin/issue" \
  -H "X-Admin-Key: $ADMIN_SECRET" \
  -H "Content-Type: application/json" \
  -d '{
    "user": "Тестовый Ученик",
    "email": "test@example.com",
    "maxActivations": 3,
    "expiresAt": "2027-04-16T00:00:00Z"
  }'
```

Ответ:
```json
{
  "ok": true,
  "token": "OC-A7K2-MQNX-R4PZ",
  "record": {
    "user": "Тестовый Ученик",
    "maxActivations": 3,
    "activations": 0,
    ...
  }
}
```

Токен `OC-A7K2-MQNX-R4PZ` отдаёшь ученику.

## Стоимость

| Что | Лимит Free | Твой объём |
|-----|-----------|------------|
| Worker requests | 100 000 / день | ~100 активаций/день = 0.1% |
| KV reads | 100 000 / день | ~3 read на активацию = минимум |
| KV writes | 1 000 / день | ~3 write на активацию |
| KV storage | 1 GB | 1 токен ≈ 200 байт → 5M токенов в лимит |

При твоих объёмах (сотни учеников в год) **бесплатно навсегда**.

## Что если Worker упадёт

Cloudflare SLA — 99.9%+ аптайм. Но даже если упадёт:
- Старые ученики (с сохранённым токеном в `~/.openclaw/.course-token`) смогут переустанавливать свою версию OpenClaw через `openclaw` CLI без участия Worker
- Новые ученики получат понятную ошибку «сеть недоступна» и смогут повторить через 5 минут

## Безопасность

- `ADMIN_SECRET` хранится только на стороне Cloudflare, **не в git**
- Токены ученикам — не предсказуемы (рандом из 32-буквенного алфавита без похожих символов)
- Формат `OC-XXXX-XXXX-XXXX` — легко диктовать по телефону
- Rate limit на `/verify` — делается отдельно через Cloudflare Dashboard (если пойдёт брут)
