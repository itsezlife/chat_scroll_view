import 'package:catalog_assets/src/atlas/glyph_atlas.dart';
import 'package:catalog_assets/src/catalog_asset_binding.dart';
import 'package:catalog_assets/src/catalog_asset_cache_type.dart';
import 'package:catalog_assets/src/catalog_asset_key.dart';
import 'package:catalog_assets/src/catalog_asset_readiness.dart';

/// Process-wide global catalog asset cache.
///
/// Host surfaces bind and paint through this API. Fetch orchestration lives in
/// the catalog data source (or host), not inside a scroll viewport.
abstract interface class CatalogAssetCache {
  /// The baked glyphs unicode bindings draw from, or null on a platform that
  /// does not bake (its surfaces draw glyphs as text).
  ///
  /// Surfaces also use it to keep the bake out of their way: they report
  /// scrolling and what is on screen through it.
  GlyphAtlas? get glyphAtlas;

  /// Attaches [key] at [cacheType], retaining the entry while bound.
  CatalogAssetBinding attach(
    CatalogAssetKey key,
    CatalogAssetCacheType cacheType,
  );

  /// Whether any surface currently retains [key] at [cacheType].
  ///
  /// `false` after the last [CatalogAssetBinding.detach] even when the cache
  /// still holds a ready/failed entry for a later re-attach.
  bool isRetained(CatalogAssetKey key, CatalogAssetCacheType cacheType);

  /// Last known readiness for [key] at [cacheType], or `null` when absent.
  ///
  /// Ready/failed entries MAY survive zero attaches so pager keep-alive
  /// leave/return does not flash loading. Loading-only orphans are dropped.
  CatalogAssetReadiness? readinessOf(
    CatalogAssetKey key,
    CatalogAssetCacheType cacheType,
  );
}
