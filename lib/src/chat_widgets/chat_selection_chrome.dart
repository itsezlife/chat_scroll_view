import 'dart:math' as math;

import 'package:chat_scroll_view/src/chat_scroll/chat_selection_allowed.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_selection_policy.dart';
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
    required this.showsCheck,
    required this.onTap,
    required this.onLongPress,
    this.policy = const ChatSelectionPolicy.mobile(),
    this.canPerformActions = true,
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

  /// Whether bundled chrome should paint the check control.
  ///
  /// False for [ChatSelectionAllowed.gutterOnly]: the mode gutter still
  /// opens so the body shifts, but the circle is omitted.
  final bool showsCheck;

  /// Host tap handler (toggle while in selection mode).
  final VoidCallback onTap;

  /// Host long-press handler (enter selection).
  final VoidCallback onLongPress;

  /// Active selection policy governing this row's selection behavior.
  final ChatSelectionPolicy policy;

  /// Whether host chrome actions (profile open, media open, sender name) may
  /// run. When `false` under mobile **selection policy**, suppress those
  /// actions so row toggles / **text selection** own the surface. Desktop
  /// keeps this `true`. Engine markdown **tap highlight** / inline hits use
  /// the selection facade separately ([ChatSelectionController.allowsInlineTapHighlight]).
  final bool canPerformActions;

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
/// Adapts to [ChatSelectionChromeState.policy]:
/// - Under mobile policy: opens a start-side gutter and slides the checkbox in
///   behind a [ClipRect] while shifting the message body.
/// - Under desktop policy: leaves the message body stationary and fades/scales
///   the checkbox in place at the trailing edge.
///
/// The selected-row tint is painted **outside** that [ClipRect]. Clipping the
/// tint to the row box was cutting its anti-aliased edges and leaving a
/// hairline of the chat background between abutting selected rows.
class DefaultSelectionChrome extends StatelessWidget {
  /// Wraps [child] with the bundled selection visuals for [state].
  const DefaultSelectionChrome({
    required this.state,
    required this.child,
    this.forceDesktop,
    super.key,
  });

  /// Explicit mobile variant (shifts message body into a start-side gutter).
  const DefaultSelectionChrome.mobile({
    required this.state,
    required this.child,
    super.key,
  }) : forceDesktop = false;

  /// Explicit desktop variant (leaves message body stationary, trailing check).
  const DefaultSelectionChrome.desktop({
    required this.state,
    required this.child,
    super.key,
  }) : forceDesktop = true;

  /// Stable default for [ChatScrollView.selectionChromeBuilder].
  ///
  /// Adapts automatically to [ChatSelectionChromeState.policy].
  static Widget wrap(
    BuildContext context,
    ChatSelectionChromeState state,
    Widget child,
  ) => DefaultSelectionChrome(state: state, child: child);

  /// Animated selection snapshot from [SelectableMessage].
  final ChatSelectionChromeState state;

  /// Message body — built once by the host and passed through [AnimatedBuilder].
  final Widget child;

  /// Optional override to pin desktop or mobile chrome styling regardless of
  /// [ChatSelectionChromeState.policy].
  final bool? forceDesktop;

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

    final isDesktop =
        forceDesktop ?? state.policy.positionsSelectionCheckAtTrailingEdge;

    if (isDesktop) {
      final layout = ChatScrollTheme.messageOf(context);
      return LayoutBuilder(
        builder: (context, constraints) {
          final rowWidth =
              constraints.maxWidth.isFinite ? constraints.maxWidth : null;
          final endSlack = constraints.maxWidth.isFinite
              ? layout.endSlack(constraints.maxWidth)
              : 0.0;
          final checkEnd = math.max(
            theme.checkTrailingMargin,
            endSlack - theme.checkSize - theme.checkTrailingMargin,
          );

          return Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              SizedBox(
                width: rowWidth,
                child: child,
              ),
              if (m > 0.0)
                Positioned.directional(
                  textDirection: Directionality.of(context),
                  end: checkEnd,
                  bottom: 6,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: m,
                      child: state.showsCheck
                          ? CustomPaint(
                              key: const ValueKey<String>(
                                'chatSelectionCheck',
                              ),
                              size: Size.square(theme.checkSize),
                              painter: _CheckPainter(
                                select: s,
                                accent: accent,
                                ring: theme.checkRing,
                                checkmark: theme.checkmark,
                              ),
                            )
                          : SizedBox.square(dimension: theme.checkSize),
                    ),
                  ),
                ),
            ],
          );
        },
      );
    }

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
                          child: state.showsCheck
                              ? CustomPaint(
                                  key: const ValueKey<String>(
                                    'chatSelectionCheck',
                                  ),
                                  size: Size.square(theme.checkSize),
                                  painter: _CheckPainter(
                                    select: s,
                                    accent: accent,
                                    ring: theme.checkRing,
                                    checkmark: theme.checkmark,
                                  ),
                                )
                              : SizedBox.square(dimension: theme.checkSize),
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
