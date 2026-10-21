import 'dart:convert';

import 'package:content_model/content_model.dart';
import 'package:emoji_catalog_pack/src/shortcodes/emoji_shortcodes.dart';
import 'package:emoji_catalog_pack/src/structure/emoji_catalog_structure.dart';

/// Turns the emoji data of JoyPixels' emoji-toolkit (`emoji.json`) into the
/// shortcodes of the catalog.
///
/// Only the toolkit's JSON is read, for its `shortname`s; its artwork is under
/// a licence of its own and never used. The shortnames are the alpha codes the
/// reference desktop client shows.
abstract final class EmojiShortcodesBuilder {
  /// Builds the shortcodes of [structure] from [toolkitJson], the text of the
  /// toolkit's `emoji.json`, labelled with [source].
  ///
  /// A code exists for the same keys a keyword pack has a record for: every
  /// entry's base and every variant without a skin tone. A tone variant shows
  /// its entry's code, as the reference client does. A key the toolkit has no
  /// code for gets none: the toolkit lags Unicode by a version or two, and a
  /// missing code only costs a hint.
  ///
  /// Sequences are matched with U+FE0F removed, since the structure and the
  /// toolkit spell the presentation selector differently; the key is written as
  /// the structure spells it.
  ///
  /// Throws a [FormatException] when the JSON is not the toolkit's shape, a
  /// shortname is empty, or two toolkit entries are one sequence.
  static EmojiShortcodes build({
    required EmojiCatalogStructure structure,
    required String toolkitJson,
    required String source,
  }) {
    final byToolkit = _shortnames(toolkitJson);
    final codes = <ContentKey$Unicode, String>{};
    void add(ContentKey$Unicode key) {
      final code = byToolkit[_withoutFe0f(key.sequence.runes)];
      if (code != null) codes[key] = code;
    }

    for (final entry in structure.entries) {
      add(entry.base);
      for (final variant in entry.variants) {
        if (variant.modifiers.tones.isEmpty) add(variant.key);
      }
    }
    return EmojiShortcodes(source: source, codes: codes);
  }

  // The shortname of each toolkit sequence, by its code points without FE0F.
  static Map<String, String> _shortnames(String toolkitJson) {
    final json = jsonDecode(toolkitJson);
    if (json is! Map<String, Object?>) {
      throw const FormatException('emoji.json is not an object of emoji.');
    }
    final shortnames = <String, String>{};
    for (final MapEntry(:key, :value) in json.entries) {
      final (sequence, shortname) = switch (value) {
        {
          'shortname': final String shortname,
          'code_points': {'fully_qualified': final String sequence},
        }
            when shortname.isNotEmpty =>
          (sequence, shortname),
        _ => throw FormatException('Unreadable toolkit emoji $key.'),
      };
      final normalised = _withoutFe0f(
        sequence.split('-').map((hex) => int.parse(hex, radix: 16)),
      );
      if (shortnames.containsKey(normalised)) {
        throw FormatException('Toolkit emoji $key repeats a sequence.');
      }
      shortnames[normalised] = shortname;
    }
    return shortnames;
  }

  static String _withoutFe0f(Iterable<int> codePoints) => [
    for (final codePoint in codePoints)
      if (codePoint != 0xFE0F) codePoint.toRadixString(16),
  ].join('-');
}
