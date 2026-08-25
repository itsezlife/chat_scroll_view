import 'package:flutter/foundation.dart';

/// Which keyboard-panel type tabs are available.
@immutable
class KeyboardPanelAllow {
  /// Creates an allow mask.
  const KeyboardPanelAllow({
    this.emoji = true,
    this.stickers = false,
    this.gifs = false,
  });

  /// Demo default: emoji only.
  static const KeyboardPanelAllow emojiOnly = KeyboardPanelAllow();

  /// All three tabs.
  static const KeyboardPanelAllow all = KeyboardPanelAllow(
    emoji: true,
    stickers: true,
    gifs: true,
  );

  /// Unicode emoji grid.
  final bool emoji;

  /// Sticker packs tab (stub until packs exist).
  final bool stickers;

  /// GIF tab (stub until packs exist).
  final bool gifs;

  /// Ordered pager pages: emoji → GIF → stickers.
  List<KeyboardPanelTab> get tabs {
    final out = <KeyboardPanelTab>[];
    if (emoji) out.add(KeyboardPanelTab.emoji);
    if (gifs) out.add(KeyboardPanelTab.gifs);
    if (stickers) out.add(KeyboardPanelTab.stickers);
    return out;
  }

  /// Whether the bottom type-tab strip should be painted.
  bool get showTypeTabs => tabs.length > 1;

  /// Copy with selective overrides.
  KeyboardPanelAllow copyWith({bool? emoji, bool? stickers, bool? gifs}) =>
      KeyboardPanelAllow(
        emoji: emoji ?? this.emoji,
        stickers: stickers ?? this.stickers,
        gifs: gifs ?? this.gifs,
      );

  @override
  bool operator ==(Object other) =>
      other is KeyboardPanelAllow &&
      other.emoji == emoji &&
      other.stickers == stickers &&
      other.gifs == gifs;

  @override
  int get hashCode => Object.hash(emoji, stickers, gifs);
}

/// Bottom type-tab identity for the keyboard panel.
enum KeyboardPanelTab {
  /// Unicode emoji.
  emoji,

  /// GIF search / trending (stub).
  gifs,

  /// Stickers (stub).
  stickers,
}

/// Maps [KeyboardPanelStore.selectedPageKey] onto [KeyboardPanelTab].
extension KeyboardPanelTabPrefs on KeyboardPanelTab {
  /// Prefs integer (0 emoji / 1 stickers / 2 GIFs).
  int get prefsPage => switch (this) {
    KeyboardPanelTab.emoji => 0,
    KeyboardPanelTab.stickers => 1,
    KeyboardPanelTab.gifs => 2,
  };

  /// Inverse of [prefsPage].
  static KeyboardPanelTab fromPrefs(int page) => switch (page) {
    1 => KeyboardPanelTab.stickers,
    2 => KeyboardPanelTab.gifs,
    _ => KeyboardPanelTab.emoji,
  };
}
