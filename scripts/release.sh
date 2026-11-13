#!/bin/bash
# Собирает релиз: универсальное приложение, .zip, .dmg и контрольные суммы в dist/.
#   ./scripts/release.sh
# Потом загрузите файлы из dist/ в GitHub Release (тег v<версия>).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
DIST=dist
rm -rf "$DIST"; mkdir -p "$DIST"

ARCHS="arm64 x86_64" ./build.sh

# .zip — его скачивает install.sh (ditto сохраняет подпись и атрибуты)
ditto -c -k --keepParent build/Terminalus.app "$DIST/Terminalus-$VERSION.zip"

# .dmg — для ручной установки перетаскиванием
STAGE=$(mktemp -d)
cp -R build/Terminalus.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp scripts/README-dmg.txt "$STAGE/Если не открывается.txt"
hdiutil create -volname "Terminalus $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DIST/Terminalus-$VERSION.dmg" >/dev/null
rm -rf "$STAGE"

( cd "$DIST" && shasum -a 256 Terminalus-* > SHA256SUMS.txt )
echo "✓ Релиз $VERSION:"; ls -lh "$DIST"
