import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/legacy_shim.dart';
import 'package:content_model/content_model.dart';
import 'package:panel_catalog/src/model/catalog_leaf.dart';
import 'package:panel_catalog/src/util/constants.dart';
import 'package:panel_catalog/src/util/logger.dart';
import 'package:panel_catalog/src/viewport/catalog_cell_paint.dart';
import 'package:panel_catalog/src/viewport/catalog_slot_projection.dart';

/// The legacy cache key of a leaf's content.
///
/// Interim: the asset-cache scope that replaces [CatalogAssetCache] is keyed by
/// [ContentKey] directly, which removes this mapping. A unicode key is the
/// glyph itself; any other key is a document id (an external key by its
/// encoding, so it cannot collide with a document id).
extension CatalogLeafLegacyKey on CatalogLeaf {
  /// The key this leaf's binding is held under in the legacy cache.
  CatalogAssetKey get legacyAssetKey => switch (key) {
    ContentKey$Unicode(:final sequence) => CatalogAssetKey.unicode(sequence),
    ContentKey$Document(:final id) => CatalogAssetKey.document(id),
    final ContentKey$External external => CatalogAssetKey.document(
      external.encoded,
    ),
  };

  /// Whether this leaf is a unicode glyph (baked or drawn as text) rather than
  /// document-backed media.
  bool get isUnicodeGlyph => key is ContentKey$Unicode;
}

/// Attaches visible leaves to [CatalogAssetCache] and detaches the rest.
///
/// Owns the **binding set** for one catalog render body: which
/// [CatalogAssetKey]s currently hold an attach against the process-wide cache.
/// Does **not** own layout slots, scroll offset, or paint — the render object
/// supplies a content-y window and reads [paintFor] at paint time.
///
/// ## Recycle contract
///
/// [syncVisible] keeps bindings for the leaf slots in the index range the owner
/// resolved for its content-y band and detaches keys that left it. Header slots are ignored — they have no asset identity.
///
/// The owning render object typically passes the viewport band **plus** one
/// cell of overscan so short drags do not thrash attach/detach every frame.
/// This pool does not invent overscan; it trusts the window it is given.
///
/// ## Paint projection
///
/// [paintFor] maps `(leaf facts, readiness)` → exactly one
/// [CatalogCellPaint]. Readiness comes from the live binding, else
/// [CatalogAssetCache.readinessOf] (settled entries survive zero attaches),
/// else loading.
///
/// **Unicode** glyphs depend on how the cache draws them. With a
/// [CatalogAssetCache.glyphAtlas] (platforms that bake emoji) a glyph is
/// content only once its binding has a sprite; until then it is the
/// [CatalogCellPaint.circle], never text, and it flips to content when the
/// atlas page lands (the binding's listener fires). Without an atlas (the web)
/// glyphs paint from a paragraph cache, so unbound / loading unicode is
/// [CatalogCellPaint.content] and the circle appears only through
/// [CatalogCellPaint.failed] when the host has marked the key
/// [CatalogAssetReadiness.failed].
///
/// **Document** leaves use the stand-in their descriptor facts name
/// ([CatalogLeaf.placeholderStyle]: a sticker is a wash, other media the
/// thumbnail silhouette) when still loading. Ready document entries retained
/// in the cache after [detachAll] still resolve to [CatalogCellPaint.content]
/// while unbound so pager leave/return does not flash thumbs.
///
/// | Leaf | loading / unbound (no settled cache) | ready | failed |
/// |------|--------------------------------------|-------|--------|
/// | unicode, atlas | [CatalogCellPaint.circle] until it has a sprite, then [CatalogCellPaint.content] | same | [CatalogCellPaint.failed] |
/// | unicode, no atlas | [CatalogCellPaint.content] | [CatalogCellPaint.content] | [CatalogCellPaint.failed] |
/// | other | [CatalogCellPaint.thumb] / [CatalogCellPaint.wash] | [CatalogCellPaint.content] | [CatalogCellPaint.failed] |
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

  /// The cache's baked glyphs, or null where glyphs are drawn as text.
  GlyphAtlas? get glyphAtlas => _assetCache.glyphAtlas;

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

  /// Syncs attaches to the leaf slots in `slots[start, end)`.
  ///
  /// The caller resolves the index range for its content-y window (binary
  /// search over the ascending [slots]) so this walk is proportional to the
  /// visible band, never to the catalogue. The range is trusted: every leaf in
  /// it is kept attached, so it MUST NOT include slots outside the intended
  /// window. Header slots in the range are ignored.
  ///
  /// [pinnedKeys] are kept attached even when outside the window — used during
  /// far-path stitch so outgoing strip bindings survive the teleport.
  ///
  /// Already-attached keys that remain in the range are kept (no re-attach).
  /// Keys that left it are [CatalogAssetBinding.detach]ed and removed from the
  /// map unless listed in [pinnedKeys]. [top] / [bottom] are the window the
  /// range was resolved for; they feed diagnostics only.
  void syncVisible({
    required List<CatalogLayoutSlot> slots,
    required int start,
    required int end,
    required double top,
    required double bottom,
    Set<CatalogAssetKey>? pinnedKeys,
  }) {
    final visibleKeys = <CatalogAssetKey>{...?pinnedKeys};
    for (var i = start; i < end; i++) {
      if (slots[i] case final CatalogLeafSlot leaf) {
        visibleKeys.add(leaf.leaf.legacyAssetKey);
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
    if (LogCategory.binding.enabled &&
        (visibleKeys.isNotEmpty || stale.isNotEmpty)) {
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
      fine(.binding, 'sync', {
        'winTop': LogFormat.f(top),
        'winBot': LogFormat.f(bottom),
        'visible': visibleKeys.length,
        'attached': _bindings.length,
        'detached': stale.length,
        'ready': ready,
        'loading': loading,
        'failed': failed,
      });
    }
  }

  /// The baked glyph of [leaf], or null when it has none (not bound, a
  /// document leaf, a platform that bakes nothing, or a page not baked yet).
  ///
  /// Read at paint time and not kept: the page behind a sprite can go away
  /// with its atlas.
  AtlasSprite? spriteFor(CatalogLeaf leaf) =>
      _bindings[leaf.legacyAssetKey]?.sprite;

  /// What to draw for [leaf], never `null`.
  ///
  /// Resolves readiness from the live binding when attached, otherwise from
  /// [CatalogAssetCache.readinessOf] so ready/failed cache entries that
  /// survived [detachAll] (pager keep-alive) do not flash loading placeholders.
  /// Absent cache entries are treated as loading.
  ///
  /// Unicode glyphs do not wait on decode bytes, but where they are baked they
  /// wait for their sprite: see the class table. Other leaves use the
  /// placeholder their facts name while still loading.
  CatalogCellPaint paintFor(CatalogLeaf leaf) {
    final key = leaf.legacyAssetKey;
    final readiness =
        _bindings[key]?.readiness ??
        _assetCache.readinessOf(key, _cacheType) ??
        CatalogAssetReadiness.loading;
    if (readiness == CatalogAssetReadiness.failed) {
      return CatalogCellPaint.failed;
    }
    if (leaf.isUnicodeGlyph) {
      return glyphAtlas == null || spriteFor(leaf) != null
          ? CatalogCellPaint.content
          : CatalogCellPaint.circle;
    }
    if (readiness == CatalogAssetReadiness.ready) {
      return CatalogCellPaint.content;
    }
    return switch (leaf.placeholderStyle) {
      CatalogPlaceholderStyle.shapedWash => CatalogCellPaint.wash,
      CatalogPlaceholderStyle.circle ||
      CatalogPlaceholderStyle.thumbFirst => CatalogCellPaint.thumb,
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
    final key = leaf.legacyAssetKey;
    if (_bindings.containsKey(key)) return;
    // Unicode cells need no async decode (paragraph or baked sprite). Mark
    // ready on attach so hosts that never call markReady still resolve content;
    // whether a baked glyph has its sprite yet is the sprite's business, not
    // readiness'.
    if (_assetCache case final MemoryCatalogAssetCache memory
        when leaf.isUnicodeGlyph) {
      memory.markReady(key, _cacheType);
    }
    final binding = _assetCache.attach(key, _cacheType);
    binding.addListener(_onReadinessChanged);
    _bindings[key] = binding;
  }
}
