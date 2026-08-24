import 'package:catalog_assets/catalog_assets.dart';
import 'package:panel_catalog/src/debug/panel_catalog_dev_log.dart';
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
/// [CatalogLeafPresentation]. Readiness comes from the live binding, else
/// [CatalogAssetCache.readinessOf] (settled entries survive zero attaches),
/// else loading.
///
/// **Unicode** glyphs paint from paragraph cache — no async asset decode.
/// Unbound / loading unicode therefore resolves to
/// [CatalogLeafPresentation.content] (not a circle). Circles only appear for
/// unicode when the host has marked the key [CatalogAssetReadiness.failed].
///
/// **Document** leaves use loading placeholders when still loading. Ready
/// document entries retained in the cache after [detachAll] still resolve to
/// [CatalogLeafPresentation.content] while unbound so pager leave/return does
/// not flash thumbs.
///
/// | Leaf | loading / unbound (no settled cache) | ready | failed |
/// |------|--------------------------------------|-------|--------|
/// | [UnicodeCatalogLeaf] | [CatalogLeafPresentation.content] | [CatalogLeafPresentation.content] | [CatalogLeafPresentation.failed] |
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
  static final PanelCatalogDevLog _log = PanelCatalogDevLog(
    'PanelCatalogBinding',
    enabled: true,
  );

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
  /// [pinnedKeys] are kept attached even when outside the window — used during
  /// far-path stitch so outgoing strip bindings survive the teleport.
  ///
  /// Slots with `bottom < top` or `top > bottom` relative to the window are
  /// skipped. Already-attached keys that remain visible are kept (no
  /// re-attach). Keys that left the window are [CatalogAssetBinding.detach]ed
  /// and removed from the map unless listed in [pinnedKeys].
  void syncVisible({
    required List<CatalogLayoutSlot> slots,
    required double top,
    required double bottom,
    Set<CatalogAssetKey>? pinnedKeys,
  }) {
    final visibleKeys = <CatalogAssetKey>{...?pinnedKeys};
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
    if (_log.enabled && (visibleKeys.isNotEmpty || stale.isNotEmpty)) {
      var ready = 0;
      var loading = 0;
      var failed = 0;
      for (final binding in _bindings.values) {
        switch (binding.readiness) {
          case CatalogAssetReadiness.ready:
            ready++;
          case CatalogAssetReadiness.loading:
            loading++;
          case CatalogAssetReadiness.failed:
            failed++;
        }
      }
      _log.event('sync', {
        'winTop': DevLogFormat.f(top),
        'winBot': DevLogFormat.f(bottom),
        'visible': visibleKeys.length,
        'attached': _bindings.length,
        'detached': stale.length,
        'ready': ready,
        'loading': loading,
        'failed': failed,
      });
    }
  }

  /// Presentation for [leaf], never `null`.
  ///
  /// Resolves readiness from the live binding when attached, otherwise from
  /// [CatalogAssetCache.readinessOf] so ready/failed cache entries that
  /// survived [detachAll] (pager keep-alive) do not flash loading placeholders.
  /// Absent cache entries are treated as loading.
  ///
  /// Unicode glyphs do not wait on decode bytes — unbound/loading unicode is
  /// [CatalogLeafPresentation.content]. Document leaves use a kind-specific
  /// loading placeholder when still loading.
  CatalogLeafPresentation presentationFor(CatalogLeaf leaf) {
    final readiness =
        _bindings[leaf.assetKey]?.readiness ??
        _assetCache.readinessOf(leaf.assetKey, _cacheType) ??
        CatalogAssetReadiness.loading;
    return switch ((leaf, readiness)) {
      (UnicodeCatalogLeaf(), CatalogAssetReadiness.failed) =>
        CatalogLeafPresentation.failed,
      (UnicodeCatalogLeaf(), _) => CatalogLeafPresentation.content,
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
    // Unicode cells paint from cached paragraphs — no async decode. Mark ready
    // on attach so hosts that never call markReady still resolve content.
    if (_assetCache case final MemoryCatalogAssetCache memory
        when leaf is UnicodeCatalogLeaf) {
      memory.markReady(key, _cacheType);
    }
    final binding = _assetCache.attach(key, _cacheType);
    binding.addListener(_onReadinessChanged);
    _bindings[key] = binding;
  }
}
