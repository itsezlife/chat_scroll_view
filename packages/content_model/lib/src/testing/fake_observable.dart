import 'package:content_model/content_model.dart';

/// An [Observable] a test signals by hand, that also counts its listeners.
///
/// Stands in for any `Observable` a unit under test listens to. Follows the
/// whole listener contract; [listenerCount] lets a test check that the unit
/// removed its listener when it should have.
final class FakeObservable implements Observable {
  final _notifier = ObservableNotifier();
  final _registered = <ObservableListener>{};

  /// How many listeners are registered now.
  int get listenerCount => _registered.length;

  /// Whether [dispose] has been called.
  bool get isDisposed => _notifier.isDisposed;

  /// Signals every listener once.
  void signal() => _notifier.notify();

  /// Drops every listener for good. Idempotent.
  void dispose() {
    _notifier.dispose();
    _registered.clear();
  }

  @override
  void addListener(ObservableListener listener) {
    if (_notifier.isDisposed) return;
    _registered.add(listener);
    _notifier.addListener(listener);
  }

  @override
  void removeListener(ObservableListener listener) {
    _registered.remove(listener);
    _notifier.removeListener(listener);
  }
}
