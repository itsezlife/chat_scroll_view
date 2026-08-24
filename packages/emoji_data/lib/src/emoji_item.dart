import 'package:flutter/foundation.dart';

/// One selectable emoji entry in a category or search results.
@immutable
sealed class EmojiItem {
  const EmojiItem();

  const factory EmojiItem.unicode({
    required String glyph,
    List<String> keywords,
    bool supportsSkinTone,
  }) = UnicodeEmojiItem;

  const factory EmojiItem.custom({
    required String id,
    String? previewGlyph,
  }) = CustomEmojiItem;

  /// Stable key for recents / persistence (glyph or custom id).
  String get pickKey;
}

/// Standard Unicode emoji cell.
@immutable
final class UnicodeEmojiItem extends EmojiItem {
  const UnicodeEmojiItem({
    required this.glyph,
    this.keywords = const <String>[],
    this.supportsSkinTone = false,
  });

  final String glyph;
  final List<String> keywords;
  final bool supportsSkinTone;

  @override
  String get pickKey => glyph;
}

/// Host-rendered custom item (stickers, animated emoji, etc.).
@immutable
final class CustomEmojiItem extends EmojiItem {
  const CustomEmojiItem({required this.id, this.previewGlyph});

  final String id;
  final String? previewGlyph;

  @override
  String get pickKey => id;
}
