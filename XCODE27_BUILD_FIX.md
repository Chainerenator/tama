# Xcode 27 build fix — Alpha 0.4.6

Исправлена ошибка:

`Multiple commands produce ... TamaDuckAlpha.app/TamaDuckAlpha`

Причина: target был помечен как старый `application.watchapp2` контейнер, хотя проект является современным однотаргетным SwiftUI watch-only приложением. Xcode одновременно создавал link command и `CopyAndPreserveArchs` для одного executable.

Исправление:

- product type: `com.apple.product-type.application`
- SDK: watchOS
- device family: Apple Watch
- deployment target: watchOS 10

Перед сборкой:

1. Product → Clean Build Folder (держать Option, либо Shift+Cmd+K)
2. Закрыть Xcode
3. Удалить DerivedData старой сборки при необходимости
4. Открыть этот новый project
5. Выбрать Team и Run Destination
6. Cmd+R
