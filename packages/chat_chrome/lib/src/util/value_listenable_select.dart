import 'package:flutter/foundation.dart';

/// Selector from a [ValueListenable.value].
typedef ValueListenableSelector<T, Value> = Value Function(T value);

/// Filter for [ValueListenableSelectX.select].
///
/// Return `true` to **allow** notify after the identical check fails.
typedef ValueListenableSelectFilter<Value> = bool Function(Value prev, Value next);

/// Projects a derived [ValueListenable] from another [ValueListenable]'s
/// [ValueListenable.value].
///
/// **identical-only** by default. Pass a [test] for records / freshly
/// allocated objects — typically `(prev, next) => prev != next`.
///
/// ```dart
/// ValueListenableBuilder(
///   valueListenable: composer.select((s) => s.data.enabled),
///   builder: (context, enabled, _) => …,
/// );
/// ```
extension ValueListenableSelectX<T> on ValueListenable<T> {
  /// Derived [ValueListenable] that re-runs [selector] on every source notify
  /// and notifies listeners only when the projected value changes.
  ValueListenable<Value> select<Value>(
    ValueListenableSelector<T, Value> selector, [
    ValueListenableSelectFilter<Value>? test,
  ]) => _ValueListenable$Select<T, Value>(this, selector, test);
}

final class _ValueListenable$Select<T, Value>
    with ChangeNotifier
    implements ValueListenable<Value> {
  _ValueListenable$Select(this._listenable, this._selector, this._test);

  final ValueListenable<T> _listenable;
  final ValueListenableSelector<T, Value> _selector;
  final ValueListenableSelectFilter<Value>? _test;
  var _subscribed = false;

  late Value _$value = _selector(_listenable.value);

  @override
  Value get value => _subscribed ? _$value : _$value = _selector(_listenable.value);

  void _update() {
    final newValue = _selector(_listenable.value);
    if (identical(_$value, newValue)) return;
    if (!(_test?.call(_$value, newValue) ?? true)) return;
    _$value = newValue;
    notifyListeners();
  }

  @override
  void addListener(VoidCallback listener) {
    if (!_subscribed) {
      _$value = _selector(_listenable.value);
      _listenable.addListener(_update);
      _subscribed = true;
    }
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners && _subscribed) {
      _listenable.removeListener(_update);
      _subscribed = false;
    }
  }

  @override
  void dispose() {
    if (_subscribed) {
      _listenable.removeListener(_update);
      _subscribed = false;
    }
    super.dispose();
  }
}
