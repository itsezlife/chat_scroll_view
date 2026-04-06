# Chat Viewport Architecture

## Обзор

Кастомный viewport для Flutter-чата, построенный на chunk-based архитектуре сообщений. Полностью кастомный scroll и rendering без использования sliver-протокола Flutter.

## Почему не стандартные решения

### ListView.builder — не подходит

- Привязан к пиксельным координатам, требует `maxScrollExtent` (знание общей высоты всех сообщений)
- Прыжок к произвольному message ID без знания пиксельного смещения невозможен без хаков
- Скроллбар требует пересчёта layout всех сообщений

### Sliver-протокол — создаёт больше проблем, чем решает

- `SliverConstraints.scrollOffset` — абсолютное пиксельное смещение от начала
- При телепортации к сообщению 1500 нужно объяснить framework'у новый `scrollOffset`, что приводит к постоянным коррекциям через `ScrollPosition.correctBy()`
- Мы не используем ни один плюс slivers (SliverList, SliverGrid, координированный скролл нескольких slivers)

## Выбранный подход

Кастомный `RenderObjectWidget` + кастомный `Element` + `RenderBox` с `ContainerRenderObjectMixin`.

### Три слоя

| Слой         | Базовый класс                              | Ответственность                                            |
| ------------ | ------------------------------------------ | ---------------------------------------------------------- |
| Widget       | `RenderObjectWidget`                       | Публичный API: `fetch` + `builder`                         |
| Element      | `RenderObjectElement`                      | Ленивое создание/удаление children по запросу RenderObject |
| RenderObject | `RenderBox` + `ContainerRenderObjectMixin` | Layout, paint, hit-testing, scroll-физика                  |

## Публичный API

```dart
ChatScrollView(
  Future<List<ChatMessage>> Function({int? from, int? to, DateTime? after}) fetch,
  Widget Function(ChatMessage message) builder,
)
```

- `fetch` — пагинация и обновление данных с сервера
- `builder` — построение виджета для каждого сообщения

## Система координат

Anchor-based, без абсолютных пиксельных смещений:

```
anchorMessageId: int       // ID сообщения — начало координат
anchorPixelOffset: double  // смещение anchor от точки привязки в viewport
```

- Никакого маппинга ID → абсолютные пиксели
- Телепортация к любому сообщению — просто смена anchor + markNeedsLayout
- Layout всегда от anchor в обе стороны, пока не заполнится viewport + cacheExtent

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

chunkId      = msgId >> 6
indexInChunk = msgId & 63
```

### Отрицательные ID

Арифметический сдвиг вправо корректно работает для отрицательных чисел и в Dart, и в Rust:

```
id =  64  → chunkId =  1, index =  0
id =   0  → chunkId =  0, index =  0
id =  -1  → chunkId = -1, index = 63
id = -64  → chunkId = -1, index =  0
id = -65  → chunkId = -2, index = 63
```

Чанк `-1` содержит сообщения от `-64` до `-1`, чанк `0` — от `0` до `63`. Непрерывность сохраняется.

## Взаимодействие слоёв

```
RenderObject: "мне нужны children для id 1500..1560"
      ↓ callback
Element: вызывает builder для каждого id,
         inflateWidget → создаёт Element + RenderObject,
         insertChildRenderObject → добавляет в parent
      ↓
RenderObject: markNeedsLayout, лейаутит появившихся детей
```

### Element — управление жизненным циклом

```dart
class ChatScrollElement extends RenderObjectElement {
  final Map<int, Element> _childElements = {};

  void buildChildren(int fromId, int toId) {
    for (var id = fromId; id <= toId; id++) {
      if (!_childElements.containsKey(id)) {
        final message = _controller.getMessage(id);
        if (message != null) {
          final widget = widget.builder(message);
          final element = inflateWidget(widget, ...);
          _childElements[id] = element;
        }
      }
    }
    // убираем далёких от viewport
    _childElements.removeWhere((id, element) {
      if (id < fromId - 128 || id > toId + 128) {
        deactivateChild(element);
        return true;
      }
      return false;
    });
  }
}
```

### RenderObject — layout

```dart
class RenderChatViewport extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, ChatParentData> {

  int anchorMessageId;
  double anchorPixelOffset;

  @override
  void performLayout() {
    var y = anchorPixelOffset;
    var id = anchorMessageId;

    // Лейаут вниз от anchor
    while (y < size.height + cacheExtent) {
      final child = getChildForId(id);
      if (child == null) {
        _needsChildrenCallback!(id, id + 64);
        break;
      }
      child.layout(constraints, parentUsesSize: true);
      (child.parentData as ChatParentData).offset = Offset(0, y);
      y += child.size.height;
      id++;
    }

    // Аналогично вверх от anchor
    // ...
  }
}
```

## Scroll-физика

Без sliver-протокола, подключается вручную через жесты и симуляцию:

```dart
// Drag
anchorPixelOffset += delta.dy;
markNeedsLayout();

// Fling (инерция)
_simulation = ClampingScrollSimulation(
  position: anchorPixelOffset,
  velocity: details.velocity.pixelsPerSecond.dy,
);
_ticker.start(); // каждый тик: anchorPixelOffset = _simulation.x(t)
```

Когда offset выносит за границу текущего anchor-сообщения — anchor пересчитывается на соседнее.

## Телепортация (Jump to message)

```dart
void jumpTo(int messageId) {
  anchorMessageId = messageId;
  anchorPixelOffset = 0.0;
  // сброс кэша children далеко от нового anchor
  markNeedsLayout();
}
```

В следующем фрейме `performLayout` запрашивает нужный чанк, лейаутит от нового anchor. Никакой анимированной прокрутки через тысячи сообщений.

## Скроллбар

- Отдельный виджет, не связанный со scroll offset
- Позиция thumb: `(anchorId - minId) / totalCount`
- `totalCount` = `maxId - minId + 1`, пересчитывается при обнаружении новых границ
- `minId` изначально предполагается `0`, расширяется при скролле вверх
- Drag скроллбара → маппинг `thumbPosition → targetMessageId` → телепортация
- Fast-scroll режим (press-hold) с on-demand chunk loading

## Rendering сообщений

Каждое сообщение — кастомный `RenderBox` с canvas-отрисовкой (Markdown, облачки и т.д.):

```
MessageRenderBox
  ├─ List<LayoutBlock> layoutCache
  │    ├─ ParagraphBlock { TextPainter, Offset }
  │    ├─ CodeBlock { TextPainter, Rect background }
  │    └─ ...
  ├─ performLayout() → строит layoutCache, вычисляет size
  ├─ paint() → итерирует layoutCache, рисует на canvas
  └─ getTextPosition(Offset) → блок по Y → TextPainter.getPositionForOffset()
```

### Оптимизация перерисовки

Без `RepaintBoundary` (один viewport RenderBox) любое изменение → перерисовка всего. Решение: кэширование отрисованных сообщений в `ui.Picture` через `PictureRecorder`, в `paint()` — `canvas.drawPicture()` для неизменённых, перерисовка только dirty.

## Selection (выделение)

Двухрежимная модель, управляется на уровне viewport:

```dart
enum SelectionMode { none, text, messages }

class ChatSelectionState {
  SelectionMode mode;

  // mode == text:
  int messageId;
  int startOffset;
  int endOffset;

  // mode == messages:
  int startMessageId;
  int endMessageId;
}
```

### Логика переключения

1. Drag начинается → hit-test определяет сообщение → `mode = text`
2. Drag выходит за границу сообщения → `mode = messages`, выделяются сообщения целиком

## Данные и загрузка

- Fetch-функция живёт в контроллере, не в Element
- Element берёт данные из кэша контроллера
- Кэш пуст → контроллер запускает fetch → данные приходят → `markNeedsBuild` → Element перестраивает нужный диапазон
- Placeholder (shimmer) фиксированной высоты для незагруженных сообщений
