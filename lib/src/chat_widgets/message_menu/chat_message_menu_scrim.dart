import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_theme.dart';
import 'package:flutter/material.dart';

/// Fallback scrim opacity when [ChatMessageMenuThemeData.scrimColor] is null.
///
/// Prefer brightness-aware tokens from
/// [ChatMessageMenuThemeData.fromScheme] (0.08 light / 0.2 dark).
const double kChatMessageMenuScrimOpacity = 0.2;

/// Fade duration for the dim layer.
const Duration kChatMessageMenuScrimDuration = Duration(milliseconds: 320);

/// Full-screen dim with one undimmed hole over the captured message.
///
/// The hole is [hole] outlined by [holeShape], or rounded by
/// [ChatMessageMenuThemeData.holeRadius] when [holeShape] is null, then
/// clipped to [holeClip] and the layer bounds. Everything outside the hole —
/// including row padding, neighbouring rows, and host chrome — is dimmed.
///
/// The hole is visual only. Any pointer down on this layer (scrim or hole)
/// dismisses; the host stacks menu chrome above so actions still receive
/// hits. The overlay stays in the tree until leave animation ends, so the
/// list does not scroll under the snapshot.
class ChatMessageMenuScrim extends StatelessWidget {
  /// Creates a scrim layer.
  const ChatMessageMenuScrim({
    required this.progress,
    required this.onDismiss,
    this.hole,
    this.holeShape,
    this.holeClip,
    super.key,
  });

  /// 0–1 enter/leave progress.
  final double progress;

  /// Any pointer down on this layer dismisses.
  final VoidCallback onDismiss;

  /// Overlay rect of the message left undimmed. Null or empty dims
  /// everything.
  final Rect? hole;

  /// Outline of the hole inside [hole]. Directional shapes resolve against
  /// the ambient [Directionality].
  final ShapeBorder? holeShape;

  /// Overlay rect the hole is clipped to, such as the part of the viewport
  /// not covered by host chrome. Null clips to the layer bounds only.
  final Rect? holeClip;

  @override
  Widget build(BuildContext context) {
    final menuTheme = ChatScrollTheme.menuOf(context);
    final base = menuTheme.scrimColor ?? const Color.fromRGBO(0, 0, 0, 0.2);
    final color = base.withValues(alpha: base.a * progress);
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => onDismiss(),
      child: CustomPaint(
        painter: _ScrimHolePainter(
          color: color,
          hole: hole,
          holeShape: holeShape,
          holeRadius: menuTheme.holeRadius ?? 16,
          holeClip: holeClip,
          textDirection: Directionality.maybeOf(context),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _ScrimHolePainter extends CustomPainter {
  _ScrimHolePainter({
    required this.color,
    required this.hole,
    required this.holeShape,
    required this.holeRadius,
    required this.holeClip,
    required this.textDirection,
  });

  final Color color;
  final Rect? hole;
  final ShapeBorder? holeShape;
  final double holeRadius;
  final Rect? holeClip;
  final TextDirection? textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final paint = Paint()..color = color;
    final clip = switch (holeClip) {
      final holeClip? => bounds.intersect(holeClip),
      null => bounds,
    };
    final hole = this.hole;
    if (hole == null || hole.isEmpty || clip.isEmpty) {
      canvas.drawRect(bounds, paint);
      return;
    }

    final outline = switch (holeShape) {
      final shape? => shape.getOuterPath(hole, textDirection: textDirection),
      null => Path()
        ..addRRect(RRect.fromRectAndRadius(hole, Radius.circular(holeRadius))),
    };
    final visibleHole = Path.combine(
      PathOperation.intersect,
      outline,
      Path()..addRect(clip),
    );
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(bounds),
        visibleHole,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScrimHolePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.hole != hole ||
      oldDelegate.holeShape != holeShape ||
      oldDelegate.holeRadius != holeRadius ||
      oldDelegate.holeClip != holeClip ||
      oldDelegate.textDirection != textDirection;
}
