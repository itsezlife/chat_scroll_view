import 'package:chat_chrome/src/panel/keyboard_panel_allow.dart';
import 'package:flutter/foundation.dart';

/// Host-provided copy for type tabs and clear-recents confirm.
///
/// Package stays locale-agnostic — the host maps strings (l10n / demo).
@immutable
class KeyboardPanelLabels {
  /// Creates labels. Prefer app l10n; English defaults are for tests/demos.
  const KeyboardPanelLabels({
    this.emoji = 'Emoji',
    this.gifs = 'GIF',
    this.stickers = 'Stickers',
    this.recentlyUsed = 'Recently used',
    this.searchHint = 'Search',
    this.searchResults = 'Search result',
    this.searchEmpty = 'No emoji found',
    this.clearRecentTitle = 'Clear recent emoji',
    this.clearRecentMessage = 'Do you want to clear all your recent emoji?',
    this.clearButton = 'Clear',
    this.cancelButton = 'Cancel',
  });

  /// English defaults (tests / demos without l10n).
  static const KeyboardPanelLabels english = KeyboardPanelLabels();

  /// Russian demo copy.
  static const KeyboardPanelLabels russian = KeyboardPanelLabels(
    emoji: 'Эмодзи',
    gifs: 'GIF',
    stickers: 'Стикеры',
    recentlyUsed: 'Недавние',
    searchHint: 'Поиск',
    searchResults: 'Результат поиска',
    searchEmpty: 'Эмодзи не найдены',
    clearRecentTitle: 'Очистить недавние эмодзи',
    clearRecentMessage: 'Вы хотите очистить все недавние эмодзи?',
    clearButton: 'Очистить',
    cancelButton: 'Отмена',
  );

  /// Emoji type tab.
  final String emoji;

  /// GIF type tab.
  final String gifs;

  /// Stickers type tab.
  final String stickers;

  /// Frequently-used section header on the emoji grid.
  final String recentlyUsed;

  /// Search-field hint.
  final String searchHint;

  /// Keyword-hit section header (`StickerOrEmojiSearchResult`).
  final String searchResults;

  /// Empty keyword-search placeholder (`NoEmojiFound`).
  final String searchEmpty;

  /// Clear-recents dialog title.
  final String clearRecentTitle;

  /// Clear-recents dialog body.
  final String clearRecentMessage;

  /// Confirm action.
  final String clearButton;

  /// Dismiss action.
  final String cancelButton;

  /// Resolves the label for [tab].
  String of(KeyboardPanelTab tab) => switch (tab) {
    KeyboardPanelTab.emoji => emoji,
    KeyboardPanelTab.gifs => gifs,
    KeyboardPanelTab.stickers => stickers,
  };

  @override
  bool operator ==(Object other) =>
      other is KeyboardPanelLabels &&
      other.emoji == emoji &&
      other.gifs == gifs &&
      other.stickers == stickers &&
      other.recentlyUsed == recentlyUsed &&
      other.searchHint == searchHint &&
      other.searchResults == searchResults &&
      other.searchEmpty == searchEmpty &&
      other.clearRecentTitle == clearRecentTitle &&
      other.clearRecentMessage == clearRecentMessage &&
      other.clearButton == clearButton &&
      other.cancelButton == cancelButton;

  @override
  int get hashCode => Object.hash(
    emoji,
    gifs,
    stickers,
    recentlyUsed,
    searchHint,
    searchResults,
    searchEmpty,
    clearRecentTitle,
    clearRecentMessage,
    clearButton,
    cancelButton,
  );
}
