import 'package:chat_outbox/chat_outbox.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_outbox.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_status_motion.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

// The appearance of a fresh outgoing row, the host's since it owns the row
// (the outbox's `OutgoingAppearancePolicy` says how; this animates it):
//
// - `DemoRowAppearanceScope`, above the chat list: the list-wide slide of
//   Android (every row moves up by the added height, `DemoListShift`), where
//   the list ends, and whether it shows its newest message.
// - `DemoShiftedRow`, around every row: paints and hit-tests the row at the
//   slide's offset, repainting only.
// - `DemoOutgoingRowAppearance`, around the user's own row: asks the outbox
//   once how it appears, and runs it.

// --- Scope ------------------------------------------------------------------

/// Where the rows of one chat list appear: put above the list, it owns the
/// slide every row follows ([DemoListShift]) and answers for the rows
/// whether the list shows its newest message ([atBottom]) and where it is.
class DemoRowAppearanceScope extends StatefulWidget {
  /// The scope of the list in [child]; [atBottom] reads, as a row first
  /// builds, whether the list showed its newest message (a chat scroll
  /// controller's `isAtTail`, which reports the layout before the row's).
  const DemoRowAppearanceScope({
    required this.atBottom,
    required this.child,
    super.key,
  });

  /// Whether the list shows its newest message.
  final bool Function() atBottom;

  /// The list.
  final Widget child;

  @override
  State<DemoRowAppearanceScope> createState() => _DemoRowAppearanceScopeState();
}

class _DemoRowAppearanceScopeState extends State<DemoRowAppearanceScope>
    with SingleTickerProviderStateMixin {
  late final DemoListShift _shift = DemoListShift(vsync: this);
  final GlobalKey _list = GlobalKey();

  @override
  void dispose() {
    _shift.dispose();
    super.dispose();
  }

  // The list's rect in global coordinates, once laid out.
  Rect? get _listRect => switch (_list.currentContext?.findRenderObject()) {
    final RenderBox box when box.attached && box.hasSize =>
      box.localToGlobal(Offset.zero) & box.size,
    _ => null,
  };

  @override
  Widget build(BuildContext context) => _AppearanceScope(
    state: this,
    child: KeyedSubtree(key: _list, child: widget.child),
  );
}

class _AppearanceScope extends InheritedWidget {
  const _AppearanceScope({required this.state, required super.child});

  final _DemoRowAppearanceScopeState state;

  static _DemoRowAppearanceScopeState? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_AppearanceScope>()?.state;

  @override
  bool updateShouldNotify(_AppearanceScope oldWidget) =>
      !identical(state, oldWidget.state);
}

// --- The list's slide ---------------------------------------------------------

/// The slide every row of a list follows while a fresh row appears at its
/// bottom: the rows are drawn [offset] below their place, which runs from
/// the added height to 0.
///
/// The list itself has already moved the rows up by the added height (it
/// keeps its newest message in view); drawing them that much lower on the
/// same frame and easing back is the rows translating up from below. A
/// second row added mid-slide starts again from where the rows are drawn,
/// plus its height.
final class DemoListShift extends ChangeNotifier {
  /// A slide ticking on [vsync].
  DemoListShift({required TickerProvider vsync}) {
    _$controller = AnimationController(vsync: vsync)
      ..addListener(notifyListeners)
      ..addStatusListener(_onStatus);
  }

  late final AnimationController _$controller;
  double _$from = 0;
  Curve _$curve = Curves.linear;
  final List<VoidCallback> _$whenDone = [];

  /// How far below its place each row is drawn now.
  double get offset => _$controller.isAnimating
      ? _$from * (1 - _$curve.transform(_$controller.value))
      : 0;

  /// Whether the rows are sliding.
  bool get sliding => _$controller.isAnimating;

  /// Slides the rows up from [height] below their place as [form] says;
  /// [whenDone] runs once the rows are at rest.
  void start(
    double height,
    OutgoingAppearance$SlideUp form, {
    VoidCallback? whenDone,
  }) {
    _$from = offset + height;
    _$curve = form.curve;
    if (whenDone != null) _$whenDone.add(whenDone);
    _$controller
      ..duration = form.duration
      ..forward(from: 0);
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _$from = 0;
    notifyListeners();
    final done = List.of(_$whenDone);
    _$whenDone.clear();
    for (final callback in done) {
      callback();
    }
  }

  @override
  void dispose() {
    _$controller.dispose();
    super.dispose();
  }
}

/// A row of a list under a [DemoRowAppearanceScope], drawn at the list's
/// slide; outside a scope it is [child] as it is.
class DemoShiftedRow extends StatelessWidget {
  /// The row [child].
  const DemoShiftedRow({required this.child, super.key});

  /// The row.
  final Widget child;

  @override
  Widget build(BuildContext context) => switch (_AppearanceScope.of(context)) {
    final scope? => _ShiftedRow(shift: scope._shift, child: child),
    null => child,
  };
}

class _ShiftedRow extends SingleChildRenderObjectWidget {
  const _ShiftedRow({required this.shift, required super.child});

  final DemoListShift shift;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderShiftedRow(shift);

  @override
  void updateRenderObject(
    BuildContext context,
    // The render object is this widget's own.
    // ignore: library_private_types_in_public_api
    covariant _RenderShiftedRow renderObject,
  ) => renderObject.shift = shift;
}

// Paints and hit-tests its child at the slide's offset; a frame of the
// slide repaints, nothing is laid out again.
class _RenderShiftedRow extends RenderProxyBox {
  _RenderShiftedRow(this._shift);

  DemoListShift _shift;
  set shift(DemoListShift value) {
    if (identical(value, _shift)) return;
    if (attached) _shift.removeListener(markNeedsPaint);
    _shift = value;
    if (attached) _shift.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  Offset get _offset => Offset(0, _shift.offset);

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _shift.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _shift.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      super.paint(context, offset + _offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintOffset(
        offset: _offset,
        position: position,
        hitTest: (result, position) =>
            super.hitTestChildren(result, position: position),
      );

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.translateByDouble(0, _shift.offset, 0, 1);
}

// --- A fresh outgoing row ------------------------------------------------------

/// The user's own row [messageId] of an [outbox] chat, appearing as its
/// platform does when the outbox says it is fresh.
///
/// It asks once, as it is first built (`DemoOutboxChat.appearanceAt`):
/// a slide starts from the row's first layout, so no frame shows the rows
/// jump; a fade and scale of the bubble waits its delay by where the row
/// ends; a flight (the media cells fly) or none leaves the row as it is.
/// While it moves the row is [DemoRowEntering], which holds back the status
/// motion the platform holds back meanwhile.
class DemoOutgoingRowAppearance extends StatefulWidget {
  /// The appearance of row [messageId] of [outbox]'s chat.
  const DemoOutgoingRowAppearance({
    required this.outbox,
    required this.messageId,
    required this.child,
    super.key,
  });

  /// The chat's outbox binding.
  final DemoOutboxChat outbox;

  /// The row.
  final int messageId;

  /// The row's content.
  final Widget child;

  /// [bubble] as its row's appearance draws it: faded and scaled around its
  /// centre while the row fades in, as it is otherwise.
  static Widget bubble(BuildContext context, Widget bubble) =>
      switch (context.getInheritedWidgetOfExactType<_BubbleAppearance>()) {
        _BubbleAppearance(:final opacity?, :final scale?) => FadeTransition(
          opacity: opacity,
          child: ScaleTransition(scale: scale, child: bubble),
        ),
        _ => bubble,
      };

  @override
  State<DemoOutgoingRowAppearance> createState() =>
      _DemoOutgoingRowAppearanceState();
}

class _DemoOutgoingRowAppearanceState extends State<DemoOutgoingRowAppearance>
    with SingleTickerProviderStateMixin {
  bool _asked = false;
  OutgoingAppearance? _appearance;
  AnimationController? _$fade;
  Animation<double>? _opacity;
  Animation<double>? _scale;
  bool _entering = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_asked) return;
    _asked = true;
    final scope = _AppearanceScope.of(context);
    if (scope == null) return;
    final appearance = widget.outbox.appearanceAt(
      widget.messageId,
      atBottom: scope.widget.atBottom(),
      reduceMotion: MediaQuery.maybeDisableAnimationsOf(context) ?? false,
      policy: DemoOutgoingMotion.appearanceOf(context),
    );
    _appearance = appearance;
    switch (appearance) {
      case OutgoingAppearance$SlideUp():
        _entering = true;
      case OutgoingAppearance$FadeScale(:final opacityFrom, :final scaleFrom):
        _entering = true;
        final fade = _$fade = AnimationController(vsync: this);
        _opacity = Tween<double>(begin: opacityFrom, end: 1).animate(fade);
        _scale = Tween<double>(begin: scaleFrom, end: 1).animate(fade);
        SchedulerBinding.instance.addPostFrameCallback((_) => _startFade());
      case OutgoingAppearance$Flight() || OutgoingAppearance$None() || null:
        break;
    }
  }

  // The first layout of the row: its height is what the rows slide by.
  void _laidOut(Size size) {
    final scope = _AppearanceScope.of(context);
    if ((_appearance, scope) case (
      final OutgoingAppearance$SlideUp slide,
      final scope?,
    )) {
      scope._shift.start(size.height, slide, whenDone: _entered);
    }
  }

  // The fade waits by where the row ends in the list, read once it is
  // painted: the curve's interval holds it at its start meanwhile.
  void _startFade() {
    final fade = _$fade;
    if (!mounted || fade == null) return;
    if (_appearance case final OutgoingAppearance$FadeScale form) {
      final delay = switch ((
        _AppearanceScope.of(context)?._listRect,
        context.findRenderObject(),
      )) {
        (final list?, final RenderBox box) when box.hasSize => form.delayAt(
          rowBottom:
              box.localToGlobal(Offset(0, box.size.height)).dy - list.top,
          listHeight: list.height,
        ),
        _ => Duration.zero,
      };
      final total = delay + form.duration;
      final start = total == Duration.zero
          ? 0.0
          : delay.inMicroseconds / total.inMicroseconds;
      final curved = CurvedAnimation(
        parent: fade,
        curve: Interval(start, 1, curve: form.curve),
      );
      setState(() {
        _opacity = Tween<double>(
          begin: form.opacityFrom,
          end: 1,
        ).animate(curved);
        _scale = Tween<double>(begin: form.scaleFrom, end: 1).animate(curved);
      });
      fade
        ..duration = total
        ..forward().whenComplete(_entered);
    }
  }

  void _entered() {
    if (!mounted || !_entering) return;
    setState(() => _entering = false);
  }

  @override
  void dispose() {
    _$fade?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DemoRowEntering(
    entering: _entering,
    child: _BubbleAppearance(
      opacity: _opacity,
      scale: _scale,
      child: _FirstLayout(onLaidOut: _laidOut, child: widget.child),
    ),
  );
}

class _BubbleAppearance extends InheritedWidget {
  const _BubbleAppearance({
    required this.opacity,
    required this.scale,
    required super.child,
  });

  final Animation<double>? opacity;
  final Animation<double>? scale;

  @override
  bool updateShouldNotify(_BubbleAppearance oldWidget) =>
      opacity != oldWidget.opacity || scale != oldWidget.scale;
}

// Tells its owner the size of its first layout, during that layout, so a
// slide it starts is painted on the same frame.
class _FirstLayout extends SingleChildRenderObjectWidget {
  const _FirstLayout({required this.onLaidOut, required super.child});

  final ValueChanged<Size> onLaidOut;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFirstLayout(onLaidOut);

  @override
  void updateRenderObject(
    BuildContext context,
    // The render object is this widget's own.
    // ignore: library_private_types_in_public_api
    covariant _RenderFirstLayout renderObject,
  ) => renderObject.onLaidOut = onLaidOut;
}

class _RenderFirstLayout extends RenderProxyBox {
  _RenderFirstLayout(this.onLaidOut);

  ValueChanged<Size> onLaidOut;
  bool _told = false;

  @override
  void performLayout() {
    super.performLayout();
    if (_told) return;
    _told = true;
    onLaidOut(size);
  }
}

// --- Entering ---------------------------------------------------------------

/// Whether the row below is still appearing: its time pill holds back the
/// status motion the platform suppresses meanwhile.
class DemoRowEntering extends InheritedWidget {
  /// Marks the row of [child] as [entering] or not.
  const DemoRowEntering({
    required this.entering,
    required super.child,
    super.key,
  });

  /// Whether the row is appearing.
  final bool entering;

  /// Whether the row of [context] is appearing; false outside any row.
  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DemoRowEntering>()?.entering ??
      false;

  @override
  bool updateShouldNotify(DemoRowEntering oldWidget) =>
      entering != oldWidget.entering;
}
