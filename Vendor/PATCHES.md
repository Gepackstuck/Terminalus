# SwiftTerm в Terminalus

Библиотека лежит в `Vendor/SwiftTerm` (версия **v1.20.0**, лицензия MIT — файл `Vendor/SwiftTerm/LICENSE`).
В репозитории хранятся только её исходники (`Sources/SwiftTerm`); тесты, демо-приложение и документация убраны.

## Наши изменения

Полный дифф относительно оригинала: [`patches/swiftterm-terminalus.patch`](patches/swiftterm-terminalus.patch).

- **`Mac/MacTerminalView.swift` → `scrollWheel`** — для «обычного колеса» дробные дельты теперь копятся, а не округляются до ±1 строки.
  Утилиты вроде Mos сглаживают колесо потоком мелких событий; раньше каждое такое событие давало минимум строку, и скролл рвался.

## Как обновить SwiftTerm

1. Скачать нужную версию в чистую папку, взять из неё `Sources/SwiftTerm` и `LICENSE`.
2. Применить патч: `git apply Vendor/patches/swiftterm-terminalus.patch` (при конфликтах поправить вручную).
3. `REBUILD_DEPS=1 ./build.sh` — пересобрать библиотеку.

Файл `Resources/SwiftTermBuildInfo.swift` заменяет код, который в SwiftPM генерирует плагин сборки.
Файл `Apple/Metal/Shaders.metal` копируется в ресурсы приложения скриптом `build.sh` — без него Metal-рендерер не включается.
