import 'package:content_model/src/observable/observable.dart';
import 'package:content_model/src/observable/observable_notifier.dart';

/// The owner side of a [ValueObservable]: holds the current snapshot and
/// signals when it is replaced by a different one.
///
/// Assigning [value] signals unless the new snapshot `==` the current one, so
/// owners that republish an unchanged snapshot do not wake their listeners.
/// Group several assignments in [batch] to deliver one signal carrying the
/// final snapshot.
///
/// After [dispose] the latest [value] stays readable, so a late reader sees
/// the truth, but nothing is signalled.
final class ObservableValue<T> implements ValueObservable<T> {
  /// Creates an observable whose first snapshot is [initial].
  ObservableValue(T initial) : _value = initial;

  final _notifier = ObservableNotifier();
  T _value;

  @override
  T get value => _value;

  set value(T next) {
    if (_value == next) return;
    _value = next;
    _notifier.notify();
  }

  /// Whether [dispose] has been called.
  bool get isDisposed => _notifier.isDisposed;

  @override
  void addListener(ObservableListener listener) =>
      _notifier.addListener(listener);

  @override
  void removeListener(ObservableListener listener) =>
      _notifier.removeListener(listener);

  /// Runs [mutation], which may assign [value] several times, and signals
  /// once afterwards if any assignment changed it. The error of a throwing
  /// [mutation] propagates after that signal, as for
  /// [ObservableNotifier.batch].
  void batch(void Function() mutation) => _notifier.batch(mutation);

  /// Drops every listener for good. Idempotent; safe from inside a listener.
  void dispose() => _notifier.dispose();
}
