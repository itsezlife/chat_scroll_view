import 'package:catalog_assets/src/memory_catalog_asset_cache.dart';

/// Deterministic in-memory cache for widget and unit tests.
///
/// Same attach/refcount/readiness API as [MemoryCatalogAssetCache]; tests
/// drive [MemoryCatalogAssetCache.markReady] / [markFailed] instead of fetch.
typedef FakeCatalogAssetCache = MemoryCatalogAssetCache;
