import 'package:catalog_assets/src/atlas/atlas_sprite.dart';
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

  /// The asset as a baked sprite, or null when it has none (yet).
  ///
  /// The optional sprite capability of what this binding paints: a surface
  /// that finds a sprite draws it, batched with the others of its page; one
  /// that does not paints the asset itself. A unicode glyph on a platform that
  /// bakes has one once its page is baked and none before, so null there means
  /// "show the placeholder", not "paint the glyph as text". Read it when
  /// painting, never keep it: the page behind it can go away.
  AtlasSprite? get sprite;

  /// Registers [listener] for readiness changes and for [sprite] appearing.
  void addListener(void Function() listener);

  /// Removes a previously registered [listener].
  void removeListener(void Function() listener);

  /// Decrements the attach refcount for this entry.
  ///
  /// MUST unregister this binding's readiness listeners. After detach, further
  /// [addListener] calls are ignored.
  void detach();
}
