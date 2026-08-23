import 'package:flutter/foundation.dart';

/// One Unicode emoji row in a locale catalog (glyph + keyword string).
@immutable
final class EmojiCatalogEntry {
  const EmojiCatalogEntry({
    required this.glyph,
    required this.keywords,
    this.supportsSkinTone = false,
  });

  /// Display glyph.
  final String glyph;

  /// Pipe-delimited English keywords (same convention as reference locale tables).
  final String keywords;

  /// Whether the catalog marks this glyph as skin-tone capable.
  final bool supportsSkinTone;

  /// Parsed keyword tokens (lowercased by search, not here).
  List<String> get keywordList => keywords
      .split(' | ')
      .map((k) => k.trim())
      .where((k) => k.isNotEmpty)
      .toList(growable: false);
}
