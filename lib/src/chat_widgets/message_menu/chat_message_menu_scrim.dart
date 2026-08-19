import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_theme.dart';
import 'package:flutter/material.dart';

/// Target scrim opacity.
const double kChatMessageMenuScrimOpacity = 0.2;

/// Fade duration for the dim layer.
const Duration kChatMessageMenuScrimDuration = Duration(milliseconds: 320);

/// Full-screen dim with an undimmed hole over the captured slot rect.
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
    super.key,
  });

  /// 0–1 enter/leave progress.
  final double progress;

  /// Any pointer down on this layer dismisses.
  final VoidCallback onDismiss;

  /// Overlay rect of the message left undimmed.
  final Rect? hole;

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
          holeRadius: menuTheme.holeRadius ?? 16,
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
    required this.holeRadius,
  });

  final Color color;
  final Rect? hole;
  final double holeRadius;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    if (hole == null || hole!.isEmpty) {
      canvas.drawRect(bounds, Paint()..color = color);
      return;
    }

    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(bounds)
      ..addRRect(RRect.fromRectAndRadius(hole!, Radius.circular(holeRadius)));
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _ScrimHolePainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.hole != hole ||
      oldDelegate.holeRadius != holeRadius;
}
