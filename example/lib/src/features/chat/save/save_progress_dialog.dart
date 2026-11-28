import 'dart:async';

import 'package:chat_scroll_view_example/src/features/chat/save/chat_save_feedback.dart';
import 'package:chat_scroll_view_example/src/features/chat/save/chat_save_strings.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart';

/// The example's progress dialog of a save: its text, a bar with the
/// percent done, and a cancel. Back cancels too; a tap outside does
/// nothing, so a stray touch does not stop a save.
abstract final class SaveProgressDialog {
  /// Key of the dialog's cancel button.
  static const ValueKey<String> cancelKey = ValueKey('save-progress-cancel');

  /// Shows [progress] over [context]'s root navigator; answers what closes
  /// it, which does nothing once the dialog is gone.
  static VoidCallback show(
    BuildContext context,
    ChatSaveProgress progress, {
    ChatSaveStrings strings = ChatSaveStrings.demo,
  }) {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _SaveProgressBody(progress, strings),
    );
    unawaited(navigator.push(route));
    return () {
      if (!route.isActive) return;
      if (route.isCurrent) {
        navigator.pop();
      } else {
        navigator.removeRoute(route);
      }
    };
  }
}

class _SaveProgressBody extends StatelessWidget {
  const _SaveProgressBody(this.progress, this.strings);

  final ChatSaveProgress progress;
  final ChatSaveStrings strings;

  @override
  Widget build(BuildContext context) {
    final text = ChromeTypography.of(context);
    return ChromeTextRoot(
      // Back cancels: the save's own close then pops the dialog.
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) progress.cancel(from: ChatSaveCancelSource.back);
        },
        child: AlertDialog(
          content: ValueListenableBuilder<double>(
            valueListenable: progress.fraction,
            builder: (context, fraction, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(strings.progressMessage, style: text),
                const SizedBox(height: 20),
                LinearProgressIndicator(value: fraction, minHeight: 4),
                const SizedBox(height: 4),
                Text(
                  '${(fraction * 100).round()}%',
                  style: text.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              key: SaveProgressDialog.cancelKey,
              onPressed: progress.cancel,
              child: Text(strings.cancel, style: text),
            ),
          ],
        ),
      ),
    );
  }
}
