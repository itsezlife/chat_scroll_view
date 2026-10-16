import 'dart:async';
import 'dart:collection';

import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// Called when a requested key is resolved: with its descriptor, or with null
/// when the host does not know the key, or with an error when the host could
/// not be asked.
@internal
typedef DescriptorWaiter =
    void Function(
      ContentDescriptor? descriptor,
      Object? error,
      StackTrace? stackTrace,
    );

/// What the pipeline knows about content: descriptors the host gave it, and
/// descriptors the host's [ContentResolver] answered for, kept in a bounded
/// least-recently-used map.
///
/// Keys asked for within one turn of the event loop go to the resolver in one
/// batch, and a key already on its way is not asked again, so a screenful of
/// bare keys costs one request. The resolver cannot be cancelled: a waiter
/// that gives up is dropped, and the answer still lands in the map.
///
/// Internal to the pipeline.
@internal
final class DescriptorDirectory {
  /// Creates a directory that keeps [capacity] descriptors and asks
  /// [resolver] for the rest (nothing is resolved without one).
  DescriptorDirectory({required this.capacity, ContentResolver? resolver})
    : _resolver = resolver,
      assert(capacity > 0, 'A directory keeps at least one descriptor.');

  /// How many descriptors are kept.
  final int capacity;

  final ContentResolver? _resolver;
  final LinkedHashMap<ContentKey, ContentDescriptor> _known = LinkedHashMap();
  final Map<ContentKey, List<DescriptorWaiter>> _waiters = {};
  final Set<ContentKey> _unsent = {};
  bool _flushScheduled = false;
  bool _disposed = false;

  /// Whether a resolver is there to ask.
  bool get canResolve => _resolver != null;

  /// Keeps [descriptor], replacing what was known for its key.
  void add(ContentDescriptor descriptor) {
    _known
      ..remove(descriptor.key)
      ..[descriptor.key] = descriptor;
    while (_known.length > capacity) {
      _known.remove(_known.keys.first);
    }
  }

  /// The descriptor known for [key], or null. Counts as a use.
  ContentDescriptor? lookup(ContentKey key) {
    final descriptor = _known.remove(key);
    if (descriptor != null) _known[key] = descriptor;
    return descriptor;
  }

  /// Asks the resolver for [key], calling [waiter] once with the outcome,
  /// never synchronously. Requires [canResolve].
  void resolve(ContentKey key, DescriptorWaiter waiter) {
    assert(canResolve, 'resolve needs a ContentResolver');
    final waiting = _waiters[key];
    if (waiting == null) {
      _waiters[key] = [waiter];
      _unsent.add(key);
    } else {
      waiting.add(waiter);
    }
    if (_flushScheduled) return;
    _flushScheduled = true;
    scheduleMicrotask(_flush);
  }

  /// Drops [waiter]; it is not called afterwards.
  void cancel(ContentKey key, DescriptorWaiter waiter) {
    final waiting = _waiters[key];
    if (waiting == null) return;
    waiting.remove(waiter);
    if (waiting.isEmpty) {
      _waiters.remove(key);
      _unsent.remove(key);
    }
  }

  /// Forgets everything and stops answering.
  void dispose() {
    _disposed = true;
    _known.clear();
    _waiters.clear();
    _unsent.clear();
  }

  void _flush() {
    _flushScheduled = false;
    if (_disposed || _unsent.isEmpty) return;
    final keys = List<ContentKey>.of(_unsent);
    _unsent.clear();
    unawaited(_ask(keys));
  }

  Future<void> _ask(List<ContentKey> keys) async {
    Map<ContentKey, ContentDescriptor> found;
    try {
      found = await _resolver!.resolve(keys);
    } on Object catch (error, stackTrace) {
      _answer(keys, null, error, stackTrace);
      return;
    }
    if (_disposed) return;
    found.values.forEach(add);
    _answer(keys, found, null, null);
  }

  void _answer(
    List<ContentKey> keys,
    Map<ContentKey, ContentDescriptor>? found,
    Object? error,
    StackTrace? stackTrace,
  ) {
    for (final key in keys) {
      final waiting = _waiters.remove(key);
      if (waiting == null) continue;
      for (final waiter in waiting) {
        waiter(found?[key], error, stackTrace);
      }
    }
  }
}
