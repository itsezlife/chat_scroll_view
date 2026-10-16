import 'dart:async';

/// Lets a fake hold its asynchronous work until the test releases it, so a
/// test can observe and race commands that are in flight.
///
/// Open by default: [turn] then completes on the next microtask, which is
/// already later than the synchronous part of the command that awaited it.
final class FakeGate {
  Completer<void>? _closed;

  /// Holds every later [turn] until [resume].
  void pause() => _closed ??= Completer<void>();

  /// Releases the work held by [pause] and opens the gate again.
  void resume() {
    _closed?.complete();
    _closed = null;
  }

  /// Completes when the gate is open.
  Future<void> turn() => _closed?.future ?? Future<void>.value();
}
