import 'package:catalog_assets/src/atlas/atlas_sprite.dart';
import 'package:catalog_assets/src/atlas/glyph_atlas.dart';
import 'package:catalog_assets/src/atlas/glyph_page_residency.dart';
import 'package:catalog_assets/src/catalog_asset_binding.dart';
import 'package:catalog_assets/src/catalog_asset_cache.dart';
import 'package:catalog_assets/src/catalog_asset_cache_type.dart';
import 'package:catalog_assets/src/catalog_asset_key.dart';
import 'package:catalog_assets/src/catalog_asset_readiness.dart';

/// In-memory [CatalogAssetCache] with attach refcounting and driven readiness.
///
/// Suitable as a process-local skeleton and as a deterministic fake for tests:
/// callers (or tests) set readiness via [markReady] / [markFailed]; this class
/// does not perform fetch/decode.
///
/// ## Retention
///
/// [isRetained] is true while at least one [CatalogAssetBinding] is live.
/// After the last [CatalogAssetBinding.detach]:
/// - **ready / failed** entries stay in the map so a surface that re-attaches
///   (pager keep-alive leave/return) does not flash [CatalogAssetReadiness.loading]
/// - **loading** entries with zero attaches are dropped (abandoned fetch)
///
/// Call [evict] / [clear] for explicit memory pressure. LRU eviction is not
/// implemented yet.
///
/// ## Baked glyphs
///
/// With a [glyphAtlas], unicode bindings resolve [CatalogAssetBinding.sprite]
/// from it, and every binding listener is told when a page of the atlas
/// becomes drawable, so a surface repaints the cells that were placeholders.
/// The cache listens to the atlas until [dispose]; it does not own the atlas.
///
/// ## Page holds
///
/// A unicode binding **holds the atlas page its glyph is on** from attach to
/// detach, so the page stays resident while any surface is bound to it (the
/// atlas keeps every page while its panel is open, and for its retention
/// after). The hold is a count taken by the binding, not by the entry: [evict]
/// and [clear] drop entries and leave the holds of live bindings alone, and a
/// binding gives back exactly what it took, once. The pixels stay with the
/// atlas; a binding reads [CatalogAssetBinding.sprite] when it paints.
final class MemoryCatalogAssetCache implements CatalogAssetCache {
  /// Creates a cache; pass [glyphAtlas] on platforms that bake glyphs.
  MemoryCatalogAssetCache({this.glyphAtlas}) {
    glyphAtlas?.addPageListener(_onPageBaked);
  }

  @override
  final GlyphAtlas? glyphAtlas;

  final Map<_EntryId, _Entry> _entries = {};
  final Set<_Binding> _live = {};

  @override
  CatalogAssetBinding attach(
    CatalogAssetKey key,
    CatalogAssetCacheType cacheType,
  ) {
    final id = _EntryId(key, cacheType);
    final entry = _entries.putIfAbsent(id, _Entry.new);
    entry.attachCount += 1;
    final binding = _Binding(
      cache: this,
      id: id,
      entry: entry,
      pageHold: switch (key) {
        UnicodeCatalogAssetKey(:final glyph) => glyphAtlas?.holdPageOf(glyph),
        DocumentCatalogAssetKey() => null,
      },
    );
    _live.add(binding);
    return binding;
  }

  @override
  bool isRetained(CatalogAssetKey key, CatalogAssetCacheType cacheType) {
    final entry = _entries[_EntryId(key, cacheType)];
    return entry != null && entry.attachCount > 0;
  }

  /// Marks [key] at [cacheType] ready and notifies listeners.
  void markReady(CatalogAssetKey key, CatalogAssetCacheType cacheType) {
    _setReadiness(key, cacheType, CatalogAssetReadiness.ready);
  }

  /// Marks [key] at [cacheType] failed and notifies listeners.
  void markFailed(CatalogAssetKey key, CatalogAssetCacheType cacheType) {
    _setReadiness(key, cacheType, CatalogAssetReadiness.failed);
  }

  @override
  CatalogAssetReadiness? readinessOf(
    CatalogAssetKey key,
    CatalogAssetCacheType cacheType,
  ) => _entries[_EntryId(key, cacheType)]?.readiness;

  /// Drops the entry for [key] at [cacheType] regardless of attach count.
  ///
  /// Live bindings keep observing the removed entry's last readiness until
  /// they [CatalogAssetBinding.detach]; prefer detaching surfaces first.
  void evict(CatalogAssetKey key, CatalogAssetCacheType cacheType) {
    _entries.remove(_EntryId(key, cacheType));
  }

  /// Drops every entry. Same live-binding caveat as [evict].
  void clear() => _entries.clear();

  /// Stops listening to [glyphAtlas] and gives back the page holds of the
  /// bindings still live, so a cache that goes away never pins pages. The atlas
  /// itself is the host's to dispose. Idempotent.
  void dispose() {
    glyphAtlas?.removePageListener(_onPageBaked);
    for (final binding in List<_Binding>.of(_live)) {
      binding.releasePage();
    }
    _live.clear();
  }

  void _onPageBaked(int pageIndex) {
    // Every binding with a listener: the cells of one page are not tracked per
    // entry, and a listener is a repaint request, which is idempotent.
    for (final entry in List<_Entry>.of(_entries.values)) {
      entry.notify();
    }
  }

  void _setReadiness(
    CatalogAssetKey key,
    CatalogAssetCacheType cacheType,
    CatalogAssetReadiness readiness,
  ) {
    final id = _EntryId(key, cacheType);
    final entry = _entries.putIfAbsent(id, _Entry.new);
    if (entry.readiness == readiness) {
      return;
    }
    entry.readiness = readiness;
    entry.notify();
  }

  // A binding releases the entry it attached to, never whatever the map holds
  // under its key now: after an evict or clear that is a newer entry with
  // other bindings, and decrementing it would unretain a live surface.
  void _detach(_Binding binding, _EntryId id, _Entry entry) {
    _live.remove(binding);
    entry.attachCount -= 1;
    if (entry.attachCount > 0) {
      return;
    }
    // Keep settled readiness for re-attach; drop abandoned loads only.
    if (entry.readiness == CatalogAssetReadiness.loading &&
        identical(_entries[id], entry)) {
      _entries.remove(id);
    }
  }
}

final class _EntryId {
  const _EntryId(this.key, this.cacheType);

  final CatalogAssetKey key;
  final CatalogAssetCacheType cacheType;

  @override
  bool operator ==(Object other) =>
      other is _EntryId && other.key == key && other.cacheType == cacheType;

  @override
  int get hashCode => Object.hash(key, cacheType);
}

final class _Entry {
  CatalogAssetReadiness readiness = CatalogAssetReadiness.loading;
  int attachCount = 0;
  final List<void Function()> listeners = [];

  void notify() {
    for (final listener in List<void Function()>.of(listeners)) {
      listener();
    }
  }
}

final class _Binding implements CatalogAssetBinding {
  _Binding({
    required MemoryCatalogAssetCache cache,
    required _EntryId id,
    required _Entry entry,
    required GlyphPageHold? pageHold,
  }) : _cache = cache,
       _id = id,
       _entry = entry,
       _pageHold = pageHold;

  final MemoryCatalogAssetCache _cache;
  final _EntryId _id;
  final _Entry _entry;
  final List<void Function()> _listeners = [];
  final GlyphPageHold? _pageHold;
  bool _detached = false;

  /// Gives the page hold back (idempotent: a hold releases once).
  void releasePage() => _pageHold?.release();

  @override
  CatalogAssetKey get key => _id.key;

  @override
  CatalogAssetCacheType get cacheType => _id.cacheType;

  @override
  CatalogAssetReadiness get readiness => _entry.readiness;

  @override
  AtlasSprite? get sprite => switch (_id.key) {
    UnicodeCatalogAssetKey(:final glyph) => _cache.glyphAtlas?.spriteOf(glyph),
    DocumentCatalogAssetKey() => null,
  };

  @override
  void addListener(void Function() listener) {
    if (_detached) {
      return;
    }
    _listeners.add(listener);
    _entry.listeners.add(listener);
  }

  @override
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
    _entry.listeners.remove(listener);
  }

  @override
  void detach() {
    if (_detached) {
      return;
    }
    _detached = true;
    for (final listener in _listeners) {
      _entry.listeners.remove(listener);
    }
    _listeners.clear();
    releasePage();
    _cache._detach(this, _id, _entry);
  }
}
