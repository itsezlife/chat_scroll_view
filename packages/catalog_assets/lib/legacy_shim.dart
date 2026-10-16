/// TEMPORARY SHIM: the readiness-flag cache API that `panel_catalog` and
/// `chat_chrome` still use, kept alive on top of the new core so the tree
/// stays green while they migrate. Deleted by the migration of those two
/// packages (`panel_catalog` binds through `AssetCacheScope`; `chat_chrome`
/// goes away). New code must not import it.
library;

export 'src/legacy/catalog_asset_binding.dart';
export 'src/legacy/catalog_asset_cache.dart';
export 'src/legacy/catalog_asset_cache_type.dart';
export 'src/legacy/catalog_asset_key.dart';
export 'src/legacy/catalog_asset_readiness.dart';
export 'src/legacy/memory_catalog_asset_cache.dart';
