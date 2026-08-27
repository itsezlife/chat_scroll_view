import 'package:chat_chrome/src/panel/keyboard_panel_allow.dart';
import 'package:chat_chrome/src/panel/emoji_tab_assets.dart';
import 'package:flutter/foundation.dart';

/// Trailing bottom-bar action for one panel type tab.
///
/// When [repeatOnHold] is true, the bar mounts [BackspaceActionButton] instead
/// of a single-shot [ScalePressable] tap.
@immutable
class KeyboardPanelBottomAction {
  /// Creates an action button descriptor.
  const KeyboardPanelBottomAction({
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

/// Resolves which trailing action to show per [KeyboardPanelTab].
///
/// [KeyboardPanelBottomActions.standard]: emoji → backspace (hold repeats),
/// GIFs → none, stickers → settings when provided.
@immutable
class KeyboardPanelBottomActions {
  /// Creates a resolver.
  const KeyboardPanelBottomActions({required this.resolve});

  /// Returns the action for [tab], or `null` when the tab has none.
  final KeyboardPanelBottomAction? Function(KeyboardPanelTab tab) resolve;

  /// Convenience lookup.
  KeyboardPanelBottomAction? forTab(KeyboardPanelTab tab) => resolve(tab);

  /// Default mapping (emoji backspace with [repeatOnHold]).
  factory KeyboardPanelBottomActions.standard({
    required VoidCallback onBackspace,
    VoidCallback? onStickerSettings,
  }) =>
      KeyboardPanelBottomActions(
        resolve: (tab) => switch (tab) {
          KeyboardPanelTab.emoji => KeyboardPanelBottomAction(
            iconAsset: EmojiTabAssets.clear,
            onPressed: onBackspace,
            repeatOnHold: true,
          ),
          KeyboardPanelTab.stickers when onStickerSettings != null =>
            KeyboardPanelBottomAction(
              iconAsset: EmojiTabAssets.settings,
              onPressed: onStickerSettings,
              semanticsLabel: 'Settings',
            ),
          _ => null,
        },
      );
}
