#!/bin/bash
# Установка Terminalus одной командой (скачивание через curl не помечается карантином macOS,
# поэтому никаких предупреждений Gatekeeper):
#   curl -fsSL https://raw.githubusercontent.com/Gepackstuck/Terminalus/main/scripts/install.sh | bash
#
# Переменные:  TERMINALUS_REPO=owner/repo   откуда брать релиз (по умолчанию ниже)
#              INSTALL_DIR=/Applications    куда ставить
# Локальная проверка:  ./scripts/install.sh /путь/к/Terminalus-X.Y.Z.zip
set -euo pipefail

REPO="${TERMINALUS_REPO:-Gepackstuck/Terminalus}"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

if [ "$(uname -s)" != "Darwin" ]; then echo "Terminalus работает только на macOS." >&2; exit 1; fi

if [ -n "${1:-}" ]; then
  ZIP="$1"
else
  echo "▸ Ищу последнюю версию ($REPO)…"
  URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
        | grep -o '"browser_download_url": *"[^"]*\.zip"' | head -1 | sed 's/.*"\(http[^"]*\)"/\1/')
  [ -n "$URL" ] || { echo "Не нашёл .zip в последнем релизе $REPO." >&2; exit 1; }
  echo "▸ Скачиваю $URL"
  ZIP="$TMP/Terminalus.zip"
  curl -fL --progress-bar "$URL" -o "$ZIP"
fi

echo "▸ Устанавливаю в $INSTALL_DIR…"
ditto -x -k "$ZIP" "$TMP/unpacked"
[ -d "$TMP/unpacked/Terminalus.app" ] || { echo "В архиве нет Terminalus.app." >&2; exit 1; }

# Закрыть запущенную копию, чтобы заменить файлы
osascript -e 'tell application "Terminalus" to quit' >/dev/null 2>&1 || true
sleep 1
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/Terminalus.app"
ditto "$TMP/unpacked/Terminalus.app" "$INSTALL_DIR/Terminalus.app"
# На случай, если архив скачан браузером и помечен карантином
xattr -dr com.apple.quarantine "$INSTALL_DIR/Terminalus.app" 2>/dev/null || true

echo "✓ Готово: $INSTALL_DIR/Terminalus.app"
[ "$INSTALL_DIR" = "/Applications" ] && open "$INSTALL_DIR/Terminalus.app" || true
