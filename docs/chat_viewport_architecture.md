# Chat Viewport Architecture

## Обзор

Кастомный viewport для Flutter-чата с бесконечной прокруткой в обе стороны.
Сообщения — обычные виджеты, которые лениво инфлейтятся во время layout кастомным
`Element` (та же механика, что у `SliverMultiBoxAdaptorElement`, но без sliver-
протокола). Координатная система — anchor-based: всё позиционируется
относительно одного «якорного» сообщения, без знания общей высоты контента.

## Почему не стандартные решения

### ListView.builder — не подходит

- Привязан к пиксельным координатам, требует `maxScrollExtent` (общую высоту
  всех сообщений).
- Прыжок к произвольному message ID без знания пиксельного смещения невозможен
  без хаков.
- Скроллбар требует пересчёта layout всех сообщений.

### Sliver-протокол — создаёт больше проблем, чем решает

- `SliverConstraints.scrollOffset` — абсолютное пиксельное смещение от начала.
- Телепортация к сообщению №1500 требует объяснить framework'у новый
  `scrollOffset` — постоянные коррекции через `ScrollPosition.correctBy()`.
- Ни один плюс slivers (SliverList, SliverGrid, координированный скролл) не
  используется.

### Выбранный подход

Кастомные `Widget` + `Element` + `RenderObject`. Сообщения — реальные виджеты
(каждое обёрнуто в `RepaintBoundary`), но инфлейтятся лениво — только видимый
диапазон ± cache extent. Якорь даёт O(viewport) телепортацию и скролл без
глобальной высоты.

## Три слоя

| Слой         | Класс                  | Ответственность                                  |
| ------------ | ---------------------- | ------------------------------------------------ |
| Widget       | `ChatScrollView`       | Публичный API: dataSource, controller, builder   |
| Element      | `ChatScrollElement`    | Ленивая инфляция детей, skip-rebuild кэш         |
| RenderObject | `RenderChatScrollView` | Layout, paint, жесты, скролл, fetch, eviction    |

`ChatScrollElement` реализует интерфейс `ChatChildManager`
(`buildChild(id)` / `removeChildren(ids)`), который `RenderChatScrollView`
вызывает из `performLayout`.

## Файловая структура

```
lib/src/
  chat_message.dart                  # ChatMessage, ChatMessage$User/System
  comments_data_source.dart          # пример ChatDataSource (asset-чанки)
  chat_scroll/                       # headless-ядро (без виджетов)
    chat_scroll_common.dart          # IChatMessage, ChatMessageStatus
    chat_scroll_chunk.dart           # ChatScrollChunk (@internal)
    chat_data_source.dart            # ChatDataSource: данные + fetch
    chat_scroll_controller.dart      # ChatScrollController: якорь + границы
    chat_selection_controller.dart   # ChatSelectionController: выделение
  chat_widgets/                      # widget-реализация viewport'а
    chat_scroll_view.dart            # ChatScrollView (RenderObjectWidget)
    chat_scroll_element.dart         # ChatScrollElement (RenderObjectElement)
    render_chat_scroll_view.dart     # RenderChatScrollView (RenderBox)
    chat_scrollbar.dart              # ChatScrollbar (геометрия + paint)
    chat_selectable_message.dart     # SelectableMessage (chrome выделения)
    chat_data_source_ext.dart        # statusOf(id) расширение
    demo/                            # пример: экран, композер, пузырьки
```

## Публичный API

```dart
ChatScrollView(
  dataSource: myDataSource,         // данные: чанки + fetch
  controller: myScrollController,   // якорь + границы + jumps
  messageBuilder: (ctx, id, message, status) => ...,
  selectionController: mySelection, // опционально: выделение сообщений
  bottomPadding: myInsetListenable, // опционально: отступ под композер
  cacheExtent: 250,                 // px за краями viewport — строятся + красятся
  extraBuildExtent: 0,              // доп. px — строятся, но не красятся
)
```

`extraBuildExtent` — чисто дистанционная зона, в которой виджеты остаются
смонтированными (их `State` переживает короткий уход за экран). Не путать с
виджетом `KeepAlive`, который удерживает конкретных детей независимо от
расстояния.

## Система координат

Anchor-based, без абсолютных пиксельных смещений:

```
anchorMessageId : int      // ID сообщения — начало координат
anchorPixelOffset : double // смещение top edge якоря от top viewport
```

- Layout всегда разворачивается от якоря в обе стороны, пока не заполнится
  viewport + cache extent.
- Телепортация к любому сообщению — `controller.jumpTo(id)` (O(viewport)).
- Скролл двигает `anchorPixelOffset`; когда якорь уезжает за cache extent,
  layout тихо переставляет якорь на первое видимое сообщение
  (`reassignAnchor`).

## ID и чанки

- ID — непрерывная последовательность целых: `..., -2, -1, 0, 1, 2, ...`.
- Чанк — 64 сообщения; `chunkIndex = id >> 6` (арифметический сдвиг корректен
  для отрицательных ID).
- `ChatScrollChunk` хранит `messages[64]`, `status` (dirty/fetching/error/valid)
  и `lastAccessTick` для LRU.

## Ленивые дети (`ChatScrollElement`)

`ChatScrollElement` владеет sparse-набором детей-элементов
(`SplayTreeMap<int, Element>`, ключ — message ID).

`RenderChatScrollView` вызывает `buildChild(id)` во время `performLayout`,
обёрнутый в `invokeLayoutCallback` — единственное место, где сборка виджетов
во время layout легальна. `buildChild` инфлейтит виджет через `updateChild`
внутри `owner.buildScope` и возвращает его `RenderBox`.

**Skip-rebuild кэш.** Элемент запоминает инстанс сообщения и статус, с которыми
ребёнок последний раз строился. Если `buildChild` запрашивают для ID с теми же
данными — существующий ребёнок переиспользуется без `updateChild` и без
`build()`. Изменения inherited-виджетов (Theme, MediaQuery) всё равно
перестраивают детей через штатный механизм зависимостей.

Каждое сообщение оборачивается в `RepaintBoundary` (для retained-слоёв), а при
наличии `selectionController` — ещё и в `SelectableMessage`.

## Layout (`performLayout`)

```
1. Проверить bounded-constraints (assert).
2. _fanOutFromAnchor: от якоря вниз и вверх, пока не покрыт
   viewport + cacheExtent + extraBuildExtent + directional lead.
   Каждый ребёнок: buildChild → child.layout → выставить offset.
3. _renormalizeAnchor: если якорь уехал за cacheExtent — переставить.
4. _clampBoundaries: прижать контент к краям на границах чата.
5. Если якорь сменился — повторный fan-out от исправленного якоря.
6. GC: дети вне build-диапазона — removeChildren (invokeLayoutCallback).
7. _evictChunks: LRU-вытеснение чанков вне layout-диапазона.
8. _scheduleFetchPoll: взвести poll, если в диапазоне есть dirty-чанки.
```

`directional lead` — построение с запасом в сторону движения (по EMA скорости
скролла), чтобы быстрый fling не обогнал построенный диапазон.

## Скролл: Tier-1

Скролл обходит layout и rebuild. `RenderChatScrollView` владеет `Ticker`'ом;
драг / fling / колесо мыши кормят `_pendingScrollDelta`, а `_onTick` каждый
кадр:

```
_onTick:
  applyScrollDelta(delta + fling-симуляция)
  _repositionFromAnchor()   // только пересчёт offset, O(видимых детей)
  _renormalizeAnchor()
  _clampBoundaries()
  markNeedsPaint()          // НЕ markNeedsLayout
```

`markNeedsLayout` вызывается только когда построенный диапазон перестаёт
покрывать viewport (`_rangeNoLongerCovers`) — тогда нужен новый fan-out.

Каждое сообщение — `RepaintBoundary`, поэтому его слой retained: при скролле
framework просто перемещает закэшированные слои, повторного `paint()` детей
нет. Клип-слой viewport'а тоже переиспользуется (`LayerHandle` + `oldLayer`).

`Ticker` подчиняется `TickerMode`: viewport на неактивном роуте (`ticking`
становится `false`) не анимирует fling за экраном.

## Fetch и eviction

`ChatDataSource` владеет чанками и контрактом `fetch({from, to, after})`.
Typed listeners (`addDataListener`) вместо `ChangeNotifier`.

**Poll.** Вместо постоянного периодического таймера — одноразовый таймер,
взводимый только пока в layout-диапазоне есть отсутствующие/dirty-чанки
(`_scheduleFetchPoll`). Полностью загруженный простаивающий viewport не
просыпается. Когда данные приходят → `notifyDataChanged` → `markNeedsLayout` →
следующий `performLayout` решает, нужен ли poll снова.

**Eviction.** `_evictChunks` LRU-вытесняет чанки вне layout-диапазона, пока их
не больше `maxChunks` (по умолчанию 16 ≈ 1024 сообщения).

## Скроллбар

`ChatScrollbar` — чистая геометрия, отрисовка и состояние drag-указателя; не
зависит от render object'а. Позиция thumb — id-математика
(`(anchorId - oldestId) / range`), без глобальной высоты. Drag по скроллбару
маппит позицию в message ID и телепортирует.

## Выделение сообщений

`ChatSelectionController` (живёт вне render-дерева, переживает eviction) хранит
множество выбранных ID. При переданном `selectionController` каждое сообщение
оборачивается в `SelectableMessage`: long-press входит в режим выделения, tap
переключает. Контент уходит в `AnimatedBuilder.child` — строится один раз,
анимируется только лёгкий chrome (чекбокс-жёлоб + тинт строки). Форма поддерева
постоянна, поэтому `State` сообщения переживает вход/выход из режима выделения.

## Разделители по дням

Опционально — включаются, когда задан `dateSeparatorBuilder`. Сообщения
группируются по дням через `dayBucketOf` (по умолчанию — локальный календарный
день).

**Inline-разделитель** встроен в виджет сообщения: первое сообщение дня
строится как `Column[separator, message]` — ноль новых children, разделитель
picture-кэшируется внутри `RepaintBoundary` сообщения. `RenderChatScrollView`
считает `startsDay` / `dayBucket` в `_buildMessage` и кладёт в `ParentData`, так
что per-frame обход — чистое чтение полей.

**Плавающий хедер** — один служебный child render box (помимо id-keyed
сообщений). Строится лениво во время layout (`buildFloatingHeader` — тот же
канал, что и `buildChild`) и **перестраивается только при смене дня**: на
пересечении границы `_onTick` делает `markNeedsLayout` вместо `markNeedsPaint`
(одна перекладка на границу — skip-rebuild кэш не даёт сообщениям
перестраиваться). Внутри дня хедер только репозиционируется — Tier-1.

**Push.** Каждый кадр `_scanTopDay` обходит видимые children: день верхнего
сообщения + Y разделителя следующего дня. Хедер стоит у верхней кромки
(`topPadding`); когда разделитель следующего дня поднимается в его зону, хедер
выталкивается вверх (`y = nextDividerY - headerHeight`), а на пересечении
сменяется новым днём. Несколько inline-разделителей на экране — бесплатно.

**Без раздвоения.** Inline- и floating-копия строятся одним
`dateSeparatorBuilder` и раскладываются одинаково: inline-разделитель верхней
секции уходит вверх ровно *за* плавающим (тот же контент, та же позиция) — без
видимого раздвоения. Поэтому у разделителя не должно быть пустого места сверху
(отступ дают соседние сообщения) — иначе inline-копия выглядывала бы из зазора
над плавающим хедером.

## Демо (`chat_widgets/demo/`)

- `WidgetChatScreen` — экран: viewport + композер + контекстный бар выделения,
  все наложены в `Stack`.
- `ChatComposer` — нижняя панель: поле ввода ⇄ кнопки действий. Её измеренная
  высота (`MeasureSize`) кормит `bottomPadding` viewport'а, чтобы новейшее
  сообщение всегда было видно над композером.
- `SelectionAppBar` — контекстный верхний бар (счётчик выбранного).
- `buildDemoMessage` — пузырёк сообщения; viewport отдаёт каждому сообщению
  полную ширину viewport'а, а пузырёк сам центрирует свою колонку.
- `DateSeparator` — пилюля даты; один виджет и для inline-разделителя, и для
  плавающего хедера.

## Тесты

```
test/widgets/
  chat_widgets_test.dart       # виртуализация, скролл, fling, jumpTo,
                               # shimmer, eviction, Tier-1, скроллбар, семантика
  chat_selection_test.dart     # выделение: long-press, tap, chrome
  chat_date_separator_test.dart # разделители по дням: inline, хедер, push
  chat_scrollbar_test.dart     # ChatScrollbar: геометрия, drag-указатель
  chat_widgets_bench_test.dart # headless-бенчмарк layout/paint
  vs_listview_bench_test.dart  # A/B-бенчмарк против ListView.builder
integration_test/
  widget_benchmark_test.dart   # профайлинг fling на устройстве
```

## Debug-инструментация

Stopwatch через assert-паттерн — zero-cost в release:
`debugLastLayoutDuration`, `debugLastPaintDuration`, `debugLayoutFrameId`,
`debugPaintFrameId`, `debugChildCount`, `debugChunkCount`.
