import 'package:emoji_data/src/emoji_item.dart';
import 'package:emoji_data/src/emoji_strip_icon.dart';
import 'package:flutter/foundation.dart';

/// Synthetic recents section id (not part of [EmojiDataSource.categories]).
const String emojiRecentsSectionId = 'recents';

/// One emoji category supplied by the host or catalog provider.
@immutable
final class EmojiCategorySpec {
  /// Creates a category. Prefer host-localized [title] and explicit [stripIcon].
  const EmojiCategorySpec({
    required this.id,
    required this.title,
    required this.items,
    this.stripIcon,
  });

  /// Stable id (`smileys`, `animals`, host-defined, …).
  final String id;

  /// Localized section title — host owns copy (l10n / demo strings).
  final String title;

  /// Grid contents for this category.
  final List<EmojiItem> items;

  /// Category-strip chrome. Omit only when the host hides the strip.
  final EmojiStripIcon? stripIcon;

  /// Unicode glyphs only (convenience for grid layout).
  List<String> get unicodeGlyphs => items
      .whereType<UnicodeEmojiItem>()
      .map((e) => e.glyph)
      .toList(growable: false);
}
