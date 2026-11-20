import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:viewport_scroll/src/fast_scrollbar_policy.dart';
import 'package:viewport_scroll/src/fast_scrollbar_style.dart';

/// Labels a place in the scrolled content: the section at the scroll
/// offset [offset] (a date, a letter), or null for none there.
typedef FastScrollLabeler = String? Function(double offset);

/// A thumb on the trailing edge of [child] that drags through the whole of
/// its scroll range, and a label beside it naming the section at the
/// offset reached ([labelAt]).
///
/// It reads and moves [controller], the one [child]'s scrollable is on,
/// and knows nothing of what is scrolled: the host says what a place is
/// called. A drag is relative to where the finger went down (a press never
/// moves the content), the thumb's travel spanning the scroll range, the
/// content following each move at once. [policy] sets the thumb's shape,
/// when it and the label show, and the haptics; [style] the colours.
///
/// The thumb and the label take presses only where they are and while
/// they show; everything else reaches [child]. A drag holds the content
/// against the content's own gestures for its length.
class FastScrollbar extends StatefulWidget {
  /// A fast scrollbar over [child], moving [controller].
  const FastScrollbar({
    required this.controller,
    required this.style,
    required this.child,
    this.policy,
    this.labelAt,
    this.labelsChanged,
    this.enabled = true,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  /// Whether the scrollbar writes its diagnostic lines (`[fastscroll]`
  /// prefix): presses, drags, the thumb against the offset, extent changes,
  /// the label's answers, the idle timers. On in debug and profile builds;
  /// nothing is written in release whatever it holds.
  static bool debugLog = !kReleaseMode;

  static void _log(String message) {
    if (kReleaseMode || !debugLog) return;
    debugPrint('[fastscroll] $message');
  }

  /// The controller of [child]'s scrollable; it must have one position.
  final ScrollController controller;

  /// Colours and text from the host's tokens.
  final FastScrollbarStyle style;

  /// The scrolled content.
  final Widget child;

  /// The platform values; null for [FastScrollbarPolicy.forPlatform].
  final FastScrollbarPolicy? policy;

  /// Names the section at a scroll offset; null for a thumb without a
  /// label.
  final FastScrollLabeler? labelAt;

  /// Tells when [labelAt] may answer differently for the same offset (the
  /// data under it landed); null when its answers never change.
  final Listenable? labelsChanged;

  /// Whether the host wants the scrollbar now (enough content, the
  /// surface settled); false hides it and lets every press through.
  final bool enabled;

  /// Insets of the track from the edges of [child] (a header or a bar
  /// laid over the content).
  final EdgeInsets padding;

  @override
  State<FastScrollbar> createState() => _FastScrollbarState();
}

/// A press on the thumb or the label, from down to up.
final class _Press {
  _Press({required this.pixels, required this.y});

  /// The content's offset at the press.
  final double pixels;

  /// The finger's global y at the press.
  final double y;

  /// Whether it became a drag (a move past slop, or a held press).
  bool dragging = false;
}

class _FastScrollbarState extends State<FastScrollbar>
    with TickerProviderStateMixin {
  late final AnimationController _$thumb = AnimationController(vsync: this);
  late final AnimationController _$label = AnimationController(vsync: this);
  late final AnimationController _$shift = AnimationController(vsync: this);
  Timer? _$thumbIdle;
  Timer? _$labelIdle;
  Timer? _$hold;

  // Whether a scroll happened within the idle delays.
  bool _thumbRecent = false;
  bool _labelRecent = false;
  _Press? _press;

  // The label shown (kept while it fades out) and the offset it was taken
  // at, for the direction of the next change.
  String? _label;
  double _labelPixels = 0;
  bool _labelForward = true;
  bool _thumbWanted = false;
  bool _labelWanted = false;
  bool _syncScheduled = false;

  FastScrollbarPolicy get _policy =>
      widget.policy ?? FastScrollbarPolicy.forPlatform();

  ScrollPosition? get _position {
    final controller = widget.controller;
    return controller.positions.length == 1 ? controller.position : null;
  }

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
    widget.labelsChanged?.addListener(_onLabels);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void didUpdateWidget(FastScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
    if (!identical(oldWidget.labelsChanged, widget.labelsChanged)) {
      oldWidget.labelsChanged?.removeListener(_onLabels);
      widget.labelsChanged?.addListener(_onLabels);
    }
    _scheduleSync();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    widget.labelsChanged?.removeListener(_onLabels);
    _$thumbIdle?.cancel();
    _$labelIdle?.cancel();
    _$hold?.cancel();
    _$thumb.dispose();
    _$label.dispose();
    _$shift.dispose();
    super.dispose();
  }

  // --- Activity ---

  void _onScroll() {
    _poke();
    _scheduleSync();
  }

  void _onLabels() => _scheduleSync();

  // A scroll, or a press ending: shows the thumb and the label and starts
  // their idle delays over. A press holds both, so its end starts them.
  void _poke() {
    final policy = _policy;
    _thumbRecent = true;
    _labelRecent = true;
    _$thumbIdle?.cancel();
    _$labelIdle?.cancel();
    if (_press != null) return;
    if (policy.thumbIdleHide case final delay?) {
      _$thumbIdle = Timer(delay, () {
        FastScrollbar._log('thumb idle after ${delay.inMilliseconds} ms');
        _thumbRecent = false;
        _sync();
      });
    }
    _$labelIdle = Timer(policy.labelIdleHide, () {
      FastScrollbar._log(
        'label idle after ${policy.labelIdleHide.inMilliseconds} ms',
      );
      _labelRecent = false;
      _sync();
    });
  }

  // Scroll positions notify during layout too (an extent correcting the
  // offset); state changes then wait for the frame's end.
  void _scheduleSync() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase != SchedulerPhase.persistentCallbacks &&
        phase != SchedulerPhase.midFrameMicrotasks) {
      _sync();
      return;
    }
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      _sync();
    });
  }

  // Brings what shows in line with the content, the press and the host.
  void _sync() {
    if (!mounted) return;
    final policy = _policy;
    final position = _position;
    final dragging = _press?.dragging ?? false;
    final scrolls = position != null && _scrolls(position, policy);
    final thumbWanted =
        widget.enabled &&
        scrolls &&
        (policy.thumbIdleHide == null || _thumbRecent || _press != null);
    final label = position == null || !position.hasPixels
        ? null
        : widget.labelAt?.call(position.pixels);
    if (position != null && position.hasContentDimensions) {
      final range = position.maxScrollExtent - position.minScrollExtent;
      if (range != _loggedRange) {
        FastScrollbar._log(
          'extent: range $_loggedRange -> $range, viewport '
          '${position.hasViewportDimension ? position.viewportDimension : '-'}'
          ', scrolls $scrolls',
        );
        _loggedRange = range;
      }
    }
    if (label != _loggedLabel) {
      FastScrollbar._log(
        'label at ${position?.hasPixels ?? false ? position!.pixels : '-'}: '
        '${label ?? 'none'}',
      );
      _loggedLabel = label;
    }
    final labelWanted =
        thumbWanted && label != null && (_labelRecent || _press != null);
    if (label != null && label != _label) {
      final pixels = position!.pixels;
      if (_label != null && dragging && policy.labelChangeHaptic) {
        unawaited(HapticFeedback.selectionClick());
      }
      _labelForward = pixels >= _labelPixels;
      _labelPixels = pixels;
    }
    if (thumbWanted != _thumbWanted || labelWanted != _labelWanted) {
      FastScrollbar._log(
        'show: thumb $thumbWanted (enabled ${widget.enabled}, scrolls '
        '$scrolls, recent $_thumbRecent, press ${_press != null}), label '
        '$labelWanted (recent $_labelRecent)',
      );
    }
    if (thumbWanted != _thumbWanted) {
      final motion = thumbWanted ? policy.thumbShow : policy.thumbHide;
      unawaited(
        _$thumb.animateTo(
          thumbWanted ? 1 : 0,
          duration: motion.duration,
          curve: motion.curve,
        ),
      );
    }
    if (labelWanted != _labelWanted) {
      final motion = labelWanted ? policy.labelShow : policy.labelHide;
      unawaited(
        _$label.animateTo(
          labelWanted ? 1 : 0,
          duration: motion.duration,
          curve: motion.curve,
        ),
      );
    }
    setState(() {
      _thumbWanted = thumbWanted;
      _labelWanted = labelWanted;
      if (label != null) _label = label;
    });
  }

  double? _loggedRange;
  String? _loggedLabel;

  static bool _scrolls(ScrollPosition position, FastScrollbarPolicy policy) {
    if (!position.hasContentDimensions || !position.hasViewportDimension) {
      return false;
    }
    final range = position.maxScrollExtent - position.minScrollExtent;
    if (range <= 0) return false;
    final viewport = position.viewportDimension;
    return switch (policy.maxViewportFraction) {
      final fraction? => viewport / (viewport + range) < fraction,
      null => true,
    };
  }

  // --- Drag ---

  void _down(DragDownDetails details) {
    final position = _position;
    if (position == null || !position.hasPixels) return;
    // A press stops a fling where it is.
    position.jumpTo(position.pixels);
    _press = _Press(pixels: position.pixels, y: details.globalPosition.dy);
    FastScrollbar._log(
      'down at y ${details.globalPosition.dy}, offset ${position.pixels}',
    );
    if (_policy.holdToDrag case final hold?) {
      _$hold = Timer(hold, _startDrag);
    }
    _poke();
    _sync();
  }

  void _startDrag() {
    final press = _press;
    if (press == null || press.dragging) return;
    _$hold?.cancel();
    press.dragging = true;
    FastScrollbar._log('drag start from offset ${press.pixels}');
    final policy = _policy;
    if (policy.dragStartHaptic) unawaited(HapticFeedback.mediumImpact());
    unawaited(
      _$shift.animateTo(
        1,
        duration: policy.dragShiftIn.duration,
        curve: policy.dragShiftIn.curve,
      ),
    );
    _sync();
  }

  // The drag's start reports where the finger is past slop, with no
  // update of its own; both move the content to the finger.
  void _move(Offset global, double travel) {
    final press = _press;
    final position = _position;
    if (press == null || position == null || travel <= 0) return;
    if (!press.dragging) _startDrag();
    final range = position.maxScrollExtent - position.minScrollExtent;
    final target = press.pixels + (global.dy - press.y) * range / travel;
    final clamped = target
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    FastScrollbar._log(
      'drag to y ${global.dy}: offset $clamped of $range '
      '(${range <= 0 ? 0 : (clamped / range * 100).toStringAsFixed(1)}%), '
      'travel $travel',
    );
    position.jumpTo(clamped);
  }

  void _end() {
    if (_press == null) return;
    FastScrollbar._log(
      'drag end at offset '
      '${_position?.hasPixels ?? false ? _position!.pixels : '-'}',
    );
    _$hold?.cancel();
    _press = null;
    final out = _policy.dragShiftOut;
    unawaited(_$shift.animateTo(0, duration: out.duration, curve: out.curve));
    _poke();
    _sync();
  }

  Widget _grip(Widget child, double travel) => RawGestureDetector(
    behavior: HitTestBehavior.opaque,
    gestures: {
      VerticalDragGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<VerticalDragGestureRecognizer>(
            () => VerticalDragGestureRecognizer(debugOwner: this),
            (recognizer) => recognizer
              ..onlyAcceptDragOnThreshold = true
              ..onDown = _down
              ..onStart = ((details) => _move(details.globalPosition, travel))
              ..onUpdate = ((details) => _move(details.globalPosition, travel))
              ..onEnd = ((_) => _end())
              ..onCancel = _end,
          ),
    },
    child: child,
  );

  // --- Build ---

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          if (notification.depth == 0) _scheduleSync();
          return false;
        },
        child: widget.child,
      ),
      Positioned.fill(
        child: ClipRect(
          child: LayoutBuilder(
            builder: (context, constraints) => AnimatedBuilder(
              animation: Listenable.merge([_$thumb, _$label, _$shift]),
              builder: (context, _) => _overlay(context, constraints.biggest),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _overlay(BuildContext context, Size size) {
    final position = _position;
    final shown = _$thumb.value;
    if (position == null ||
        !position.hasPixels ||
        !position.hasContentDimensions ||
        (shown == 0 && !_thumbWanted)) {
      return const SizedBox.shrink();
    }
    final policy = _policy;
    final padding = widget.padding;
    final extent = policy.thumbExtent;
    final travel =
        size.height - padding.vertical - 2 * policy.trackInset - extent;
    final range = position.maxScrollExtent - position.minScrollExtent;
    final progress = range <= 0
        ? 0.0
        : ((position.pixels - position.minScrollExtent) / range).clamp(
            0.0,
            1.0,
          );
    final top =
        padding.top + policy.trackInset + progress * math.max(0, travel);
    final left =
        policy.mirrorsInRtl && Directionality.of(context) == TextDirection.rtl;
    final takesPresses = _thumbWanted || _press != null;
    final shift = _$shift.value;

    Positioned place(
      String part, {
      required double inset,
      required double top,
      required Widget child,
      double? width,
      double? height,
    }) => left
        ? Positioned(
            key: ValueKey(part),
            left: inset,
            top: top,
            width: width,
            height: height,
            child: child,
          )
        : Positioned(
            key: ValueKey(part),
            right: inset,
            top: top,
            width: width,
            height: height,
            child: child,
          );

    final label = _label;
    final labelShown = _$label.value;
    return Stack(
      children: [
        place(
          'thumb',
          inset: 0,
          top: top,
          width: switch (policy.thumb) {
            FastScrollThumb$Line(:final activeWidth, :final edgeInset) =>
              activeWidth + edgeInset,
            FastScrollThumb$Tab(:final radius, :final centerInset) =>
              radius + centerInset,
          },
          height: extent,
          child: IgnorePointer(
            child: Opacity(
              opacity: shown,
              child: _thumb(policy, extent, shift, left: left),
            ),
          ),
        ),
        if (takesPresses)
          place(
            'grip',
            inset: 0,
            top: top - policy.hitSlop,
            width: policy.hitWidth,
            height: extent + 2 * policy.hitSlop,
            child: _grip(const SizedBox.expand(), travel),
          ),
        if (label != null && (labelShown > 0 || _labelWanted))
          place(
            'label',
            inset: policy.labelGap + policy.dragShift * shift,
            top: top + extent / 2,
            child: FractionalTranslation(
              translation: const Offset(0, -0.5),
              child: Opacity(
                opacity: labelShown,
                child: Transform.scale(
                  scale: lerpDouble(policy.labelScaleFrom, 1, labelShown),
                  alignment: left
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  child: _maybeGrip(
                    _FastScrollLabel(
                      key: const ValueKey('fast-scrollbar-label'),
                      text: label,
                      forward: _labelForward,
                      policy: policy,
                      style: widget.style,
                    ),
                    travel,
                    grips: takesPresses && _labelWanted,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _maybeGrip(Widget child, double travel, {required bool grips}) =>
      grips ? _grip(child, travel) : IgnorePointer(child: child);

  Widget _thumb(
    FastScrollbarPolicy policy,
    double extent,
    double shift, {
    required bool left,
  }) {
    final style = widget.style;
    switch (policy.thumb) {
      case FastScrollThumb$Line(
        :final width,
        :final activeWidth,
        :final edgeInset,
      ):
        final w = lerpDouble(width, activeWidth, shift)!;
        return Align(
          alignment: left ? Alignment.centerLeft : Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.only(
              left: left ? edgeInset : 0,
              right: left ? 0 : edgeInset,
            ),
            child: Container(
              key: const ValueKey('fast-scrollbar-thumb'),
              width: w,
              height: extent,
              decoration: ShapeDecoration(
                color: style.thumbColor,
                shape: const StadiumBorder(),
              ),
            ),
          ),
        );
      case final FastScrollThumb$Tab tab:
        final disc = Size.square(2 * tab.radius);
        final chevrons = CustomPaint(
          size: disc,
          painter: _ChevronsPainter(
            tab: tab,
            color: style.thumbIconColor,
            spread: shift,
            left: left,
          ),
        );
        final surface = switch (style.surfaceBuilder) {
          final build? => build(context, const CircleBorder(), chevrons),
          null => DecoratedBox(
            decoration: ShapeDecoration(
              color: style.thumbColor,
              shape: const CircleBorder(),
            ),
            child: chevrons,
          ),
        };
        return SizedBox(
          key: const ValueKey('fast-scrollbar-thumb'),
          width: tab.centerInset + tab.radius,
          height: extent,
          child: OverflowBox(
            minWidth: disc.width,
            maxWidth: disc.width,
            minHeight: disc.height,
            maxHeight: disc.height,
            alignment: left ? Alignment.centerRight : Alignment.centerLeft,
            child: surface,
          ),
        );
    }
  }
}

/// The tab thumb's chevrons: one pointing up above the disc's centre, one
/// down below it, [spread] (0 to 1) moving them apart.
final class _ChevronsPainter extends CustomPainter {
  _ChevronsPainter({
    required this.tab,
    required this.color,
    required this.spread,
    required this.left,
  });

  final FastScrollThumb$Tab tab;
  final Color color;
  final double spread;
  final bool left;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    // The tips sit chevronInset in from the edge the disc's centre is
    // centerInset in from.
    final dx = tab.chevronInset - tab.centerInset;
    final x = left ? center.dx + dx : center.dx - dx;
    final offset = tab.chevronOffset + tab.chevronSpread * spread;
    final half = tab.chevron.width / 2;
    final h = tab.chevron.height;
    final paint = Paint()..color = color;
    final up = center.dy - offset;
    final down = center.dy + offset;
    canvas
      ..drawPath(
        Path()
          ..moveTo(x, up)
          ..lineTo(x + half, up + h)
          ..lineTo(x - half, up + h)
          ..close(),
        paint,
      )
      ..drawPath(
        Path()
          ..moveTo(x, down)
          ..lineTo(x + half, down - h)
          ..lineTo(x - half, down - h)
          ..close(),
        paint,
      );
  }

  @override
  bool shouldRepaint(_ChevronsPainter old) =>
      old.tab != tab ||
      old.color != color ||
      old.spread != spread ||
      old.left != left;
}

/// The label: its text on the policy's surface, rolling from one text to
/// the next. When both texts end in the same word ("March 2024" to "April
/// 2024") only what comes before it rolls.
class _FastScrollLabel extends StatefulWidget {
  const _FastScrollLabel({
    required this.text,
    required this.forward,
    required this.policy,
    required this.style,
    super.key,
  });

  final String text;

  // Whether the content moved forward (down the list) to this text: the old
  // one leaves upward and the new one comes from below.
  final bool forward;
  final FastScrollbarPolicy policy;
  final FastScrollbarStyle style;

  @override
  State<_FastScrollLabel> createState() => _FastScrollLabelState();
}

class _FastScrollLabelState extends State<_FastScrollLabel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _$roll = AnimationController(
    vsync: this,
    value: 1,
  );
  String? _old;

  @override
  void didUpdateWidget(_FastScrollLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text == widget.text) return;
    _old = oldWidget.text;
    final motion = widget.policy.labelChange;
    _$roll.value = 0;
    unawaited(
      _$roll.animateTo(1, duration: motion.duration, curve: motion.curve),
    );
  }

  @override
  void dispose() {
    _$roll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final policy = widget.policy;
    final style = widget.style;
    final textStyle = style.labelTextStyle;
    final scaler =
        MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling;
    final direction = Directionality.of(context);
    Size measure(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: textStyle),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final size = painter.size;
      painter.dispose();
      return size;
    }

    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(policy.labelRadius),
    );
    final padding = policy.labelPadding;
    final text = widget.text;
    final textHeight = measure(text).height;
    final height = policy.labelHeight ?? textHeight + padding.vertical;
    final content = AnimatedBuilder(
      animation: _$roll,
      builder: (context, _) {
        final t = _$roll.value;
        final old = _old;
        if (old == null || t >= 1) {
          return _box(Text(text, style: textStyle, maxLines: 1), padding);
        }
        final (oldHead, newHead, tail) = _split(old, text);
        final rolling = SizedBox(
          width: lerpDouble(measure(oldHead).width, measure(newHead).width, t),
          height: textHeight,
          child: ClipRect(
            child: Stack(
              clipBehavior: Clip.none,
              alignment: AlignmentDirectional.centerEnd,
              children: [
                _rolled(oldHead, textStyle, out: true, t: t),
                _rolled(newHead, textStyle, out: false, t: t),
              ],
            ),
          ),
        );
        return _box(
          tail == null
              ? rolling
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    rolling,
                    SizedBox(width: measure(' ').width),
                    Text(tail, style: textStyle, maxLines: 1),
                  ],
                ),
          padding,
        );
      },
    );
    final sized = SizedBox(height: height, child: content);
    return switch (style.surfaceBuilder) {
      final build? => build(context, shape, sized),
      null => DecoratedBox(
        decoration: ShapeDecoration(color: style.labelColor, shape: shape),
        child: sized,
      ),
    };
  }

  Widget _box(Widget child, EdgeInsets padding) => Padding(
    padding: EdgeInsets.only(left: padding.left, right: padding.right),
    child: Center(widthFactor: 1, child: child),
  );

  Widget _rolled(
    String text,
    TextStyle style, {
    required bool out,
    required double t,
  }) {
    final slide = widget.policy.labelChangeSlide;
    final up = widget.forward ? -1.0 : 1.0;
    final dy = out ? up * slide * t : -up * slide * (1 - t);
    return Transform.translate(
      offset: Offset(0, dy),
      child: Opacity(
        opacity: out ? 1 - t : t,
        child: Text(text, style: style, maxLines: 1, softWrap: false),
      ),
    );
  }

  // The parts of [old] and [now] that roll, and the last word they share
  // (which stays), if they share one.
  static (String, String, String?) _split(String old, String now) {
    final a = old.lastIndexOf(' ');
    final b = now.lastIndexOf(' ');
    if (a > 0 && b > 0 && old.substring(a + 1) == now.substring(b + 1)) {
      return (old.substring(0, a), now.substring(0, b), now.substring(b + 1));
    }
    return (old, now, null);
  }
}
