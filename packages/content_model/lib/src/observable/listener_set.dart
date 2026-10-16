import 'dart:async';

/// The registry behind every notifier: dedup-on-add, snapshot dispatch,
/// isolation of throwing listeners, silence after disposal.
///
/// Internal, so the public notifiers share one implementation of the listener
/// contract instead of each hand-rolling it.
final class ListenerSet<F extends Function> {
  final _listeners = <F>[];
  var _disposed = false;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  /// Registers [listener] unless it is already registered or the set is
  /// disposed.
  void add(F listener) {
    if (_disposed || _listeners.contains(listener)) return;
    _listeners.add(listener);
  }

  /// Unregisters [listener]; an unknown one is ignored.
  void remove(F listener) => _listeners.remove(listener);

  /// Clears the registry for good. Safe during [dispatch]: the pass in flight
  /// finds nobody left to call.
  void dispose() {
    _disposed = true;
    _listeners.clear();
  }

  /// Runs [invoke] on a snapshot of the listeners, skipping any removed since
  /// the snapshot was taken: a listener that unregistered because its owner
  /// is gone must not be called into that owner afterwards.
  ///
  /// A throwing listener is reported to the zone and the pass goes on, so one
  /// faulty listener cannot starve the rest or break the code that changed
  /// the state.
  void dispatch(void Function(F listener) invoke) {
    if (_disposed) return;
    for (final listener in List<F>.of(_listeners, growable: false)) {
      if (!_listeners.contains(listener)) continue;
      try {
        invoke(listener);
      } on Object catch (error, stackTrace) {
        Zone.current.handleUncaughtError(error, stackTrace);
      }
    }
  }
}
