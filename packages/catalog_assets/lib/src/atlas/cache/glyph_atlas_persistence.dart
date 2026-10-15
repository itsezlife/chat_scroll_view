import 'package:catalog_assets/src/atlas/cache/glyph_art_version_source.dart';
import 'package:catalog_assets/src/atlas/cache/glyph_cache_key.dart';
import 'package:catalog_assets/src/atlas/cache/glyph_cache_store.dart';
import 'package:meta/meta.dart';

/// What a `GlyphAtlas` needs to persist its pages across launches.
///
/// The atlas derives the cache key from these and from its own plan: the art
/// version from [artVersion], the density from [devicePixelRatio], the baked
/// glyph size, layout version and catalogue hash from the plan itself.
@immutable
final class GlyphAtlasPersistence {
  /// Persists into [cache], keyed by what [artVersion] and
  /// [devicePixelRatio] say.
  const GlyphAtlasPersistence({
    required this.cache,
    required this.artVersion,
    required this.devicePixelRatio,
  });

  /// Where the pages live between launches.
  final GlyphCacheStore cache;

  /// Tells whether the system emoji art changed since the pages were baked.
  final GlyphArtVersionSource artVersion;

  /// Density of the view the pages are baked for; a changed density discards
  /// the persisted pages.
  final double devicePixelRatio;
}

/// What a persistent atlas decided and how long its circles lasted, for a
/// host that measures the first-run and cold-start flows.
///
/// Times run on the atlas's injected clock from `start()`. A non-persistent
/// atlas has a [verdict] of null and no times.
@immutable
final class GlyphCacheReport {
  /// Creates a report.
  const GlyphCacheReport({
    this.verdict,
    this.restoredPages = 0,
    this.stalePages = 0,
    this.swapped = false,
    this.firstPageAfterStart,
    this.allPagesAfterStart,
  });

  /// How the persisted set related to the key this atlas needs, or null before
  /// it is known (the art version and the cache are still being read) and for
  /// an atlas without persistence.
  final GlyphCacheVerdict? verdict;

  /// Pages of the current plan restored from disk ([GlyphCacheVerdict.hit]).
  final int restoredPages;

  /// Pages of the old set loaded to keep drawing while the new set bakes
  /// ([GlyphCacheVerdict.stale]).
  final int stalePages;

  /// Whether a stale set was replaced by the new one.
  final bool swapped;

  /// From `start()` until the first glyph could be drawn from a page.
  final Duration? firstPageAfterStart;

  /// From `start()` until every page of the plan could be drawn. For a hit
  /// this is the cold-start time circles last; for a first run it is the
  /// bake time.
  final Duration? allPagesAfterStart;

  @override
  String toString() =>
      'GlyphCacheReport($verdict, restored: $restoredPages, '
      'stale: $stalePages, swapped: $swapped, first: $firstPageAfterStart, '
      'all: $allPagesAfterStart)';
}
