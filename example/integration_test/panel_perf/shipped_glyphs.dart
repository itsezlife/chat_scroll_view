import 'package:emoji_data/emoji_data.dart';
import 'package:flutter/services.dart';

/// The base glyph of every entry of the shipped emoji catalogue, in palette
/// order: the realistic glyph set the bake harness plans its atlas over.
Future<List<String>> loadShippedGlyphs() async {
  final structure = await EmojiCatalogLoader(rootBundle.loadString).structure();
  return [
    for (final entry in EmojiCatalog(structure).entries) entry.base.sequence,
  ];
}
