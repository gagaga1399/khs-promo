# KHS

Менеджер задач на Flutter (Windows + Android) с синхронизацией заметок в Obsidian.

## Сборка

- Windows: `flutter build windows --release` → `build\windows\x64\runner\Release\`
- Android: `flutter build apk --release` → `build\app\outputs\flutter-apk\app-release.apk`

Данные хранятся в локальной SQLite-базе; заметки дня синхронизируются с vault Obsidian.
