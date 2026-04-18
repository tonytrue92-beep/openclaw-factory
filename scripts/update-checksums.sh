#!/usr/bin/env bash
# Генерация SHA256SUMS для всех публично распространяемых скриптов.
#
# Запускается:
#   bash scripts/update-checksums.sh
#
# Результат: файл SHA256SUMS в корне репо со строками вида
#   <hash>  scripts/<name>.sh
#
# Зачем: для параноидальных клиентов (B2B, корп-ЦА), которые хотят
# убедиться, что скрипт не подменён между GitHub и их терминалом.
# Они могут сравнить локально:
#   curl -fsSL .../main/scripts/demo-install.sh | shasum -a 256
# с тем, что лежит в SHA256SUMS в репе того же коммита.
#
# NB: это НЕ защита от MITM (GitHub TLS и так делает это), а скорее
# инструмент доверия — видно, какие скрипты версии X соответствовали
# каким байтам.

set -euo pipefail

cd "$(dirname "$0")/.."

OUT="SHA256SUMS"
TMP=$(mktemp)

echo "# SHA-256 checksums for publicly distributed installer scripts." > "$TMP"
echo "# Generated: $(date -u '+%Y-%m-%d %H:%M:%S UTC')" >> "$TMP"
echo "# Commit: $(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')" >> "$TMP"
echo "#" >> "$TMP"
echo "# Verify a downloaded script matches the committed version:" >> "$TMP"
echo "#   curl -fsSL <raw-url> | shasum -a 256" >> "$TMP"
echo "#   (or on Linux: sha256sum <file>)" >> "$TMP"
echo "#" >> "$TMP"
echo "" >> "$TMP"

# Выбираем инструмент: macOS даёт `shasum -a 256`, Linux — `sha256sum`.
if command -v sha256sum &>/dev/null; then
  HASHER="sha256sum"
elif command -v shasum &>/dev/null; then
  HASHER="shasum -a 256"
else
  echo "ERROR: ни sha256sum, ни shasum не установлены" >&2
  exit 1
fi

for f in scripts/*.sh; do
  # Формат результата: "hash  path" — стандартный для утилит проверки.
  $HASHER "$f" >> "$TMP"
done

mv "$TMP" "$OUT"

echo "✓ Обновлён: $OUT"
cat "$OUT"
