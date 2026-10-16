import 'dart:async';

import 'package:content_model/content_model.dart';

/// Tells a fetch that nobody wants its result any more.
///
/// The pipeline cancels the token of a fetch when the last binding of its
/// entry leaves. A fetcher watches it to stop work and free its connection;
/// cancelling a token is a request, never a failure, and a fetch that
/// finishes anyway is simply ignored.
final class CancellationToken {
  final ObservableNotifier _listeners = ObservableNotifier();
  bool _cancelled = false;

  /// Whether [cancel] was called.
  bool get isCancelled => _cancelled;

  /// Cancels the token and runs the callbacks registered so far, once.
  /// Further calls do nothing. A callback that throws is reported to the zone
  /// and does not stop the others.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _listeners
      ..notify()
      ..dispose();
  }

  /// Runs [callback] when the token is cancelled, at once if it already is.
  void onCancel(ObservableListener callback) {
    if (!_cancelled) {
      _listeners.addListener(callback);
      return;
    }
    try {
      callback();
    } on Object catch (error, stackTrace) {
      Zone.current.handleUncaughtError(error, stackTrace);
    }
  }
}
