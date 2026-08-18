import 'package:flutter/foundation.dart';

/// Maps a source listenable, notifying only when the mapped value changes.
class MappedValueListenable<T, R> extends ChangeNotifier
    implements ValueListenable<R> {
  /// Creates a derived listenable.
  MappedValueListenable({
    required ValueListenable<T> source,
    required R Function(T value) map,
    bool Function(R previous, R next)? equals,
  }) : _source = source,
       _map = map,
       _equals = equals ?? _defaultEquals,
       _value = map(source.value) {
    _source.addListener(_onSourceChanged);
  }

  static bool _defaultEquals<R>(R previous, R next) => previous == next;

  final ValueListenable<T> _source;
  final R Function(T value) _map;
  final bool Function(R previous, R next) _equals;
  late R _value;
  var _disposed = false;

  @override
  R get value => _value;

  void _onSourceChanged() {
    if (_disposed) return;
    final next = _map(_source.value);
    if (_equals(_value, next)) return;
    _value = next;
    notifyListeners();
  }

  /// Detaches from the source and releases listeners.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _source.removeListener(_onSourceChanged);
    super.dispose();
  }
}

/// Helpers for composing listenables.
extension ValueListenableUtilsX<T> on ValueListenable<T> {
  /// Returns a derived listenable that applies [map] to this value.
  ///
  /// Caller must dispose the result when no longer needed.
  MappedValueListenable<T, R> map<R>(
    R Function(T value) map, {
    bool Function(R previous, R next)? equals,
  }) => MappedValueListenable<T, R>(
    source: this,
    map: map,
    equals: equals,
  );
}
