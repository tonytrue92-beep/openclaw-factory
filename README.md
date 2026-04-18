# 🤖 OpenClaw Factory

**Скрипты для установки и настройки [OpenClaw](https://openclaw.ai) — AI-шлюза, который соединяет мессенджеры с искусственным интеллектом.**

OpenClaw позволяет подключить Telegram, WhatsApp, Discord, Slack и 30+ других каналов к AI-моделям (Claude, GPT, Gemini) — и получить умных ботов-ассистентов, которые отвечают людям автоматически. Всё работает на вашем компьютере.

---

## 🚀 Быстрый старт

Одна команда — и вы в интерактивном демо с пошаговым объяснением на русском:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-factory/main/scripts/demo-install.sh)
```

> ⚠️ Не используйте `curl ... | bash` — скрипт интерактивный и требует ввода с клавиатуры.

Или клонируйте репозиторий:

```bash
git clone https://github.com/tonytrue92-beep/openclaw-factory.git
bash openclaw-factory/scripts/demo-install.sh
```

### Проверить целостность перед запуском (для параноиков)

Если вы хотите убедиться, что скачанный скрипт не подменён:

```bash
# 1) Скачать скрипт в файл (не запускать)
curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-factory/main/scripts/demo-install.sh -o demo-install.sh

# 2) Посчитать его хэш
shasum -a 256 demo-install.sh       # macOS
sha256sum demo-install.sh           # Linux

# 3) Сравнить со значением в SHA256SUMS в репе:
# https://github.com/tonytrue92-beep/openclaw-factory/blob/main/SHA256SUMS

# Хэши совпадают — запускайте:
bash demo-install.sh
```

Хэши актуальны для последнего коммита в `main` (в файле указана дата + commit).

### Что нового — [CHANGELOG.md](./CHANGELOG.md)

Смотрите этот файл, чтобы узнать, что поменялось в последней версии —
какие баги починены, какие фичи добавлены, какие breaking changes.

---

## 📖 Что внутри

### `scripts/demo-install.sh` — Демо + Установщик

Интерактивный скрипт «два в одном»:

**Часть 1 — Демо (10 шагов):**
Симуляция полного процесса установки OpenClaw. Ничего не устанавливает — только показывает, как всё работает. Каждый шаг объяснён на русском для новичков.

- Проверка системы (Node.js, npm)
- Установка OpenClaw через npm
- Первый запуск и настройка (onboard)
- Проверка gateway
- Dashboard — панель управления
- Подключение Telegram-бота
- Создание AI-агентов
- Отправка первого сообщения
- Диагностика и починка
- Шпаргалка по командам

**После демо — выбор из 3 вариантов:**

| Вариант | Что делает |
|---------|-----------|
| `1` Завершить | Выход. Установите позже самостоятельно |
| `2` Установить | Реальная установка OpenClaw + подключение Telegram-бота + создание первого ассистента |
| `3` Симуляция | Показывает процесс установки без реальных изменений. После — возврат в меню |

**Часть 2 — Реальная установка (6 шагов):**
- Проверка Node.js и npm
- Установка / обновление OpenClaw
- Интерактивная настройка (onboard)
- Ввод токена Telegram-бота (проверка через Telegram API)
- Создание агента и привязка к боту
- Финальная диагностика

**Флаги запуска:**

```bash
bash demo-install.sh              # Полный путь: демо → выбор → установка
bash demo-install.sh --install    # Пропустить демо, сразу к установке
bash demo-install.sh --dry-run    # Пропустить демо, симуляция установки
bash demo-install.sh --help       # Справка
```

---

### `scripts/install-claude-proxy.sh` — Установщик Claude Proxy

Автоматическая установка [proxy-acpx-x](https://www.npmjs.com/package/proxy-acpx-x) — обёртки над Claude Code CLI, превращающей его в OpenAI-совместимый HTTP-сервер.

```bash
# Предпросмотр (ничего не устанавливает):
bash scripts/install-claude-proxy.sh --dry-run

# Установка:
bash scripts/install-claude-proxy.sh

# Удаление:
bash scripts/install-claude-proxy.sh --uninstall
```

**Что делает:**
- Устанавливает `proxy-acpx-x` через npm
- Создаёт системный сервис (LaunchAgent на macOS / systemd на Linux)
- Регистрирует провайдер `claude-local` в OpenClaw
- Патчит SSE-поток (убирает метки инструментов из ответов)
- Настраивает таймаут LLM

---

### `docs/claude-proxy-setup.md` — Инструкция по настройке Claude Proxy

Пошаговая документация для ручной настройки Claude Proxy без скрипта.

---

### `docs/windows-install.md` — Установка на Windows через WSL2

Отдельная инструкция для пользователей Windows: как развернуть Ubuntu в WSL2 и запустить установщик внутри неё. Минимум 20 минут, включая перезагрузку.

---

## 📋 Требования

- **Node.js** >= 22.14 — [скачать с nodejs.org](https://nodejs.org)
- **npm** — идёт вместе с Node.js
- **macOS** или **Linux** (для **Windows** — см. [docs/windows-install.md](docs/windows-install.md), установка через WSL2)
- **Telegram-бот** — создаётся через [@BotFather](https://t.me/BotFather)
- **API-ключ [opencode.ai](https://opencode.ai)** — один ключ даёт доступ ко всем моделям (Claude, GPT, Gemini, Grok, Kimi, MiniMax). По умолчанию установщик ставит бесплатную `opencode/minimax-m2.5-free` (раздел **OpenCode Zen** → **MiniMax M2.5 Free**)

---

## 🔧 Полезные команды OpenClaw

```bash
openclaw status --all              # Полный отчёт о системе
openclaw gateway status            # Статус шлюза
openclaw doctor --fix              # Автопочинка проблем
openclaw logs --follow             # Логи в реальном времени
openclaw channels status --probe   # Проверка каналов
openclaw sessions cleanup          # Очистка сессий агентов
openclaw gateway restart           # Перезапуск шлюза
```

### Helper-команды (ставятся вместе с установщиком)

```bash
openclaw-switch-model                                  # интерактивное меню смены модели
openclaw-switch-model opencode/claude-sonnet-4-5       # сразу на указанную модель
openclaw-switch-model --list                           # показать все доступные
```

Helper сам меняет дефолтную модель, переписывает override'ы у всех агентов, чистит сессии и перезапускает gateway — одной командой вместо четырёх. Живёт в `~/.openclaw/bin/`.

---

## 📚 Ссылки

- [Документация OpenClaw](https://docs.openclaw.ai)
- [OpenClaw](https://openclaw.ai)

---

## 📄 Лицензия

Proprietary. Все права защищены. (c) 2026 Anton Polakov.

Просмотр кода в образовательных целях — разрешён. Копирование, модификация и коммерческое использование — только с письменного разрешения автора. Подробности в [LICENSE](LICENSE).
