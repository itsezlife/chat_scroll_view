import 'dart:async';

/// A clock that moves only when a test says so, for fakes that simulate
/// latency without real waiting.
final class ManualClock {
  Duration _now = Duration.zero;
  final List<({Duration due, Completer<void> done})> _waiting = [];

  /// How much time has been advanced.
  Duration get now => _now;

  /// A future that completes once [advance] has moved the clock [duration]
  /// beyond its value now. A zero duration completes on the next microtask.
  Future<void> delay(Duration duration) {
    if (duration <= Duration.zero) return Future<void>.value();
    final done = Completer<void>();
    _waiting.add((due: _now + duration, done: done));
    return done.future;
  }

  /// Moves the clock forward by [duration] and completes every delay that
  /// falls due, oldest due time first.
  void advance(Duration duration) {
    assert(duration >= Duration.zero, 'time does not run backwards');
    _now += duration;
    final due = [
      for (final waiting in _waiting)
        if (waiting.due <= _now) waiting,
    ]..sort((a, b) => a.due.compareTo(b.due));
    _waiting.removeWhere((waiting) => waiting.due <= _now);
    for (final waiting in due) {
      waiting.done.complete();
    }
  }
}
