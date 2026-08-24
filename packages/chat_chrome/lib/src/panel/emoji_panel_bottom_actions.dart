import 'package:chat_chrome/src/panel/emoji_panel_allow.dart';
import 'package:chat_chrome/src/panel/emoji_tab_assets.dart';
import 'package:flutter/foundation.dart';

/// Trailing bottom-bar action for one panel type tab.
///
/// When [repeatOnHold] is true, the bar mounts [BackspaceActionButton] instead
/// of a single-shot [ScalePressable] tap.
@immutable
class EmojiPanelBottomAction {
  /// Creates an action button descriptor.
  const EmojiPanelBottomAction({
    required this.iconAsset,
    required this.onPressed,
    this.repeatOnHold = false,
    this.semanticsLabel,
  });

  /// Package asset path ([EmojiTabAssets]).
  final String iconAsset;

  /// Tap / repeat handler.
  final VoidCallback onPressed;

  /// Hold-to-repeat backspace.
  final bool repeatOnHold;

  /// Optional accessibility label.
  final String? semanticsLabel;
}

/// Resolves which trailing action to show per [EmojiPanelTab].
///
/// [EmojiPanelBottomActions.standard]: emoji → backspace (hold repeats),
/// GIFs → none, stickers → settings when provided.
@immutable
class EmojiPanelBottomActions {
  /// Creates a resolver.
  const EmojiPanelBottomActions({required this.resolve});

  /// Returns the action for [tab], or `null` when the tab has none.
  final EmojiPanelBottomAction? Function(EmojiPanelTab tab) resolve;

  /// Convenience lookup.
  EmojiPanelBottomAction? forTab(EmojiPanelTab tab) => resolve(tab);

  /// Default mapping (emoji backspace with [repeatOnHold]).
  factory EmojiPanelBottomActions.standard({
    required VoidCallback onBackspace,
    VoidCallback? onStickerSettings,
  }) =>
      EmojiPanelBottomActions(
        resolve: (tab) => switch (tab) {
          EmojiPanelTab.emoji => EmojiPanelBottomAction(
            iconAsset: EmojiTabAssets.clear,
            onPressed: onBackspace,
            repeatOnHold: true,
          ),
          EmojiPanelTab.stickers when onStickerSettings != null =>
            EmojiPanelBottomAction(
              iconAsset: EmojiTabAssets.settings,
              onPressed: onStickerSettings,
              semanticsLabel: 'Settings',
            ),
          _ => null,
        },
      );
}
