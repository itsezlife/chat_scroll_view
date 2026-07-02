import 'package:flutter/foundation.dart';

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
