# Changelog

История значимых изменений в установщике OpenClaw Factory.

Формат — по [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/):
новое сверху, старое внизу; каждое событие помечено категорией
(Added / Changed / Fixed / Security).

---

## 2026-06-11.2 — Установка без ключей и моделей (решение Антона)

- Шаг ввода API-ключа opencode.ai **удалён из установки полностью** — никаких
  упоминаний моделей в процессе. Бот подключается к Telegram, а в финале —
  рекомендация: «Остался один шаг — выбрать модель» (openclaw-add-codex /
  models auth login). Пункт existing-меню «Ввести новый API-ключ» заменён на
  «Как подключить/сменить модель» (печатает команды).

## 2026-06-11.1 — Нейтральные формулировки моделей + бридж профиля

- По решению Антона установщик не «рекомендует» модели: «Рекомендованная
  (бесплатная)» → «Стартовая модель системы»; пункт R3 «Вернуть бесплатную
  модель» → «Сбросить модель на стартовую» и заодно переводит auth-профиль
  старых установок opencode → opencode-go (ключ снова виден модели).

## 2026-06-11 — Главное меню: только боевые пункты

- «Демо» и «Симуляция» убраны из меню (решение Антона — клиенты запускали их
  вместо установки). Новое меню: **1) Установить OpenClaw** (Enter, по
  умолчанию) · **2) Установить AI-команду агентов** (движок уже стоит — сразу
  качает bundled agents-pack) · **3) VPS 24/7**. Код демо остался для отладки.

## 2026-06-10.2 — Повторный запуск поверх готовой установки

- **R4/R5 теперь самодиагностируются** (живой прогон Антона): если Telegram-канал
  уже подключён — шаг токена пропускается («✓ Telegram уже подключён: @бот»);
  если агенты уже есть в конфиге — создание ассистента пропускается. Клиент
  с готовым движком доезжает до установки агентов без единого лишнего вопроса.

## 2026-06-10.1 — Хотфикс по живому саппорту

- **P0: мёртвая дефолт-модель.** OpenClaw переименовал провайдер `opencode` →
  `opencode-go`; `opencode/minimax-m2.5-free` больше не существует («Unknown
  model» у клиентов). Дефолт → `opencode-go/deepseek-v4-flash`, provider/profile
  в auth-profiles.json → `opencode-go` (тоже в reauth/switch-model/add-codex).
- **Node ровно 22:** v24/системный Node ломал `npm install -g` (саппорт-кейсы) —
  гейт теперь предлагает автопереход на nvm+Node 22 и при major>22.

## 2026-06-10 — Cloudflare убран (решение Антона)

### Removed
- Каталог `cloudflare/` (Worker аналитики установок + D1-схема). Аналитика
  переезжает на **сервер технаря** (рядом с Prodamus-webhook) — код Worker
  сохранён как референс в `openclaw-agents-pack/handoff/analytics-endpoint-reference/`,
  спека эндпоинтов — в брифе бота. Установщики не затронуты: пинг и так
  выключен (endpoint задаётся переменной, к Cloudflare не привязан).
- lint.yml: paths/шаг node-check для worker.js.

---

## 2026-06-10 — Аудит R2: VPS-чейн, честная диагностика, HRM, TG-префилл

### Fixed
- **Чейн пробрасывает `--vps`** дочернему agents-pack (терялись headless-режим
  и SSH-tunnel-инструкция) + **factory сам отключает bonjour** на VPS до чейна
  (раньше «gateway циклически рестартится» возвращался у SUB/объединённого потока).
- **Честная диагностика чейна:** «не скачалось (GitHub)» и «установщик агентов
  завершился с ошибкой — смотри выше» различаются (раньше всё списывалось на GitHub).
- **HRM-токен** — целевое сообщение («это токен Hermes, ставится пунктом 4
  установщика агентов») вместо «формат не распознан».
- **Telegram ID** на шаге allowlist префиллится из токена (Enter = взять его),
  при расхождении — предупреждение (иначе второй шаг отверг бы токен и стёр кэш).
- Кэш токена при недоступном stat — fail-closed (chmod 600); regex подписи
  выровнен с другими репо ({80,100}).
- worker.js: `/issue` без tier не перетирает track; `/activation` заполняет
  tier (страховка для до-ботовых токенов); README cloudflare — честные шаги
  подключения пингов, `wrangler dev` без удалённого `--persist`.
- lint.yml: paths += cloudflare/docs, shellcheck глоб (add-codex теперь
  проверяется), node --check для worker.js.
- README: объединённый поток (агенты ставятся сами), полная таблица флагов,
  убран миф про onboard.

`INSTALLER_VERSION 2026.06.09 → 2026.06.10`

---

## 2026-06-09 — Аудит: харднинг Worker аналитики + чистка

### Fixed (cloudflare/worker.js)
- **CSV-инъекция** в `/stats?format=csv`: ячейки, начинающиеся с `= + - @`,
  префиксуются `'` (анти formula-injection).
- **`track`** теперь заполняется на `/issue` (из тарифа: TRY→trial, иначе paid) —
  колонка не пустует.
- ON CONFLICT-семантика задокументирована (last-write-wins; issued_at сохраняем первый).

### Removed
- `cloudflare/installer-integration.md` — устаревший док про KV/`/verify`,
  противоречил текущему D1-worker.js. (CORS/timing на admin-эндпоинтах — negligible:
  нужен `X-Admin-Key`, Worker не публичный; оставлено осознанно.)

`INSTALLER_VERSION 2026.06.06.3 → 2026.06.09` (изменения только в cloudflare/доках)

---

## 2026-06-06.3 — Фикс: `openclaw-add-codex` меняет модель у ВСЕХ агентов

### Fixed
- Реальный кейс (клиент): после подключения Codex бот «отвечал на minimax» /
  молчал, пока вручную не сменить модель. Причина — `models set`/`--set-default`
  меняли только `agents.defaults.model.primary`, а у каждого агента в
  `agents.list[]` оставался свой override (minimax с установки).
- Шаг 4 хелпера теперь зовёт `openclaw-switch-model` (или эквивалентный inline-
  fallback): меняет модель у **default + каждого агента**, чистит сессии,
  рестартит gateway. Бот сразу отвечает на ChatGPT-модели.

`INSTALLER_VERSION 2026.06.06.2 → 2026.06.06.3`

---

## 2026-06-06.2 — Хелпер `openclaw-add-codex` (умные мозги ChatGPT одной командой)

### Added
- Хелпер **`openclaw-add-codex`** (ставится в `~/.openclaw/bin/`): опционально
  подключает ChatGPT/Codex одной командой — ставит Codex-плагин
  (`clawhub:@openclaw/codex` → npm fallback), enable + registry refresh,
  рестарт gateway, вход `models auth login --provider openai` (для 2026.6.x;
  `openai-codex` — legacy), модель `openai/gpt-5.5`. Opt-in, обязательный поток
  установки не трогает — при неудаче бесплатная модель остаётся рабочей.
- Флаги хелпера: `--device-code` (VPS/без браузера), `--provider <id>` (override),
  позиционный аргумент = модель.

### Почему так
Реальный кейс (клиент, OpenClaw 2026.6.1): `--provider openai-codex` падал
(«No provider plugins found»). На 2026.6.x вход в ChatGPT — через provider
`openai`; `openai-codex` стал legacy-именем. Codex — отдельный runtime-плагин.

`INSTALLER_VERSION 2026.06.06.1 → 2026.06.06.2`

---

## 2026-06-06.1 — Устойчивая дотяжка агентов (обход 504 GitHub)

### Fixed
- Чейн STD/VIP качал агентов только через `releases/latest/download/…`. Когда
  GitHub отдаёт **504 на редиректе `/latest/`** — установка агентов срывалась.
  Добавлен `_fetch_agents_installer`: `latest` → **прямой тег** (через GitHub
  API) → **git clone**. Fallback-сообщение теперь даёт и git-clone-команду.

`INSTALLER_VERSION 2026.06.06 → 2026.06.06.1`

---

## 2026-06-06 — Объединённый платный установщик (одна команда)

### Changed
- При тарифе **STD/VIP** в финале R6 factory **сам докачивает и запускает**
  `install-agents-bundled.sh` (agents-pack) с тем же `--course-token` — клиент
  ставит движок + агентов **одной командой**. Агенты ставятся в той же
  сессии терминала, поэтому `command not found` между шагами исключён.
- **SUB** — без изменений: только движок + main-агент.
- Demo / симуляция / dry-run агентов не тянут.

### Added
- Флаг `--engine-only` — отключить дотяжку агентов (отладка / переустановка движка).

### Fixed
- Если докачка агентов сорвётся (сеть/CDN) — движок уже установлен, скрипт не
  падает, показывает ручную команду-fallback.

`INSTALLER_VERSION 2026.06.04.1 → 2026.06.06`

---

## 2026-06-04 — Фикс: «openclaw: command not found» после установки

### Триггер

Клиент (bash): после успешной установки `openclaw` не вызывается в
терминале — `bash: openclaw: command not found`. Gateway при этом работает
(он launchd-сервис), но интерактивный shell не видит `openclaw`, т.к. он
стоит под **nvm**, а PATH в текущей сессии не обновлён.

### Fixed
- В финале установщик теперь **всегда** прописывает nvm в shell-rc
  (`persist_nvm_in_shell_rc`, идемпотентно) — на случай, если node уже стоял
  через nvm и rc не был обновлён.
- Добавлена **чёткая подсказка**: команда `openclaw` работает в НОВОМ окне
  терминала; в текущем — `source ~/.zshrc` (zsh) или `source ~/.bash_profile`
  (bash). Раньше финал показывал `openclaw …`-команды без предупреждения, и
  клиент думал, что установка не удалась.

`INSTALLER_VERSION 2026.06.04 → 2026.06.04.1`

---

## 2026-06-04 — Откат: шаг «мозги» вернули на opencode-ключ (фикс блокера)

### Fixed
- **Регрессия Codex-входа.** Шаг «мозги» через `openclaw models auth login
  --provider openai-codex` падал на **свежей** машине клиента:
  `Error: No provider plugins found` — стоковый провайдер-плагин ещё не
  загружен на чистой установке. Плюс вызов несуществующей в factory функции
  `err` валил скрипт (`err: command not found`, exit 127).
- **Откат** шага «мозги» к проверенному потоку: ключ opencode.ai →
  `auth-profiles.json` напрямую (не использует `models auth login` /
  провайдер-плагины, поэтому не зависит от их состояния). Это разблокирует
  платную установку немедленно.
- Авто-обновление движка до `openclaw@latest` сохранено (оно было до Codex).
- ChatGPT Codex-вход вернём отдельно, когда проверим на чистой машине
  (нужно гарантировать наличие провайдер-плагина перед `models auth login`).

`INSTALLER_VERSION 2026.06.03.1 → 2026.06.04`

---

## 2026-06-03 — Codex-вход: не открываем свою вкладку (UX-уточнение)

### Changed
- На шаге «мозги» установщик **больше не открывает** chatgpt.com своей
  вкладкой. Настоящую ссылку/код для входа показывает сам
  `openclaw models auth login` — клиент открывает именно её. Раньше две
  ссылки (наша chatgpt.com + ссылка из команды) путали клиента.
- Текст переписан: «ссылку для входа покажет САМ установщик строкой ниже»;
  chatgpt.com упомянут только как место регистрации, без авто-открытия.

`INSTALLER_VERSION 2026.06.03 → 2026.06.03.1`

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
