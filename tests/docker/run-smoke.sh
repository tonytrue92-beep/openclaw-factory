#!/usr/bin/env bash
# Локальный раннер для Docker smoke-тестов.
# Запускается без аргументов:
#   bash tests/docker/run-smoke.sh         # оба образа
#   bash tests/docker/run-smoke.sh debian  # только debian
#   bash tests/docker/run-smoke.sh alpine  # только alpine
#
# Использует `docker build` + `docker run` — не требует compose.

set -euo pipefail

cd "$(dirname "$0")/../.."

WHICH="${1:-all}"

build_and_run() {
  local variant="$1"
  local dockerfile="tests/docker/Dockerfile.${variant}"
  local tag="openclaw-factory-test:${variant}"

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Docker smoke: ${variant}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  docker build --quiet -t "$tag" -f "$dockerfile" . >/dev/null
  docker run --rm "$tag"
  echo ""
}

case "$WHICH" in
  debian)  build_and_run debian ;;
  alpine)  build_and_run alpine ;;
  all|"")
    build_and_run debian
    build_and_run alpine
    ;;
  *)
    echo "Usage: $0 [debian|alpine|all]"
    exit 1
    ;;
esac

echo "✓ All Docker smoke tests passed"
