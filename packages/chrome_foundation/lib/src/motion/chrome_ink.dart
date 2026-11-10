import 'dart:math' as math;

import 'package:chrome_foundation/src/motion/chrome_motion_scope.dart';
import 'package:chrome_foundation/src/motion/pointer_menu_motion.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// The **press feedback** of a chrome button or menu row, one per platform
/// family.
enum ChromeInkKind {
  /// Android: a ripple grows from the touch over 225 ms (fast out, slow in),
  /// its colour fading in over the first 75 ms, and fades over 150 ms once
  /// the press ends.
  ripple,

  /// iOS: the highlight fills the target at once while pressed and fades
  /// over 300 ms once the press ends.
  highlight,

  /// A desktop: the hover fill while the mouse is over the target, and a
  /// ripple from the press that grows over 650 ms (ease out quint) and fades
  /// over 200 ms once the press ends.
  pointer;

  /// The kind of [platform]'s family.
  static ChromeInkKind forPlatform(TargetPlatform platform) =>
      switch (platform) {
        TargetPlatform.macOS ||
        TargetPlatform.windows ||
        TargetPlatform.linux => ChromeInkKind.pointer,
        TargetPlatform.iOS => ChromeInkKind.highlight,
        TargetPlatform.android ||
        TargetPlatform.fuchsia => ChromeInkKind.ripple,
      };
}

/// The timings of [ChromeInk]. Literal: feedback that keeps pace with the
/// finger is not slowed by a speed, only removed by an instant one.
abstract final class ChromeInkTiming {
  /// How long an Android ripple takes to grow.
  static const Duration rippleGrow = Duration(milliseconds: 225);

  /// How long an Android ripple's colour takes to come in.
  static const Duration rippleIn = Duration(milliseconds: 75);

  /// How long an Android ripple takes to fade once the press ends.
  static const Duration rippleFade = Duration(milliseconds: 150);

  /// The curve an Android ripple grows on (fast out, slow in).
  static const Curve rippleCurve = Cubic(0.4, 0, 0.2, 1);

  /// How long an iOS highlight takes to fade once the press ends.
  static const Duration highlightFade = Duration(milliseconds: 300);
}

/// A target that answers a press with the platform's [ChromeInkKind]
/// feedback, drawn over [child] inside [borderRadius] (or a circle of
/// [circleRadius] around its centre), and calls [onTap].
///
/// [color] is the ripple's or the highlight's colour; [hoverColor], when
/// given, fills the target while a mouse is over it (only for
/// [ChromeInkKind.pointer]). A null [onTap] draws nothing and takes no
/// press. Under an instant motion speed nothing ripples: the target shows the
/// highlight while pressed.
class ChromeInk extends StatefulWidget {
  /// A pressable [child].
  const ChromeInk({
    required this.child,
    required this.color,
    required this.onTap,
    this.kind,
    this.hoverColor,
    this.borderRadius = BorderRadius.zero,
    this.circleRadius,
    super.key,
  });

  /// What is pressed.
  final Widget child;

  /// The colour of the ripple or the highlight.
  final Color color;

  /// The fill under a hovering mouse, or null for none.
  final Color? hoverColor;

  /// Called on a tap; null disables the target.
  final VoidCallback? onTap;

  /// The feedback, or null for the running platform's.
  final ChromeInkKind? kind;

  /// The corners the feedback is clipped to.
  final BorderRadiusGeometry borderRadius;

  /// Draw the feedback in a circle of this radius around the centre instead
  /// of the box.
  final double? circleRadius;

  @override
  State<ChromeInk> createState() => _ChromeInkState();
}

class _ChromeInkState extends State<ChromeInk> with TickerProviderStateMixin {
  // How far the ripple has grown, 0 to 1.
  late final AnimationController _grow = AnimationController(vsync: this);
  // The ripple's or the highlight's alpha, 0 to 1.
  late final AnimationController _alpha = AnimationController(vsync: this);
  Offset _origin = Offset.zero;
  var _hovered = false;
  var _pressed = false;

  ChromeInkKind get _kind =>
      widget.kind ?? ChromeInkKind.forPlatform(defaultTargetPlatform);

  bool get _instant =>
      (ChromeMotionScope.maybeOf(context) ?? ChromeMotionData.standard)
          .speed
          .isInstant;

  @override
  void dispose() {
    _grow.dispose();
    _alpha.dispose();
    super.dispose();
  }

  void _down(PointerDownEvent event) {
    if (widget.onTap == null) return;
    _pressed = true;
    setState(() => _origin = event.localPosition);
    if (_instant) {
      _grow.value = 1;
      _alpha.value = 1;
      return;
    }
    switch (_kind) {
      case ChromeInkKind.ripple:
        _grow
          ..duration = ChromeInkTiming.rippleGrow
          ..forward(from: 0).ignore();
        _alpha
          ..duration = ChromeInkTiming.rippleIn
          ..forward(from: 0).ignore();
      case ChromeInkKind.pointer:
        _grow
          ..duration = PointerMenuTiming.rippleGrow
          ..forward(from: 0).ignore();
        _alpha.value = 1;
      case ChromeInkKind.highlight:
        _grow.value = 1;
        _alpha.value = 1;
    }
  }

  void _up(PointerEvent _) {
    if (!_pressed) return;
    _pressed = false;
    if (_instant) {
      _alpha.value = 0;
      return;
    }
    _alpha.duration = switch (_kind) {
      ChromeInkKind.ripple => ChromeInkTiming.rippleFade,
      ChromeInkKind.pointer => PointerMenuTiming.rippleFade,
      ChromeInkKind.highlight => ChromeInkTiming.highlightFade,
    };
    _alpha.reverse().ignore();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final hover = _kind == ChromeInkKind.pointer ? widget.hoverColor : null;
    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (event) {
        if (hover != null && event.kind == PointerDeviceKind.mouse) {
          setState(() => _hovered = true);
        }
      },
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      child: Listener(
        onPointerDown: _down,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: CustomPaint(
            foregroundPainter: _InkPainter(
              grow: _grow,
              alpha: _alpha,
              kind: _kind,
              origin: _origin,
              color: widget.color,
              hover: enabled && _hovered ? hover : null,
              radius: widget.borderRadius.resolve(
                Directionality.maybeOf(context),
              ),
              circleRadius: widget.circleRadius,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _InkPainter extends CustomPainter {
  _InkPainter({
    required this.grow,
    required this.alpha,
    required this.kind,
    required this.origin,
    required this.color,
    required this.hover,
    required this.radius,
    required this.circleRadius,
  }) : super(repaint: Listenable.merge([grow, alpha]));

  final Animation<double> grow;
  final Animation<double> alpha;
  final ChromeInkKind kind;
  final Offset origin;
  final Color color;
  final Color? hover;
  final BorderRadius radius;
  final double? circleRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final box = Offset.zero & size;
    final clip = switch (circleRadius) {
      final r? =>
        Path()..addOval(Rect.fromCircle(center: box.center, radius: r)),
      null => Path()..addRRect(radius.toRRect(box)),
    };
    canvas
      ..save()
      ..clipPath(clip);
    if (hover case final fill?) canvas.drawPaint(Paint()..color = fill);
    final a = alpha.value;
    if (a > 0) {
      final paint = Paint()..color = color.withValues(alpha: color.a * a);
      switch (kind) {
        case ChromeInkKind.highlight:
          canvas.drawPaint(paint);
        case ChromeInkKind.ripple || ChromeInkKind.pointer:
          final reach = _farthest(box, origin);
          final t = kind == ChromeInkKind.ripple
              ? ChromeInkTiming.rippleCurve.transform(grow.value)
              : Curves.easeOutQuint.transform(grow.value);
          canvas.drawCircle(origin, reach * t, paint);
      }
    }
    canvas.restore();
  }

  static double _farthest(Rect box, Offset from) => [
    box.topLeft,
    box.topRight,
    box.bottomLeft,
    box.bottomRight,
  ].map((corner) => (corner - from).distance).reduce(math.max);

  @override
  bool shouldRepaint(_InkPainter oldDelegate) =>
      oldDelegate.kind != kind ||
      oldDelegate.origin != origin ||
      oldDelegate.color != color ||
      oldDelegate.hover != hover ||
      oldDelegate.radius != radius ||
      oldDelegate.circleRadius != circleRadius;
}
