/// Process-wide global catalog asset cache for catalog and chat leaves.
///
/// Callers bind by key and cache type, observe leaf readiness, and
/// attach/detach so entries are retained while a surface is bound.
/// Fetch orchestration stays outside this package.
library;

export 'src/catalog_asset_binding.dart';
export 'src/catalog_asset_cache.dart';
export 'src/catalog_asset_cache_type.dart';
export 'src/catalog_asset_key.dart';
export 'src/catalog_asset_readiness.dart';
export 'src/fake_catalog_asset_cache.dart';
export 'src/memory_catalog_asset_cache.dart';
