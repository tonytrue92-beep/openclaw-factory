# 🪟 Установка OpenClaw на Windows

Установщик написан на bash и требует Linux-среду. На Windows это решается через **WSL2** (Windows Subsystem for Linux) — официальный способ от Microsoft.

Инструкция рассчитана на Windows 10 (сборка 19041+) и Windows 11. Для более старых версий Windows этот путь не подходит.

---

## ⏱️ Займёт около 15–20 минут

Разделено на 4 части:

1. Включить WSL2 и поставить Ubuntu (5–10 минут, с перезагрузкой)
2. Поставить Node.js внутри Ubuntu (3 минуты)
3. Запустить установщик OpenClaw (5 минут)
4. Проверить, что бот работает (2 минуты)

---

## Часть 1 — Поставить WSL2 + Ubuntu

### 1.1 Открыть PowerShell от имени администратора

- Нажать на кнопку Пуск
- Набрать `powershell`
- Нажать правой кнопкой на **Windows PowerShell** → **Запуск от имени администратора**

### 1.2 Установить WSL одной командой

В открывшемся синем окне PowerShell ввести:

```powershell
wsl --install -d Ubuntu
```

Система скачает и установит:
- ядро WSL2
- виртуальную машину
- дистрибутив Ubuntu

### 1.3 Перезагрузить компьютер

После сообщения `The requested operation is successful. Changes will not be effective until the system is rebooted.` — перезагрузиться.

### 1.4 Создать пользователя Ubuntu

После перезагрузки Ubuntu откроется автоматически (или запустить вручную: Пуск → Ubuntu).

Появится чёрное окно с текстом:

```
Installing, this may take a few minutes...
Please create a default UNIX user account. The username does not need to match your Windows username.
Enter new UNIX username:
```

- Ввести любое имя латиницей, например `anton`
- Нажать Enter
- Ввести пароль (символы не отображаются — это нормально) → Enter
- Повторить пароль → Enter

Когда появится приглашение `anton@DESKTOP-XXX:~$` — готово. WSL2 работает.

> ⚠️ Этот пароль пригодится для команд с `sudo`. Запишите его.

---

## Часть 2 — Поставить Node.js внутри Ubuntu

Все команды ниже вводятся в окне Ubuntu, не в PowerShell.

### 2.1 Обновить пакеты

```bash
sudo apt update && sudo apt upgrade -y
```

Запросит пароль, введённый на шаге 1.4.

### 2.2 Поставить Node.js 22 через NodeSource

```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
```

### 2.3 Проверить версии

```bash
node --version
npm --version
```

Должно показать:

```
v22.14.0   (или новее)
10.x.x
```

Если Node ниже 22.14 — OpenClaw не запустится.

---

## Часть 3 — Запустить установщик OpenClaw

### 3.1 Запустить скрипт

В том же окне Ubuntu:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-factory/main/scripts/demo-install.sh)
```

### 3.2 Выбрать пункт меню

Появится меню на русском:

```
1 — Пройти демо
2 — Начать реальную установку
3 — Симуляция
```

Для реальной установки — ввести `2` → Enter.

### 3.3 Следовать подсказкам

Установщик попросит по очереди:

1. **API-ключ opencode.ai** — получить на [opencode.ai](https://opencode.ai) в разделе API Keys
2. **Провайдер** — `OpenCode Zen`
3. **Модель** — `MiniMax M2.5 Free` (бесплатная, без карты)
4. **Токен Telegram-бота** — создать через [@BotFather](https://t.me/BotFather), скопировать из его ответа
5. **Ваш Telegram ID** — узнать через [@userinfobot](https://t.me/userinfobot), скопировать цифры из поля `Id`

---

## Часть 4 — Проверить, что бот работает

### 4.1 Открыть своего бота в Telegram

Установщик в конце покажет `@username_бота` — открыть его в Telegram.

### 4.2 Отправить `/status`

Бот должен ответить что-то вроде:

```
🟢 OpenClaw is running
agent: assistant
model: opencode/minimax-m2.5-free
```

Если бот молчит — ввести в Ubuntu:

```bash
openclaw gateway status --deep
openclaw channels status --probe
```

И прислать вывод в поддержку.

---

## 🛠 Что делать, если что-то пошло не так

### WSL не ставится

- Проверить, что Windows обновлён: `Параметры` → `Центр обновления Windows`
- Проверить, что виртуализация включена в BIOS (Intel VT-x / AMD-V)

### `wsl --install` пишет, что команда не найдена

- Сборка Windows слишком старая. Обновить до Windows 10 21H2 / Windows 11
- Альтернатива: вручную через `Включение компонентов Windows` → `Подсистема Windows для Linux` + `Платформа виртуальной машины`

### Ubuntu запускается, но Node.js ≥ 22.14 не ставится

- Убрать старый: `sudo apt remove -y nodejs npm && sudo apt autoremove -y`
- Повторить шаг 2.2

### Установщик падает после ввода Telegram ID

- Это известный баг, починенный в последних версиях installer. Запустить заново — он подхватит уже введённые данные
- Если падает снова — сделать полный сброс:
  ```bash
  openclaw reset --scope config+creds+sessions --yes --non-interactive
  ```
  И запустить установщик заново.

### Бот отвечает `401 No payment method`

- Установилась платная модель. Перепрошить на бесплатную:
  ```bash
  openclaw config set agents.defaults.model.primary "opencode/minimax-m2.5-free"
  openclaw config set 'agents.list[0].model' '"opencode/minimax-m2.5-free"' --strict-json
  openclaw gateway restart
  ```

### Gateway пишет `closed (1006 abnormal closure)`

- Не выставлен `gateway.mode`. Починка:
  ```bash
  openclaw config set gateway.mode local
  openclaw config validate
  openclaw gateway restart
  openclaw gateway status --deep
  ```

---

## 🧭 Как вернуться в Ubuntu в следующий раз

1. Пуск → набрать `Ubuntu` → Enter
2. Для проверки статуса OpenClaw:
   ```bash
   openclaw status --all
   ```

WSL и OpenClaw работают в фоне сами, перезапускать ничего не нужно.

---

## 📌 Важные отличия от macOS/Linux

| Что | macOS/Linux | Windows (WSL) |
|-----|-------------|---------------|
| Где живёт OpenClaw | `~/.openclaw/` в домашней папке | `~/.openclaw/` внутри Ubuntu, а не в `C:\Users\...` |
| Автозапуск gateway | LaunchAgent / systemd | systemd внутри WSL (стартует при первом входе в Ubuntu) |
| Доступ к файлам | обычный Finder | из Проводника Windows: `\\wsl$\Ubuntu\home\<имя>\.openclaw` |
| Редактор конфига | любой | `nano ~/.openclaw/openclaw.json` внутри Ubuntu или из Windows через `\\wsl$\...` |

---

## 🔗 Полезные ссылки

- [Официальная документация WSL2](https://learn.microsoft.com/windows/wsl/install) (Microsoft)
- [OpenClaw](https://openclaw.ai)
- [Документация OpenClaw](https://docs.openclaw.ai)

Если что-то совсем не получается — написать в поддержку с выводом команды `openclaw status --all` или `wsl --status`.
