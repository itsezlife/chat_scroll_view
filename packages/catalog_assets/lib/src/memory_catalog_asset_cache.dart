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
/// **Retention**: an entry is kept while [CatalogAssetBinding.detach] has not
/// dropped the last attach. After the last detach, the entry is removed.
final class MemoryCatalogAssetCache implements CatalogAssetCache {
  final Map<_EntryId, _Entry> _entries = {};

  @override
  CatalogAssetBinding attach(
    CatalogAssetKey key,
    CatalogAssetCacheType cacheType,
  ) {
    final id = _EntryId(key, cacheType);
    final entry = _entries.putIfAbsent(id, _Entry.new);
    entry.attachCount += 1;
    return _Binding(cache: this, id: id, entry: entry);
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

  /// Current readiness when an entry is present; otherwise `null`.
  CatalogAssetReadiness? readinessOf(
    CatalogAssetKey key,
    CatalogAssetCacheType cacheType,
  ) =>
      _entries[_EntryId(key, cacheType)]?.readiness;

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

  void _detach(_EntryId id) {
    final entry = _entries[id];
    if (entry == null) {
      return;
    }
    entry.attachCount -= 1;
    if (entry.attachCount <= 0) {
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
  })  : _cache = cache,
        _id = id,
        _entry = entry;

  final MemoryCatalogAssetCache _cache;
  final _EntryId _id;
  final _Entry _entry;
  final List<void Function()> _listeners = [];
  bool _detached = false;

  @override
  CatalogAssetKey get key => _id.key;

  @override
  CatalogAssetCacheType get cacheType => _id.cacheType;

  @override
  CatalogAssetReadiness get readiness => _entry.readiness;

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
    _cache._detach(_id);
  }
}
