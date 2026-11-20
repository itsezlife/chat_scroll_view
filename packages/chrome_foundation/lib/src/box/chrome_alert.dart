import 'dart:math' as math;

import 'package:chrome_foundation/src/box/chrome_box_layer.dart';
import 'package:chrome_foundation/src/motion/chrome_ink.dart';
import 'package:chrome_foundation/src/motion/chrome_motion.dart';
import 'package:chrome_foundation/src/motion/chrome_motion_scope.dart';
import 'package:chrome_foundation/src/sheet/chrome_sheet_route.dart';
import 'package:chrome_foundation/src/theme/chrome_theme_scope.dart';
import 'package:chrome_foundation/src/theme/chrome_typography.dart';
import 'package:flutter/widgets.dart';

/// The chrome's **alert**: a bold [title], an optional [message] and two
/// text actions at the end, the confirming one in the palette's
/// destructive colour when [destructive], on the palette's surface.
///
/// Laid out as a messenger's alert: 24 from the sides, the title (20 bold)
/// 19 from the top, the message (16) 20 above the actions, the actions
/// (16 bold, 40 tall, 12 inside) in a row 8 from the edges; as wide as the
/// screen less 48, at most [maxWidth].
class ChromeAlert extends StatelessWidget {
  /// An alert asking [title].
  const ChromeAlert({
    required this.title,
    required this.confirm,
    required this.cancel,
    required this.onAnswer,
    this.message,
    this.destructive = true,
    super.key,
  });

  /// The widest an alert grows.
  static const double maxWidth = 356;

  /// The dim behind it.
  static const Color barrier = Color(0x66000000);

  /// Shows an alert over [context]'s navigator and completes with the
  /// answer: true when confirmed, false when cancelled, null when dismissed
  /// (a tap outside, back).
  static Future<bool?> show(
    BuildContext context, {
    required String title,
    required String confirm,
    required String cancel,
    String? message,
    bool destructive = true,
  }) => ChromeBoxLayer.open<bool>(
    context,
    barrierColor: barrier,
    barrierLabel: cancel,
    transitionDuration: ChromeMotionScope.of(
      context,
    ).specOf(MotionRole.popupShow).duration,
    builder: (context) => ChromeTextRoot(
      child: ChromeAlert(
        title: title,
        message: message,
        confirm: confirm,
        cancel: cancel,
        destructive: destructive,
        onAnswer: (answer) => Navigator.of(context).pop(answer),
      ),
    ),
  );

  /// The question.
  final String title;

  /// The line under it; null for none.
  final String? message;

  /// The confirming action's words.
  final String confirm;

  /// The dismissing action's words.
  final String cancel;

  /// Whether confirming destroys something (its words in the destructive
  /// colour).
  final bool destructive;

  /// Called with the answer: true to confirm.
  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) {
    final palette = ChromeThemeScope.paletteOf(context);
    final face = ChromeTypography.of(context);
    final width = math.min(maxWidth, MediaQuery.sizeOf(context).width - 48);
    Widget action(String label, Color color, {required bool answer}) =>
        Semantics(
          button: true,
          child: ChromeInk(
            key: ValueKey('chrome-alert-${answer ? 'confirm' : 'cancel'}'),
            color: color.withAlpha(0x24),
            borderRadius: BorderRadius.circular(6),
            onTap: () => onAnswer(answer),
            child: Container(
              height: 40,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                label,
                style: face.copyWith(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        );
    return SizedBox(
      key: const ValueKey('chrome-alert'),
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: palette.shadow, blurRadius: 24)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                19,
                24,
                message == null ? 20 : 10,
              ),
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: face.copyWith(
                    color: palette.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (message case final message?)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
                child: Text(
                  message,
                  style: face.copyWith(color: palette.onSurface, fontSize: 16),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  action(cancel, palette.accent, answer: false),
                  action(
                    confirm,
                    destructive ? palette.destructive : palette.accent,
                    answer: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
