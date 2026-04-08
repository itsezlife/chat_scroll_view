# Chat Viewport Architecture

## Обзор

Кастомный viewport для Flutter-чата, построенный на chunk-based архитектуре. Использует `LeafRenderObjectWidget` — все сообщения рисуются на одном canvas без child-виджетов. Каждое сообщение представлено лёгким `ChatMessageRender` объектом с `ui.Picture` кэшированием.

## Почему не стандартные решения

### ListView.builder — не подходит

- Привязан к пиксельным координатам, требует `maxScrollExtent` (знание общей высоты всех сообщений)
- Прыжок к произвольному message ID без знания пиксельного смещения невозможен без хаков
- Скроллбар требует пересчёта layout всех сообщений

### Sliver-протокол — создаёт больше проблем, чем решает

- `SliverConstraints.scrollOffset` — абсолютное пиксельное смещение от начала
- При телепортации к сообщению 1500 нужно объяснить framework'у новый `scrollOffset`, что приводит к постоянным коррекциям через `ScrollPosition.correctBy()`
- Мы не используем ни один плюс slivers (SliverList, SliverGrid, координированный скролл нескольких slivers)

### MultiChildRenderObjectWidget — лишний overhead

- Каждое сообщение — полноценный Element + RenderObject, которые нам не нужны
- Мы не используем виджет-дерево внутри сообщений (Markdown, облачка — всё рисуется на canvas)
- Element lifecycle management (inflateWidget, deactivateChild) дублирует логику, которая проще решается через массив `ChatMessageRender`

## Выбранный подход

`LeafRenderObjectWidget` + `RenderBox` — один RenderObject на весь viewport. Сообщения — это лёгкие `ChatMessageRender` объекты (не RenderObject), хранящиеся в чанках.

### Два слоя вместо трёх

| Слой         | Класс                   | Ответственность                                        |
| ------------ | ----------------------- | ------------------------------------------------------ |
| Widget       | `ChatScrollView` (Leaf) | Публичный API: `dataSource` + `controller` + `builder` |
| RenderObject | `RenderChatScrollView`  | Layout, paint, hit-testing, chunk management, eviction |

Element создаётся автоматически фреймворком (стандартный `LeafRenderObjectElement`), кастомный не нужен.

## Файловая структура

```
lib/src/
  chat_scroll_view_common.dart   # IChatMessage, ChatMessageStatus
  chat_message.dart              # ChatMessage, ChatMessage$User/System
  chat_scroll/
    chat_scroll_chunk.dart       # ChatScrollChunk (@internal)
    chat_message_render.dart     # ChatMessageRender, ChatMessageRenderFactory
    chat_data_source.dart        # ChatDataSource (данные + fetch + typed listeners)
    chat_scroll_controller.dart  # ChatScrollController (навигация + границы + typed listeners)
    chat_scroll_layout.dart      # ChatScrollLayoutHelper (stateless, устраняет дупликацию)
    chat_scroll_view.dart        # ChatScrollView + RenderChatScrollView (Ticker-driven)
```

### Граф зависимостей

```
chat_scroll_view_common.dart   (IChatMessage, ChatMessageStatus)
       |
       v
chat_scroll_chunk.dart         (ChatScrollChunk)
       |
       v
chat_message_render.dart       (ChatMessageRender, ChatMessageRenderFactory)
       |
       ├─────────────────────────────────┐
       v                                 v
chat_data_source.dart            chat_scroll_controller.dart
(ChatDataSource)                 (ChatScrollController)
       |                                 |
       └────────────┬────────────────────┘
                    v
       chat_scroll_layout.dart   (ChatScrollLayoutHelper)
                    |
                    v
       chat_scroll_view.dart     (ChatScrollView, RenderChatScrollView)
```

## Публичный API

```dart
ChatScrollView(
  dataSource: myDataSource,       // откуда данные (чанки + fetch)
  controller: myScrollController, // навигация + границы
  builder: (msg) => MyRender(msg),
)
```

### IChatMessage

```dart
abstract interface class IChatMessage {
  abstract final int id;
  abstract final DateTime createdAt;
  abstract final DateTime updatedAt;
}
```

Минимальный контракт для данных сообщения. Конкретная реализация добавляет свои поля (текст, автор, вложения).

## Система координат

Anchor-based, без абсолютных пиксельных смещений:

```
anchorMessageId: int       // ID сообщения — начало координат
anchorPixelOffset: double  // смещение top edge anchor-сообщения от top viewport
```

- Никакого маппинга ID → абсолютные пиксели
- Телепортация к любому сообщению — просто `controller.jumpTo(id)`
- Layout всегда от anchor-чанка в обе стороны, пока не заполнится viewport + cacheExtent

## ID сообщений

- Непрерывная последовательность целых чисел: `..., -2, -1, 0, 1, 2, ...`
- Пропусков нет (soft delete отображается как "сообщение удалено")
- В сторону `+∞` — всегда могут прийти новые сообщения
- В сторону `-∞` — скроллим, пока сервер не вернёт пустой ответ
- Стартовая позиция — `maxId`, прижат к низу viewport

## Chunk-архитектура

```
CHUNK_BITS = 6
CHUNK_SIZE = 64

chunkIndex   = msgId >> 6  (для положительных)
indexInChunk = msgId - chunk.firstId
```

### Структура чанка

```dart
class ChatScrollChunk {
  final int index;            // chunk index
  final int firstId;          // first message id (inclusive)
  int get lastId;             // firstId + 63

  List<IChatMessage?> messages; // [64] — данные
  List<ChatMessageRender?> renders; // [64] — рендеры (лениво)

  ChatMessageStatus status;   // dirty, fetching, error, valid (bitfield)
  int lastAccessTick;          // LRU — бамп при layout
  double offsetY;              // Y позиция в viewport
  double height;               // суммарная высота всех renders
}
```

### Отрицательные ID

Арифметический сдвиг корректно работает для отрицательных:

```
id =  64  → chunkIndex =  1, firstId =  64
id =   0  → chunkIndex =  0, firstId =   0
id =  -1  → chunkIndex = -1, firstId = -64
id = -64  → chunkIndex = -1, firstId = -64
id = -65  → chunkIndex = -2, firstId = -128
```

Чанк `-1` содержит сообщения от `-64` до `-1`, чанк `0` — от `0` до `63`. Непрерывность сохраняется.

## ChatMessageRender

Лёгкий объект рендеринга (не Flutter RenderObject). Каждое сообщение имеет свой `ChatMessageRender`, который управляет layout-кэшем и picture-кэшем.

### Жизненный цикл

```
create (factory)
  → update() → performLayout() → height
  → [enters attach zone]  → attachLayer()  (@mustCallSuper, creates layers → subclass reacts)
  → paintMessage()
  → [scroll]               → OffsetLayer.offset updated (GPU composites)
  → [leaves detach zone]  → detachLayer()  (@mustCallSuper, subclass cleanup → super disposes)
  → [может повторно attach/detach при скролле туда-обратно]
  → dispose()              (eviction / RenderBox.dispose)
```

### API

```dart
abstract class ChatMessageRender {
  // --- Subclass overrides ---
  void update(covariant IChatMessage? message, ChatMessageStatus status);
  double performLayout(double availableWidth);
  void paintMessage(Canvas canvas, Size size);

  /// Сообщение входит в видимую зону. Override для анимаций, ресурсов, стримов.
  @mustCallSuper
  void attachLayer(double width);

  /// Сообщение покидает видимую зону. Override для остановки анимаций.
  @mustCallSuper
  void detachLayer();

  /// Есть ли живые layers.
  bool get isAttached;

  /// Пересоздать PictureLayer (анимация, invalidatePaint).
  void rerecordPicture();

  /// Для анимированных сообщений — viewport пересоздаёт Picture каждый фрейм.
  bool get needsRepaint => false;

  void invalidatePaint() {
    if (isAttached) rerecordPicture();
  }
}
```

### Compositing-архитектура (OffsetLayer per message)

Каждое сообщение владеет поддеревом `OffsetLayer` → `PictureLayer`. Viewport управляет жизненным циклом слоёв через зоны видимости с гистерезисом.

- **Статичное сообщение**: `paintMessage` вызывается один раз при `attachLayer`, результат кэшируется в `PictureLayer`. При скролле обновляется только `OffsetLayer.offset` — GPU композитит без re-record
- **Анимированное сообщение**: subclass переопределяет `needsRepaint → true`, viewport вызывает `rerecordPicture()` каждый фрейм

### Зоны видимости (гистерезис)

```
static const double _attachFactor = 1.0;  // attach: 1× viewport от краёв
static const double _detachFactor = 1.7;  // detach: 1.7× viewport от краёв

         ┌─────────────────────┐
         │   detach zone       │  -detachExtent
         │  ┌───────────────┐  │
         │  │ attach zone   │  │  -attachExtent
         │  │ ┌───────────┐ │  │
         │  │ │ VIEWPORT  │ │  │   0 .. viewportHeight
         │  │ └───────────┘ │  │
         │  │ attach zone   │  │  +attachExtent
         │  └───────────────┘  │
         │   detach zone       │  +detachExtent
         └─────────────────────┘
```

Detach-зона шире attach-зоны — предотвращает thrashing при мелких подёргиваниях скролла.

### Update и dirty-флаг

`update(IChatMessage? message, ChatMessageStatus status)` — абстрактный. Базовый класс не хранит message/status, это решение subclass'а. Subclass сам решает:

- Изменились ли данные → `dirty = true` (нужен relayout + repaint)
- Изменился ли визуал без изменения размера → `invalidatePaint()` (только repaint)
- Ничего не изменилось → ничего не делает

### Поля, управляемые viewport'ом

```dart
@nonVirtual double offsetY = 0.0;   // позиция в viewport
@nonVirtual double height = 0.0;    // высота после layout
@nonVirtual bool dirty = true;       // нужен relayout

// Layer-поля (@internal — доступны viewport'у, недоступны subclass'у)
OffsetLayer? layer;                  // compositing layer
double layerWidth = 0.0;            // ширина для записи
bool pictureInvalid = false;        // нужен re-record
```

## ChatMessageStatus (bitfield)

```dart
extension type const ChatMessageStatus._(int _value) {
  static const valid    = ChatMessageStatus._(0);
  static const dirty    = ChatMessageStatus._(1 << 0);
  static const error    = ChatMessageStatus._(1 << 1);
  static const fetching = ChatMessageStatus._(1 << 2);

  bool contains(ChatMessageStatus flag);
  ChatMessageStatus add(ChatMessageStatus flag);
  ChatMessageStatus remove(ChatMessageStatus flag);
}
```

Используется как extension type для type-safe bitfield. Чанк может одновременно быть `dirty | fetching`. Передаётся в `ChatMessageRender.update` — рендер может отображать состояние загрузки.

## ChatDataSource — данные

Владеет чанками и fetch-контрактом. Typed listeners вместо ChangeNotifier.

```dart
abstract class ChatDataSource {
  // --- Fetch контракт (subclass реализует) ---
  Future<List<IChatMessage>> fetch({int? from, int? to, DateTime? after});
  int get maxChunks => 16;

  // --- Хранилище ---
  IChatMessage? getMessage(int messageId);
  void upsertMessage(IChatMessage message);
  void upsertMessages(Iterable<IChatMessage> messages);

  // --- Typed listener: данные изменились ---
  void addDataListener(VoidCallback cb);
  void removeDataListener(VoidCallback cb);

  // --- Viewport-only доступ ---
  @internal Map<int, ChatScrollChunk> get chunks;
}
```

**Кто слушает:** viewport (`_onDataChanged → markNeedsLayout()`), пользователь (UI-индикаторы).

## ChatScrollController — навигация + границы

Владеет anchor-состоянием и boundary-флагами. Typed listeners.

```dart
class ChatScrollController {
  // --- Jump: typed listener с payload ---
  void addJumpListener(ValueChanged<int> cb);
  void removeJumpListener(ValueChanged<int> cb);
  void jumpTo(int messageId);

  // --- Boundary: typed listener ---
  void addBoundaryListener(VoidCallback cb);
  void removeBoundaryListener(VoidCallback cb);

  bool reachedOldest;
  bool reachedNewest;
  int? oldestKnownId;
  int? newestKnownId;

  // --- Anchor state (read-only для пользователя) ---
  int get anchorMessageId;
  double get anchorPixelOffset;

  // --- Viewport-only: тихая мутация без нотификаций ---
  @internal void applyScrollDelta(double delta);
  @internal void reassignAnchor(int messageId, double pixelOffset);
}
```

**Кто слушает:**

- `addJumpListener` → viewport (`_cancelFling(); markNeedsLayout()`), пользователь ("scroll to bottom" кнопка)
- `addBoundaryListener` → viewport (`markNeedsLayout()`), пользователь ("показать FAB при reachedNewest == false")

### Сравнение с ChangeNotifier

```
ChangeNotifier (один контроллер):
  notifyListeners()                         // "что-то произошло"
  + _scrollOnly флаг                        // маршрутизация в listener'е
  + _pendingScrollOnly, _layoutPending      // координация pipeline

Typed listeners (два контроллера):
  dataSource.notifyDataChanged()            → viewport._onDataChanged()
  scrollController.jumpTo(id)               → viewport._onJump(id)
  scrollController.reachedNewest = true     → viewport._onBoundaryChanged()
  [scroll delta]                            → _pendingScrollDelta (Ticker, без нотификаций)
```

0 флагов маршрутизации. Каждый listener знает что произошло.

## Scroll-архитектура: Ticker-driven

### Два пути обработки событий

```
                    ┌─────────────────────┐
                    │      СОБЫТИЕ        │
                    └─────────┬───────────┘
                              │
         ┌────────────────────┼────────────────────┐
         │                    │                    │
 ┌───────▼────────┐  ┌───────▼────────┐  ┌───────▼──────────┐
 │  DRAG           │  │  FLING/ANIM    │  │  DATA CHANGE     │
 │  (pointer event)│  │  (simulation)  │  │  (upsert, jumpTo,│
 └───────┬────────┘  └───────┬────────┘  │   resize, fonts) │
         │                    │           └───────┬──────────┘
         ▼                    │                    │
  _pendingDelta += dy         │           markNeedsLayout()
  _ticker.start()             │                    │
         │                    │                    ▼
         └────────┬───────────┘           ┌──────────────────┐
                  │                       │  layout + paint   │
                  ▼                       │  (framework path) │
         ┌─────────────────┐              │                   │
         │  TICKER TICK     │              │ layoutChunks()    │
         │  (animation      │              │ position()        │
         │   phase, ДО      │              │ renormalize()     │
         │   paint)         │              │ clampBounds()     │
         │                  │              │ evict()           │
         │ consume delta    │              └──────────────────┘
         │ advance fling    │
         │ reposition()     │
         │ clampBounds()    │
         │ attach/detach    │
         │ update offsets   │
         │                  │
         │ Compositor       │
         │ re-composites    │
         │ (без paint!)     │
         └─────────────────┘
```

**Ключевое:** scroll-only path полностью обходит paint pipeline.
Ticker → обновляет OffsetLayer.offset → compositor re-composites → GPU рисует.
Никакого markNeedsPaint, никакого paint().

### Когда paint() вызывается

- Initial paint: `context.addLayer(clipLayer)` регистрирует layer tree
- Resize: clipRect меняется
- Data change: новые messages → новые layers

### Ticker lifecycle

```dart
void attach(PipelineOwner owner) {
  super.attach(owner);
  _ticker = Ticker(_onTick);  // vsync через SchedulerBinding
}
void detach() {
  _ticker?.dispose();
  super.detach();
}
```

Ticker автоматически останавливается при `framesEnabled = false` (app backgrounded).
Start/stop по необходимости — idle чат не тикает.

## Layout (performLayout)

Chunk-based, от anchor в обе стороны. Единый метод `positionFromAnchor()` (ChatScrollLayoutHelper) устраняет тройное дублирование:

```
1. Определить anchorChunkIndex по anchorMessageId
2. Layout anchor chunk → layoutChunkRenders(chunk, width, builder)
3. Позиционировать anchor chunk: offsetY = anchorPixelOffset - beforeAnchorHeight
4. Layout + позиционирование вниз, пока не выйдем за viewport + cacheExtent
5. Layout + позиционирование вверх аналогично
6. renormalizeAnchor() — если anchor за cacheExtent
7. clampScrollBoundaries() — граничные условия
8. evictChunks() — LRU eviction (maxChunks = 16)
```

### positionFromAnchor — единственная копия

Вызывается из обоих путей:

- Full layout: `positionFromAnchor(layoutChunk: _doLayout)`
- Ticker scroll-only: `positionFromAnchor()` (без layout, только reposition)

### LRU Eviction

Простой while-цикл вместо over-engineered partial selection:

```dart
while (chunks.length > maxChunks) {
  // Найти chunk с наименьшим lastAccessTick вне layout range
  // Dispose renders, удалить из map
}
```

O(n·k), k ≈ 1-2 evictions. `lastAccessTick` естественно защищает недавно использованные чанки.

## Paint (layer-tree based)

Viewport строит дерево слоёв:

```
ClipRectLayer (корень, = layer viewport'а)
  ├─ OffsetLayer (msg 1) → PictureLayer
  ├─ OffsetLayer (msg 2) → PictureLayer
  ├─ ...
  └─ PictureLayer (sticky overlays — аватары, даты; будущее)
```

## Hit Testing

```dart
bool hitTestSelf(Offset position) => true;
```

Viewport перехватывает все жесты внутри своих bounds.

## Телепортация (Jump to message)

```dart
controller.jumpTo(messageId);
// anchorMessageId = messageId
// anchorPixelOffset = 0.0
// → _jumpListeners → viewport._onJump(id) → markNeedsLayout()
```

Мгновенный переход, layout от нового anchor в следующем фрейме.

## Debug инструментация

Stopwatch через assert-pattern — zero-cost в release:

```dart
assert(() { _debugSw..reset()..start(); return true; }());
_performLayoutImpl();
assert(() { debugLastLayoutDuration = _debugSw.elapsed; _debugSw.stop(); return true; }());
```

## Диаграмма зависимостей

```
ChatScrollView (LeafRenderObjectWidget)
  └─ RenderChatScrollView (RenderBox, alwaysNeedsCompositing)
       │
       ├─ reads ─── ChatDataSource
       │              ├─ Map<int, ChatScrollChunk>
       │              │    ├─ messages[64]  (IChatMessage?)
       │              │    ├─ renders[64]   (ChatMessageRender?)
       │              │    ├─ status        (ChatMessageStatus)
       │              │    ├─ offsetY, height
       │              │    └─ lastAccessTick
       │              ├─ addDataListener()
       │              └─ fetch(), maxChunks
       │
       ├─ reads ─── ChatScrollController
       │              ├─ anchor state (messageId, pixelOffset)
       │              ├─ boundaries (reachedOldest, reachedNewest)
       │              ├─ addJumpListener(), addBoundaryListener()
       │              └─ applyScrollDelta(), reassignAnchor() (@internal)
       │
       ├─ creates ── ChatMessageRender (via factory)
       │               ├─ update()
       │               ├─ performLayout() → height
       │               ├─ paintMessage() → recorded into PictureLayer
       │               ├─ attachLayer() / detachLayer() (@mustCallSuper)
       │               ├─ rerecordPicture() (animation / invalidate)
       │               ├─ needsRepaint → bool
       │               └─ dispose()
       │
       ├─ owns ───── Ticker (_onTick: scroll-only path)
       │               ├─ consume _pendingScrollDelta
       │               ├─ advance ClampingScrollSimulation
       │               ├─ positionFromAnchor()
       │               ├─ clampBoundaries()
       │               └─ updateLayers() → OffsetLayer.offset
       │
       └─ layer tree:
            ClipRectLayer
              ├─ OffsetLayer(msg) → PictureLayer  (per attached render)
              ├─ ...
              └─ PictureLayer (sticky overlays, future)
```

## Скроллбар (планируется)

- Отдельный виджет, не связанный со scroll offset
- Позиция thumb: `(anchorId - minId) / totalCount`
- Drag скроллбара → маппинг `thumbPosition → targetMessageId` → телепортация

## Selection (планируется)

Двухрежимная модель на уровне viewport:

```dart
enum SelectionMode { none, text, messages }
```

1. Drag начинается → hit-test определяет сообщение → `mode = text`
2. Drag выходит за границу сообщения → `mode = messages`, выделяются сообщения целиком

Перерисовка выделения — через `invalidatePaint()` без relayout.
