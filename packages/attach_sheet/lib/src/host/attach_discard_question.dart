import 'package:attach_sheet/src/policy/attach_sheet_policy.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';

/// The stock **discard guard** question: a small dialog asking whether to
/// drop the selection, in the policy's wording.
///
/// A host with its own dialogs overrides `AttachSheetHost.confirmDiscard`
/// instead. Labels come from `ChromeStrings.attach`, colours from the
/// palette.
final class AttachDiscardQuestion extends StatelessWidget {
  /// The question in [wording]; [onAnswer] receives true to drop.
  const AttachDiscardQuestion({
    required this.wording,
    required this.onAnswer,
    super.key,
  });

  /// Which question to ask.
  final AttachDiscardWording wording;

  /// Called with the answer: true drops the selection.
  final ValueChanged<bool> onAnswer;

  /// Shows the question over [context]'s navigator and completes with the
  /// answer; false when it is dismissed without one.
  static Future<bool> show(
    BuildContext context,
    AttachDiscardWording wording,
  ) async {
    final answer = await Navigator.of(context).push<bool>(
      PageRouteBuilder<bool>(
        opaque: false,
        barrierDismissible: true,
        barrierColor: const Color(0x00000000),
        pageBuilder: (context, _, _) => AttachDiscardQuestion(
          wording: wording,
          onAnswer: (value) => Navigator.of(context).pop(value),
        ),
      ),
    );
    return answer ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final strings = ChromeStringsScope.attachOf(context);
    final palette = ChromeThemeScope.paletteOf(context);
    final (title, confirm, keep) = switch (wording) {
      AttachDiscardWording.discardSelection => (
        strings.discardSelectionTitle,
        strings.discardSelectionConfirm,
        strings.discardSelectionKeep,
      ),
      AttachDiscardWording.cancelSelection => (
        strings.cancelSelectionTitle,
        strings.cancelSelectionConfirm,
        strings.cancelSelectionKeep,
      ),
    };
    Widget action(String label, Color color, {required bool answer}) =>
        Semantics(
          button: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onAnswer(answer),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text(label, style: TextStyle(color: color, fontSize: 15)),
            ),
          ),
        );
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 300),
        padding: const EdgeInsets.fromLTRB(20, 20, 8, 8),
        decoration: BoxDecoration(
          color: palette.surfaceRaised,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: palette.shadow, blurRadius: 24)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 12, bottom: 12),
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: TextStyle(
                    color: palette.onSurface,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                action(keep, palette.accent, answer: false),
                action(confirm, palette.destructive, answer: true),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
