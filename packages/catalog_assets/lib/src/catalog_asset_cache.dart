import 'package:catalog_assets/src/catalog_asset_binding.dart';
import 'package:catalog_assets/src/catalog_asset_cache_type.dart';
import 'package:catalog_assets/src/catalog_asset_key.dart';

/// Process-wide global catalog asset cache.
///
/// Host surfaces bind and paint through this API. Fetch orchestration lives in
/// the catalog data source (or host), not inside a scroll viewport.
abstract interface class CatalogAssetCache {
  /// Attaches [key] at [cacheType], retaining the entry while bound.
  CatalogAssetBinding attach(
    CatalogAssetKey key,
    CatalogAssetCacheType cacheType,
  );

  /// Whether any surface currently retains [key] at [cacheType].
  bool isRetained(CatalogAssetKey key, CatalogAssetCacheType cacheType);
}
