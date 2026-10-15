import 'dart:async';

/// Timers for the page retention that only fire when a test moves time.
///
/// Pass [start] as the `startTimer` of a `GlyphPageResidency`; call [elapse]
/// to let the time-to-live pass. Timers due within the span fire in due order,
/// and a timer started by a firing one is honoured if it falls in the span.
final class ManualRetentionTimers {
  Duration _now = Duration.zero;
  final List<_ManualTimer> _timers = <_ManualTimer>[];

  /// Timers started and neither fired nor cancelled.
  int get pending => _timers.where((t) => t.isActive).length;

  /// The factory to inject.
  Timer start(Duration delay, void Function() callback) {
    final timer = _ManualTimer(_now + delay, callback);
    _timers.add(timer);
    return timer;
  }

  /// Moves time forward by [by], firing the timers that fall due.
  void elapse(Duration by) {
    assert(!by.isNegative, 'time does not run backwards');
    final end = _now + by;
    while (true) {
      final due = _timers.where((t) => t.isActive && t.due <= end).toList()
        ..sort((a, b) => a.due.compareTo(b.due));
      if (due.isEmpty) break;
      final next = due.first;
      _now = next.due;
      next.fire();
    }
    _now = end;
    _timers.removeWhere((t) => !t.isActive);
  }
}

final class _ManualTimer implements Timer {
  _ManualTimer(this.due, this._callback);

  final Duration due;
  final void Function() _callback;
  bool _active = true;
  int _ticks = 0;

  @override
  bool get isActive => _active;

  @override
  int get tick => _ticks;

  void fire() {
    _active = false;
    _ticks++;
    _callback();
  }

  @override
  void cancel() => _active = false;
}
