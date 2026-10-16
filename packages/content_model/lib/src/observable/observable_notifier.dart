import 'package:content_model/src/observable/listener_set.dart';
import 'package:content_model/src/observable/observable.dart';

/// The owner side of an [Observable]: holds the listeners and publishes
/// signals. The model's replacement for hand-rolled listener lists.
///
/// An owner exposes itself as an [Observable] (or composes one) and calls
/// [notify] after each logical change of its state. Mutation helpers that
/// touch state in several steps wrap them in [batch] so listeners hear one
/// signal, after the last step, instead of one per step.
///
/// The listener contract is the one on [Observable]. After [dispose] every
/// entry point is a silent no-op.
final class ObservableNotifier implements Observable {
  final _listeners = ListenerSet<ObservableListener>();
  var _batchDepth = 0;
  var _pending = false;

  /// Whether [dispose] has been called.
  bool get isDisposed => _listeners.isDisposed;

  @override
  void addListener(ObservableListener listener) => _listeners.add(listener);

  @override
  void removeListener(ObservableListener listener) =>
      _listeners.remove(listener);

  /// Signals every registered listener, or, inside a [batch], records that a
  /// signal is owed when the outermost batch ends.
  void notify() {
    if (_batchDepth > 0) {
      _pending = true;
      return;
    }
    _listeners.dispatch((listener) => listener());
  }

  /// Runs [mutation] and signals once afterwards if [notify] was called
  /// during it, however many times.
  ///
  /// Batches nest: only the outermost one signals. If [mutation] throws, the
  /// signal still goes out first, because the state may be partly changed and
  /// listeners must not be left holding a stale view; the error then
  /// propagates.
  void batch(void Function() mutation) {
    _batchDepth++;
    try {
      mutation();
    } finally {
      _batchDepth--;
      if (_batchDepth == 0 && _pending) {
        _pending = false;
        notify();
      }
    }
  }

  /// Drops every listener for good. Idempotent; safe from inside a listener.
  void dispose() => _listeners.dispose();
}
