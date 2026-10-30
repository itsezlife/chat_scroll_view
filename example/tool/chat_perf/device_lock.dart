/// Per-device exclusivity between runs started through the runner (spec 9).
library;

/// Atomic named locks; the runner backs it with directories, tests with a map.
abstract interface class LockStore {
  /// Creates [key] holding [owner]; false when it already exists.
  bool tryCreate(String key, String owner);

  String? owner(String key);

  void delete(String key);
}

final class DeviceLockedException implements Exception {
  const DeviceLockedException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class DeviceLock {
  const DeviceLock._(this._store, this._key);

  /// Takes the lock for [deviceId] or throws [DeviceLockedException] naming
  /// the holder.
  factory DeviceLock.acquire(
    LockStore store,
    String deviceId, {
    required String owner,
  }) {
    final key = 'chat-perf-$deviceId';
    if (!store.tryCreate(key, owner)) {
      throw DeviceLockedException(
        'device $deviceId is locked by ${store.owner(key) ?? 'another run'}; '
        'wait for it, or remove the lock "$key" if that run is gone',
      );
    }
    return DeviceLock._(store, key);
  }

  final LockStore _store;
  final String _key;

  void release() => _store.delete(_key);
}
