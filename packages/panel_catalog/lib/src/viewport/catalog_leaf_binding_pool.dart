import 'package:catalog_assets/catalog_assets.dart';
import 'package:panel_catalog/src/model/catalog_leaf.dart';
import 'package:panel_catalog/src/model/catalog_leaf_presentation.dart';
import 'package:panel_catalog/src/viewport/catalog_slot_projection.dart';

/// Attaches visible leaves to [CatalogAssetCache] and detaches the rest.
///
/// Owns the **binding set** for one catalog render body: which
/// [CatalogAssetKey]s currently hold an attach against the process-wide cache.
/// Does **not** own layout slots, scroll offset, or paint — the render object
/// supplies a content-y window and reads [presentationFor] at paint time.
///
/// ## Recycle contract
///
/// [syncVisible] keeps bindings for leaf slots whose vertical span intersects
/// `[top, bottom]` (inclusive band in content coordinates) and detaches keys
/// that left the band. Header slots are ignored — they have no asset identity.
///
/// The owning render object typically passes the viewport band **plus** one
/// cell of overscan so short drags do not thrash attach/detach every frame.
/// This pool does not invent overscan; it trusts the window it is given.
///
/// ## Presentation projection
///
/// [presentationFor] maps `(leaf kind, readiness)` → exactly one
/// [CatalogLeafPresentation]. Unbound leaves (not yet in [_bindings], or
/// never intersecting the window) are treated as
/// [CatalogAssetReadiness.loading] so paint can still show a placeholder
/// without a null path.
///
/// | Leaf | loading | ready | failed |
/// |------|---------|-------|--------|
/// | [UnicodeCatalogLeaf] | [CatalogLeafPresentation.circlePlaceholder] | [CatalogLeafPresentation.content] | [CatalogLeafPresentation.failed] |
/// | [DocumentCatalogLeaf] | [CatalogLeafPresentation.thumbFirstPlaceholder] | [CatalogLeafPresentation.content] | [CatalogLeafPresentation.failed] |
///
/// ## Lifecycle
///
/// MUST [detachAll] when the owning render object detaches or disposes so
/// cache refcounts fall even if the same [CatalogAssetCache] is shared with
/// another surface. [replaceCache] / [replaceCacheType] detach before swapping;
/// the owner re-syncs (usually from layout) to re-attach the visible band.
///
/// [onReadinessChanged] is registered on every new binding (typically
/// `markNeedsPaint`) so placeholders flip without a full catalog reproject.
final class CatalogLeafBindingPool {
  /// Creates an empty binding pool.
  ///
  /// [onReadinessChanged] fires when any attached binding's readiness
  /// changes. Pass a stable tear-off (e.g. `markNeedsPaint`) — the pool does
  /// not dedup listener registration beyond one listener per binding.
  CatalogLeafBindingPool({
    required CatalogAssetCache assetCache,
    required CatalogAssetCacheType cacheType,
    required void Function() onReadinessChanged,
  }) : _assetCache = assetCache,
       _cacheType = cacheType,
       _onReadinessChanged = onReadinessChanged;

  CatalogAssetCache _assetCache;
  CatalogAssetCacheType _cacheType;
  final void Function() _onReadinessChanged;
  final Map<CatalogAssetKey, CatalogAssetBinding> _bindings = {};

  /// Number of leaves currently retained via asset-cache attach.
  ///
  /// Bounded by the last [syncVisible] window, not by total catalog size.
  int get attachedCount => _bindings.length;

  /// Replaces the cache; detaches every existing binding first.
  ///
  /// Does not re-attach — the owner MUST [syncVisible] (usually after layout)
  /// against the new cache.
  void replaceCache(CatalogAssetCache cache) {
    detachAll();
    _assetCache = cache;
  }

  /// Replaces the attach size class; detaches every existing binding first.
  ///
  /// Does not re-attach — the owner MUST [syncVisible] afterward.
  void replaceCacheType(CatalogAssetCacheType cacheType) {
    detachAll();
    _cacheType = cacheType;
  }

  /// Syncs attaches to leaf slots intersecting `[top, bottom]` in content y.
  ///
  /// Slots with `bottom < top` or `top > bottom` relative to the window are
  /// skipped. Already-attached keys that remain visible are kept (no
  /// re-attach). Keys that left the window are [CatalogAssetBinding.detach]ed
  /// and removed from the map.
  void syncVisible({
    required List<CatalogLayoutSlot> slots,
    required double top,
    required double bottom,
  }) {
    final visibleKeys = <CatalogAssetKey>{};
    for (final slot in slots) {
      if (slot case final CatalogLeafSlot leaf) {
        if (leaf.bottom < top || leaf.top > bottom) continue;
        visibleKeys.add(leaf.leaf.assetKey);
        _ensure(leaf.leaf);
      }
    }
    final stale = [
      for (final key in _bindings.keys)
        if (!visibleKeys.contains(key)) key,
    ];
    for (final key in stale) {
      _bindings.remove(key)?.detach();
    }
  }

  /// Presentation for [leaf], or a loading placeholder when unbound.
  ///
  /// Never returns `null` — unbound means loading-mode for that leaf kind.
  /// Callers that need “key absent from projection” must check slots first.
  CatalogLeafPresentation presentationFor(CatalogLeaf leaf) {
    final readiness =
        _bindings[leaf.assetKey]?.readiness ?? CatalogAssetReadiness.loading;
    return switch ((leaf, readiness)) {
      (UnicodeCatalogLeaf(), CatalogAssetReadiness.ready) =>
        CatalogLeafPresentation.content,
      (UnicodeCatalogLeaf(), CatalogAssetReadiness.failed) =>
        CatalogLeafPresentation.failed,
      (UnicodeCatalogLeaf(), CatalogAssetReadiness.loading) =>
        CatalogLeafPresentation.circlePlaceholder,
      (DocumentCatalogLeaf(), CatalogAssetReadiness.ready) =>
        CatalogLeafPresentation.content,
      (DocumentCatalogLeaf(), CatalogAssetReadiness.failed) =>
        CatalogLeafPresentation.failed,
      (DocumentCatalogLeaf(), CatalogAssetReadiness.loading) =>
        CatalogLeafPresentation.thumbFirstPlaceholder,
    };
  }

  /// Detaches every binding and clears the map.
  ///
  /// Idempotent. Safe during detach/dispose even if [syncVisible] never ran.
  void detachAll() {
    for (final binding in _bindings.values) {
      binding.detach();
    }
    _bindings.clear();
  }

  void _ensure(CatalogLeaf leaf) {
    final key = leaf.assetKey;
    if (_bindings.containsKey(key)) return;
    final binding = _assetCache.attach(key, _cacheType);
    binding.addListener(_onReadinessChanged);
    _bindings[key] = binding;
  }
}
