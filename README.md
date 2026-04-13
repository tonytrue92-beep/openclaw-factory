# OpenClaw Factory — Scripts & Tools

Scripts for installing and configuring [OpenClaw](https://openclaw.ai) AI gateway.

## Quick Start

### Demo Installation (safe, isolated)

Run the interactive demo to learn how OpenClaw works — no changes to your system:

```bash
curl -fsSL https://raw.githubusercontent.com/tonytrue92-beep/openclaw-factory/main/scripts/demo-install.sh | bash
```

Or clone and run:

```bash
git clone https://github.com/tonytrue92-beep/openclaw-factory.git
bash openclaw-factory/scripts/demo-install.sh
```

### Claude Proxy Installer

Automated installer for [proxy-acpx-x](https://www.npmjs.com/package/proxy-acpx-x) — wraps Claude Code CLI as OpenAI-compatible HTTP server:

```bash
# Dry run (preview only, no changes):
bash scripts/install-claude-proxy.sh --dry-run

# Install:
bash scripts/install-claude-proxy.sh

# Uninstall:
bash scripts/install-claude-proxy.sh --uninstall
```

## Contents

| File | Description |
|------|-------------|
| `scripts/demo-install.sh` | Interactive demo — simulates full OpenClaw setup with Russian explanations |
| `scripts/install-claude-proxy.sh` | Claude Proxy automated installer (macOS/Linux) |
| `docs/claude-proxy-setup.md` | Claude Proxy setup guide |

## Requirements

- Node.js >= 22.14
- npm
- macOS or Linux

## License

MIT
