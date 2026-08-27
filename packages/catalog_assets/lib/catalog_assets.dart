/// Process-wide global catalog asset cache for catalog and chat leaves.
///
/// Callers bind by key and cache type, observe leaf readiness, and
/// attach/detach. Ready/failed entries survive the last detach so pager
/// keep-alive leave/return does not flash loading; [isRetained] still tracks
/// live surface binds. Fetch orchestration stays outside this package.
library;

export 'src/catalog_asset_binding.dart';
export 'src/catalog_asset_cache.dart';
export 'src/catalog_asset_cache_type.dart';
export 'src/catalog_asset_key.dart';
export 'src/catalog_asset_readiness.dart';
export 'src/fake_catalog_asset_cache.dart';
export 'src/memory_catalog_asset_cache.dart';
