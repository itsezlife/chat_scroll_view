import 'package:content_model/content_model.dart';
import 'package:emoji_data/src/catalog/emoji_catalog.dart';

/// The names a screen reader speaks for emoji, taken from keyword packs.
///
/// A pack lists the spoken name of an emoji first, then its search keywords
/// (see `BundledKeywordSource`), so the name of a key is the first word of its
/// record. [packs] are in language order, the active language first: the first
/// pack that names the key wins, so a language that lacks an emoji hands it to
/// the next one.
///
/// A key a pack has no record for (a skin-tone variant: only entries and
/// gender variants have records) is named as its entry's base, the same words
/// a reader would say for the emoji without the tone. A key no pack names has
/// no spoken name, never a guess: the consumer falls back to its own text.
final class EmojiSpokenNames {
  /// Names over [packs], most preferred first, for the emoji of [catalog].
  EmojiSpokenNames(this._catalog, Iterable<KeywordPack> packs)
    : _packs = List<KeywordPack>.unmodifiable(packs);

  final EmojiCatalog _catalog;
  final List<KeywordPack> _packs;

  /// The spoken name of [key], or null when no pack names it.
  String? of(ContentKey$Unicode key) {
    final base = _catalog.entryOf(key)?.base;
    for (final pack in _packs) {
      for (final candidate in [key, ?base]) {
        if (pack.keywords[candidate] case [final name, ...]) return name;
      }
    }
    return null;
  }
}
