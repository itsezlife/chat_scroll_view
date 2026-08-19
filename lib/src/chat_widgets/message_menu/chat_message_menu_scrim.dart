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
    final opacity = (kChatMessageMenuScrimOpacity * progress).clamp(0.0, 1.0);
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => onDismiss(),
      child: CustomPaint(
        painter: _ScrimHolePainter(
          color: Color.fromRGBO(0, 0, 0, opacity),
          hole: hole,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _ScrimHolePainter extends CustomPainter {
  _ScrimHolePainter({required this.color, required this.hole});

  final Color color;
  final Rect? hole;

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
      ..addRRect(RRect.fromRectAndRadius(hole!, const Radius.circular(16)));
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _ScrimHolePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.hole != hole;
}
