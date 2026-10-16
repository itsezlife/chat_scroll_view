import 'package:panel_presentation/panel_presentation.dart';

/// A [PanelClock] that only moves when a test says so.
///
/// Timers run inside [advance], in due order (ties in scheduling order). A
/// timer scheduled by a callback while time is advancing runs in the same
/// call when it falls due before the target.
final class ManualPanelClock implements PanelClock {
  final _timers = <_ManualTimer>[];
  var _now = Duration.zero;
  var _sequence = 0;

  /// How much time has been advanced in total.
  Duration get elapsed => _now;

  /// How many timers are scheduled and neither run nor cancelled.
  int get pendingCount => _timers.length;

  @override
  PanelTimer after(Duration delay, void Function() callback) {
    final timer = _ManualTimer(this, _now + delay, _sequence++, callback);
    _timers.add(timer);
    return timer;
  }

  /// Moves time forward by [duration], running every timer that falls due.
  void advance(Duration duration) {
    final target = _now + duration;
    while (true) {
      final due = _nextDue(target);
      if (due == null) break;
      _timers.remove(due);
      _now = due.due;
      due.callback();
    }
    _now = target;
  }

  _ManualTimer? _nextDue(Duration target) {
    _ManualTimer? next;
    for (final timer in _timers) {
      if (timer.due > target) continue;
      if (next == null ||
          timer.due < next.due ||
          (timer.due == next.due && timer.sequence < next.sequence)) {
        next = timer;
      }
    }
    return next;
  }
}

final class _ManualTimer implements PanelTimer {
  _ManualTimer(this._clock, this.due, this.sequence, this.callback);

  final ManualPanelClock _clock;
  final Duration due;
  final int sequence;
  final void Function() callback;

  @override
  void cancel() => _clock._timers.remove(this);
}
