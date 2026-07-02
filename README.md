# Worder

Личное iOS-приложение для заучивания английских слов (EN ↔ RU) с интервальными повторениями (FSRS). Один пользователь, один iPhone, все данные локально.

## Структура

- `WorderCore/` — SPM-пакет с логикой (схема данных, планировщик, проверка ответов, импорт). Тестируется на macOS без симулятора.
- `App/` — SwiftUI-оболочка (iOS 26+).
- `AppTests/` — тесты уровня приложения.
- `data/` — эталонные пачки слов в каноническом JSON.
- `scripts/` — разовые инструменты (конвертация PDF → JSON).
- `project.yml` — источник правды для Xcode-проекта; `Worder.xcodeproj` генерируется и не коммитится.

## Команды

```sh
# Тесты ядра (быстрые, без симулятора)
swift test --package-path WorderCore

# Сгенерировать Xcode-проект (после изменения project.yml)
xcodegen generate

# Сборка приложения
xcodebuild build -project Worder.xcodeproj -scheme Worder \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.1'

# Тесты приложения
xcodebuild test -project Worder.xcodeproj -scheme Worder \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.1'
```

Разработка в Xcode: `xcodegen generate && open Worder.xcodeproj`.
