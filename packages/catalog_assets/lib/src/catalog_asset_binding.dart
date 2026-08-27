import 'package:catalog_assets/src/catalog_asset_cache_type.dart';
import 'package:catalog_assets/src/catalog_asset_key.dart';
import 'package:catalog_assets/src/catalog_asset_readiness.dart';

/// A live attach to one cache entry.
///
/// Surfaces observe [readiness] and call [detach] when unbound so the
/// process-wide cache can reclaim the entry.
abstract interface class CatalogAssetBinding {
  /// Bound asset identity.
  CatalogAssetKey get key;

  /// Size class this attach uses.
  CatalogAssetCacheType get cacheType;

  /// Current leaf readiness.
  CatalogAssetReadiness get readiness;

  /// Registers [listener] for readiness changes.
  void addListener(void Function() listener);

  /// Removes a previously registered [listener].
  void removeListener(void Function() listener);

  /// Decrements the attach refcount for this entry.
  ///
  /// MUST unregister this binding's readiness listeners. After detach, further
  /// [addListener] calls are ignored.
  void detach();
}
