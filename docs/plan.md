# План реализации ChatScrollView

## Context

Виджет имеет ядро: чанки по 64 сообщения, anchor-based координатная система (`anchorMessageId` + `anchorPixelOffset`), LRU-вытеснение с защитой двух новейших чанков, layout от якоря в обе стороны. `ChatMessageRenderFactory` принимает `IChatMessage?` (nullable для placeholder-слотов).

### Реализовано: OffsetLayer compositing + scroll-only оптимизация

Каждый `ChatMessageRender` владеет `OffsetLayer` → `PictureLayer`. Viewport управляет жизненным циклом слоёв через зоны видимости с гистерезисом (`_attachFactor = 1.0`, `_detachFactor = 1.7`). При скролле viewport обновляет только `OffsetLayer.offset` — GPU композитит без re-record.

- `attachLayer(width)` / `detachLayer()` — создание/высвобождение слоёв
- `rerecordPicture()` — пересоздание PictureLayer (анимации, invalidatePaint)
- `needsRepaint` — getter для анимированных renders
- `_notifyScroll()` / `_notifyData()` — разделение уведомлений контроллера
- `_repositionChunks()` — пересчёт offsetY без relayout при scroll-only
- `alwaysNeedsCompositing => true`

Нет: скролла, fetch-логики, отображения, анимаций, выделения. `main.dart` — заглушка "Hello World".

**Файлы:**

- `lib/src/chat_scroll_view.dart` — все core-классы
- `lib/src/chat_message.dart` — `ChatMessage`, `ChatMessage$System`, `ChatMessage$User`
- `lib/main.dart` — точка входа
- `docs/chat_viewport_acrhitecture.md` — архитектурная документация

---

## Этап 1: Scroll — жесты и физика

### 1.1 GestureRecognizer в RenderBox

`RenderChatScrollView` уже имеет `hitTestSelf → true`. Добавить:

```dart
late final VerticalDragGestureRecognizer _drag;
// + dispose в dispose()

@override
void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
  if (event is PointerDownEvent) _drag.addPointer(event);
}
```

Drag:

```dart
_onDragUpdate: _controller.anchorPixelOffset += delta.dy
```

### 1.2 Fling (инерция)

`ClampingScrollSimulation` + `SchedulerBinding.instance.createTicker()`. Хранить `_lastFlingValue` и применять **дельту** (не абсолютное значение) — корректно работает с ренормализацией якоря.

### 1.3 Anchor re-normalization

В конце `performLayout`: если якорное сообщение ушло за `cacheExtent`, найти первое видимое сообщение (offsetY + height > 0) и тихо переставить anchor (без `notifyListeners`, мы уже в layout).

### 1.4 Overscroll / границы чата

Новые поля в `ChatScrollController`:

```dart
bool _reachedOldest = false;
bool _reachedNewest = false;
int? _oldestKnownId;
int? _newestKnownId;
```

В конце `performLayout`: clamping — не дать "дну" уехать выше нижней кромки viewport'а (если `_reachedNewest`), аналогично для верха.

### 1.5 Верификация

- Захардкодить 200+ сообщений в чанках
- Drag скролл — плавный, без артефактов
- Fling — инерция, остановка на границах
- `flutter analyze` clean

---

## Этап 2: Fetch-система

### 2.1 Фазы контроллера

```dart
enum _ControllerPhase { uninitialized, initialFetching, ready }
```

### 2.2 Initial fetch

`fetch()` без параметров → самые новые сообщения. Определяет `_newestKnownId`, `anchorMessageId`. Если < 64 — `_reachedOldest = true`. Пока `initialFetching` — скролл заблокирован, viewport показывает shimmer.

### 2.3 On-demand fetch при скролле

В `performLayout`, при обнаружении отсутствующего чанка в пределах `cacheExtent`:

1. Создать пустой чанк, поместить в `_chunks`
2. `chunk.status = fetching`
3. Запустить `fetch(from: chunk.firstId, to: chunk.lastId)`
4. Layout продолжается — пустой чанк имеет placeholder-высоты (shimmer)

Fetch-логику разместить в `ChatScrollController` (метод `requestChunk(int chunkIndex)`), а не в RenderBox.

### 2.4 Partial chunks

Первый и последний чанки чата неполные. `null`-слоты получают render через `_messageBuilder(null)` — render возвращает `height = 0` для пустых крайних слотов (не shimmer, а реально отсутствующие).

Различие: **shimmer** = слот ещё загружается (чанк `fetching`), **пустой** = слот за пределами реальных сообщений (чанк `valid`, но `message == null`).

### 2.5 Верификация

- Mock `fetch()` с задержкой 500ms
- Скролл вверх триггерит загрузку старых чанков
- Shimmer → данные — плавный переход
- Пустой чат (fetch вернул []) — корректное отображение

---

## Этап 3: Error handling и backoff

### 3.1 Retry state

```dart
class _RetryState {
  int attempt = 0;
  Timer? timer;
  Duration get nextDelay => Duration(seconds: min(1 << attempt, 30));
}
```

Map `<int, _RetryState>` в контроллере (по chunk index).

### 3.2 Retry с проверкой видимости

При ошибке: `chunk.status = error`, планируем retry через `nextDelay`. Перед retry проверяем — чанк ещё в `[_layoutMinChunk, _layoutMaxChunk]`? Если нет — сбрасываем attempt, не ретраим.

### 3.3 Отображение ошибки

Render получает `status.isError` в `update()` — рисует UI ошибки. Hit-test на кнопке "повторить" → `controller.retryChunk(chunkIndex)`.

### 3.4 Верификация

- Mock fetch, который периодически кидает ошибку
- Backoff растёт: 1s, 2s, 4s...
- Уехали от ошибочного чанка — retry не происходит
- Вернулись — retry возобновляется

---

## Этап 4: Пример — "Бойцовский клуб"

### 4.1 Данные

Парсинг текста книги в массив `ChatMessage`: реплики как `ChatMessage$User` (от разных персонажей — Рассказчик, Тайлер, Марла), описания как `ChatMessage$System`.

### 4.2 Corner-case примеры (отдельные экраны/вкладки)

| Кейс                    | Описание                                     |
| ----------------------- | -------------------------------------------- |
| Пустой чат              | `fetch()` → `[]`                             |
| Одно сообщение          | `fetch()` → 1 элемент                        |
| Счётчик                 | ID от -1000 до 1000, `content = "$id"`       |
| Только отрицательные ID | Проверка арифметического сдвига для чанков   |
| Всегда ошибка           | `fetch()` всегда throws — backoff, UI ошибки |
| Медленный fetch         | 3s задержка — shimmer, отмена при уходе      |
| Очень длинные сообщения | Тест layout с сообщениями 10000+ символов    |
| Быстрый скролл          | 10000+ сообщений, fling через всю историю    |

### 4.3 Конкретная реализация ChatMessageRender

`BookMessageRender` — subclass `ChatMessageRender`:

- `TextPainter` для текста
- Цвет пузырька по автору
- Аватар (первая буква имени в круге)
- Shimmer при `message == null`

### 4.4 Верификация

- Все corner-case работают без крашей
- Performance profiling: 60fps при быстром скролле

---

## Этап 5: Rendering — пузырьки, аватары, даты

### 5.1 Message bubbles

`drawRRect` с `Radius.circular` + хвост через `drawPath`. Picture-кэширование через `OffsetLayer` → `PictureLayer` compositing.

### 5.2 Sticky avatars

Viewport рисует ПОСЛЕ основного pass'а в `_paintMessages`. Алгоритм:

1. Найти первое видимое сообщение у top viewport
2. Если это не первое в группе автора — аватар "приклеивается" к top
3. `max(topY, originalAvatarY)` для позиции

Нужно: поле author/senderId в `IChatMessage` (или в конкретном subclass).

### 5.3 Sticky date separators

Аналогично sticky headers:

1. Дата первого видимого сообщения → sticky header
2. Следующий date separator "выталкивает" текущий вверх
3. Кэш `TextPainter` для дат (`Map<String, TextPainter>`)

### 5.4 Порядок слоёв в ClipRectLayer

```
1. OffsetLayer → PictureLayer (per attached message render)
2. PictureLayer (sticky overlays — аватары, даты, selection)
```

Sticky elements рисуются на отдельном `PictureLayer`, который append'ится последним в `ClipRectLayer` — гарантированно поверх всех message layers.

### 5.5 Верификация

- Sticky элементы визуально корректны при скролле
- Picture cache не ломается при sticky overlay

---

## Этап 6: Shimmer-плейсхолдеры

### 6.1 Shimmer render

`update(null, fetching)` → shimmer mode. `performLayout` возвращает фиксированную высоту (~72px). `needsRepaint` возвращает `true` (анимация) — viewport вызывает `rerecordPicture()` каждый фрейм.

### 6.2 Shared gradient

Viewport хранит `_shimmerPhase` (из `DateTime.now().millisecondsSinceEpoch % 1500 / 1500`). Все shimmer renders используют один gradient с parallax-коррекцией по `offsetY`.

### 6.3 Автоостановка

Когда все shimmer renders получают данные → `needsRepaint` возвращает `false` → анимация прекращается автоматически.

### 6.4 Верификация

- Shimmer непрерывный между placeholder'ами
- Переход shimmer → контент без мерцания
- CPU usage падает до нуля когда shimmer'ов нет

---

## Этап 7: Markdown

### 7.1 Парсинг

`package:markdown` для AST. В `performLayout`: AST → список `_LayoutBlock` (TextBlock, CodeBlock, ImageBlock, ListItemBlock).

### 7.2 TextPainter per block

Каждый параграф/heading → `TextPainter` с `TextSpan` (вложенные spans для bold/italic/code/links). Один `TextPainter` на параграф — позволяет `getPositionForOffset` для selection.

### 7.3 Code blocks

Моноширинный шрифт + фон `drawRRect`. Подсветка синтаксиса опционально (через `TextSpan` с цветами).

### 7.4 Inline images

Async загрузка → placeholder-высота → по готовности `dirty = true` → relayout. `ui.Image` кэшируется в render.

### 7.5 Верификация

- Все базовые markdown-элементы рендерятся корректно
- Mixed content (text + code + images) без артефактов
- `TextPainter` корректно disposed

---

## Этап 8: Выделение текста

### 8.1 Модель

```dart
enum SelectionMode { none, text, messages }
class ChatSelection {
  SelectionMode mode;
  // text: messageId + TextPosition start/end
  // messages: startId..endId range
}
```

На уровне `RenderChatScrollView`, не render'а.

### 8.2 Жесты

Desktop: click+drag. Mobile: long press → drag. Переход `text → messages` при пересечении границы сообщения.

`ChatMessageRender` получает новый метод:

```dart
TextPosition? getTextPosition(Offset localOffset);
```

### 8.3 Рендеринг

- **Text mode**: render получает selection range, рисует highlight через `TextPainter.getBoxesForSelection()` ДО текста.
- **Messages mode**: viewport рисует полупрозрачный overlay ПОВЕРХ выделенных сообщений (не инвалидирует picture cache).

### 8.4 Clipboard

`Clipboard.setData` с extracted text. Для messages mode — конкатенация через `\n`.

### 8.5 Верификация

- Выделение текста внутри одного сообщения
- Переход в messages mode при пересечении границ
- Copy работает корректно
- Скролл во время выделения не ломает selection

---

## Этап 9: Trusted chunks и обновления данных

### 9.1 Generation counter

```dart
int _trustGeneration = 0;
final Map<int, int> _chunkTrustGen = {};
bool isChunkTrusted(int ci) => _chunkTrustGen[ci] == _trustGeneration;
void invalidateAllTrust() { _trustGeneration++; notifyListeners(); }
```

`O(1)` инвалидация вместо итерации по всем чанкам.

### 9.2 Точки сброса

- SSE/WS reconnect → `invalidateAllTrust()`
- `AppLifecycleState.resumed` → `invalidateAllTrust()`
- Переоткрытие чата → `invalidateAllTrust()` + `_chunks.clear()`

### 9.3 Layout integration

В `_layoutChunkRenders`: если `!isChunkTrusted(chunk.index)` и не `isFetching` → запустить refetch. Чанк показывает текущие (возможно устаревшие) данные пока refetch не завершится.

### 9.4 Верификация

- Симуляция reconnect → видимые чанки рефетчатся
- Невидимые чанки НЕ рефетчатся (lazy)
- Обновлённые данные отображаются без мерцания

---

## Этап 10: Animated jump to message

### 10.1 Close jump (сообщение в памяти)

Вычислить текущий offsetY целевого render'а → анимировать `anchorPixelOffset` через `Curves.easeOutCubic` за 200-600ms (пропорционально расстоянию).

### 10.2 Far jump (сообщение не в памяти)

1. Телепорт: `anchorMessageId = targetId`, `anchorPixelOffset = -200` (чуть выше target)
2. Ждём layout + fetch (shimmer)
3. После получения данных — короткая анимация (300ms) к точной позиции

### 10.3 Ticker

`SchedulerBinding.instance.createTicker()` в `RenderChatScrollView`. Анимация работает через дельты — совместима с ренормализацией якоря.

### 10.4 Highlight после jump

Fade-out подсветка целевого сообщения (opacity 1.0 → 0.0 за ~1.5s). Render переопределяет `needsRepaint → true` на время анимации — viewport вызывает `rerecordPicture()` каждый фрейм.

### 10.5 Верификация

- Close jump — плавная анимация
- Far jump — телепорт + финальная анимация
- Jump во время анимации — предыдущая отменяется
- Jump к несуществующему ID — fallback

---

## Этап 11: Оптимизации

### ~~11.1 Разделение scroll/data notifications~~ ✅ Реализовано

Реализовано в рамках OffsetLayer compositing:
- `_notifyScroll()` → `markNeedsPaint()` — только обновление `OffsetLayer.offset`
- `_notifyData()` → `markNeedsLayout()` — полный relayout
- `_repositionChunks()` — пересчёт offsetY без relayout renders

### 11.2 Scrollbar

Отдельный виджет. Thumb position: `(anchorId - minId) / totalCount`. Drag thumb → маппинг позиция → messageId → телепортация.

### 11.3 Keyboard scroll

`RawKeyboardListener` / `Actions+Shortcuts`: Page Up/Down, Home/End, стрелки.

### 11.4 Тесты

- Unit: chunk math, anchor renormalization, LRU eviction, trust generation
- Widget: scroll, fetch, boundary constraints
- Golden: message bubbles, shimmer, selection highlights
- Performance: 10k+ messages, memory usage profiling

---

## Тестирование, бенчмарки и профайлинг

Стратегия: инструментация добавляется рано (после Этапа 1), полноценное сравнение с `ListView.builder` — после Этапа 4. Цель — убедиться что архитектура выигрывает у стандартного подхода и найти слабые места до того, как они закопаются под фичами.

### После Этапа 1 (Scroll) — baseline замер

Минимальный момент для сравнения: есть рендеринг, скролл, compositing layers.

**Timeline инструментация** (`dart:developer`):

```dart
import 'dart:developer';

// В ключевых точках:
Timeline.startSync('ChatScroll.performLayout');
// ... layout code ...
Timeline.finishSync();

Timeline.startSync('ChatScroll.paint');
// ... paint code ...
Timeline.finishSync();

// Частота вызовов:
Timeline.startSync('ChatScroll.attachLayer', arguments: {'messageId': id});
Timeline.finishSync();
```

Точки инструментации:
- `performLayout` — общее время
- `paint` — общее время
- `attachLayer` / `detachLayer` — частота вызовов
- `rerecordPicture` — сколько раз за фрейм

**Unit-тесты** (первая партия):
- `messageIdToChunkIndex` / `messageIdToSlotIndex` — chunk math
- Anchor renormalization
- LRU eviction порядок
- Attach/detach зоны — гистерезис (сообщение в attach zone → attached, между зонами → без изменений, за detach zone → detached)

**Service Protocol метрики**:
- Frame build time vs raster time через `SchedulerBinding`
- `debugDumpLayerTree()` — количество layer'ов

### После Этапа 4 (Fight Club) — полноценный A/B бенчмарк

Первый момент с реалистичными данными и рендерингом.

**A/B benchmark app** — два экрана с переключателем:
- `ListView.builder` с аналогичными виджетами пузырьков
- `ChatScrollView` с `BookMessageRender`
- Одинаковые данные, одинаковый автоматический fling-скролл
- Overlay с метриками: avg/p95/p99 frame time, layer count, memory

**Integration test** (`flutter_test` + `IntegrationTestWidgetsFlutterBinding`):
- Автоматический скролл через 10000 сообщений
- Сбор `FrameTiming` через `SchedulerBinding.instance.addTimingsCallback`
- Assert: p99 < 16ms (60fps)

**Memory profiling**:
- `ProcessInfo.currentRss` до/после длинного скролла
- Количество живых `Picture` объектов
- Верификация что LRU eviction + detach реально освобождают память

### После Этапов 7-8 (Markdown + Selection) — stress-тест

- Сообщения с тяжёлым markdown (code blocks, images, вложенные списки)
- Выделение текста через 50+ сообщений
- Верификация что `rerecordPicture` не вызывается без необходимости
- Golden-тесты: пузырьки, shimmer, selection highlights

### Структура файлов

```
benchmark/
  lib/
    comparison_screen.dart       — A/B: ListView vs ChatScrollView
    auto_scroll_driver.dart      — программный fling с замерами
    metrics_overlay.dart         — overlay с frame times
  integration_test/
    scroll_performance_test.dart

test/
  unit/
    chunk_math_test.dart
    hysteresis_zone_test.dart
    anchor_renorm_test.dart
  widget/
    scroll_basic_test.dart
    fetch_trigger_test.dart
```

### Ключевые метрики для сравнения с ListView.builder

| Метрика | ListView.builder | ChatScrollView | Почему выигрыш |
|---------|-----------------|----------------|-----------------|
| Scroll-only frame | rebuild + layout + paint | paint only (offset update) | Нет Element tree reconciliation |
| Layer count | 1 RepaintBoundary per item | 1 OffsetLayer per message | Сопоставимо |
| Picture re-record | Каждый scroll (RenderParagraph) | Только attach + dirty | Picture кэшируется |
| Memory (idle) | Widget + Element + RenderObject per visible | ChatMessageRender per cached | Меньше объектов |
| GC pressure | Создание/уничтожение виджетов | Reuse renders в чанках | Меньше аллокаций |

---

## Прочее для учёта

- **Accessibility**: `SemanticsNode` per message для screen readers
- **RTL**: `TextDirection` из контекста, зеркальное расположение пузырьков
- **Resize**: `performLayout` автоматически вызовется, все `TextPainter` нужно relayout (`_markAllRendersDirty`)
- **Hot reload**: `updateRenderObject` уже обрабатывает смену controller/builder
- **Memory**: `OffsetLayer` + `PictureLayer` + `ui.Picture` + `TextPainter` — основные потребители. Attach/detach зоны с гистерезисом контролируют количество живых слоёв, LRU eviction контролирует чанки
- **Platform scroll**: мышь (mousewheel) → `Listener` на `PointerScrollEvent` → `anchorPixelOffset += event.scrollDelta.dy`
- **Trackpad**: momentum scrolling на macOS — `PointerScrollEvent` уже содержит momentum-дельты
