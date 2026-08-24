import 'package:emoji_data/src/catalog/emoji_catalog_entry.dart';
import 'package:flutter/foundation.dart';

/// Raw category bucket before mapping to [EmojiCategorySpec].
@immutable
final class EmojiCatalogCategory {
  const EmojiCatalogCategory({
    required this.id,
    required this.entries,
  });

  /// Stable id (`smileys`, `animals`, …).
  final String id;

  final List<EmojiCatalogEntry> entries;
}
