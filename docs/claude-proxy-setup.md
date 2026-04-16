# Claude Code → OpenClaw Proxy Setup

Инструкция для Claude Code: как настроить proxy-acpx-x — мост между подпиской Claude Code и OpenClaw.

## Что это даёт
OpenClaw получает провайдер `claude-local/claude-code-proxy`, который работает через подписку Claude (без API-ключа) как OpenAI-совместимый HTTP-сервер на порту 52088.

## Требования
- macOS или Linux
- Node.js >= 22.14
- OpenClaw установлен и настроен (`openclaw --version`)
- Claude Code CLI установлен (`claude --version`)
- Активная подписка Claude (Max/Pro)
- Claude CLI залогинен (`claude auth status`)

---

## Шаг 1: Установить proxy-acpx-x

```bash
npm install -g proxy-acpx-x
```

---

## Шаг 2: Создать сервис

### macOS (LaunchAgent)

Определить пути:
```bash
NODE_PATH=$(which node)
PROXY_PATH="$(npm root -g)/proxy-acpx-x/dist/http-server.js"
USER_HOME="$HOME"
echo "Node: $NODE_PATH"
echo "Proxy: $PROXY_PATH"
echo "Home: $USER_HOME"
```

Создать директорию логов:
```bash
mkdir -p ~/.openclaw/logs
```

Создать файл `~/Library/LaunchAgents/ai.openclaw.claude-proxy.plist`, подставив значения NODE_PATH, PROXY_PATH, USER_HOME:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>ai.openclaw.claude-proxy</string>
    <key>ProgramArguments</key>
    <array>
        <string>NODE_PATH</string>
        <string>PROXY_PATH</string>
        <string>--port</string>
        <string>52088</string>
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
        <string>USER_HOME</string>
        <key>PATH</key>
        <string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin</string>
    </dict>
    <key>StandardOutPath</key>
    <string>USER_HOME/.openclaw/logs/claude-proxy.log</string>
    <key>StandardErrorPath</key>
    <string>USER_HOME/.openclaw/logs/claude-proxy.err.log</string>
</dict>
</plist>
```

Загрузить:
```bash
launchctl load ~/Library/LaunchAgents/ai.openclaw.claude-proxy.plist
```

### Linux (systemd)

Создать `~/.config/systemd/user/claude-proxy.service` (подставить NODE_PATH, PROXY_PATH, USER_HOME):

```ini
[Unit]
Description=Claude Code Proxy for OpenClaw
After=network.target

[Service]
ExecStart=NODE_PATH PROXY_PATH --port 52088
Restart=always
RestartSec=5
Environment=HOME=USER_HOME
Environment=PATH=/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=default.target
```

```bash
systemctl --user daemon-reload
systemctl --user enable --now claude-proxy
```

### Проверить:
```bash
curl http://127.0.0.1:52088/v1/models
# Ответ: {"object":"list","data":[{"id":"claude-code-proxy",...}]}
```

---

## Шаг 3: Зарегистрировать провайдер в OpenClaw

```bash
openclaw backup create 2>/dev/null || bash ~/.openclaw/backup.sh

openclaw config set models.providers.claude-local '{
  "baseUrl": "http://127.0.0.1:52088/v1",
  "apiKey": "sk-dummy-key",
  "api": "openai-completions",
  "models": [{
    "id": "claude-code-proxy",
    "name": "Claude Code (subscription)",
    "api": "openai-completions",
    "reasoning": true,
    "input": ["text", "image"],
    "output": ["text"],
    "contextWindow": 200000,
    "maxOutput": 128000
  }]
}' --strict-json

openclaw gateway restart
```

Проверить:
```bash
openclaw models list --all | grep claude-local
# Ожидается: claude-local/claude-code-proxy
```

---

## Шаг 4: Патч — скрыть tool labels из ответов

Без патча в ответах будут появляться строки типа `🔧 Read: /path/to/file`.

```bash
PROXY_FILE="$(npm root -g)/proxy-acpx-x/dist/http-server.js"
cp "$PROXY_FILE" "${PROXY_FILE}.orig"
```

Внести 3 правки в `$PROXY_FILE`:

**Правка 1** — найти блок `content_block_stop` для tool_use (~строка 447):
```js
// БЫЛО:
currentRes.write(sseChunk(toolLabel, currentModel));
hasStreamedText = true;

// СТАЛО: заменить эти 2 строки на:
log(`Tool done (hidden from client): ${toolLabel}`);
```
И убрать `toolCallsSummary.push(toolLabel);`

**Правка 2** — найти разделитель `---` (~строка 456):
```js
// УДАЛИТЬ эти строки:
if (toolCallsSummary.length > 0 && !hasStreamedText) {
    currentRes.write(sseChunk("\n\n---\n\n", currentModel));
}
```

**Правка 3** — fallback path для tool_use (~строка 469):
```js
// БЫЛО:
currentRes.write(sseChunk(toolLabel, currentModel));
hasStreamedText = true;

// СТАЛО: заменить на:
log(`Tool (fallback, hidden): ${formatToolSummary(block.name, inputStr)}`);
```
И убрать `toolCallsSummary.push(toolLabel);`

Перезапустить прокси:
```bash
# macOS
launchctl kickstart -k gui/$(id -u)/ai.openclaw.claude-proxy
# Linux
systemctl --user restart claude-proxy
```

---

## Шаг 5: Увеличить таймаут LLM (рекомендуется)

```bash
openclaw config set agents.defaults.llm.idleTimeoutSeconds 60
openclaw gateway restart
```

---

## Готово

Провайдер `claude-local/claude-code-proxy` доступен в OpenClaw. Использовать:
- Как default: `openclaw config set agents.defaults.model.primary "claude-local/claude-code-proxy"`
- Как per-agent override: через `agents.list[N].model.primary`
- Как fallback: `openclaw models fallbacks add claude-local/claude-code-proxy`

## Диагностика

| Команда | Что проверяет |
|---------|---------------|
| `curl http://127.0.0.1:52088/v1/models` | Прокси жив |
| `tail -f ~/.openclaw/logs/claude-proxy.err.log` | Логи прокси |
| `openclaw gateway status` | Gateway статус |
| `openclaw models list --all \| grep claude-local` | Провайдер зарегистрирован |

## ⚠️ После `npm update -g proxy-acpx-x`

Патч из Шага 4 будет перезаписан — переприменить и перезапустить прокси.

## Откат

```bash
openclaw config unset models.providers.claude-local
# macOS:
launchctl unload ~/Library/LaunchAgents/ai.openclaw.claude-proxy.plist
# Linux:
systemctl --user disable --now claude-proxy
openclaw gateway restart
```
