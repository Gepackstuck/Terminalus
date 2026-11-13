# Terminalus

macOS-приложение: несколько терминалов (для Claude Code) во вкладках одного окна + режим сетки.
Swift/AppKit + SwiftTerm (vendored, `Vendor/SwiftTerm`, v1.20.0, с нашим патчем в `scrollWheel`).

- Сборка: `./build.sh` (или `./build.sh run`). SwiftPM не используется.
- Иконка: `swift scripts/make_icon.swift <dir.iconset>` + `iconutil -c icns`, результат — `Resources/AppIcon.icns`.

## Правило: история версий
После каждой итерации работы с пользователем:
1. добавь запись в начало `Resources/CHANGELOG.md` (новая версия, дата, список изменений человеческим языком);
2. подними версию в `Resources/Info.plist` (CFBundleShortVersionString / CFBundleVersion).
Этот файл показывается в окне «О Terminalus».

## Правило: git
Репозиторий: https://github.com/Gepackstuck/Terminalus (ветка `main`). Владелец проекта **разрешил** коммитить и пушить каждое изменение без отдельного вопроса.
- После каждой итерации: коммит с понятным сообщением на русском + `git push`.
- Автор коммитов — локальная конфигурация репозитория (`Gepackstuck`, адрес `…@users.noreply.github.com`). Глобальный git-конфиг содержит рабочую почту и ФИО — **не использовать** их для коммитов и ничего личного в репозиторий не добавлять.
- В `Vendor/SwiftTerm` лежат только исходники и лицензия; наши правки библиотеки описаны в `Vendor/PATCHES.md` и `Vendor/patches/`.

