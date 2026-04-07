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
| Widget       | `ChatScrollView` (Leaf) | Публичный API: `controller` + `builder`                |
| RenderObject | `RenderChatScrollView`  | Layout, paint, hit-testing, chunk management, eviction |

Element создаётся автоматически фреймворком (стандартный `LeafRenderObjectElement`), кастомный не нужен.

## Публичный API

```dart
ChatScrollView(
  controller: chatScrollController,
  builder: (IChatMessage message) => MyMessageRender(message),
)
```

- `controller` — `ChatScrollController`, владеет данными (чанки), anchor-состоянием и fetch-функцией
- `builder` — `ChatMessageRenderFactory`, создаёт `ChatMessageRender` для каждого сообщения

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
- Телепортация к любому сообщению — просто смена anchor + `notifyListeners()`
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
class _ChatScrollChunk {
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

1. **Создание**: `ChatMessageRenderFactory(message)` — при первом появлении сообщения в layout
2. **Обновление**: `update(message, status)` — при каждом последующем layout; subclass сравнивает через `identical` и решает, нужен ли relayout
3. **Layout**: `performLayout(width) → height` — вычисляет размер, строит layout-кэш (TextPainter'ы и т.д.)
4. **Paint**: `paintMessage(canvas, size)` — рисует на canvas
5. **Dispose**: `dispose()` — освобождает ресурсы

### Compositing-архитектура (OffsetLayer per message)

Каждое сообщение владеет поддеревом `OffsetLayer` → `PictureLayer`. Viewport управляет жизненным циклом слоёв через зоны видимости с гистерезисом.

```dart
abstract class ChatMessageRender {
  // Subclass переопределяет — что рисовать
  void paintMessage(Canvas canvas, Size size);

  // Viewport вызывает при входе в attach-зону
  void attachLayer(double width);   // создаёт OffsetLayer → PictureLayer

  // Viewport вызывает при выходе из detach-зоны
  void detachLayer();               // высвобождает слои и Picture

  // Пересоздать PictureLayer (анимация, invalidatePaint)
  void rerecordPicture();

  // Для анимированных сообщений — viewport пересоздаёт Picture каждый фрейм
  bool get needsRepaint => false;

  void invalidatePaint() {
    if (_attached) rerecordPicture();
  }
}
```

- **Статичное сообщение**: `paintMessage` вызывается один раз при `attachLayer`, результат кэшируется в `PictureLayer`. При скролле обновляется только `OffsetLayer.offset` — GPU композитит без re-record
- **Анимированное сообщение**: subclass переопределяет `needsRepaint → true`, viewport вызывает `rerecordPicture()` каждый фрейм и планирует следующий через `markNeedsPaint()`

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

Detach-зона шире attach-зоны — предотвращает thrashing при мелких подёргиваниях скролла. Между зонами — ничего не делать (гистерезис).

### Update и dirty-флаг

`update(IChatMessage, ChatMessageStatus)` — абстрактный. Базовый класс не хранит message/status, это решение subclass'а. Subclass сам решает:

- Изменились ли данные → `dirty = true` (нужен relayout + repaint)
- Изменился ли визуал без изменения размера → `invalidatePaint()` (только repaint)
- Ничего не изменилось → ничего не делает

### Поля, управляемые viewport'ом

```dart
@nonVirtual double offsetY = 0.0;   // позиция в viewport
@nonVirtual double height = 0.0;    // высота после layout
@nonVirtual bool dirty = true;       // нужен relayout

// Layer-поля
OffsetLayer? _layer;                 // compositing layer
PictureLayer? _pictureLayer;         // cached picture
bool _attached = false;              // есть ли живой layer
double _layerWidth = 0.0;            // ширина для записи
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

## ChatScrollController

```dart
abstract class ChatScrollController extends ChangeNotifier {
  Future<List<IChatMessage>> fetch({int? from, int? to, DateTime? after});

  int get maxChunks => 16; // ≈ 1024 сообщений

  // Anchor state
  int anchorMessageId;
  double anchorPixelOffset;
  void jumpTo(int messageId);
}
```

- Владеет `Map<int, _ChatScrollChunk>` — хранилище чанков
- `RenderChatScrollView` читает данные напрямую из контроллера
- Изменение anchor → `notifyListeners()` → `markNeedsLayout()`
- `maxChunks` — лимит на количество чанков в памяти (для LRU-eviction)

## Layout (performLayout)

Chunk-based, от anchor в обе стороны:

```
1. Определить anchorChunkIndex по anchorMessageId
2. Layout anchor chunk → _layoutChunkRenders(chunk, width)
3. Позиционировать anchor chunk так, чтобы anchorId.top == anchorPixelOffset
4. Layout чанков вниз, пока не выйдем за viewport + cacheExtent
5. Layout чанков вверх аналогично
6. Evict старых чанков
```

### \_layoutChunkRenders

Для каждого сообщения в чанке:

1. Бамп `lastAccessTick` (LRU)
2. Если render отсутствует — создать через factory
3. Если render есть — вызвать `update(message, status)`
4. Если `dirty` — вызвать `performLayout(width)`, обновить высоту, сбросить picture-кэш
5. Суммировать высоты → `chunk.height`

### \_positionChunkRenders

Последовательно расставляет `offsetY` каждого render'а, начиная от `chunk.offsetY`.

## Paint (layer-tree based)

Viewport строит дерево слоёв вместо рисования на canvas:

```
ClipRectLayer (корень, = layer viewport'а)
  ├─ OffsetLayer (msg 1) → PictureLayer
  ├─ OffsetLayer (msg 2) → PictureLayer
  ├─ ...
  └─ PictureLayer (sticky overlays — аватары, даты; будущее)
```

Один проход по laid-out чанкам:

```
1. Scroll-only? → _repositionChunks() (пересчёт offsetY без relayout)
2. Для каждого render:
   a. attached + вне detach-зоны → detachLayer()
   b. attached + в зоне → обновить OffsetLayer.offset
   c. attached + needsRepaint → rerecordPicture()
   d. !attached + в attach-зоне → attachLayer(), установить offset
3. clipLayer.removeAllChildren()
4. Re-append все attached layers в порядке чанков
   (порядок не критичен — сообщения не перекрываются)
5. Append sticky overlay layer последним (поверх всех)
```

Viewport является `isRepaintBoundary = true` и `alwaysNeedsCompositing = true`.

### Scroll-only оптимизация

`ChatScrollController` разделяет уведомления:

- `anchorPixelOffset` setter → `_notifyScroll()` → viewport вызывает только `markNeedsPaint()`
- Изменение данных/anchor ID → `_notifyData()` → viewport вызывает `markNeedsLayout()`

При scroll-only: `_repositionChunks()` пересчитывает offsetY всех renders от текущего anchor, затем paint обновляет `OffsetLayer.offset`. Никакого relayout, никакого re-record Picture.

## LRU Eviction

При каждом layout проверяется количество чанков. Если превышен `maxChunks`:

1. Подсчитать `toRemove = chunks.length - maxChunks`
2. Алгоритм partial selection: фиксированный массив из `toRemove` элементов
3. За один проход по `chunks.values` (O(n·k)) — найти `toRemove` чанков с наименьшим `lastAccessTick`
4. Чанки из текущего layout диапазона `[_layoutMinChunk, _layoutMaxChunk]` не evict'ятся
5. Dispose renders жертв, удалить из map

Преимущество: нет аллокации growable list, нет сортировки. Один проход с фиксированным массивом.

## Hit Testing

```dart
bool hitTestSelf(Offset position) => true;
```

Viewport перехватывает все жесты внутри своих bounds. `ChatMessageRender.hitTest(position)` — для будущего per-message hit-testing.

## Телепортация (Jump to message)

```dart
controller.jumpTo(messageId);
// anchorMessageId = messageId
// anchorPixelOffset = 0.0
// notifyListeners() → markNeedsLayout()
```

В следующем фрейме `performLayout` лейаутит от нового anchor. Никакой анимированной прокрутки через тысячи сообщений — мгновенный переход.

## Скроллбар (планируется)

- Отдельный виджет, не связанный со scroll offset
- Позиция thumb: `(anchorId - minId) / totalCount`
- Drag скроллбара → маппинг `thumbPosition → targetMessageId` → телепортация

## Scroll-физика (планируется)

Без sliver-протокола, через жесты и симуляцию:

```dart
// Drag
anchorPixelOffset += delta.dy;

// Fling (инерция)
ClampingScrollSimulation → каждый тик обновляет anchorPixelOffset
```

Когда offset выносит за границу текущего anchor-сообщения — anchor пересчитывается на соседнее.

## Selection (планируется)

Двухрежимная модель на уровне viewport:

```dart
enum SelectionMode { none, text, messages }
```

1. Drag начинается → hit-test определяет сообщение → `mode = text`
2. Drag выходит за границу сообщения → `mode = messages`, выделяются сообщения целиком

Перерисовка выделения — через `invalidatePaint()` без relayout.

## Диаграмма зависимостей

```
ChatScrollView (LeafRenderObjectWidget)
  └─ RenderChatScrollView (RenderBox, alwaysNeedsCompositing)
       │
       ├─ reads ─── ChatScrollController
       │              ├─ anchor state (messageId, pixelOffset)
       │              ├─ _scrollOnly flag (_notifyScroll vs _notifyData)
       │              ├─ Map<int, _ChatScrollChunk>
       │              │    ├─ messages[64]  (IChatMessage?)
       │              │    ├─ renders[64]   (ChatMessageRender?)
       │              │    ├─ status        (ChatMessageStatus)
       │              │    ├─ offsetY, height
       │              │    └─ lastAccessTick
       │              └─ fetch(), maxChunks
       │
       ├─ creates ── ChatMessageRender (via factory)
       │               ├─ update()
       │               ├─ performLayout() → height
       │               ├─ paintMessage() → recorded into PictureLayer
       │               ├─ attachLayer() / detachLayer() (lifecycle)
       │               ├─ rerecordPicture() (animation / invalidate)
       │               ├─ needsRepaint → bool
       │               └─ dispose()
       │
       └─ layer tree:
            ClipRectLayer
              ├─ OffsetLayer(msg) → PictureLayer  (per attached render)
              ├─ ...
              └─ PictureLayer (sticky overlays, future)
```
