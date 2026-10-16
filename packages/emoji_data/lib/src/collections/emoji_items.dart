import 'package:content_model/content_model.dart';
import 'package:emoji_data/src/catalog/emoji_catalog.dart';
import 'package:emoji_data/src/collections/emoji_spoken_names.dart';

/// Turns catalogue entries and keys into the [CollectionItem]s a page shows:
/// the one place that applies the user's variant choice and the device's
/// glyph support, so a grid and search results cannot disagree about either.
final class EmojiItems {
  /// Creates the resolver over [catalog] and the two stores that shape it.
  EmojiItems({
    required this.catalog,
    required this.preferences,
    this.glyphSupport,
  });

  /// The catalogue entries come from.
  final EmojiCatalog catalog;

  /// Holds the variant the user chose per base.
  final PreferenceStore preferences;

  /// Says which keys the device can draw; null shows everything.
  final GlyphSupport? glyphSupport;

  /// What a screen reader says for an emoji, once the packs of the active
  /// languages are known; null leaves the items unnamed.
  EmojiSpokenNames? spokenNames;

  /// The key the grid shows for [entry]: the variant chosen for it, else the
  /// one in the tone chosen for all ([PreferenceStore.defaultVariant]: the
  /// variant every person of which has that tone), else the base.
  ///
  /// A choice that is not a variant of [entry] (the catalogue moved on) is
  /// ignored, and so is one the device cannot draw, so a missing tone never
  /// hides an emoji whose base is fine. Null when the base is missing, in
  /// every tone: only what the grid planned is probed, so a variant nobody
  /// probed reads as drawable, and a device that lacks the emoji lacks its
  /// tones too.
  ContentKey$Unicode? shownKey(EmojiEntry entry) {
    if (!_supports(entry.base)) return null;
    final chosen =
        preferences.preferredVariant(entry.base) ?? _defaultOf(entry);
    if (chosen != null &&
        entry.modifiersOf(chosen) != null &&
        _supports(chosen)) {
      return chosen;
    }
    return _supports(entry.base) ? entry.base : null;
  }

  ContentKey$Unicode? _defaultOf(EmojiEntry entry) {
    final tones = preferences.defaultVariant?.tones;
    if (tones == null) return null;
    if (tones.isEmpty) return entry.base;
    final tone = tones.first;
    for (final variant in entry.variants) {
      final own = variant.modifiers.tones;
      if (own.isNotEmpty && own.every((each) => each == tone)) {
        return variant.key;
      }
    }
    return null;
  }

  /// The item for [entry] as the grid shows it, or null when hidden.
  CollectionItem? itemOf(EmojiEntry entry) => switch (shownKey(entry)) {
    final key? => describe(key),
    null => null,
  };

  /// The item for a key taken as it is (a recent), or null when the device
  /// cannot draw it. A key that is not a unicode key stays a bare item.
  CollectionItem? itemForKey(ContentKey key) => switch (key) {
    final ContentKey$Unicode unicode =>
      _supports(unicode) ? describe(unicode) : null,
    _ => CollectionItem.bare(key),
  };

  /// The described item of the unicode emoji [key].
  CollectionItem describe(ContentKey$Unicode key) => CollectionItem.described(
    ContentDescriptor(
      key: key,
      semanticKind: SemanticKind.unicodeEmoji,
      mediaForm: MediaForm.glyph,
      spokenName: spokenNames?.of(key),
    ),
  );

  bool _supports(ContentKey$Unicode key) => glyphSupport?.supports(key) ?? true;
}
