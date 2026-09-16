import 'package:chat_scroll_view/src/chat_widgets/chat_selectable_message.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_selection_chrome.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_selection_gesture_exclusion.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_smooth_contour.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_span_feedback.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Press-lifecycle **tap highlight** around an arbitrary [child].
///
/// Ink arms on pointer **down**, holds while pressed, and fades on **up**.
/// Pointer **cancel**, or travel past touch slop (scroll / drag), clears
/// immediately with no release fade — so list pan on mobile does not leave a
/// fading plate. Short tap and long-press share the same paint; [onTap] /
/// [onLongPress] are separate action channels.
///
/// ## Selection gestures
///
/// - **Mobile / touch:** when [onLongPress] is null, long-press is **not**
///   claimed — the viewport may enter **message selection** (Telegram name
///   chrome). Pass [onLongPress] (even empty) to absorb, like an avatar.
/// - **Desktop / mouse:** pointer-down excludes the pointer from viewport
///   message pan (see [ChatSelectionGestureExclusion]) so chrome press-drag
///   does not drag-select. No competing pan recognizer.
///
/// ## Geometry
///
/// [padding] expands the **painted contour and hit target** only — it does
/// not change [child]'s layout size, so sibling chrome stays aligned.
/// Contour corners use [radius] via [ChatSmoothContour]. Hit targets **wrap**
/// [child] (not an overlay expand) so descendants stay selectable.
///
/// ## Color
///
/// Pass the **label** accent in [color] (e.g. sender name paint). Ink is
/// derived with [inkColorFromLabel] at [labelInkAlpha] — not painted at the
/// opaque label color. Peak held opacity uses factors `1.0` on that ink.
///
/// ## Selection chrome gate
///
/// When mounted under [ChatSelectionStateScope], ink and callbacks are off
/// while [ChatSelectionChromeState.canPerformActions] is false (mobile
/// **message selection** / **text selection**). Pass [enabled]: false to
/// force-disable, or [respectSelectionActions]: false to ignore the scope.
///
/// Does **not** talk to the selection facade. Markdown body tap highlight
/// stays on the selection facade + [ChatSpanFeedbackPainter] path.
class ChatTapHighlight extends StatefulWidget {
  /// Creates a press-lifecycle tap highlight around [child].
  const ChatTapHighlight({
    required this.child,
    super.key,
    this.onTap,
    this.onLongPress,
    this.enabled = true,
    this.respectSelectionActions = true,
    this.color,
    this.padding = defaultPadding,
    this.radius = defaultRadius,
    this.cursor = SystemMouseCursors.click,
  });

  /// Content that receives the highlight plate behind / over its bounds.
  final Widget child;

  /// Invoked on a completed tap when interactive.
  final VoidCallback? onTap;

  /// Invoked on long-press when interactive.
  ///
  /// When non-null, this hit absorbs the press so the viewport does not start
  /// **message selection**. When null on touch, long-press passes through
  /// (Telegram sender-name chrome).
  final VoidCallback? onLongPress;

  /// When false, skips ink and does not invoke [onTap] / [onLongPress].
  final bool enabled;

  /// When true, also requires ambient [ChatSelectionChromeState.canPerformActions].
  final bool respectSelectionActions;

  /// Label / foreground accent (e.g. sender name color). Ink uses
  /// [inkColorFromLabel] — not this color at full opacity.
  final Color? color;

  /// Paint- and hit-only inset around [child] (layout size unchanged).
  final EdgeInsetsGeometry padding;

  /// Contour corner radius in logical pixels.
  final double radius;

  /// Pointer cursor while interactive (desktop / web hover).
  final MouseCursor cursor;

  /// Default paint/hit inset around the label.
  static const EdgeInsets defaultPadding = EdgeInsets.fromLTRB(
    4,
    1.33,
    4,
    1.33,
  );

  /// Default contour corner radius.
  static const double defaultRadius = 6;

  /// Peak ink alpha applied to a label accent via [inkColorFromLabel].
  static const double labelInkAlpha = 0.12;

  /// Derives press-ink color from a label accent (same RGB, [labelInkAlpha]).
  static Color inkColorFromLabel(Color label) =>
      label.withValues(alpha: labelInkAlpha);

  @override
  State<ChatTapHighlight> createState() => _ChatTapHighlightState();
}

class _ChatTapHighlightState extends State<ChatTapHighlight>
    with TickerProviderStateMixin {
  final _childKey = GlobalKey();
  AnimationController? _pressController;
  AnimationController? _releaseController;
  ChatSpanFeedback? _feedback;
  bool _armed = false;
  int _feedbackGen = 0;
  int? _activePointer;
  Offset? _downGlobal;
  double _touchSlop = kTouchSlop;

  bool _isInteractive(BuildContext context) {
    if (!widget.enabled) return false;
    if (!widget.respectSelectionActions) return true;
    final actions = ChatSelectionStateScope.maybeOf(context)?.canPerformActions;
    return actions ?? true;
  }

  @override
  void dispose() {
    _armed = false;
    _activePointer = null;
    _downGlobal = null;
    _clearFeedback(notify: false);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _touchSlop =
        MediaQuery.maybeGestureSettingsOf(context)?.touchSlop ?? kTouchSlop;
    if (_armed && !_isInteractive(context)) {
      _abort();
    }
  }

  @override
  void didUpdateWidget(ChatTapHighlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && oldWidget.enabled) {
      _feedbackGen++;
      _armed = false;
      _clearFeedback();
    }
  }

  void _begin(Offset localOrigin, Size childSize, EdgeInsets pad) {
    if (!mounted) return;
    _clearFeedback(notify: false);

    // Paint contour in child-local space, inflated by [pad] (no layout shift).
    final box = Rect.fromLTRB(
      -pad.left,
      -pad.top,
      childSize.width + pad.right,
      childSize.height + pad.bottom,
    );
    final contour = ChatSmoothContour.buildPath(<Rect>[
      box,
    ], radius: widget.radius);

    final press = AnimationController(
      vsync: this,
      duration: ChatSpanFeedback.pressDuration,
    );
    final release = AnimationController(
      vsync: this,
      duration: ChatSpanFeedback.releaseDuration,
    );
    _pressController = press;
    _releaseController = release;

    final label = widget.color ?? const Color(0xFF007AFF);
    // messageId is unused outside the selection facade; 0 is a sentinel.
    final feedback = ChatSpanFeedback(
      messageId: 0,
      contourPath: contour,
      touchOrigin: localOrigin,
      pressController: press,
      releaseController: release,
      color: ChatTapHighlight.inkColorFromLabel(label),
      baseOpacity: 1,
      rippleOpacity: 1,
    );
    setState(() {
      _feedback = feedback;
      _armed = true;
    });
    press.forward();
  }

  void _release() {
    if (!_armed) return;
    _armed = false;
    _activePointer = null;
    _downGlobal = null;
    final press = _pressController;
    final release = _releaseController;
    if (press == null || release == null || !mounted) return;
    if (release.isAnimating || release.value > 0.0) return;

    final gen = ++_feedbackGen;
    () async {
      if (press.value < 1.0) {
        await press.forward();
      }
      if (!mounted || gen != _feedbackGen || _releaseController != release) {
        return;
      }
      await release.forward();
      if (mounted && gen == _feedbackGen && _releaseController == release) {
        _clearFeedback();
      }
    }();
  }

  void _abort() {
    _feedbackGen++;
    _armed = false;
    _activePointer = null;
    _downGlobal = null;
    _clearFeedback();
  }

  void _clearFeedback({bool notify = true}) {
    if (_pressController case final press?) {
      _pressController = null;
      press.dispose();
    }
    if (_releaseController case final release?) {
      _releaseController = null;
      release.dispose();
    }
    if (_feedback == null) return;
    _feedback = null;
    if (notify && mounted) {
      setState(() {});
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!mounted || !_isInteractive(context)) return;
    // Desktop/mouse: exclude so chrome press does not pan-select.
    // Touch: exclude only when the host owns long-press; null [onLongPress]
    // lets the viewport claim message selection (Telegram name chrome).
    if (_excludesViewportSelection(event)) {
      ChatSelectionGestureExclusion.exclude(event.pointer);
    }
    final box = _childKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final pad = widget.padding.resolve(Directionality.of(context));
    final local = box.globalToLocal(event.position);
    _activePointer = event.pointer;
    _downGlobal = event.position;
    _begin(local, box.size, pad);
  }

  /// Whether this down should keep the viewport from arming selection gestures.
  bool _excludesViewportSelection(PointerDownEvent event) {
    switch (event.kind) {
      case PointerDeviceKind.mouse:
      case PointerDeviceKind.trackpad:
        return true;
      case PointerDeviceKind.touch:
      case PointerDeviceKind.stylus:
      case PointerDeviceKind.invertedStylus:
      case PointerDeviceKind.unknown:
        return widget.onLongPress != null;
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!mounted || !_armed || event.pointer != _activePointer) return;
    final origin = _downGlobal;
    if (origin == null) return;
    // Scrollables rarely deliver [PointerCancel] to a [Listener]; past-slop
    // travel is the reliable cancel signal (list pan / drag). Cache [_touchSlop]
    // in [didChangeDependencies] — do not read [context] here (disposed
    // [Listener] can still see moves after unmount).
    if ((event.position - origin).distance > _touchSlop) {
      _abort();
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!mounted || event.pointer != _activePointer) return;
    ChatSelectionGestureExclusion.take(event.pointer);
    if (_armed) _release();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (!mounted) return;
    if (event.pointer != _activePointer && _activePointer != null) return;
    ChatSelectionGestureExclusion.take(event.pointer);
    if (_armed) _abort();
  }

  @override
  Widget build(BuildContext context) {
    final feedback = _feedback;
    final interactive = _isInteractive(context);
    final pad = widget.padding.resolve(Directionality.of(context));

    // Listener / detectors **wrap** [child] so descendants stay on the hit
    // path (character-range **text selection**). An overlay [SizedBox.expand]
    // sibling would win the Stack hit test and steal those events.
    // [_HitPadding] expands the hit ring without changing layout size; paint
    // uses the same pad in child-local coords (Stack does not clip).
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _HitPadding(
          padding: pad,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerCancel,
            child: MouseRegion(
              cursor: interactive ? widget.cursor : SystemMouseCursors.basic,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: interactive ? widget.onTap : null,
                onLongPress: interactive ? widget.onLongPress : null,
                child: CustomPaint(
                  key: _childKey,
                  foregroundPainter: feedback != null
                      ? ChatSpanFeedbackPainter(
                          feedback: feedback,
                          repaint: feedback.listenable,
                        )
                      : null,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Expands hit-testing by [padding] without changing the child's layout size.
class _HitPadding extends SingleChildRenderObjectWidget {
  const _HitPadding({required this.padding, required super.child});

  final EdgeInsets padding;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHitPadding(padding);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderHitPadding renderObject,
  ) {
    renderObject.padding = padding;
  }
}

class _RenderHitPadding extends RenderProxyBox {
  _RenderHitPadding(this._padding);

  EdgeInsets _padding;
  EdgeInsets get padding => _padding;
  set padding(EdgeInsets value) {
    if (_padding == value) return;
    _padding = value;
    markNeedsPaint();
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final expanded = Rect.fromLTRB(
      -_padding.left,
      -_padding.top,
      size.width + _padding.right,
      size.height + _padding.bottom,
    );
    if (!expanded.contains(position)) {
      return false;
    }
    // Prefer the child (and its descendants) so markdown text selection stays
    // on the path; still register this box so pad-ring presses hit.
    if (child != null) {
      final hitChild = result.addWithPaintOffset(
        offset: Offset.zero,
        position: position,
        hitTest: (r, transformed) => child!.hitTest(r, position: transformed),
      );
      if (hitChild) {
        result.add(BoxHitTestEntry(this, position));
        return true;
      }
    }
    if (size.contains(position) || expanded.contains(position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }
}
