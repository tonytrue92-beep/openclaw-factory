# Changelog

История значимых изменений в установщике OpenClaw Factory.

Формат — по [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/):
новое сверху, старое внизу; каждое событие помечено категорией
(Added / Changed / Fixed / Security).

---

## 2026-06-03 — Brain via ChatGPT Codex login (вместо opencode-ключа)

### Changed
- Шаг «мозги» (R3) теперь подключает модель через **вход в аккаунт
  ChatGPT** (`openclaw models auth login --provider openai-codex
  --set-default`) вместо запроса API-ключа opencode.ai. Клиент логинится
  своим ChatGPT (бесплатного достаточно; ChatGPT Plus $20 — умнее),
  `--set-default` сам ставит рекомендованную Codex-модель (GPT-5.4/5.5).
- На `--vps` используется `--device-code` (вход по коду с любого
  устройства). Нужен интерактивный TTY (есть при обычной установке).
- Демо-нарратив (R3 / onboard preview / preview-команда) переписан под
  вход в ChatGPT — простым языком, с пояснением про аккаунт.

### Почему это безопасно для мульти-агента
OAuth-креды OpenClaw **глобальные** — их автоматически видят все агенты
(проверено: не-дефолтные агенты видят `openai-codex` без своего профиля).
Поэтому второй установщик (agents-pack) ничего копировать не должен —
Base/Pro агенты получают Codex-мозги сами.

### ⚠️ Требует живой проверки
Сам OAuth-флоу (завершение входа в ChatGPT) статически не тестируется —
проверить на чистой машине: установка → вход в ChatGPT → агент отвечает.

`INSTALLER_VERSION 2026.05.25 → 2026.06.03`

---

## 2026-05-25 — Wave 20 (public tier rebrand)

### Changed
- Публичные названия тарифов в `scripts/demo-install.sh` приведены к
  новой линейке: `STD` → **Base**, `VIP` → **Pro**, `SUB` →
  **OpenClaw**. Внутренние `COURSE_TIER`/payload-префиксы
  `SUB`/`STD`/`VIP` не менялись, чтобы старые токены продолжали работать.
- Help и финальный экран SUB-установки больше не показывают старый
  нейминг клиенту.

---

## 2026-04-18 — Wave 4 (VPS deployment)

### Added
- **Пункт 4 «Развернуть на VPS сервере»** в главном меню установщика.
  Показывает пошаговый гайд для ученика с нулевым техбэкграундом: как
  выбрать VPS (Timeweb / Beget / Hetzner / DigitalOcean с ценами), как
  подключиться по SSH (инструкции для Mac и Windows), какую команду
  запустить на VPS, как отключиться без потери бота.
- **Флаг `--vps` / `--headless`** — режим установки на Linux-сервер:
  пропускает macOS-специфичные шаги (Homebrew, xcode-select, admin-check),
  не пытается открыть браузер через `open`/`xdg-open`, в post-install
  даёт готовую SSH-tunnel команду для dashboard (с автоопределением IP
  из `$SSH_CONNECTION`).
- **`docs/vps-install.md`** — полный гайд (300+ строк): провайдеры,
  тарифы, SSH, troubleshooting, FAQ, чек-лист для распечатки.

### Команда для VPS
```bash
# На самом VPS после SSH:
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/\
openclaw-factory/main/scripts/demo-install.sh) --vps --install
```

---

## 2026-04-18 — Wave 3 (observability++ и безопасность)

### Security
- Автоматически `unset` для `API_KEY` после записи в auth-profiles.json
  и `BOT_TOKEN` после подключения Telegram-канала — чтобы секреты не
  висели в памяти процесса до конца работы установщика.
- Вывод `openclaw channels add --token ...` пропускается через inline-маску,
  чтобы даже если CLI случайно распечатает токен в stdout — клиент не
  увидел его в терминале (и мы не в скриншоте бага в саппорте).
- `SHA256SUMS` в корне репо с хэшами всех скриптов + инструкция в README,
  как проверить целостность перед запуском (для B2B/параноиков).
- CI-job `security-audit` — 5 статических проверок: direct echo секретов,
  env-дампы в debug-bundle, пропущенный unset, реальные токены в коде,
  redact_secrets на всех файлах bundle.
- CI-job `checksums` — автоматически проверяет, что `SHA256SUMS` актуален
  (если нет — PR не вмерджится).

### Added
- Флаг `--collect-debug` — сборка debug-bundle без TTY, для саппорта.
- Флаг `--version` — быстрая проверка версии установщика.
- Preflight network check: 5-секундная проверка доступности
  `registry.npmjs.org`, `raw.githubusercontent.com`, `opencode.ai`,
  `api.telegram.org` ДО начала установки. Конкретный диагноз при
  блокировке (прокси / VPN / DNS / регион).
- Trap на ERR: при любом падении автоматически собирается
  `~/openclaw-debug-YYYYMMDD-HHMMSS.zip` со всей диагностикой.
- `redact_secrets` — маскировка sk-ключей, Telegram-токенов,
  Bearer-токенов, password-полей в JSON.
- Helper `openclaw-factory-reauth` — одна команда для перезаписи
  auth-profile (кейс Саввы: «HTTP 401 Invalid API key» даже после
  `configure --section model`).
- GitHub Actions CI: shellcheck, `bash -n`, smoke-тесты функций,
  security-audit, проверка свежести `SHA256SUMS`.

### Changed
- `INSTALLER_VERSION` + `INSTALLER_COMMIT` в заголовке каждого экрана.
  При запуске из git-checkout автоматически подставляется реальный hash.

---

## 2026-04-17 — Wave 2 (UX hardening + hotfix Homebrew)

### Fixed
- **Критический hotfix**: `install_homebrew` зависал намертво при попытке
  нажать `Press RETURN/ENTER to continue`. Причина — Homebrew-скрипт был
  обёрнут в `... | tail -10 | while IFS= read -r line`, что разрывало
  его stdin (pipe вместо TTY) и буферизовало первые строки (пользователь
  не видел приглашения). Теперь установщик Homebrew запускается напрямую,
  без pipe. Решение зафиксировано как правило в decisions-log #14.

### Added (по отчёту куратора 2026-04-17)
- `heartbeat` на длинных шагах (npm/brew install) — раз в 30 секунд
  печатает «я жив», через 5 минут советует Ctrl+C.
- Pre-check admin-прав macOS перед Homebrew + понятное меню skip/switch.
- Предупреждение про невидимый sudo-пароль ДО запуска (самый массовый
  источник «скрипт завис» — люди не знали, что нужно печатать вслепую).
- Проверка `xcode-select -p` после Homebrew + подсказка перезапустить
  терминал, если Command Line Tools не подхватились.
- Раздельная диагностика `npm EACCES`: глобальная установка (`/usr/local`)
  vs `~/.npm` ownership — разные команды под каждый случай.
- `ensure_model_consistency` — синхронизация `agents.defaults.model.primary`
  с `agents.list[*].model` (кейс Елены: «выбрал MiniMax, но Model is disabled»).
- Troubleshooting пункты 10 (Model is disabled), 12 (npm EACCES), 13 (sudo
  пароль невидимый), 14 (команда `--collect-debug`).

---

## 2026-04-16 — Initial release

### Added
- Установщик OpenClaw с нуля одной bash-командой.
- Интерактивный flow: демо (10 шагов объяснения на русском) → меню выбора
  (демо / реальная установка / симуляция) → 6 реальных фаз R1-R6.
- Обход известных багов OpenClaw CLI: `onboard` не вызывается (падает с
  `TypeError: Cannot read properties of undefined (reading 'trim')`),
  `gateway.mode=local` выставляется явно (иначе `1006 abnormal closure`).
- Helper `openclaw-switch-model` — быстрая смена модели одной командой,
  ставится в `~/.openclaw/bin/`.
- Бесплатная модель по умолчанию: `opencode/minimax-m2.5-free`
  (без привязки карты).
- Stale-config handling: меню из 4 пунктов если обнаружен существующий
  `~/.openclaw/openclaw.json` (оставить / сменить модель / новый ключ /
  полный сброс).
- Post-install подсказки на 5 типовых вопросов: сменить модель, изменить
  характер агента, подключить WhatsApp/Discord, завести второго агента,
  где хранятся конфиги.
- Troubleshooting на 10 частых проблем с готовыми командами-фиксами.
- Публичный GitHub-репо, Proprietary-лицензия.
- Cloudflare Worker (код готов, не задеплоен) для будущего
  токен-гейтинга установщика.
- Windows-поддержка через WSL2 (`docs/windows-install.md`).

---

## Планируется (roadmap)

Всё что в разработке, но ещё не вошло — см. `04-pending-tasks.md` в handoff.
Главное:

- Деплой Cloudflare Worker + интеграция `verify_token` в установщик.
- Telegram-бот для автоматических продаж (после первых 10-20 ручных выдач).
- Docker smoke-тесты на чистых `node:22-bookworm` / `node:22-alpine`.
- Opt-in telemetry (пока локально логируется, endpoint позже).
- Режим `--diagnose-only` (live-проверка без изменений).
