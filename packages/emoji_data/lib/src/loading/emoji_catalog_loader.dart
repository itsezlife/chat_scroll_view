import 'package:emoji_catalog_pack/emoji_catalog_pack.dart';
import 'package:emoji_data/src/loading/cached_futures.dart';
import 'package:emoji_data/src/loading/emoji_asset_loader.dart';

/// Reads the shipped catalog assets through the host's [EmojiAssetLoader] and
/// decodes them, once each.
///
/// The structure and the shortcodes are locale-independent and read on first
/// use; a keyword pack is read when its locale is first asked for, never
/// ahead of that. A read
/// that succeeded is kept for the life of the loader. One that failed is not:
/// the next call reads again, so a transient failure is not final. Callers
/// asking while a read is in flight share it.
///
/// Decoding is the pack's: a damaged or newer-format asset fails with a
/// `FormatException` rather than yielding a partial catalog.
final class EmojiCatalogLoader {
  /// Creates a loader reading assets through [load].
  EmojiCatalogLoader(EmojiAssetLoader load) : _load = load;

  final EmojiAssetLoader _load;
  final CachedFutures<String, EmojiCatalogStructure> _structures =
      CachedFutures();
  final CachedFutures<String, EmojiShortcodes> _shortcodes = CachedFutures();
  final CachedFutures<String, EmojiKeywordPack> _packs = CachedFutures();

  /// The catalog structure.
  Future<EmojiCatalogStructure> structure() => _structures.of(
    'structure',
    () async => EmojiCatalogStructure.decode(
      await _load(EmojiCatalogPackAssets.structure),
    ),
  );

  /// The shortcodes of the catalog (`:grinning:`).
  Future<EmojiShortcodes> shortcodes() => _shortcodes.of(
    'shortcodes',
    () async =>
        EmojiShortcodes.decode(await _load(EmojiCatalogPackAssets.shortcodes)),
  );

  /// The keyword pack of [locale], a CLDR locale id such as `de`.
  ///
  /// Fails with an [ArgumentError] for text that is not a locale id. A locale
  /// without a shipped pack fails like any missing asset; check
  /// `EmojiCatalogPackAssets.locales` first.
  Future<EmojiKeywordPack> keywordPack(String locale) => _packs.of(
    locale,
    () async => EmojiKeywordPack.decode(
      await _load(EmojiCatalogPackAssets.keywordPack(locale)),
    ),
  );
}
