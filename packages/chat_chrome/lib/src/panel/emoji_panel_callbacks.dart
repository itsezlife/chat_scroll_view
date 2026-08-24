import 'dart:async';

import 'package:chat_chrome/src/panel/emoji_panel_labels.dart';
import 'package:flutter/material.dart';

/// Request to wipe frequently-used emoji after host confirmation.
///
/// Clear-recents request — the panel does **not**
/// clear on long-press; the host shows UI, then calls [clear].
@immutable
class EmojiClearRecentsRequest {
  /// Creates a clear request.
  const EmojiClearRecentsRequest({
    required this.context,
    required this.labels,
    required this.clear,
  });

  /// Host / panel [BuildContext] for dialogs.
  final BuildContext context;

  /// Localized copy for a confirm dialog.
  final EmojiPanelLabels labels;

  /// Permanently clears the recents store and refreshes the panel UI.
  final Future<void> Function() clear;
}

/// Handler for long-press on a frequently-used glyph.
typedef EmojiClearRecentsHandler =
    FutureOr<void> Function(EmojiClearRecentsRequest request);

/// Built-in [EmojiClearRecentsHandler]s.
abstract final class EmojiClearRecents {
  /// Material confirm dialog, then [EmojiClearRecentsRequest.clear].
  static Future<void> materialConfirm(EmojiClearRecentsRequest request) async {
    final labels = request.labels;
    final confirmed = await showDialog<bool>(
      context: request.context,
      builder: (context) => AlertDialog(
        title: Text(labels.clearRecentTitle),
        content: Text(labels.clearRecentMessage),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(labels.cancelButton),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(labels.clearButton),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await request.clear();
    }
  }

  /// Clears immediately (tests / non-interactive hosts).
  static Future<void> immediate(EmojiClearRecentsRequest request) =>
      request.clear();

  /// Ignores long-press clear (recents stay).
  static Future<void> ignore(EmojiClearRecentsRequest request) async {}
}

/// Secondary host hooks for [EmojiPanel] (settings, clear-recents confirm, …).
///
/// Keep insert / backspace on [EmojiPanel] itself; put optional UX that needs a
/// [BuildContext] or confirm flow here so the host has one place to customize.
@immutable
class EmojiPanelCallbacks {
  /// Creates host callbacks. Defaults to confirm-then-clear.
  const EmojiPanelCallbacks({
    this.onStickerSettings,
    this.onClearRecents = EmojiClearRecents.materialConfirm,
    this.onSearchClosed,
  });

  /// No secondary hooks (clear-recents long-press is ignored).
  static const EmojiPanelCallbacks none = EmojiPanelCallbacks(
    onClearRecents: EmojiClearRecents.ignore,
  );

  /// Stickers settings.
  final VoidCallback? onStickerSettings;

  /// Long-press on frequently-used — host confirms, then calls [clear].
  final EmojiClearRecentsHandler onClearRecents;

  /// Search mode ended while the panel stays open (IME dismissed).
  ///
  /// Host SHOULD restore composer focus with soft IME still suppressed
  /// (Telegram: focus only). Keyboard handoff owns its own [requestKeyboard].
  final VoidCallback? onSearchClosed;
}
