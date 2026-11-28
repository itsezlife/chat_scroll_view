import 'package:chat_scroll_view_example/src/app/demo_chrome_strings.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart';
import 'package:mpx_library/mpx_library.dart';
import 'package:mpx_transfer/mpx_transfer.dart';

/// Asks the user for a file again when a failed message's upload source is
/// gone (`failed(sourceLost)`: a web page reloaded over its copy limit),
/// for the outbox's retry with it (`DemoOutboxChat.retry`'s
/// `askForSource`).
///
/// A dialog says why, and its action opens the system file dialog; the
/// picked file is the item's new source.
abstract final class SourceLostPrompt {
  /// Key of the dialog's action that opens the file dialog.
  static const ValueKey<String> pickKey = ValueKey('source-lost-pick');

  /// Asks over [context] and picks through [intake]; null when the user
  /// cancelled either.
  static Future<SourceBytes?> ask(
    BuildContext context, {
    required FileIntake intake,
  }) async {
    final pick = await showDialog<bool>(
      context: context,
      builder: (context) {
        final text = ChromeTypography.of(context);
        return ChromeTextRoot(
          child: AlertDialog(
            title: Text(DemoTransferStrings.sourceLostTitle, style: text),
            content: Text(DemoTransferStrings.sourceLostMessage, style: text),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(DemoTransferStrings.cancel, style: text),
              ),
              TextButton(
                key: pickKey,
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(DemoTransferStrings.pickFile, style: text),
              ),
            ],
          ),
        );
      },
    );
    if (pick != true) return null;
    final files = await intake.pickFiles(multiple: false);
    if (files.isEmpty) return null;
    return sourceOf(files.single);
  }

  /// The upload source of [file]: a file on this device, or the page's
  /// blob on the web.
  static SourceBytes sourceOf(IntakeFile file) => switch (file.source) {
    IntakeSource$Path(:final path) => SourceBytes.file(path, size: file.size),
    IntakeSource$Blob(:final handle) => SourceBytes.blob(handle),
  };
}
