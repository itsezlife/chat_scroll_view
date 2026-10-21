import 'package:content_model/content_model.dart';
import 'package:emoji_catalog_pack/emoji_catalog_pack.dart';
import 'package:emoji_data/src/loading/cached_futures.dart';
import 'package:emoji_data/src/loading/emoji_catalog_loader.dart';
import 'package:listen/listen.dart';

/// The keyword packs shipped in `emoji_catalog_pack`, as a [KeywordSource]:
/// the offline baseline search answers from before any host pack arrives.
///
/// A pack is read when its language is first asked for and kept. Each record
/// becomes the keywords of its key, the spoken name first (lower-cased) so
/// that a search finds an emoji by the name a screen reader speaks, then the
/// pack's keywords in CLDR order. Packs are version `0`: any pack a host
/// supplies for the language supersedes them (see [LayeredKeywordSource]).
///
/// A language tag matches a shipped locale exactly or by its primary subtag
/// (`pt-BR` and `pt_BR` read `pt`), ignoring case. A language without a
/// shipped pack answers null, and nothing is read for it. A shipped pack that
/// cannot be read fails the future and is read again on the next ask.
///
/// The bundle never changes, so [changes] never signals.
final class BundledKeywordSource with ChangeNotifier implements KeywordSource {
  /// Creates a source over the packs [loader] reads.
  ///
  /// [languages] are the locale ids that have a shipped pack; the default is
  /// every locale of `EmojiCatalogPackAssets.locales`.
  BundledKeywordSource(
    this._loader, {
    Iterable<String> languages = EmojiCatalogPackAssets.locales,
  }) : _languages = {for (final language in languages) language.toLowerCase()};

  final EmojiCatalogLoader _loader;
  final Set<String> _languages;
  final CachedFutures<String, KeywordPack> _packs = CachedFutures();
  bool _disposed = false;

  @override
  Listenable get changes => this;

  @override
  Future<KeywordPack?> pack(String language) async {
    if (_disposed) return null;
    final tag = language.toLowerCase().replaceAll('_', '-');
    final locale = _languages.contains(tag) ? tag : tag.split('-').first;
    if (!_languages.contains(locale)) return null;
    return _packs.of(
      locale,
      () async => _convert(await _loader.keywordPack(locale)),
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }

  static KeywordPack _convert(EmojiKeywordPack pack) => KeywordPack(
    language: pack.locale,
    version: 0,
    keywords: {
      for (final record in pack.records)
        record.key: [
          for (final word in [record.spokenName, ...record.keywords])
            word.toLowerCase(),
        ],
    },
  );
}
