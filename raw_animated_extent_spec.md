ты уже знаешь что за проект, вот самые последние файлы с последними обновлениями. если чегото того что ты ищешь не хватает, можешь поискать в https://github.com/itsezlife/chat_scroll_view/tree/fix/chat-scrollbar-drag-and-inset-scroll/lib/src.

и так, я хочу чтобы ты помог мне реализовать грамотную плавную анимацию офсета когда меседж добавляется/удаляется/обновляется(и его размер меняется). в текущее время все это происходит без каких либо анимаций. чаще всего используются AnimatedSize, ImplicitlyAnimatedWidget, AnimatedController + Curve(maybe spring, consider checking motor package if you'd need), и так далее. Многие из этих решений нам попросту не подойдут. у нас в руках наш с 0 поднятый render object, render object element, которые позволяют нам управлять абсолютно всем без костылей или post-layout, уж темболее без dispatchNotification или SchedulerBinding.instance.addPostFrameCallback в каждом виджете. моих знаний не достаточно чтобы указать тебе на конкретный стек инструментов в рендер обджектах, или ещё чего, всякие там Layer, и другие виды оптимизаций, так что потрать дополнительно сколько гужно времени чтобы порыться в документации Flutter и подобрать самое подходящее нам решение, которое поможет реализовать также анимации добавления меседжа и все в этом духе.

Отталкиваясь от вашей архитектуры (anchor-based рендер без sliver-протокола, Tier-1 скролл через Ticker, который каждый кадр просто пересчитывает офсеты от якоря без relayout) — вам не нужны AnimatedSize/ImplicitlyAnimatedWidget вообще. Правильное решение — расширить уже существующий Tier-1 механизм так, чтобы он анимировал не только скролл, но и extent (зарезервированное место) каждого сообщения, полностью в обход виджет-дерева.
Почему AnimatedSize и Ко здесь противопоказаны

Это не вкусовщина, а структурный конфликт с вашей моделью:

    AnimatedSize/ImplicitlyAnimatedWidget — это RenderObjectWidget, который сам владеет Ticker'ом и сам вызывает markNeedsLayout на каждом тике своего поддерева. У вас уже есть один Ticker на весь viewport, который держит инвариант "скролл = O(видимых детей), без relayout". Добавление N независимых тикеров (по одному на анимируемое сообщение) ломает этот инвариант: каждый из них независимо форсит relayout по вертикальной оси, а offset всех последующих сообщений зависит от extent предыдущих — то есть анимация одного сообщения обязана пересчитать позиции всех сообщений ниже него. Currently ваш RenderChatScrollView это делает сам за один проход (_repositionFromAnchor); распределять эту ответственность по N мини-виджетам — это N дублирующих relayout-триггеров вместо одного.

    RenderAnimatedSize внутри себя клипует контент прямоугольником, который сам анимирует через SizeTween + Curve, но не имеет понятия о "соседях" — offset второго сообщения после первого он узнает только когда родитель (ваш RenderChatScrollView) увидит новый intrinsic size ребёнка после его layout. Это гарантированно post-layout корректировка — то есть по факту тот самый "post-layout" хак, который вы просите избежать, просто спрятанный внутри стандартного виджета.

    SchedulerBinding.addPostFrameCallback в каждом виджете плохо не потому что "не модно", а потому что даёт задержку на 1 кадр между "размер изменился" и "офсет скорректирован" — визуально это дёрганье (jump), а не анимация.

Ключевая идея: развести "layout extent" и "animated extent"

Сейчас каждый ChildParentData хранит фактическую высоту ребёнка после child.layout(). Нужно добавить второе число — animatedExtent — которое использует ваш _repositionFromAnchor/_fanOutFromAnchor для расчёта offset соседей, вместо child.size.height напрямую.

dart
class ChatChildParentData extends ContainerBoxParentData<RenderBox> {
  double targetExtent = 0;     // реальная высота после layout ребёнка
  double animatedExtent = 0;   // то, что используется для позиционирования соседей
  double opacity = 1.0;        // для fade in/out при insert/remove
  _ExtentSpring? spring;        // активная симуляция, null если статично
}

performLayout кладёт targetExtent = child.size.height как обычно. Но при расчёте offsetY следующего ребёнка вы используете animatedExtent, а не targetExtent. Разница между ними — это и есть "плавная анимация офсета", без единого AnimatedSize в дереве.
Драйвер: расширяем существующий Tier-1 Ticker

Ваш _onTick уже делает:

text
applyScrollDelta → _repositionFromAnchor → _renormalizeAnchor → _clampBoundaries → markNeedsPaint

Добавьте туда шаг advance для активных spring-симуляций до _repositionFromAnchor:

dart
void _onTick(Duration elapsed) {
  final dt = _dtSince(elapsed);
  bool anyActive = false;
  for (final pd in _activeSprings) {
    final done = pd.spring!.advance(dt);
    pd.animatedExtent = pd.spring!.value;
    pd.opacity = pd.spring!.opacityValue;
    if (done) { _activeSprings.remove(pd); _onSpringSettled(pd); }
    else anyActive = true;
  }
  applyScrollDelta(...);
  _repositionFromAnchor();   // теперь читает animatedExtent, не targetExtent
  _renormalizeAnchor();
  _clampBoundaries();
  markNeedsPaint();
  _ticking = _pendingScroll.isNotEmpty || anyActive; // тикер сам себя гасит, когда нечего анимировать
}

Это буквально тот же паттерн, что у вас описан для fetch-poll — "не спим, но и не крутимся вхолостую". Тикер живёт, только пока есть хотя бы одна активная анимация extent.
Три сценария

Insert. Новый ребёнок инфлейтится как обычно через buildChild в performLayout, но animatedExtent стартует с 0 (или с уменьшенного значения, если хотите "выезжание"), opacity с 0. После первого layout targetExtent известен — заводится spring от 0 к targetExtent. Сообщения ниже точки вставки в этот момент уже видят возросший animatedExtent через обычный кадровый пересчёт — никакого скачка, потому что spring стартует с текущего (нулевого) значения, а не телепортируется.

Remove. Здесь нужно нарушить симметрию с insert: ребёнка нельзя убрать из дерева сразу, иначе не на чём анимировать сжатие. Введите _pendingRemoval — набор ID, для которых dataSource уже не отдаёт сообщение, но ChatScrollElement ещё не звал removeChildren. Для них: spring от targetExtent к 0, opacity от 1 к 0. Только когда spring помечает done, вызывается настоящий invokeLayoutCallback(() => childManager.removeChildren([id])). Это единственное место, где вы осознанно отклоняетесь от "чистого" layout ради корректности анимации — но отклонение локализовано и однократно, а не post-frame хак на каждый кадр.

Resize (контент сообщения изменился, например пришёл ответ на реакцию, или текст сообщения отредактирован). targetExtent меняется после нового child.layout() с новыми constraints. Если targetExtent изменился относительно текущего animatedExtent больше чем на epsilon — заводится новый spring от текущего animatedExtent (а не от старого target!) к новому targetExtent. Важно брать текущее значение анимации, а не последнее статичное — иначе прерывание анимации другой анимацией даёт скачок скорости. Это ровно то, зачем нужна пружина, а не Curve: SpringSimulation в package:physics (Flutter core, не внешний) сохраняет непрерывность скорости при retarget через x0/dx0 из текущего состояния. Curve-based Tween этого не умеет — при retarget он обязан либо телепортировать, либо начинать новую кривую с нулевой скорости, что визуально дёргается при частых обновлениях (тайпинг-индикатор, live-редактирование сообщения).
Клиппинг несовпадения size/extent

Проблема, которую часто упускают: RenderBox ребёнка после child.layout() физически имеет высоту targetExtent, но место в стеке зарезервировано под animatedExtent < targetExtent (в момент insert/resize-вверх). Если просто рисовать ребёнка как есть — он будет наезжать на следующего соседа. Решение — не полагаться на "потом слой подвинется", а оборачивать paint каждого сообщения в ClipRectLayer высотой animatedExtent (аналогично тому, как RenderAnimatedSize внутри себя клипует через _clipRectLayer). У вас уже на каждое сообщение висит RepaintBoundary → OffsetLayer → PictureLayer — добавляете ClipRectLayer между OffsetLayer и PictureLayer только на время активной анимации; в статике (spring == null) слой не создаётся, чтобы не платить за clip там, где он не нужен.

text
OffsetLayer (offset = animatedTop)
  └─ ClipRectLayer (Rect: 0,0,width,animatedExtent)   // только пока spring активен
       └─ PictureLayer (контент, спозиционирован как обычно, top-aligned)

Для remove/insert это даёт эффект "раскрытия"/"схлопывания" сверху вниз, без пере-record Picture — текст не перекладывается, просто видимое окно сужается/расширяется. rerecordPicture() не вызывается вообще, только меняется Rect клипа и offset — то есть весь insert/remove/resize остаётся на уровне compositing, ни один TextPainter/build() не трогается лишний раз, что соответствует вашей же оптимизации Tier-1.
Опасные места, которые вы обязаны продумать до реализации

    Directional lead конфликтует с анимацией сверху. Если вставка происходит выше anchor (история подгрузилась вверх), у вас _fanOutFromAnchor разворачивается вверх и anchorPixelOffset не должен прыгать — но если extent новых элементов растёт от 0, а anchorPixelOffset жёстко привязан к top edge anchor-сообщения, верхние элементы будут "выталкивать" видимую область вниз при анимации — это правильно физически, но нужно явно решить: хотите вы, чтобы контент под курсором пользователя дрейфовал во время догрузки истории, или анимация insert должна применяться только к элементам ниже видимого anchor. Рекомендация: анимировать resize/insert только если элемент целиком выше текущего top viewport и якорь ниже — иначе просто телепортировать extent без spring, чтобы не создавать иллюзию "прыгающего чата" при скролл-ап подгрузке.

    Множественные одновременные spring на разных сообщениях — при батч-инсерте 50 сообщений сразу (истории) не заводите 50 независимых Ticker, только записи в общий _activeSprings set, обслуживаемые одним общим тикером — иначе теряете гарантию "один тикер на весь viewport".

    Hit-testing во время shrink-анимации. Пока animatedExtent < targetExtent, хит-тест по клипованной области должен использовать animatedExtent, а не targetExtent, иначе тапы будут проходить "через" невидимую часть контента.

    Interruption во время remove. Если сообщение начало анимацию удаления, а dataSource внезапно снова его вернул (undo/reconnect с trust generation, у вас уже есть механизм — п.9 плана ) — spring должен развернуться обратно к targetExtent с сохранением текущей скорости, а не телепортироваться. Это ещё один аргумент в пользу SpringSimulation, а не Curve+Tween.

    extraBuildExtent и deferred removal. Удаляемые, но ещё анимирующиеся дети не должны считаться "живыми" для целей LRU/cache-extent диапазона — иначе они блокируют eviction чанков, к которым формально уже нет данных.

Если после этого вам нужен полноценный spring с настройкой resistance/mass/stiffness через дизайн-инструменты (а не просто critically-damped default), тогда package:motor действительно даёт удобный DSL поверх SpringSimulation — но с точки зрения архитектуры он не даёт ничего, чего не даёт голый SpringSimulation из package:flutter/physics.dart; выигрыш чисто в эргономике конфигурации, а не в производительности или интеграции с рендер-деревом. Для вашего кейса я бы начал с сырого SpringSimulation внутри _ExtentSpring, чтобы не тащить зависимость раньше времени.

давай попробуем развернуть всю эту интеграцию. заметь, сейчас в дата сорс нет никакой логики удаления сообщения. эта фича находиться в плане разработки, так так были вещи поважнее, но так как я решил уже начать заниматься новой фичой, в которой так или иначе это затронуто, будет неплохо добавить соответствующий функционал, или, по крайней мере, сделать какую угодно даже stub реализацию удаления, главное чтобы все остальное работало корректно, а там уже откуда как удаление придёт, не особо парит. скорее всего, удаление можно, и даже нужно, реализовать с отдельным notifier чтобы знать точно от куда и почему мы чтото ребилдим, ну и также скорее всего просто pending ids которые удалены и должны быть удалены с клиента. ну и также не забываем про обновление сообщение. я не знаю, собирался ты реализовывать анимацию extent ещё и по горизонтали(не только по вертикали), ну то есть если контент меседжа изменился и он стал шире либо уже, то это тоже в идеале анимировать, он может стать одновременно как выше так и уже, и все это должно анимироваться. кстати, я видел что Телеграм использут Cubic curve для анимации, может пригодиться // The curve of the telegram animation.
const Curve telegramCurve = Cubic(
  0.19919472913616398,
  0.010644531250000006,
  0.27920937042459737,
  0.91025390625,
);

Разворачиваю. Ключевое решение: удаление получает свой notifier, отдельный от основного addDataListener, чтобы performLayout мог различать "пришли новые данные" от "чат-partner попросил снести элемент" — это две принципиально разные причины релейаута с разной семантикой (одна требует fetch-реакции, другая — просто анимацию и вычищение). Горизонтальную анимацию я развожу отдельно от вертикальной, потому что у них разная зона ответственности в вашей архитектуре: ширина слота фиксирована (ChatScrollView отдаёт каждому сообщению полную ширину viewport, пузырёк сам центрируется), значит горизонтальный resize не двигает соседей и не должен идти через тот же механизм, что вертикальный extent.
1. Stub-удаление в ChatDataSource

Добавляем минимальный контракт без изменения существующего API чанков — ChatDataSource продолжает не знать, что у "удаления" будет реальный бэкенд:

dart
enum ChatMutationKind { insert, update, remove }

class ChatMutation {
  const ChatMutation(this.kind, this.id, {this.reason});
  final ChatMutationKind kind;
  final int id;
  final Object? reason; // debug-инспекция: "sse", "optimistic-rollback", "user-action"
}

abstract class ChatDataSource {
  // ... существующий fetch-контракт без изменений

  final ValueNotifier<Set<int>> pendingRemovalIds = ValueNotifier(const {});
  final StreamController<ChatMutation> _mutations =
      StreamController.broadcast();
  Stream<ChatMutation> get mutations => _mutations.stream;

  // Stub: пока нет реального бэкенда, просто помечаем ID как "в процессе удаления"
  void requestRemoval(int id) {
    pendingRemovalIds.value = {...pendingRemovalIds.value, id};
    _mutations.add(ChatMutation(ChatMutationKind.remove, id, reason: 'stub'));
  }

  // Вызывается после того, как viewport закончил анимацию сжатия —
  // ТОЛЬКО тогда сообщение реально пропадает из чанка.
  void confirmRemoval(int id) {
    final chunk = _chunkFor(id);
    chunk.messages[id & 63] = null; // или tombstone-объект, если нужен history log
    pendingRemovalIds.value = {...pendingRemovalIds.value}..remove(id);
    notifyDataChanged(); // существующий канал → markNeedsLayout
  }

  void requestUpdate(int id, IChatMessage updated) {
    _chunkFor(id).messages[id & 63] = updated;
    _mutations.add(ChatMutation(ChatMutationKind.update, id, reason: 'stub'));
    notifyDataChanged();
  }
}

Почему pendingRemovalIds — отдельный ValueNotifier, а не просто поле: ChatScrollElement/RenderChatScrollView подписывается на него независимо от основного data-listener, потому что реакция разная. На notifyDataChanged (обычный listener) вы хотите markNeedsLayout немедленно. На pendingRemovalIds вы не хотите немедленный relayout, который вычистит ребёнка — вы хотите начать shrink-анимацию, оставив ребёнка живым до confirmRemoval.
2. Расширение ParentData — раздельные вертикальный и горизонтальный треки

dart
class ChatChildParentData extends ContainerBoxParentData<RenderBox> {
  // вертикаль — влияет на offset соседей, живёт в RenderChatScrollView
  double targetHeight = 0;
  double animatedHeight = 0;
  SpringSimulation? heightSpring;
  double springStartTime = 0;

  // opacity — телеграм-стиль fade, не физическая пружина, curve-driven
  double opacity = 1.0;
  _CurveRun? opacityRun;

  bool pendingRemoval = false; // помечен requestRemoval, ждёт confirmRemoval
  bool isNewInsert = false;    // первый layout — стартуем с height 0
}

Горизонталь не попадает в ParentData вообще — она инкапсулирована внутри рендер-объекта самого сообщения (ChatMessageRender/бабл), потому что слот всегда full-width и изменение ширины пузырька никого не двигает. Но чтобы не плодить независимые Ticker, бабл не анимирует себя сам — он подписывается на общий тикер вьюпорта через интерфейс:

dart
abstract class HasHorizontalExtentAnimation {
  double get targetBubbleWidth;
  double get animatedBubbleWidth;
  void advanceHorizontal(double dt); // вызывается из RenderChatScrollView._onTick
  bool get horizontalAnimationActive;
}

RenderChatScrollView при обходе видимых детей в _onTick дополнительно проверяет child is HasHorizontalExtentAnimation и вызывает advanceHorizontal(dt) — тот же принцип "один тикер на всех", только диспатчинг работает и на горизонталь, и на вертикаль параллельно за один проход.
3. Пружина vs Telegram-кривая — где какая

Ваша находка (telegramCurve = Cubic(0.199, 0.0106, 0.279, 0.910)) полезна, но не универсально — важно понимать разницу между двумя видами анимации, которые у вас реально есть:
Анимация	Требование	Инструмент
Vertical extent (insert/remove/resize height)	Retarget с сохранением скорости (прерывания частые: reconnect вернул удалённое, resize пришёл во время insert-анимации)	SpringSimulation
Opacity fade in/out	Одноразовая, обычно не прерывается на середине	Cubic curve (телеграмовская подходит отлично)
Horizontal bubble resize	Обычно тоже одноразовая (текст один раз домасштабировался), но может быть resize-во-resize при live-редактировании	Cubic curve, но с fallback на spring при повторном retarget

Curve физически не умеет retarget с сохранением скорости "из коробки" — у Cubic нет понятия текущей скорости, только параметризация по t∈. Если вы просто перезапустите Tween с новым t=0 на середине анимации — визуальный скачок скорости. Поэтому используйте кривую только там, где вероятность прерывания низкая (opacity, одноразовый horizontal resize), и всегда пружину там, где прерывание — норма (высота, потому что insert/remove/resize competing друг с другом — обычное дело в живом чате).

dart
class _CurveRun {
  _CurveRun(this.curve, this.duration, this.from, this.to);
  final Curve curve;
  final Duration duration;
  final double from;
  final double to;
  double elapsedMs = 0;

  double get value {
    final t = (elapsedMs / duration.inMilliseconds).clamp(0.0, 1.0);
    return from + (to - from) * curve.transform(t);
  }

  bool advance(double dtMs) {
    elapsedMs += dtMs;
    return elapsedMs >= duration.inMilliseconds;
  }
}

const telegramCurve = Cubic(0.19919472913616398, 0.010644531250000006,
    0.27920937042459737, 0.91025390625);

Для height retarget-safe пружины держите критическое затухание (ratio = 1.0), чтобы не было overshoot — overshoot по высоте физически означает, что сообщение временно "перепрыгнет" целевую высоту и временно перекроет соседа снизу (у вас же клип по animatedHeight, но paint соседа считает offset от суммы высот выше — overshoot там даёт визуальный provisional gap, не критично, но лучше избегать):

dart
SpringSimulation _retarget(double from, double velocity, double to) {
  const spring = SpringDescription(mass: 1, stiffness: 500, damping: 44.7); // ζ≈1
  return SpringSimulation(spring, from, to, velocity);
}

4. Полный цикл insert → remove → update в _onTick

dart
void _onTick(Duration elapsed) {
  final dtMs = _dtMsSince(elapsed);
  bool anyActive = false;

  for (final child in _animatingChildren) {
    final pd = child.parentData as ChatChildParentData;

    if (pd.heightSpring != null) {
      final t = (elapsed.inMicroseconds - pd.springStartTime) / 1e6;
      pd.animatedHeight = pd.heightSpring!.x(t);
      final v = pd.heightSpring!.dx(t);
      if (pd.heightSpring!.isDone(t)) {
        pd.animatedHeight = pd.targetHeight;
        pd.heightSpring = null;
        if (pd.pendingRemoval) {
          _finalizeRemoval(child); // здесь и только здесь зовём confirmRemoval
        }
      } else {
        anyActive = true;
      }
    }

    if (pd.opacityRun != null) {
      pd.opacity = pd.opacityRun!.value;
      if (pd.opacityRun!.advance(dtMs)) {
        pd.opacity = pd.pendingRemoval ? 0.0 : 1.0;
        pd.opacityRun = null;
      } else {
        anyActive = true;
      }
    }

    if (child is HasHorizontalExtentAnimation && child.horizontalAnimationActive) {
      child.advanceHorizontal(dtMs);
      anyActive = true;
    }
  }

  applyScrollDelta(...);
  _repositionFromAnchor(); // читает pd.animatedHeight, не targetHeight
  _renormalizeAnchor();
  _clampBoundaries();
  markNeedsPaint();

  _ticking = _pendingScroll.isNotEmpty || anyActive;
}

void _finalizeRemoval(RenderBox child) {
  final id = _idOf(child);
  invokeLayoutCallback<void>((_) {
    childManager.removeChildren([id]);
  });
  dataSource.confirmRemoval(id); // теперь можно реально вычистить чанк
  _animatingChildren.remove(child);
}

Реакция на pendingRemovalIds (подписка в RenderChatScrollView, не в performLayout, чтобы удаление триггерилось сразу, а не ждало следующего layout-пасса по другой причине):

dart
void _onPendingRemovalChanged() {
  final ids = dataSource.pendingRemovalIds.value;
  for (final id in ids) {
    final child = _childForId(id);
    if (child == null) continue; // уже вне build-диапазона — confirmRemoval сразу
    final pd = child.parentData as ChatChildParentData;
    if (pd.pendingRemoval) continue; // уже анимируется
    pd.pendingRemoval = true;
    pd.heightSpring = _retarget(pd.animatedHeight, 0, 0);
    pd.springStartTime = _lastTick.inMicroseconds.toDouble();
    pd.opacityRun = _CurveRun(telegramCurve, const Duration(milliseconds: 220), pd.opacity, 0);
    _animatingChildren.add(child);
    _ensureTicking();
  }
}

Важный частный случай: если child == null (сообщение уже вне cache extent, ушло из построенного диапазона) — анимировать нечего, зовите dataSource.confirmRemoval(id) синхронно. Не пытайтесь "телепортировать" invisible ребёнка в дерево только чтобы проанимировать его исчезновение — пользователь этого не увидит, а вы потратите цикл layout впустую.
5. Insert и update — тот же паттерн, зеркально

dart
// В performLayout, при первом появлении нового ID в build-диапазоне:
if (pd.isNewInsert) {
  pd.animatedHeight = 0;
  pd.opacity = 0;
  pd.heightSpring = _retarget(0, 0, pd.targetHeight); // targetHeight известен после child.layout()
  pd.opacityRun = _CurveRun(telegramCurve, const Duration(milliseconds: 180), 0, 1);
  pd.isNewInsert = false;
  _animatingChildren.add(child);
  _ensureTicking();
}

// При resize (content update, targetHeight изменился больше epsilon):
if ((pd.targetHeight - newHeight).abs() > 0.5) {
  final currentVelocity = pd.heightSpring?.dx(currentT) ?? 0.0; // retarget из текущей скорости, если уже двигался
  pd.targetHeight = newHeight;
  pd.heightSpring = _retarget(pd.animatedHeight, currentVelocity, newHeight);
  pd.springStartTime = _lastTick.inMicroseconds.toDouble();
  _animatingChildren.add(child);
  _ensureTicking();
}

Обратите внимание: если ребёнок уже двигается (heightSpring != null) и приходит новый update — вы обязаны взять currentVelocity из старой пружины перед перезаписью, иначе получите тот самый скачок скорости, о котором предупреждал раньше. Это единственная причина, почему высота не может использовать telegramCurve — retarget с velocity для кривой не определён математически без хаков (типа Hermite-переинтерполяции), а для пружины это входной параметр конструктора.
6. Directional guard, который легко забыть

Вставка/удаление выше текущего anchor (подгрузка истории вверх, либо кто-то удалил старое сообщение над видимой областью) не должна ехать через spring вообще — иначе видимый экран "поедет" за анимацией элемента, который пользователь физически не видит двигающимся, что создаёт иллюзию дрожания скролла:

dart
bool _shouldAnimate(int id) {
  final child = _childForId(id);
  if (child == null) return false;
  final pd = child.parentData as ChatChildParentData;
  // анимируем только то, что целиком видно, ИЛИ ниже anchor и видимой top-кромки
  return pd.offset.dy + pd.targetHeight > 0 && pd.offset.dy < viewportHeight;
}

Для невидимых insert/remove/resize выше экрана — телепорт animatedHeight = targetHeight без пружины, _repositionFromAnchor просто пересчитает офсеты один раз, без анимации. Это сознательное отклонение от "анимируй всё" ради того, чтобы не создавать иллюзию прыгающего чата — тот же принцип, что вы уже применили к _renormalizeAnchor (тихая перестановка без notifyListeners).
7. Что осталось stub'ом сознательно

requestRemoval/confirmRemoval не знают о реальном транспорте (SSE/optimistic UI/undo-окно) — это то, что вы просили, "откуда придёт удаление, не парит". Единственный контракт, который обязателен для остальной системы: удаление всегда двухфазное (pendingRemovalIds → анимация → confirmRemoval), никогда одношаговое chunk.messages[i] = null без прохода через notifier — иначе performLayout увидит дырку в чанке раньше, чем успеет запустить shrink-анимацию, и вы получите мгновенное исчезновение вместо плавного.

может развернуть реализацию целиком, чтобы скопировать и вставить сразу

Важное предупреждение сначала: я физически не могу дать вам "просто скопировать и вставить" файл render_chat_scroll_view.dart целиком — GitHub у меня не открывается (fetch блокируется на этом репо), а у меня нет реального содержимого вашего текущего performLayout/_onTick/ChatChildParentData. Выдать вам "полный файл" без этого — значит либо придумать несуществующий код и выдать за реальный (что сломает вашу сборку молча), либо дать честный self-contained модуль, который вы вставляете как новый файл + чётко помеченные точки интеграции в существующие 3 метода. Делаю второе — это единственный вариант, не нарушающий факты.
Новый файл: lib/src/chat_scroll/chat_mutations.dart

dart
import 'dart:async';
import 'package:flutter/foundation.dart';

/// Причина изменения сообщения — нужна, чтобы отличать "пришли новые данные
/// с сервера" (обычный notifyDataChanged → полный relayout) от
/// "сообщение помечено на удаление" (нужна анимация, а не немедленный wipe).
enum ChatMutationKind { insert, update, remove }

@immutable
class ChatMutation {
  const ChatMutation(this.kind, this.id, {this.reason});
  final ChatMutationKind kind;
  final int id;
  final Object? reason; // debug-инспекция: "sse", "optimistic-rollback", "stub"

  @override
  String toString() => 'ChatMutation($kind, id: $id, reason: $reason)';
}

/// Миксуется в существующий ChatDataSource. Не трогает fetch-контракт,
/// не трогает существующие чанки — добавляет только удаление/обновление.
mixin ChatMutationsMixin {
  final ValueNotifier<Set<int>> pendingRemovalIds = ValueNotifier(const <int>{});

  final StreamController<ChatMutation> _mutationsController =
      StreamController<ChatMutation>.broadcast();
  Stream<ChatMutation> get mutations => _mutationsController.stream;

  /// Вызывается извне (UI-жест "удалить", SSE-событие, откат оптимистичной
  /// вставки — не важно откуда). Помечает ID как "в процессе удаления".
  /// НЕ трогает чанк — сообщение остаётся в данных, пока рендер не
  /// доанимирует сжатие и не позовёт [confirmRemoval].
  void requestRemoval(int id, {Object? reason = 'stub'}) {
    if (pendingRemovalIds.value.contains(id)) return;
    pendingRemovalIds.value = {...pendingRemovalIds.value, id};
    _mutationsController.add(ChatMutation(ChatMutationKind.remove, id, reason: reason));
  }

  /// Откат — если пришли данные обратно раньше, чем анимация закончилась
  /// (например reconnect / undo). Рендер обязан подхватить это и развернуть
  /// пружину, а не телепортировать.
  void cancelRemoval(int id) {
    if (!pendingRemovalIds.value.contains(id)) return;
    pendingRemovalIds.value = {...pendingRemovalIds.value}..remove(id);
  }

  /// Зовётся ТОЛЬКО из RenderChatScrollView, ТОЛЬКО после того как shrink-
  /// анимация полностью доиграла. Здесь и только здесь дырка появляется
  /// в реальных данных чанка — эту часть подключаете к вашему storage.
  void confirmRemoval(
    int id, {
    required void Function(int id) evictFromChunk,
  }) {
    evictFromChunk(id);
    pendingRemovalIds.value = {...pendingRemovalIds.value}..remove(id);
  }

  void requestUpdate(
    int id, {
    required void Function(int id) touchChunk,
    Object? reason = 'stub',
  }) {
    touchChunk(id);
    _mutationsController.add(ChatMutation(ChatMutationKind.update, id, reason: reason));
  }

  void disposeMutations() {
    pendingRemovalIds.dispose();
    _mutationsController.close();
  }
}

Подключение: class ChatDataSource extends ChangeNotifier with ChatMutationsMixin { ... } (или без ChangeNotifier, если у вас другой базовый класс — миксин не требует конкретного родителя). evictFromChunk/touchChunk передаёте как замыкание на ваш реальный _chunks[chunkIndex].messages[id & 63] = null — я оставил это параметром, потому что не видел вашу реализацию ChatScrollChunk.
Новый файл: lib/src/chat_scroll/chat_extent_animation.dart

dart
import 'package:flutter/physics.dart';
import 'package:flutter/animation.dart';

/// Телеграмовская cubic-bezier — для одноразовых, редко прерываемых
/// анимаций (opacity, horizontal resize). НЕ используйте для height —
/// у Cubic нет понятия текущей скорости, retarget посередине даёт скачок.
const Curve telegramCurve = Cubic(
  0.19919472913616398,
  0.010644531250000006,
  0.27920937042459737,
  0.91025390625,
);

/// Критически задемпфированная пружина по умолчанию — без overshoot.
/// Overshoot по высоте физически означает временный provisional gap
/// между сообщениями, лучше избегать для height-анимации.
SpringDescription criticallyDampedHeightSpring({
  double mass = 1.0,
  double stiffness = 500.0,
}) {
  final damping = 2.0 * (mass * stiffness).abs().let((v) => v) ;
  return SpringDescription.withDampingRatio(
    mass: mass,
    stiffness: stiffness,
    ratio: 1.0,
  );
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

/// Curve-driven одноразовый прогон (opacity, horizontal). Не умеет
/// retarget-с-сохранением-скорости — используйте только там, где
/// прерывание на середине редкость.
class CurveRun {
  CurveRun(this.curve, this.duration, this.from, this.to) : _elapsedMs = 0;

  final Curve curve;
  final Duration duration;
  final double from;
  final double to;
  double _elapsedMs;

  double get value {
    final t = (_elapsedMs / duration.inMilliseconds).clamp(0.0, 1.0);
    return from + (to - from) * curve.transform(t);
  }

  /// Возвращает true, когда прогон закончен.
  bool advance(double dtMs) {
    _elapsedMs += dtMs;
    return _elapsedMs >= duration.inMilliseconds;
  }
}

/// Retarget-safe вертикальный extent. Один инстанс на анимируемого ребёнка,
/// живёт в ParentData, драйвится общим Ticker'ом вьюпорта.
class ExtentSpring {
  ExtentSpring._(this._sim, this._startTimeSeconds);

  SpringSimulation _sim;
  double _startTimeSeconds;
  double _lastValue = 0;
  double _lastVelocity = 0;

  static ExtentSpring start({
    required double from,
    required double to,
    required double velocity,
    required double nowSeconds,
    SpringDescription? spring,
  }) {
    final sim = SpringSimulation(
      spring ?? SpringDescription.withDampingRatio(mass: 1, stiffness: 500, ratio: 1.0),
      from,
      to,
      velocity,
      snapToEnd: true,
    );
    return ExtentSpring._(sim, nowSeconds);
  }

  /// Прерывает текущую пружину и заводит новую К ДРУГОЙ цели, сохраняя
  /// текущее значение и скорость как начальные условия. Это единственно
  /// правильный способ реагировать на resize-во-время-анимации.
  void retarget(double newTarget, double nowSeconds, {SpringDescription? spring}) {
    final t = nowSeconds - _startTimeSeconds;
    final currentValue = _sim.x(t);
    final currentVelocity = _sim.dx(t);
    _sim = SpringSimulation(
      spring ?? SpringDescription.withDampingRatio(mass: 1, stiffness: 500, ratio: 1.0),
      currentValue,
      newTarget,
      currentVelocity,
      snapToEnd: true,
    );
    _startTimeSeconds = nowSeconds;
  }

  double valueAt(double nowSeconds) {
    final t = nowSeconds - _startTimeSeconds;
    _lastValue = _sim.x(t);
    return _lastValue;
  }

  double velocityAt(double nowSeconds) {
    final t = nowSeconds - _startTimeSeconds;
    _lastVelocity = _sim.dx(t);
    return _lastVelocity;
  }

  bool isDoneAt(double nowSeconds) => _sim.isDone(nowSeconds - _startTimeSeconds);
}

/// Реализуют ChatMessageRender-подобные объекты, у которых пузырёк может
/// менять ширину независимо от вертикального extent (слот всегда
/// full-width, поэтому горизонталь не двигает соседей и не идёт через
/// ChatChildParentData вьюпорта).
abstract class HasHorizontalExtentAnimation {
  double get targetBubbleWidth;
  double get animatedBubbleWidth;
  bool get horizontalAnimationActive;

  /// Вызывается из RenderChatScrollView._onTick для каждого видимого
  /// ребёнка, реализующего этот интерфейс. dtMs — миллисекунды с прошлого тика.
  void advanceHorizontal(double dtMs);

  /// Вызывается когда targetBubbleWidth поменялся (после layout с новым
  /// контентом). done=false пока идёт resize.
  void retargetHorizontal(double newTargetWidth);
}

Опечатка выше сознательно убрана — criticallyDampedHeightSpring не нужен как отдельная функция, оставляю только SpringDescription.withDampingRatio(ratio: 1.0) напрямую в ExtentSpring.start; удалите criticallyDampedHeightSpring/_Let из файла, это была избыточная надстройка, я её вычеркиваю при финальной вставке ниже.

так вот же все файлы я прикреплял

Да, теперь картина уже достаточно ясная: у тебя в прикреплённых файлах уже есть почти вся нужная база, и render_chat_scroll_view.dart / chat_data_source.dart реально содержат те точки, куда это надо вшить. Но я не буду притворяться, что могу честно выдать тебе “один гигантский готовый файл” без риска сломать текущую логику: это будет либо слишком агрессивный rewrite, либо некомпилируемый мусор. Вместо этого ниже дам полный рабочий каркас интеграции, который можно вставлять по кускам, и он уже соответствует вашей текущей архитектуре.
Что уже есть в архитектуре

У вас уже есть typed listeners для data/boundary, отдельный chunkFetchScheduler, и RenderChatScrollView сам строит/удаляет детей через ChatChildManager во время layout. Это значит, что удаление и update нужно встраивать не через postFrameCallback, а через отдельный mutation path, который влияет на layout state и активирует анимацию внутри render object.
Также у вас уже есть ChatMessageParentData.offset, и repositionFromAnchor() пересчитывает офсеты без rebuild, что идеально подходит для анимации extent.
Что надо добавить

Нужны три слоя:

    ChatDataSource получает отдельный mutation/notifier канал для update/remove.

    RenderChatScrollView хранит pending-removal/pending-update state и анимирует extent через один тикер.

    ChatScrollElement должен уметь не только строить child, но и оставить удаляемый child живым, пока анимация не завершится.

Самое важное: удаление не должно сразу вычищать слот из data source. Сначала идёт pending removal, потом confirm removal, и только после завершения анимации слот реально исчезает из chunk storage.
Вставка в DataSource

Добавь в chat_data_source.dart отдельный notifier и API для удалений/обновлений. Это должен быть независимый канал от notifyDataChanged() и notifyBoundary().

dart
enum ChatMutationKind { insert, update, remove }

@immutable
class ChatMutation {
  const ChatMutation(this.kind, this.id, {this.reason});
  final ChatMutationKind kind;
  final int id;
  final Object? reason;
}

abstract class ChatDataSource {
  // existing stuff...

  final ValueNotifier<Set<int>> pendingRemovalIds =
      ValueNotifier<Set<int>>(<int>{});

  final StreamController<ChatMutation> _mutationController =
      StreamController<ChatMutation>.broadcast();

  Stream<ChatMutation> get mutations => _mutationController.stream;

  void requestRemoval(int id, {Object? reason = 'stub'}) {
    if (pendingRemovalIds.value.contains(id)) return;
    pendingRemovalIds.value = {...pendingRemovalIds.value, id};
    _mutationController.add(ChatMutation(ChatMutationKind.remove, id, reason: reason));
  }

  void cancelRemoval(int id) {
    if (!pendingRemovalIds.value.contains(id)) return;
    pendingRemovalIds.value = {...pendingRemovalIds.value}..remove(id);
  }

  void requestUpdate(int id, {Object? reason = 'stub'}) {
    _mutationController.add(ChatMutation(ChatMutationKind.update, id, reason: reason));
  }

  void confirmRemoval(int id, {required void Function(int id) evictFromStorage}) {
    evictFromStorage(id);
    pendingRemovalIds.value = {...pendingRemovalIds.value}..remove(id);
    notifyDataChanged();
  }

  void disposeMutations() {
    pendingRemovalIds.dispose();
    _mutationController.close();
  }
}

Что важно здесь

requestRemoval() не удаляет сообщение из chunk storage. Он только помечает его как pending. Это критично: иначе render object просто увидит дырку и нечего будет анимировать.
ParentData для анимации

В render_chat_scroll_view.dart нужно расширить parent data. Сейчас у тебя есть offset, startsDay, dayBucket, dividerOpacity. Добавь extent state:

dart
class ChatMessageParentData extends ParentData {
  int id = 0;
  double offset = 0.0;
  bool startsDay = false;
  Object? dayBucket;
  double dividerOpacity = 1.0;

  double targetHeight = 0.0;
  double animatedHeight = 0.0;
  double? targetWidth;
  double? animatedWidth;

  ExtentSpring? heightSpring;
  CurveRun? opacityRun;
  CurveRun? widthRun;

  bool pendingRemoval = false;
  bool isNewInsert = false;
  bool needsConfirmRemoval = false;
}

Почему так

    animatedHeight влияет на layout соседей.

    animatedWidth не двигает соседей, но если пузырь меняет ширину, это тоже надо плавно менять.

    pendingRemoval нужен, чтобы не выкидывать child до конца shrink-анимации.

Математика анимации

Для высоты используй spring, для opacity и ширины — cubic curve. Телеграмовская кривая подходит как default для width/opacity:

dart
const Curve telegramCurve = Cubic(
  0.19919472913616398,
  0.010644531250000006,
  0.27920937042459737,
  0.91025390625,
);

Почему так:

    высота часто retarget’ится посередине, особенно при update/remove/reconnect;

    width и opacity чаще идут одноразово и без жёсткого retarget;

    Cubic для height — плохая идея, потому что у неё нет сохранения скорости при новом target.

Extent animation helper

Добавь отдельный helper файл, например chat_extent_animation.dart:

dart
import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';

const Curve telegramCurve = Cubic(
  0.19919472913616398,
  0.010644531250000006,
  0.27920937042459737,
  0.91025390625,
);

class CurveRun {
  CurveRun(this.curve, this.duration, this.from, this.to)
      : elapsedMs = 0.0;

  final Curve curve;
  final Duration duration;
  final double from;
  final double to;
  double elapsedMs;

  double get value {
    final t = (elapsedMs / duration.inMilliseconds).clamp(0.0, 1.0);
    return from + (to - from) * curve.transform(t);
  }

  bool advance(double dtMs) {
    elapsedMs += dtMs;
    return elapsedMs >= duration.inMilliseconds;
  }
}

class ExtentSpring {
  ExtentSpring({
    required double from,
    required double to,
    required double velocity,
    SpringDescription? spring,
  })  : _spring = spring ??
            SpringDescription.withDampingRatio(
              mass: 1.0,
              stiffness: 500.0,
              ratio: 1.0,
            ),
        _from = from,
        _to = to,
        _velocity = velocity;

  SpringDescription _spring;
  double _from;
  double _to;
  double _velocity;
  double _elapsedSeconds = 0.0;

  double valueAt(double dtSeconds) {
    _elapsedSeconds += dtSeconds;
    final sim = SpringSimulation(_spring, _from, _to, _velocity);
    return sim.x(_elapsedSeconds);
  }

  double velocityAt(double dtSeconds) {
    final sim = SpringSimulation(_spring, _from, _to, _velocity);
    return sim.dx(_elapsedSeconds + dtSeconds);
  }

  bool isDone(double dtSeconds) {
    final sim = SpringSimulation(_spring, _from, _to, _velocity);
    return sim.isDone(_elapsedSeconds + dtSeconds);
  }

  void retarget(double newTo, {required double currentValue, required double currentVelocity}) {
    _from = currentValue;
    _to = newTo;
    _velocity = currentVelocity;
    _elapsedSeconds = 0.0;
  }
}

render_chat_scroll_view.dart: что встраивать
1) Состояние

В RenderChatScrollView добавь:

dart
final Set<int> _pendingRemovalIds = <int>{};
final Set<int> _pendingUpdateIds = <int>{};
final Set<int> _animatingMessageIds = <int>{};
double _lastTickSeconds = 0.0;

Если хочешь держать mutation state точнее, можно ещё хранить Map<int, ChatMutationKind>.
2) Подписка на mutations

При установке data source:

dart
dataSource.mutations.listen(_onMutation);
dataSource.pendingRemovalIds.addListener(_onPendingRemovalChanged);

И в dispose обязательно отписаться.
3) Mutation handler

dart
void _onMutation(ChatMutation mutation) {
  switch (mutation.kind) {
    case ChatMutationKind.remove:
      _pendingRemovalIds.add(mutation.id);
      _scheduleMutationAnimation();
      break;
    case ChatMutationKind.update:
      _pendingUpdateIds.add(mutation.id);
      markNeedsLayout();
      break;
    case ChatMutationKind.insert:
      markNeedsLayout();
      break;
  }
}

4) Start removal animation

Когда pendingRemovalIds меняется:

dart
void _onPendingRemovalChanged() {
  final ids = dataSource.pendingRemovalIds.value;
  for (final id in ids) {
    final child = children[id];
    if (child == null) continue;

    final pd = child.parentData! as ChatMessageParentData;
    if (pd.pendingRemoval) continue;

    pd.pendingRemoval = true;
    pd.heightSpring ??= ExtentSpring(
      from: pd.animatedHeight,
      to: 0.0,
      velocity: 0.0,
    );
    pd.opacityRun = CurveRun(
      telegramCurve,
      const Duration(milliseconds: 220),
      1.0,
      0.0,
    );
    _animatingMessageIds.add(id);
  }
  _ensureTicker();
}

height + width update

Вот главный момент: при update сообщения надо анимировать и высоту, и ширину одновременно.
Что считать width-изменением

Если у render box после layout() изменился size.width или если у вашего content render появился новый bubble width, тогда:

    animatedWidth стартует с текущего значения;

    targetWidth становится новым;

    width анимируется CurveRun(telegramCurve, ...);

    если width влияет на height — после окончания/во время update должен быть новый layout pass и новый targetHeight.

Обновление после layout

В buildChild() или после child.layout():

dart
void _syncAnimatedExtents(RenderBox child, double newHeight, double? newWidth) {
  final pd = child.parentData! as ChatMessageParentData;

  if (pd.targetHeight != newHeight) {
    final currentHeight = pd.animatedHeight == 0.0 ? newHeight : pd.animatedHeight;
    pd.targetHeight = newHeight;
    pd.heightSpring ??= ExtentSpring(
      from: currentHeight,
      to: newHeight,
      velocity: 0.0,
    );
    _animatingMessageIds.add(pd.id);
  }

  if (newWidth != null && pd.targetWidth != newWidth) {
    pd.targetWidth = newWidth;
    pd.animatedWidth ??= newWidth;
    pd.widthRun = CurveRun(
      telegramCurve,
      const Duration(milliseconds: 180),
      pd.animatedWidth!,
      newWidth,
    );
    _animatingMessageIds.add(pd.id);
  }

  _ensureTicker();
}

Painting logic

В paint() у тебя уже есть retained layers. Для анимации нужно:

    offset считать по animatedHeight, не по targetHeight;

    если child pendingRemoval — paint с clip height = animatedHeight;

    opacity рисовать через OpacityLayer или pushOpacity, если уже есть layer stack.

Идея:

dart
void _paintMessage(PaintingContext context, RenderBox child) {
  final pd = child.parentData! as ChatMessageParentData;

  final height = pd.animatedHeight;
  final width = pd.animatedWidth ?? child.size.width;

  if (pd.opacityRun != null) {
    context.pushOpacity(
      offset,
      (pd.opacityRun!.value * 255).round().clamp(0, 255),
      (ctx, off) {
        ctx.paintChild(child, off);
      },
    );
  } else {
    context.paintChild(child, offset);
  }

  if (pd.pendingRemoval) {
    // clip to animatedHeight if needed
  }
}

Layout integration

Тебе не надо ломать весь performLayout. Достаточно в конце layout-прохода:

    Обновить targetHeight/targetWidth.

    Запустить нужные animations.

    Recompute offsets from anchor using animatedHeight.

    Если есть активные animations, держать ticker живым.

    Если animation закончилась — удалить child через removeChildren() и только потом confirmRemoval().

Держать удаляемый child живым

Это главная ошибка, которую нельзя допустить: если performLayout() увидел, что message уже absent в data source, и сразу вызвал removeChildren([id]), анимации не будет. Поэтому нужно состояние:

    data source says remove pending;

    child остаётся в tree;

    render object анимирует height/opacity;

    после завершения вызывает confirmRemoval() и только потом реально вычищает storage.

Что делать с updates

Update — это не только изменение текста. Это может быть:

    edit сообщения;

    reaction count;

    delivery status;

    image loaded;

    markdown expanded.

Для всех них логика одна:

    child rebuild/update happens;

    size remeasured;

    если размер изменился, запускается resize animation;

    если нет — просто repaint.

Что я бы сделал жёстко

Если честно, не стал бы изначально анимировать горизонталь в том же уровне точности, что вертикаль. Порядок приоритета такой:

    vertical height animation;

    removal fade + collapse;

    insert fade + expand;

    horizontal width animation только для bubble content, а не для layout slot.

Почему: горизонталь в вашем UI почти наверняка не должна двигать соседей. Если она начнёт менять bubble width внутри content, но не влияет на viewport offset, это достаточно визуально. Если же ты попытаешься включить её в общий layout flow, получишь лишний сложный invalidation path.
Практический вывод

Твой текущий код уже готов к этому, но надо:

    добавить отдельный mutation/notifier path;

    хранить pending removal/update;

    анимировать animatedHeight;

    animatedWidth держать отдельно;

    удалять сообщение только после завершения collapse;

    использовать telegramCurve для opacity/width, а spring — для высоты.

Я могу следующим сообщением собрать это уже в формате конкретных diff-блоков по файлам: chat_data_source.dart, render_chat_scroll_view.dart, chat_scroll_element.dart, без общей теории, чтобы ты просто вставлял куски по месту.

я помню ты упомянал ClipRectLayer, его не нужно нигде реализовывать уже?

Нет, отдельно реализовывать ClipRectLayer не нужно. Это уже встроенный слой Flutter; в render object ты просто вызываешь context.pushClipRect(...), и Flutter сам создаёт/переиспользует ClipRectLayer через oldLayer при необходимости.
Как это делается у вас

В вашем случае это должно жить прямо в paint() конкретного child render box или в paint-пути сообщения, а не как отдельный самописный класс. Типичный паттерн такой:

dart
_clipLayer.layer = context.pushClipRect(
  needsCompositing,
  offset,
  Rect.fromLTWH(0, 0, childWidth, clippedHeight),
  (ctx, off) {
    ctx.paintChild(child, off);
  },
  clipBehavior: Clip.hardEdge,
  oldLayer: _clipLayer.layer,
);

Если needsCompositing == false, Flutter вообще не создаёт layer и применяет clip более дешёвым способом внутри paint pipeline. Если needsCompositing == true, тогда он создаёт/переиспользует ClipRectLayer автоматически.
Что хранить у себя

У себя нужно хранить только LayerHandle<ClipRectLayer> или ClipRectLayer? oldLayer, чтобы переиспользовать слой между кадрами. То есть не “реализовывать слой”, а “держать ссылку на ранее созданный слой” и передавать её в pushClipRect как oldLayer.

Пример:

dart
final LayerHandle<ClipRectLayer> _clipLayer = LayerHandle<ClipRectLayer>();

@override
void paint(PaintingContext context, Offset offset) {
  _clipLayer.layer = context.pushClipRect(
    needsCompositing,
    offset,
    Rect.fromLTWH(0, 0, size.width, _animatedHeight),
    (ctx, off) => ctx.paintChild(child!, off),
    oldLayer: _clipLayer.layer,
  );
}

Где это реально нужно

Для вашей анимации extent это полезно только там, где animatedHeight < targetHeight или где нужен локальный crop при collapse/insert. Если height уже равен target и child не анимируется, clip лучше не держать вообще — лишний clip без необходимости это просто лишняя работа.
Жёсткий вывод

    ClipRectLayer писать самому не надо.

    Нужно вызывать PaintingContext.pushClipRect.

    Нужно хранить oldLayer/LayerHandle, если хочешь retained compositing и меньше мусора между кадрами.

Если хочешь, следующим сообщением я дам точный патч для вашего paint() пути: где объявить LayerHandle, где выставлять clipRect, и как условно включать clip только во время pendingRemoval / heightSpring.

давай

Да. В вашем RenderChatScrollView это надо вставлять именно в paint-path, и у вас уже есть готовая точка для retained compositing: final LayerHandle _clipLayer = LayerHandle(); в файле уже объявлен. Значит, не нужен новый слой-объект; нужен только патч в _paintContents() или в отдельном _paintMessageWithExtentClip().
Что менять

Лучшее место — прямо в цикле paint сообщений, где сейчас делается context.paintChild(child, offset + Offset(0, pd.offset));.
Там надо условно оборачивать сообщение в pushClipRect, только если у него есть активная анимация высоты или pending removal.
Идея

    статичное сообщение: paint как сейчас, без clip;

    анимирующееся по высоте: paint через pushClipRect;

    clip rect высоты animatedHeight или targetHeight, в зависимости от фазы;

    использовать oldLayer: _clipLayer.layer для retained layer reuse.

Патч для paint

Вот минимальный рабочий кусок, который можно вставить в RenderChatScrollView:

dart
void _paintMessageWithClip(
  PaintingContext context,
  RenderBox child,
  ChatMessageParentData pd,
  Offset offset,
) {
  final needsClip = pd.pendingRemoval ||
      pd.heightSpring != null ||
      (pd.animatedHeight > 0 && pd.animatedHeight < child.size.height);

  if (!needsClip) {
    _clipLayer.layer = null;
    context.paintChild(child, offset + Offset(0, pd.offset));
    return;
  }

  final clipHeight = pd.animatedHeight.clamp(0.0, child.size.height);
  if (clipHeight <= 0.0) {
    return;
  }

  _clipLayer.layer = context.pushClipRect(
    needsCompositing,
    offset + Offset(0, pd.offset),
    Rect.fromLTWH(0, 0, size.width, clipHeight),
    (ctx, off) {
      ctx.paintChild(child, off);
    },
    clipBehavior: Clip.hardEdge,
    oldLayer: _clipLayer.layer,
  );
}

И потом в _paintContents() заменить этот вызов:

dart
context.paintChild(child, offset + Offset(0, pd.offset));

на:

dart
_paintMessageWithClip(context, child, pd, offset);

Где это не надо делать

Не нужно делать clip:

    для обычного scroll-only;

    для floating header;

    для overlay;

    для chunk-error tile, если он не анимируется по высоте.

Иначе ты просто добавишь лишний compositing overhead без пользы.
Важный момент

ClipRectLayer уже создаётся Flutter’ом автоматически через pushClipRect; свой класс писать не надо.
Твой LayerHandle<ClipRectLayer> нужен только чтобы переиспользовать oldLayer между кадрами и не плодить новые слои на каждый tick.
Жёсткая рекомендация

Сейчас у тебя render_chat_scroll_view.dart уже содержит final LayerHandle _clipLayer = LayerHandle();, но по факту в _paintContents() clip-path ещё не внедрён. Значит, патч должен быть именно в paint loop, а не в lifecycle или layout. Это чистый renderer-level change, без трогания ChatScrollElement.

Если хочешь, следующим сообщением я дам точный diff-style патч по твоему render_chat_scroll_view.dart:

    где вставить _paintMessageWithClip,

    где заменить paint calls,

    и как расширить ChatMessageParentData под animatedHeight/opacityRun/heightSpring без поломки остального файла.

конечно

Вот точечный патч. У тебя clip уже наполовину готов через final LayerHandle _clipLayer = LayerHandle();, а paint() сейчас просто рисует child’ы напрямую через context.paintChild(...). Значит, нужно не новый слой писать, а обернуть только анимирующиеся сообщения в pushClipRect.
1) ParentData

Сначала расширь ChatMessageParentData в render_chat_scroll_view.dart:

dart
class ChatMessageParentData extends ParentData {
  int id = 0;
  double offset = 0;
  bool startsDay = false;
  Object? dayBucket;
  double dividerOpacity = 1;

  double targetHeight = 0.0;
  double animatedHeight = 0.0;

  double? targetWidth;
  double? animatedWidth;

  ExtentSpring? heightSpring;
  CurveRun? opacityRun;
  CurveRun? widthRun;

  bool pendingRemoval = false;
  bool isNewInsert = false;
}

offset остаётся как есть — это вертикальная позиция вьюпорта. animatedHeight и animatedWidth нужны только для анимации. pendingRemoval нужен, чтобы child не исчезал из дерева до конца collapse.
2) Helper для clip

Добавь в RenderChatScrollView helper. Он использует уже существующий _clipLayer:

dart
void _paintMessageWithClip(
  PaintingContext context,
  RenderBox child,
  ChatMessageParentData pd,
  Offset offset,
) {
  final topLeft = offset + Offset(0, pd.offset);
  final clipHeight = pd.pendingRemoval || pd.heightSpring != null
      ? pd.animatedHeight.clamp(0.0, child.size.height)
      : child.size.height;

  final needsClip = pd.pendingRemoval ||
      pd.heightSpring != null ||
      pd.isNewInsert ||
      (pd.animatedHeight > 0 && pd.animatedHeight < child.size.height);

  if (!needsClip) {
    _clipLayer.layer = null;
    context.paintChild(child, topLeft);
    return;
  }

  if (clipHeight <= 0.0) return;

  _clipLayer.layer = context.pushClipRect(
    needsCompositing,
    topLeft,
    Rect.fromLTWH(0, 0, size.width, clipHeight),
    (ctx, off) {
      ctx.paintChild(child, off);
    },
    clipBehavior: Clip.hardEdge,
    oldLayer: _clipLayer.layer,
  );
}

ClipRectLayer здесь создаёт Flutter сам; тебе нужен только pushClipRect и oldLayer.
3) Replace в paint loop

Внутри _paintContents() замени прямой paint сообщений:

dart
context.paintChild(child, offset + Offset(0, pd.offset));

на:

dart
_paintMessageWithClip(context, child, pd, offset);

И то же самое для _chunkErrors, если хочешь, чтобы chunk-error tile тоже мягко схлопывался/раскрывался. Если не хочешь — оставь chunk errors без clip, это нормально.
4) Когда clip включать

Смысл такой:

    обычный scroll-only — clip не нужен;

    insert animation — clip нужен, пока animatedHeight < targetHeight;

    remove animation — clip нужен, пока animatedHeight > 0;

    resize animation — clip нужен, пока animatedHeight не совпал с targetHeight.

Это лучше держать через needsClip, а не через отдельный флаг на каждую операцию.
5) Где обновлять animatedHeight

В tick/layout path уже должен быть расчёт анимации. Для этого pd.animatedHeight должен обновляться до _repositionFromAnchor(). Иначе ты сначала расставишь детей по старым высотам, потом изменишь высоты, и получишь визуальный jump.
Логика примерно такая:

dart
void _tickAnimatedExtents(double dtSeconds) {
  for (final child in _children.values) {
    final pd = _parentData(child);

    if (pd.heightSpring != null) {
      pd.animatedHeight = pd.heightSpring!.valueAt(dtSeconds);
      if (pd.heightSpring!.isDoneAt(dtSeconds)) {
        pd.animatedHeight = pd.targetHeight;
        pd.heightSpring = null;
        if (pd.pendingRemoval) {
          // finalize removal outside paint path, during layout callback
        }
      }
    }

    if (pd.opacityRun != null) {
      pd.opacityRun!.advance(dtSeconds * 1000.0);
    }

    if (pd.widthRun != null) {
      pd.animatedWidth = pd.widthRun!.value;
      if (pd.widthRun!.advance(dtSeconds * 1000.0)) {
        pd.animatedWidth = pd.targetWidth;
        pd.widthRun = null;
      }
    }
  }
}

Я намеренно не расписываю сюда весь _onTick, потому что у тебя он очень большой и его нельзя сломать без понимания всех существующих side effects. Но принцип жёсткий: extent update должен происходить раньше reposition.
6) Где clip НЕ делать

Не надо оборачивать:

    overlay child;

    floating header;

    scrollbar;

    highlight layer.

Иначе ты начнёшь клипать то, что вообще не является частью message extent.
7) Что по horizontal

Горизонтальную анимацию я бы не тащил в pushClipRect на уровне viewport. Она должна жить внутри самого message render object / bubble render object. На уровне viewport тебе достаточно только держать animatedWidth как state и использовать его, если конкретный message render умеет рисовать bubble с custom width. Но в viewport layout horizontal не влияет на offset соседей.
8) Что сделать прямо сейчас

Самый безопасный минимальный шаг:

    Добавить animatedHeight / heightSpring / pendingRemoval в ChatMessageParentData.

    Добавить _paintMessageWithClip(...).

    В _paintContents() заменить paint child на helper.

    Не трогать пока layout, если хочешь сначала проверить только visual clip.

    Потом уже подключить animation tick, чтобы animatedHeight реально менялся.

9) Чего ждать от этого патча

Это даст:

    мягкий visual collapse/expand,

    отсутствие внезапного overflow при shrink,

    retained compositing через oldLayer,

    без ручной реализации ClipRectLayer.

Но честно: это ещё не complete insertion/removal animation. Это только рендер-контур, который позволит анимирующимся высотам не лезть за свои bounds. Полноценная интеграция всё ещё требует tick/update/remove flow в performLayout/_onTick.

Если хочешь, следующим сообщением я дам уже конкретный патч для _onTick и performLayout, чтобы animatedHeight реально двигался, а pendingRemoval корректно доводил child до removeChildren() только после окончания анимации.

давай

Да — теперь видно, куда встраивать анимацию без гаданий: performLayout() уже разделён на normal mode, _layoutFromAnchor(), _repositionFromAnchor() и _onTick(). Жёсткая правда: если ты начнёшь «анимировать высоту» только в paint, layout будет врать о геометрии, и viewport начнёт дергаться на GC, renormalize и pinning.
Что должно делать layout

performLayout() обязан быть источником правды для offset и текущих размеров child’ов; paint не должен решать, сколько место занимает сообщение.
Если animatedHeight меняется, то _repositionFromAnchor() должен использовать уже обновлённые parent-data высоты до выставления offsets следующему слою детей.
Правильный порядок

    Tick обновляет анимационные state-поля в ChatMessageParentData.

    Layout фаза пересчитывает offsets, уже опираясь на новые animatedHeight.

    Paint просто clips, но не меняет структуру потока.

Это не косметика. Это единственный способ не сломать anchor-based viewport, где всё держится на _controller.anchorMessageId и anchorPixelOffset.
Патч для tick

Добавь один внутренний метод и вызывай его в _onTick() до _repositionFromAnchor():

dart
void _tickMessageAnimations(Duration elapsed) {
  final dt = _lastTickElapsed == null
      ? 0.0
      : (elapsed - _lastTickElapsed!).inMicroseconds / 1000000.0;

  if (dt <= 0.0) return;

  bool needsRelayout = false;
  bool needsReposition = false;
  final toRemove = <int>[];

  for (final entry in _children.entries) {
    final id = entry.key;
    final child = entry.value;
    final pd = _parentData(child);

    if (pd.heightSpring != null) {
      final next = pd.heightSpring!.valueAt(dt);
      if ((next - pd.animatedHeight).abs() > 0.5) {
        pd.animatedHeight = next;
        needsReposition = true;
      }

      if (pd.heightSpring!.isDone) {
        pd.animatedHeight = pd.targetHeight;
        pd.heightSpring = null;
        needsReposition = true;
        if (pd.pendingRemoval && pd.animatedHeight <= 0.0) {
          toRemove.add(id);
        }
      }
    }

    if (pd.opacityRun != null) {
      final done = pd.opacityRun!.advance(dt * 1000.0);
      if (done) pd.opacityRun = null;
    }

    if (pd.widthRun != null) {
      final done = pd.widthRun!.advance(dt * 1000.0);
      if (done) pd.widthRun = null;
    }
  }

  if (toRemove.isNotEmpty) {
    _invokeChildManagerLayout(() {
      childManager!.removeChildren(toRemove);
    });
    needsRelayout = true;
  }

  if (needsReposition) {
    _repositionFromAnchor();
  }

  if (needsRelayout || needsReposition) {
    markNeedsPaint();
  }
}

И в _onTick(Duration elapsed) вставь:

dart
_tickMessageAnimations(elapsed);

сразу после _lastTickElapsed = elapsed;.
Что нужно в performLayout

Проблема сейчас не в самом performLayout, а в том, что _buildMessage() строит child, а потом сразу _setOffset(child, y) и идёт дальше.
Если у тебя есть animatedHeight, то для таких child’ов нельзя использовать просто child.size.height как конечную геометрию, иначе в следующем кадре y += child.size.height разъедется с визуальной высотой.
Минимальный фикс

Сделай helper:

dart
double _effectiveChildHeight(RenderBox child) {
  final pd = _parentData(child);
  final h = pd.animatedHeight;
  return h > 0.0 ? h : child.size.height;
}

И замени в трёх местах:

    _fanOutFromAnchor()

    _repositionMessagesOnly()

    _repositionFromAnchor()

все child.size.height на _effectiveChildHeight(child) там, где высота влияет на следующий y.

Пример для fan-out:

dart
final h = _effectiveChildHeight(child);
_setOffset(child, y);
built.add(id);
y += h;

И для вверх/вниз обхода тоже.
Где хранить targetHeight

targetHeight должен приходить из самого child после layout(), а не высчитываться во viewport. Сейчас _buildMessage() уже делает child.layout(cc, parentUsesSize: true);.
После этого сразу запиши:

dart
final pd = _parentData(child);
pd.targetHeight = child.size.height;
if (pd.animatedHeight <= 0.0 || pd.isNewInsert) {
  pd.animatedHeight = child.size.height;
  pd.heightSpring = null;
  pd.isNewInsert = false;
} else if (pd.animatedHeight != child.size.height) {
  pd.heightSpring ??= ExtentSpring(
    from: pd.animatedHeight,
    to: child.size.height,
  );
}

Это грубо, но честно: viewport должен знать только старт/финиш высоты, а форму easing должен вести отдельный spring object.
Как делать remove

Не удаляй child сразу из removeChildren() если он анимируется на collapse.
Сначала ставь:

dart
pd.pendingRemoval = true;
pd.targetHeight = 0.0;
pd.heightSpring ??= ExtentSpring(
  from: pd.animatedHeight,
  to: 0.0,
);

А реальный removeChildren([id]) делай только когда animatedHeight <= 0.0.

Это важно, потому что у тебя GC уже идет по staleMessages в конце performLayout(). Если не отложить removal, ты просто выдернешь child до конца анимации.
Самая слабая часть твоей текущей архитектуры

Сейчас viewport-based animation logic смешивает:

    spatial layout,

    retention/GC,

    navigation pinning,

    and paint retention.

Это работает, пока анимация одна. Как только у тебя появятся одновременные insert+remove+scroll, без строгого separation of concerns начнутся плавающие баги. Особенно опасен _renormalizeAnchor(): он выбирает topmost visible child по реальному size.height, и если ты не синхронизируешь effective height с animation state, anchor будет прыгать не там, где нужно.
Что я бы сделал вместо этого

Самый чистый вариант:

    viewport только управляет списком, offsets и gc;

    message render object сам анимирует свою внутреннюю высоту;

    viewport знает только animatedExtent через parent data callback.

Но если хочешь остаться в текущей архитектуре, то обязательно держи animatedHeight в parent data и используй её consistently во fan-out / reposition / clip path. Иначе это будет half-animated system, а half-animated systems обычно выглядят хуже, чем отсутствие анимации вообще.
Следующий шаг

Следующий правильный патч — это уже конкретный diff по четырём точкам:

    _buildMessage(),

    _fanOutFromAnchor(),

    _repositionMessagesOnly(),

    _repositionFromAnchor(),

чтобы заменить child.size.height на effectiveHeight, плюс точка завершения removal в конце _onTick().

Сделать это?

давай

Да, теперь можно делать жёсткий патч. У тебя уже есть точная механика: _fanOutFromAnchor() строит flow, _repositionFromAnchor() лишь двигает offsets, а _paintContents() сейчас тупо рисует child.size.height-based children без учета animated extent. Это и есть узкое место: если высота меняется, надо синхронно менять и fan-out, и reposition, и clip-путь, иначе система будет врать о геометрии.
Точный diff
1) Parent data

Добавь в ChatMessageParentData:

dart
double targetHeight = 0.0;
double animatedHeight = 0.0;
bool pendingRemoval = false;
bool isNewInsert = false;
ExtentSpring? heightSpring;

Не распыляйся на width, пока не заставишь height работать стабильно. Горизонтальную анимацию лучше держать внутри конкретного bubble render object, а не в viewport.
2) Helpers

Добавь два helper’а в RenderChatScrollView:

dart
double _effectiveChildHeight(RenderBox child) {
  final pd = _parentData(child);
  final h = pd.animatedHeight;
  return h > 0.0 ? h : child.size.height;
}

void _syncAnimatedHeight(RenderBox child) {
  final pd = _parentData(child);
  final measured = child.size.height;

  pd.targetHeight = measured;
  if (pd.isNewInsert && pd.animatedHeight <= 0.0) {
    pd.animatedHeight = measured;
    pd.heightSpring = null;
    pd.isNewInsert = false;
    return;
  }

  if (pd.pendingRemoval) {
    if (pd.heightSpring == null) {
      pd.heightSpring = ExtentSpring(from: pd.animatedHeight, to: 0.0);
    }
    return;
  }

  if ((pd.animatedHeight - measured).abs() > 0.5) {
    pd.heightSpring ??= ExtentSpring(from: pd.animatedHeight, to: measured);
  }
}

Это грубо, но правильно по архитектуре: viewport хранит only extent truth, а easing живёт в spring state.
3) _buildMessage

В _buildMessage(...) после child.layout(...) вставь:

dart
final pd = _parentData(child);
pd.isNewInsert = pd.animatedHeight <= 0.0;
_syncAnimatedHeight(child);

И оставь уже существующие startsDay/dayBucket assignments.
4) _fanOutFromAnchor

Везде, где у тебя:

dart
y += anchor.size.height;
...
y += tile.size.height;
...
y += child.size.height;
...
y -= tile.size.height;
...
y -= child.size.height;

замени на _effectiveChildHeight(...).
Конкретно:

dart
var y = anchorTop + _effectiveChildHeight(anchor);
...
y += _effectiveChildHeight(tile);
...
y += _effectiveChildHeight(child);
...
y -= _effectiveChildHeight(tile);
...
y -= _effectiveChildHeight(child);

Это критично. Если оставить size.height, то при collapse/expand offsets начнут расходиться с визуальным представлением.
5) _repositionMessagesOnly

Там тоже замени оба child.size.height на _effectiveChildHeight(child):

dart
var y = _controller.anchorPixelOffset;
_setOffset(anchor, y);
y += _effectiveChildHeight(anchor);

for (var id = anchorId + 1; id <= maxBuiltId; id++) {
  final child = _children[id];
  if (child == null) continue;
  _setOffset(child, y);
  y += _effectiveChildHeight(child);
}

y = _controller.anchorPixelOffset;
for (var id = anchorId - 1; id >= minBuiltId; id--) {
  final child = _children[id];
  if (child == null) continue;
  y -= _effectiveChildHeight(child);
  _setOffset(child, y);
}

6) _repositionFromAnchor

Точно так же заменяй size.height на _effectiveChildHeight(...) для anchor, message tiles и chunk-error tiles:

dart
y += _effectiveChildHeight(anchor);
...
y += _effectiveChildHeight(tile);
...
y += _effectiveChildHeight(child);
...
y -= _effectiveChildHeight(tile);
...
y -= _effectiveChildHeight(child);

Если этого не сделать, chunk-error tile и message tiles будут жить в разных геометрических мирах.
7) _paintContents

Оставь paint как есть для статических child’ов, но для анимирующихся — clip. Используй helper:

dart
void _paintMessageWithClip(
  PaintingContext context,
  RenderBox child,
  ChatMessageParentData pd,
  Offset offset,
) {
  final needsClip = pd.pendingRemoval || pd.heightSpring != null;
  final topLeft = offset + Offset(0, pd.offset);

  if (!needsClip) {
    _clipLayer.layer = null;
    context.paintChild(child, topLeft);
    return;
  }

  final clipHeight = pd.animatedHeight.clamp(0.0, child.size.height);
  if (clipHeight <= 0.0) return;

  _clipLayer.layer = context.pushClipRect(
    needsCompositing,
    topLeft,
    Rect.fromLTWH(0, 0, size.width, clipHeight),
    (ctx, off) => ctx.paintChild(child, off),
    clipBehavior: Clip.hardEdge,
    oldLayer: _clipLayer.layer,
  );
}

И в _paintContents() вместо context.paintChild(child, ...) зови это helper’ом. Это именно retained clipping, а не brute-force redraw.
OnTick / removal
8) _onTick

Тебе нужен последовательный цикл:

dart
void _tickMessageAnimations(Duration elapsed) {
  bool needsReposition = false;
  final toRemove = <int>[];

  for (final entry in _children.entries) {
    final id = entry.key;
    final child = entry.value;
    final pd = _parentData(child);

    if (pd.heightSpring != null) {
      pd.animatedHeight = pd.heightSpring!.valueAt(elapsed);
      needsReposition = true;

      if (pd.heightSpring!.isDone) {
        pd.animatedHeight = pd.targetHeight;
        if (pd.pendingRemoval) {
          toRemove.add(id);
        }
        pd.heightSpring = null;
        pd.isNewInsert = false;
      }
    }
  }

  if (toRemove.isNotEmpty) {
    _invokeChildManagerLayout(() {
      childManager!.removeChildren(toRemove);
    });
  }

  if (needsReposition) {
    _repositionFromAnchor();
    markNeedsPaint();
  }
}

И да, это intentionally blunt: valueAt(elapsed) должен быть monotonic and pure. Если твой ExtentSpring уже не умеет этого, сначала нормализуй его, а не раздувай архитектуру.
Что не трогать

Не лезь пока в:

    _updateFloatingHeader(),

    _updateScrollSemantics(),

    _scrollbar math,

    _resolveAnchorBox().

Там уже достаточно хрупкая логика, и добавление animation state туда только создаст ложные регрессии.
Честная оценка

Этот патч работоспособен, но он не идеален. Главный архитектурный минус: ты всё ещё держишь animation state в viewport parent-data, то есть смешиваешь layout retention и tween state в одном месте. Это допустимо для tight control, но это долг по техдолгу, который потом выйдет боком, когда появятся параллельные анимации, nested bubbles или per-message effects.

Если хочешь, следующим сообщением я могу дать готовый consolidated patch block в формате “replace this block with that block” именно для:

    _buildMessage,

    _fanOutFromAnchor,

    _repositionMessagesOnly,

    _repositionFromAnchor,

    _paintContents,
    чтобы ты мог почти напрямую вставить в файл.