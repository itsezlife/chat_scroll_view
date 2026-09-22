import 'package:chat_scroll_view/src/chat_scroll/chat_selection_policy.dart';
import 'package:flutter/foundation.dart';

/// How a **message menu session** is drawn.
///
/// One product concept — not a second menu API. [sheet] is the mobile
/// scrim with an undimmed target slot; [popup] is the desktop/web light
/// popup at the pointer with no viewport dim and no slot outline / lift
/// chrome. Session presence, dismiss, and result contracts are shared.
///
/// Defaults from **selection policy** via [forPolicy] / [forPlatform];
/// hosts may pass an explicit value to [showChatMessageMenu] for a single
/// present.
enum ChatMessageMenuPresentation {
  /// Scrim sheet: dimmed viewport, target slot left undimmed, column
  /// anchored for the mobile sheet path.
  sheet,

  /// Pointer popup: no viewport dim, no slot outline / lift, origin
  /// follows the tap within edge clamps.
  popup;

  /// Maps [policy] to the matching presentation.
  ///
  /// [$Mobile] → [sheet]; [$Desktop] → [popup].
  factory ChatMessageMenuPresentation.forPolicy(ChatSelectionPolicy policy) =>
      switch (policy) {
        ChatSelectionPolicy$Mobile() => ChatMessageMenuPresentation.sheet,
        ChatSelectionPolicy$Desktop() => ChatMessageMenuPresentation.popup,
      };

  /// Default from OS family — same matrix as [ChatSelectionPolicy.forPlatform].
  ///
  /// Convenience for hosts that want presentation without constructing a
  /// policy; [showChatMessageMenu] itself resolves via [forPolicy] on an
  /// explicit or platform policy.
  factory ChatMessageMenuPresentation.forPlatform({
    TargetPlatform? platform,
    bool? isWeb,
  }) => ChatMessageMenuPresentation.forPolicy(
    ChatSelectionPolicy.forPlatform(platform: platform, isWeb: isWeb),
  );
}
