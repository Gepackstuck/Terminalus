#!/bin/bash
# Сборка без SwiftPM (в этой установке CLT он не работает): swiftc напрямую.
#   ./build.sh                       — собрать build/Terminalus.app под архитектуру этого Mac
#   ./build.sh run                   — собрать и запустить
#   ARCHS="arm64 x86_64" ./build.sh  — универсальная сборка (Apple Silicon + Intel), нужна для релиза
#   REBUILD_DEPS=1 ./build.sh        — пересобрать SwiftTerm
set -euo pipefail
cd "$(dirname "$0")"

OUT=build
APP=$OUT/Terminalus.app
ARCHS="${ARCHS:-$(uname -m)}"
MIN_OS=13.0     # минимальная версия macOS (должна совпадать с LSMinimumSystemVersion в Info.plist)
mkdir -p "$OUT/bin" "$APP/Contents/MacOS"

BINS=()
for ARCH in $ARCHS; do
  OBJ=$OUT/obj/$ARCH
  TARGET="$ARCH-apple-macos$MIN_OS"
  mkdir -p "$OBJ"

  # 1. SwiftTerm → статическая библиотека (пересобирается, если нет библиотеки или исходник новее — у нас есть патчи)
  NEWER=""
  [ -f "$OBJ/libSwiftTerm.a" ] && NEWER=$(find Vendor/SwiftTerm/Sources Resources/SwiftTermBuildInfo.swift -name '*.swift' -newer "$OBJ/libSwiftTerm.a" | head -1)
  if [ ! -f "$OBJ/libSwiftTerm.a" ] || [ -n "${REBUILD_DEPS:-}" ] || [ -n "$NEWER" ]; then
    echo "▸ [$ARCH] Собираю SwiftTerm (один раз, ~1-3 мин)…"
    swiftc -O -swift-version 5 -wmo -parse-as-library -target "$TARGET" \
      -module-name SwiftTerm \
      -emit-module -emit-module-path "$OBJ/SwiftTerm.swiftmodule" \
      -emit-library -static -o "$OBJ/libSwiftTerm.a" \
      Resources/SwiftTermBuildInfo.swift \
      $(find Vendor/SwiftTerm/Sources/SwiftTerm -name '*.swift' -not -path '*/iOS/*')
  fi

  # 2. Приложение
  echo "▸ [$ARCH] Собираю Terminalus…"
  swiftc -O -swift-version 5 -target "$TARGET" -module-name Terminalus \
    -I "$OBJ" -L "$OBJ" -lSwiftTerm \
    Sources/Terminalus/*.swift \
    -o "$OUT/bin/Terminalus-$ARCH"
  BINS+=("$OUT/bin/Terminalus-$ARCH")
done

if [ "${#BINS[@]}" -gt 1 ]; then
  lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/Terminalus"
else
  cp "${BINS[0]}" "$APP/Contents/MacOS/Terminalus"
fi

mkdir -p "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/CHANGELOG.md "$APP/Contents/Resources/"
# Шейдер для Metal-рендерера SwiftTerm: без него он не включается и терминалы рисуются на CPU
cp Vendor/SwiftTerm/Sources/SwiftTerm/Apple/Metal/Shaders.metal "$APP/Contents/Resources/"
touch "$APP"
codesign --force --deep -s - -r="designated => identifier \"com.terminalus.app\"" "$APP" >/dev/null 2>&1 || true
echo "✓ $APP  ($(lipo -archs "$APP/Contents/MacOS/Terminalus"))"

[ "${1:-}" = "run" ] && open "$APP"
exit 0
