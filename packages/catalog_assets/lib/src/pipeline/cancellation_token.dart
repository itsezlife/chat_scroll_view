import 'package:listen/listen.dart';

/// Tells a fetch that nobody wants its result any more.
///
/// The pipeline cancels the token of a fetch when the last binding of its
/// entry leaves. A fetcher watches it to stop work and free its connection;
/// cancelling a token is a request, never a failure, and a fetch that
/// finishes anyway is simply ignored.
final class CancellationToken {
  final _CancelSignal _listeners = _CancelSignal();
  bool _cancelled = false;

  /// Whether [cancel] was called.
  bool get isCancelled => _cancelled;

  /// Cancels the token and runs the callbacks registered so far, once.
  /// Further calls do nothing. A callback that throws is reported to
  /// [Listenable.onError]; whether the others still run is up to that handler
  /// (the host sets one that does not rethrow).
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _listeners
      ..fire()
      ..dispose();
  }

  /// Runs [callback] when the token is cancelled, at once if it already is.
  void onCancel(VoidCallback callback) {
    if (!_cancelled) {
      _listeners.addListener(callback);
      return;
    }
    try {
      callback();
    } on Object catch (error, stackTrace) {
      Listenable.onError(error, stackTrace, ErrorContext.listener);
    }
  }
}

/// The one-shot signal behind [CancellationToken]: `notifyListeners` is
/// protected, so the token reaches it through this subclass.
final class _CancelSignal extends ChangeNotifier {
  void fire() => notifyListeners();
}
