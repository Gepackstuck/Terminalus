Terminalus не подписан сертификатом Apple Developer, поэтому macOS может заблокировать первый запуск.

Если приложение не открывается:
  1) перетащите Terminalus в «Программы»;
  2) откройте «Системные настройки → Конфиденциальность и безопасность»,
     прокрутите вниз и нажмите «Всё равно открыть» рядом с Terminalus;
  или выполните в Terminal:
     xattr -dr com.apple.quarantine /Applications/Terminalus.app

Установка одной командой без этих шагов (скачивание через curl не помечается карантином):
     curl -fsSL https://raw.githubusercontent.com/Gepackstuck/Terminalus/main/scripts/install.sh | bash
