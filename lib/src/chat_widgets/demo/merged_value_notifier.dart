import 'package:flutter/foundation.dart';

/// A [ValueNotifier] whose [value] is derived from a single [ValueListenable].
///
/// Analogous to [Stream.map]. Disposing this notifier removes the listener
/// from [source] but does not dispose [source].
class MappedValueNotifier<T, R> extends ValueNotifier<R> {
  /// Creates a notifier whose [value] is always [map]([source.value]).
  MappedValueNotifier({
    required ValueListenable<T> source,
    required R Function(T value) map,
  }) : _source = source,
       _map = map,
       super(map(source.value)) {
    _source.addListener(_recompute);
  }

  final ValueListenable<T> _source;
  final R Function(T value) _map;

  void _recompute() => value = _map(_source.value);

  @override
  void dispose() {
    _source.removeListener(_recompute);
    super.dispose();
  }
}

/// Combines two [ValueListenable]s into a single derived [ValueNotifier].
///
/// The merged [value] is recomputed whenever either source notifies. Disposing
/// this notifier removes listeners from the sources but does not dispose them.
class MergedValueNotifier<A, B, T> extends ValueNotifier<T> {
  /// Creates a notifier whose [value] is always [merge]([first.value],
  /// [second.value]).
  MergedValueNotifier({
    required ValueListenable<A> first,
    required ValueListenable<B> second,
    required T Function(A first, B second) merge,
  }) : _first = first,
       _second = second,
       _merge = merge,
       super(merge(first.value, second.value)) {
    _first.addListener(_recompute);
    _second.addListener(_recompute);
  }

  final ValueListenable<A> _first;
  final ValueListenable<B> _second;
  final T Function(A first, B second) _merge;

  void _recompute() {
    value = _merge(_first.value, _second.value);
  }

  @override
  void dispose() {
    _first.removeListener(_recompute);
    _second.removeListener(_recompute);
    super.dispose();
  }
}

/// Stream-like transforms for [ValueListenable] sources.
extension ValueListenableCompute<T> on ValueListenable<T> {
  /// Returns a derived [ValueNotifier] that recomputes whenever this listenable
  /// notifies.
  MappedValueNotifier<T, R> map<R>(R Function(T value) transform) =>
      MappedValueNotifier(source: this, map: transform);

  /// Combines this listenable with [other] into a derived [ValueNotifier].
  MergedValueNotifier<T, U, R> combine<U, R>(
    ValueListenable<U> other,
    R Function(T first, U second) merge,
  ) =>
      MergedValueNotifier(first: this, second: other, merge: merge);
}
