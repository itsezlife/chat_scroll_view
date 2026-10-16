/// Keeps the future of a read per key while it runs and after it succeeded,
/// and forgets one that failed so that the next call tries again.
final class CachedFutures<K, T> {
  final Map<K, Future<T>> _cache = {};

  /// The future of [key], starting [read] when there is none.
  Future<T> of(K key, Future<T> Function() read) {
    if (_cache[key] case final running?) return running;
    final future = _cache[key] = read();
    // The handler must not return the removed future: it would be adopted,
    // and its error would surface again as unhandled.
    future.then<void>(
      (_) {},
      onError: (Object _) {
        _cache.remove(key);
      },
    );
    return future;
  }
}
