import 'package:attach_sheet/src/policy/attach_sheet_policy.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';

/// The stock **discard guard** question: the chrome's alert asking whether
/// to drop the selection, in the policy's wording (title, a line under it,
/// Keep and the destructive Discard).
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

  /// Shows the question over [context]'s navigator as the chrome's alert
  /// and completes with the answer; false when it is dismissed without one.
  static Future<bool> show(
    BuildContext context,
    AttachDiscardWording wording,
  ) async {
    final strings = ChromeStringsScope.attachOf(context);
    final words = _wordsOf(strings, wording);
    final answer = await ChromeAlert.show(
      context,
      title: words.title,
      message: words.message,
      confirm: words.confirm,
      cancel: words.keep,
    );
    return answer ?? false;
  }

  static ({String title, String? message, String confirm, String keep})
  _wordsOf(AttachStrings strings, AttachDiscardWording wording) =>
      switch (wording) {
        AttachDiscardWording.discardSelection => (
          title: strings.discardSelectionTitle,
          message: strings.discardSelectionMessage,
          confirm: strings.discardSelectionConfirm,
          keep: strings.discardSelectionKeep,
        ),
        AttachDiscardWording.cancelSelection => (
          title: strings.cancelSelectionTitle,
          message: null,
          confirm: strings.cancelSelectionConfirm,
          keep: strings.cancelSelectionKeep,
        ),
      };

  @override
  Widget build(BuildContext context) {
    final words = _wordsOf(ChromeStringsScope.attachOf(context), wording);
    return ChromeAlert(
      title: words.title,
      message: words.message,
      confirm: words.confirm,
      cancel: words.keep,
      onAnswer: onAnswer,
    );
  }
}
