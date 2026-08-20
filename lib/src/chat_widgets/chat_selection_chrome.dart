import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_theme.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_selection_theme.dart';
import 'package:flutter/material.dart';

/// Snapshot handed to a [ChatSelectionChromeBuilder] each animation frame.
@immutable
final class ChatSelectionChromeState {
  /// Creates a chrome snapshot for message [id].
  const ChatSelectionChromeState({
    required this.id,
    required this.modeProgress,
    required this.selectProgress,
    required this.isSelectionMode,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  /// Message id this row represents.
  final int id;

  /// 0 → selection mode closed, 1 → fully open. Animates on enter / exit.
  final double modeProgress;

  /// 0 → not selected, 1 → selected.
  ///
  /// Frozen at its last value while [isSelectionMode] is false so `clear()`
  /// and last-item toggle do not play an unselect animation — the check
  /// rides the mode collapse instead.
  final double selectProgress;

  /// Live controller flag (not frozen).
  final bool isSelectionMode;

  /// Live controller flag (not frozen). Prefer [selectProgress] for paint.
  final bool isSelected;

  /// Host tap handler (toggle while in selection mode).
  final VoidCallback onTap;

  /// Host long-press handler (enter selection).
  final VoidCallback onLongPress;

  /// Combined overlay strength in 0..1 — fade a row tint with both axes.
  double get overlayProgress => modeProgress * selectProgress;
}

/// Builds selection chrome around the already-built message [child].
///
/// Pass a stable tear-off. Use [ChatSelectionChromeState.selectProgress] /
/// [ChatSelectionChromeState.overlayProgress] for paint so freeze-on-exit
/// works; [ChatSelectionChromeState.isSelected] is the live set and drops
/// immediately on `ChatSelectionController.clear`.
typedef ChatSelectionChromeBuilder =
    Widget Function(
      BuildContext context,
      ChatSelectionChromeState state,
      Widget child,
    );

/// Bundled checkbox + row-tint chrome. Restyle via [ChatSelectionThemeData].
///
/// The checkbox slides in from off-start behind a [ClipRect]. A start-side
/// spacer opens in sync so start-aligned bodies shift while end-aligned bodies
/// stay on the trailing edge (unless squeezed by the check).
///
/// The selected-row tint is painted **outside** that [ClipRect]. Clipping the
/// tint to the row box was cutting its anti-aliased edges and leaving a
/// hairline of the chat background between abutting selected rows.
class DefaultSelectionChrome extends StatelessWidget {
  /// Wraps [child] with the bundled selection visuals for [state].
  const DefaultSelectionChrome({
    required this.state,
    required this.child,
    super.key,
  });

  /// Stable default for [ChatScrollView.selectionChromeBuilder].
  static Widget wrap(
    BuildContext context,
    ChatSelectionChromeState state,
    Widget child,
  ) => DefaultSelectionChrome(state: state, child: child);

  /// Animated selection snapshot from [SelectableMessage].
  final ChatSelectionChromeState state;

  /// Message body — built once by the host and passed through [AnimatedBuilder].
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme =
        ChatScrollTheme.resolve(context).selection ??
        ChatSelectionThemeData.resolve(context);
    final scheme = Theme.of(context).colorScheme;
    final m = state.modeProgress.clamp(0.0, 1.0);
    final s = state.selectProgress.clamp(0.0, 1.0);
    final accent = theme.checkAccent ?? scheme.primary;
    final overlay = state.overlayProgress.clamp(0.0, 1.0);
    final tint = theme.selectedTint ?? accent;

    if (m == 0.0 && overlay == 0.0) return child;

    final slot = theme.slotWidth;
    final layout = ChatScrollTheme.messageOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final fits = layout.selectionGutterFits(
          viewportWidth: constraints.maxWidth,
          slotWidth: slot,
        );
        final t = fits ? m : 0.0;
        if (t == 0.0 && overlay == 0.0) return child;

        // Tint outside ClipRect; clip only the sliding check.
        return Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            if (overlay > 0.0)
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    key: const ValueKey<String>('chatSelectionTint'),
                    color: tint.withValues(alpha: 0.13 * overlay),
                  ),
                ),
              ),
            ClipRect(
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      SizedBox(width: slot * t),
                      Expanded(child: child),
                    ],
                  ),
                  if (t > 0.0)
                    Positioned.directional(
                      textDirection: Directionality.of(context),
                      start: slot * (t - 1.0),
                      bottom: 6,
                      width: slot,
                      child: IgnorePointer(
                        child: Center(
                          child: CustomPaint(
                            key: const ValueKey<String>('chatSelectionCheck'),
                            size: Size.square(theme.checkSize),
                            painter: _CheckPainter(
                              select: s,
                              accent: accent,
                              ring: theme.checkRing,
                              checkmark: theme.checkmark,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter({
    required this.select,
    required this.accent,
    required this.ring,
    required this.checkmark,
  });

  final double select;
  final Color accent;
  final Color ring;
  final Color checkmark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 1.5;

    // Ring — lerps from neutral grey to the accent as the message is selected.
    final ringColor = Color.lerp(ring, accent, select)!;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ringColor,
    );

    if (select <= 0.0) return;

    // Filled disc.
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = accent.withValues(alpha: accent.a * select),
    );

    // Checkmark — pops in with a slight overshoot.
    final scale = Curves.easeOutBack.transform(select);
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..scale(scale);
    final tick = Path()
      ..moveTo(-4.5, 0.5)
      ..lineTo(-1.5, 3.7)
      ..lineTo(5, -3.5);
    canvas
      ..drawPath(
        tick,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = checkmark,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(_CheckPainter old) =>
      old.select != select ||
      old.accent != accent ||
      old.ring != ring ||
      old.checkmark != checkmark;
}
