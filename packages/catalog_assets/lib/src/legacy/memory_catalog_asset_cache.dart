import 'package:catalog_assets/src/asset/asset_binding.dart';
import 'package:catalog_assets/src/asset/asset_cache_scope.dart';
import 'package:catalog_assets/src/asset/asset_profile.dart';
import 'package:catalog_assets/src/asset/asset_spec.dart';
import 'package:catalog_assets/src/atlas/atlas_sprite.dart';
import 'package:catalog_assets/src/atlas/glyph_atlas.dart';
import 'package:catalog_assets/src/legacy/catalog_asset_binding.dart';
import 'package:catalog_assets/src/legacy/catalog_asset_cache.dart';
import 'package:catalog_assets/src/legacy/catalog_asset_cache_type.dart';
import 'package:catalog_assets/src/legacy/catalog_asset_key.dart';
import 'package:catalog_assets/src/legacy/catalog_asset_readiness.dart';
import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// TEMPORARY SHIM, deleted with the migration of `panel_catalog` and
/// `chat_chrome` to `AssetCacheScope`: the readiness-flag cache the catalogue
/// viewport and the keyboard panel still talk to.
///
/// Readiness is a driven flag as before ([markReady] / [markFailed]; nothing
/// is fetched here). The baked-glyph half is not legacy any more: with a
/// [glyphAtlas], unicode bindings attach through an `AssetCacheScope` that
/// has the atlas registered as its glyph source, so the sprite, the page hold
/// taken at attach and given back at detach, and the page signal all come from
/// the real glyph media form. The shim keeps the old surface on top of it:
///
/// - [isRetained] is true while at least one [CatalogAssetBinding] is live.
/// - After the last detach, ready / failed entries stay (so a surface that
///   re-attaches does not flash loading) and loading-only entries are dropped.
/// - [evict] and [clear] drop entries and leave the holds of live bindings
///   alone: the counts belong to the bindings.
final class MemoryCatalogAssetCache implements CatalogAssetCache {
  /// Creates a cache; pass [glyphAtlas] on platforms that bake glyphs.
  MemoryCatalogAssetCache({this.glyphAtlas})
    : _scope = AssetCacheScope(glyphSource: glyphAtlas);

  @override
  final GlyphAtlas? glyphAtlas;

  final AssetCacheScope _scope;
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
      glyph: switch (key) {
        UnicodeCatalogAssetKey(:final glyph) when glyphAtlas != null =>
          _scope.attach(
            ContentKey.unicode(glyph),
            _specOf(cacheType),
            const AssetProfile(),
          ),
        _ => null,
      },
    );
    _live.add(binding);
    return binding;
  }

  // The glyph form ignores the spec (the atlas has one glyph size); the two
  // old cache types only need to stay distinct.
  static AssetSpec _specOf(CatalogAssetCacheType cacheType) =>
      switch (cacheType) {
        CatalogAssetCacheType.keyboard => const AssetSpec(
          pixelWidth: 72,
          pixelHeight: 72,
        ),
        CatalogAssetCacheType.messages => const AssetSpec(
          pixelWidth: 36,
          pixelHeight: 36,
        ),
      };

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

  /// Gives back the page holds of the bindings still live, so a cache that
  /// goes away never pins pages. The atlas itself is the host's to dispose.
  /// Idempotent.
  void dispose() {
    _scope.dispose();
    for (final binding in List<_Binding>.of(_live)) {
      binding.releaseGlyph();
    }
    _live.clear();
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

/// Deterministic in-memory cache for widget and unit tests: the same
/// attach / refcount / readiness API, driven by [MemoryCatalogAssetCache.markReady]
/// and [MemoryCatalogAssetCache.markFailed].
typedef FakeCatalogAssetCache = MemoryCatalogAssetCache;

@immutable
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
    required AssetBinding? glyph,
  }) : _cache = cache,
       _id = id,
       _entry = entry,
       _glyph = glyph;

  final MemoryCatalogAssetCache _cache;
  final _EntryId _id;
  final _Entry _entry;
  final List<void Function()> _listeners = [];
  final AssetBinding? _glyph;
  bool _detached = false;

  /// Detaches the underlying glyph binding (idempotent: it gives its hold
  /// back once).
  void releaseGlyph() => _glyph?.detach();

  @override
  CatalogAssetKey get key => _id.key;

  @override
  CatalogAssetCacheType get cacheType => _id.cacheType;

  @override
  CatalogAssetReadiness get readiness => _entry.readiness;

  @override
  AtlasSprite? get sprite => _glyph?.paintable.sprite;

  @override
  void addListener(void Function() listener) {
    if (_detached) {
      return;
    }
    _listeners.add(listener);
    _entry.listeners.add(listener);
    _glyph?.addListener(listener);
  }

  @override
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
    _entry.listeners.remove(listener);
    _glyph?.removeListener(listener);
  }

  @override
  void detach() {
    if (_detached) {
      return;
    }
    _detached = true;
    _listeners.forEach(_entry.listeners.remove);
    _listeners.clear();
    releaseGlyph();
    _cache._detach(this, _id, _entry);
  }
}
