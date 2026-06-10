# Install analytics Worker (Cloudflare + D1)

Считает **кто и сколько ставил** установщики AI TEAM + связывает установку с
**email** (привязан к токену при оплате). Склейка по `sha256(токена)`.

## Как это работает

```
  БОТ @AITeamVIPBot ── POST /issue ──→┐ {token_hash, tg_id, email, tier}
  (при выдаче токена)                 │
                                      ├─ D1 (таблица installs, ключ token_hash)
  УСТАНОВЩИК ──────── POST /activation┘ {token_hash, tg_id, installer_version, client_os, track}
  (при установке)
                                      ↓
  АНТОН ──────────── GET /stats ──────→ email + tg_id + тариф + версия + ОС + когда + счётчик
```

- Установщик **не знает email** — он приходит только от бота через `/issue`.
- Храним **хэш** токена, не сырой токен.
- `/activation` обновляет только уже `/issue`-нутые строки → мусором не засорить.

## Эндпоинты

| Метод / путь | Кто | Заголовок | Тело |
|---|---|---|---|
| `POST /issue` | бот | `X-Admin-Key: <ADMIN_SECRET>` | `{token_hash, tg_id, email, tier}` |
| `POST /activation` | установщик | — | `{token_hash, tg_id, installer_version, client_os, track}` |
| `GET /stats` | Антон | `X-Admin-Key: <ADMIN_SECRET>` | — (`?format=csv` для выгрузки) |
| `GET /health` | — | — | — |

## Деплой (нужен аккаунт Cloudflare)

```bash
cd cloudflare
npm install -g wrangler
wrangler login

# 1. База D1
wrangler d1 create aiteam-installs
#    → скопировать выданный database_id в wrangler.toml ([[d1_databases]].database_id)
wrangler d1 execute aiteam-installs --remote --file=schema.sql

# 2. Секрет (длинная случайная строка — её же дать боту для /issue и себе для /stats)
wrangler secret put ADMIN_SECRET

# 3. Деплой
wrangler deploy
#    → получишь URL: https://aiteam-installs.<аккаунт>.workers.dev
```

## После деплоя
1. Дать **URL Worker** разработчику установщиков. Сейчас пинг реализован в
   agents-pack: дефолт `VIP_ACTIVATION_ENDPOINT` **пуст** (no-op) — подставить
   `https://<worker>/activation` в `scripts/lib/vip.sh` (1 строка) и
   перевыпустить bundled. Пинги в factory/trial добавляются тем же шагом
   (задача H5; пока их в коде нет).
2. Дать **URL + ADMIN_SECRET** технарю для бота (см.
   `openclaw-agents-pack/handoff/install-analytics-bot-brief.md`).

## Проверка
```bash
W=https://aiteam-installs.<аккаунт>.workers.dev
curl -s $W/health
curl -s -X POST $W/issue -H "X-Admin-Key: <ADMIN_SECRET>" -H 'Content-Type: application/json' \
  -d '{"token_hash":"test1","tg_id":"1","email":"a@b.com","tier":"VIP"}'
curl -s -X POST $W/activation -H 'Content-Type: application/json' \
  -d '{"token_hash":"test1","tg_id":"1","installer_version":"2026.06.06","client_os":"darwin-arm64","track":"paid"}'
curl -s "$W/stats?format=csv" -H "X-Admin-Key: <ADMIN_SECRET>"
```
Ожидаемо: в CSV строка вида `"a@b.com","1","VIP","paid",...,"1"` (все поля в
кавычках) — email/tier/track заполнены, activation_count = 1.

## Локальный тест (без деплоя)
```bash
cd cloudflare
wrangler d1 execute aiteam-installs --local --file=schema.sql
echo 'ADMIN_SECRET=testkey' > .dev.vars
wrangler dev   # локальный режим — дефолт в wrangler 3+; http://127.0.0.1:8787
# затем те же curl, но на localhost:8787 и X-Admin-Key: testkey
```

> Прежняя версия Worker (KV, проверка `OC-`токенов) заменена на аналитику D1.
> Серверный токен-гейтинг (`/verify` с лимитом активаций) — отдельная будущая
> возможность; сейчас токены проверяются локально (Ed25519) в установщиках.
