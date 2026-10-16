/// Where the shipped assets live, as keys for the host's asset bundle
/// (`rootBundle.loadString` in Flutter).
///
/// The pack does not load anything itself: reading an asset is the host's
/// platform, decoding the text is [EmojiCatalogStructure.decode] and
/// [EmojiKeywordPack.decode].
abstract final class EmojiCatalogPackAssets {
  /// The asset key of the locale-independent structure.
  static const String structure =
      'packages/emoji_catalog_pack/assets/structure.tsv';

  /// The asset key of the keyword pack of [locale], a CLDR locale id such as
  /// `de` or `pt`.
  ///
  /// Throws an [ArgumentError] when [locale] is not a plain locale id, so a
  /// host-supplied string cannot name another asset. A locale without a
  /// shipped pack is not detected here; loading its key fails in the bundle.
  static String keywordPack(String locale) {
    if (locale.isEmpty || _notLocaleChar.hasMatch(locale)) {
      throw ArgumentError.value(locale, 'locale', 'Not a locale id.');
    }
    return 'packages/emoji_catalog_pack/assets/keywords/$locale.tsv';
  }

  static final RegExp _notLocaleChar = RegExp('[^A-Za-z0-9_-]');
}
