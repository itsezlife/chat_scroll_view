import 'package:chat_chrome/src/glass/glass_backdrop.dart';
import 'package:chat_chrome/src/glass/glass_source.dart';
import 'package:chat_chrome/src/glass/telegram_glass_style.dart';
import 'package:flutter/material.dart';

/// Floating chrome shell with Telegram-style liquid glass.
///
/// The backdrop is a [GlassBackdrop]: under a [GlassSourceScope] it samples
/// the scope's [GlassSource], elsewhere it filters the scene. Hosts must keep
/// [ChatContentBottomFade] **under** this island with an island-shaped
/// cutout, or outside the [GlassSource], so the wash is not sampled into the
/// glass.
///
/// ## Route motion
///
/// Without a [GlassSourceScope], while the enclosing [ModalRoute] moves —
/// pushed, popped, dragged by a back gesture, or shifted by a route
/// transitioning above it — the surface paints [TelegramGlassStyle.fill] flat
/// instead of filtering the backdrop. A backdrop filter re-reads and
/// re-filters everything under it on each frame it moves, which costs several
/// frame budgets per frame on mobile GPUs. The glass returns once the route
/// settles. A sampled backdrop stays on throughout.
class TelegramGlass extends StatefulWidget {
  /// Creates a glass surface around [child].
  const TelegramGlass({required this.style, required this.child, super.key});

  /// Material tokens (radius, tint, strokes, liquid params).
  final TelegramGlassStyle style;

  /// Content drawn above the glass. Sizes the surface.
  final Widget child;

  @override
  State<TelegramGlass> createState() => _TelegramGlassState();
}

class _TelegramGlassState extends State<TelegramGlass> {
  Animation<double>? _routeAnimation;
  Animation<double>? _coveringAnimation;

  /// Whether the enclosing route is at rest, so the backdrop can be filtered.
  bool _routeSettled = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    _follow(route?.animation, route?.secondaryAnimation);
  }

  @override
  void dispose() {
    _follow(null, null);
    super.dispose();
  }

  void _follow(Animation<double>? animation, Animation<double>? covering) {
    if (identical(animation, _routeAnimation) &&
        identical(covering, _coveringAnimation)) {
      return;
    }
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _coveringAnimation?.removeStatusListener(_onRouteStatus);
    _routeAnimation = animation?..addStatusListener(_onRouteStatus);
    _coveringAnimation = covering?..addStatusListener(_onRouteStatus);
    _routeSettled = _settled();
  }

  bool _settled() {
    final entered = _routeAnimation?.isCompleted ?? true;
    final covering = _coveringAnimation?.status ?? AnimationStatus.dismissed;
    return entered && !covering.isAnimating;
  }

  void _onRouteStatus(AnimationStatus _) {
    final settled = _settled();
    if (settled == _routeSettled || !mounted) return;
    setState(() => _routeSettled = settled);
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final radius = BorderRadius.circular(style.cornerRadius);
    final shadow = style.shadowColor.a > 0
        ? <BoxShadow>[
            BoxShadow(
              color: style.shadowColor,
              blurRadius: style.shadowBlur,
              offset: style.shadowOffset,
            ),
          ]
        : const <BoxShadow>[];
    final glassOn = _routeSettled || GlassBackdrop.capturesAt(context);

    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: shadow),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: glassOn
                  ? GlassBackdrop(style: style)
                  : ColoredBox(color: style.fill),
            ),
            Positioned.fill(
              child: CustomPaint(painter: _GlassStrokePainter(style: style)),
            ),
            widget.child,
          ],
        ),
      ),
    );
  }
}

/// Dual top/bottom stroke matching Android glass edge chrome.
class _GlassStrokePainter extends CustomPainter {
  _GlassStrokePainter({required this.style});

  final TelegramGlassStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final radius = style.cornerRadius;
    final rect = Offset.zero & size;

    _paintStroke(
      canvas: canvas,
      rect: rect,
      radius: radius,
      strokeWidth: style.strokeWidthTop,
      color: style.strokeTop,
      isTop: true,
    );
    _paintStroke(
      canvas: canvas,
      rect: rect,
      radius: radius,
      strokeWidth: style.strokeWidthBottom,
      color: style.strokeBottom,
      isTop: false,
    );
  }

  void _paintStroke({
    required Canvas canvas,
    required Rect rect,
    required double radius,
    required double strokeWidth,
    required Color color,
    required bool isTop,
  }) {
    if (strokeWidth <= 0 || color.a == 0) return;
    final half = strokeWidth / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..isAntiAlias = true;

    canvas.save();
    if (isTop) {
      canvas.clipRect(
        Rect.fromLTRB(
          rect.left,
          rect.top,
          rect.right,
          (rect.top + radius * 2).clamp(rect.top, rect.bottom),
        ),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            rect.left - half,
            rect.top + half,
            rect.right + half,
            rect.bottom + half,
          ),
          Radius.circular(radius),
        ),
        paint,
      );
    } else {
      canvas.clipRect(
        Rect.fromLTRB(
          rect.left,
          (rect.bottom - radius * 2).clamp(rect.top, rect.bottom),
          rect.right,
          rect.bottom,
        ),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            rect.left - half,
            rect.top - half,
            rect.right + half,
            rect.bottom - half,
          ),
          Radius.circular(radius),
        ),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GlassStrokePainter oldDelegate) =>
      oldDelegate.style != style;
}
