#!/bin/bash
# Картинки для README: настоящие вьюхи приложения с вымышленными данными.
#   ./scripts/make_screenshots.sh          → docs/images/screens/*.png
# Нужна собранная библиотека SwiftTerm (./build.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
ARCH=$(uname -m)
OBJ=build/obj/$ARCH
[ -f "$OBJ/libSwiftTerm.a" ] || { echo "Сначала запустите ./build.sh"; exit 1; }
OUT=build/demo; mkdir -p "$OUT" docs/images/screens
SRC=$(ls Sources/Terminalus/*.swift | grep -vE "/(main|AppDelegate|MainWindowController)\.swift$")
swiftc -O -swift-version 5 -target "$ARCH-apple-macos13.0" -I "$OBJ" -L "$OBJ" -lSwiftTerm \
  $SRC scripts/demo/main.swift -o "$OUT/demo" 2>&1 | grep -E " error" || true
"$OUT/demo" docs/images/screens
