import 'package:flutter/foundation.dart';

/// Which emoji-panel tabs are available .
@immutable
class EmojiPanelAllow {
  /// Creates an allow mask.
  const EmojiPanelAllow({
    this.emoji = true,
    this.stickers = false,
    this.gifs = false,
  });

  /// Demo default: emoji only.
  static const EmojiPanelAllow emojiOnly = EmojiPanelAllow();

  /// All three tabs.
  static const EmojiPanelAllow all = EmojiPanelAllow(
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
  List<EmojiPanelTab> get tabs {
    final out = <EmojiPanelTab>[];
    if (emoji) out.add(EmojiPanelTab.emoji);
    if (gifs) out.add(EmojiPanelTab.gifs);
    if (stickers) out.add(EmojiPanelTab.stickers);
    return out;
  }

  /// Whether the bottom type-tab strip should be painted.
  bool get showTypeTabs => tabs.length > 1;

  /// Copy with selective overrides.
  EmojiPanelAllow copyWith({bool? emoji, bool? stickers, bool? gifs}) =>
      EmojiPanelAllow(
        emoji: emoji ?? this.emoji,
        stickers: stickers ?? this.stickers,
        gifs: gifs ?? this.gifs,
      );

  @override
  bool operator ==(Object other) =>
      other is EmojiPanelAllow &&
      other.emoji == emoji &&
      other.stickers == stickers &&
      other.gifs == gifs;

  @override
  int get hashCode => Object.hash(emoji, stickers, gifs);
}

/// Bottom type-tab identity .
enum EmojiPanelTab {
  /// Unicode emoji.
  emoji,

  /// GIF search / trending (stub).
  gifs,

  /// Stickers (stub).
  stickers,
}

/// Maps persisted `selected_page` onto [EmojiPanelTab].
extension EmojiPanelTabPrefs on EmojiPanelTab {
  /// Prefs integer (0 emoji / 1 stickers / 2 GIFs).
  int get prefsPage => switch (this) {
    EmojiPanelTab.emoji => 0,
    EmojiPanelTab.stickers => 1,
    EmojiPanelTab.gifs => 2,
  };

  /// Inverse of [prefsPage].
  static EmojiPanelTab fromPrefs(int page) => switch (page) {
    1 => EmojiPanelTab.stickers,
    2 => EmojiPanelTab.gifs,
    _ => EmojiPanelTab.emoji,
  };
}
