import 'package:chat_composer/chat_composer.dart';

/// A [ComposerClock] that only moves when a test says so.
///
/// Timers run inside [advance], in due order (ties in scheduling order), with
/// [now] at each one's due time. A timer scheduled by a callback while time
/// is advancing runs in the same call when it falls due before the target.
final class ManualComposerClock implements ComposerClock {
  /// A clock that starts at [start].
  ManualComposerClock(DateTime start) : _now = start;

  final _timers = <_ManualTimer>[];
  DateTime _now;
  var _sequence = 0;

  @override
  DateTime now() => _now;

  /// How many timers are scheduled and neither run nor cancelled.
  int get pendingCount => _timers.length;

  /// The delays the scheduled timers were asked for, in scheduling order.
  List<Duration> get pendingDelays => [
    for (final timer in _timers) timer.delay,
  ];

  @override
  ComposerTimer after(Duration delay, void Function() callback) {
    final timer = _ManualTimer(
      this,
      _now.add(delay),
      delay,
      _sequence++,
      callback,
    );
    _timers.add(timer);
    return timer;
  }

  /// Moves time forward by [duration], running every timer that falls due.
  void advance(Duration duration) {
    final target = _now.add(duration);
    while (true) {
      final due = _nextDue(target);
      if (due == null) break;
      _timers.remove(due);
      _now = due.due;
      due.callback();
    }
    _now = target;
  }

  _ManualTimer? _nextDue(DateTime target) {
    _ManualTimer? next;
    for (final timer in _timers) {
      if (timer.due.isAfter(target)) continue;
      if (next == null ||
          timer.due.isBefore(next.due) ||
          (timer.due == next.due && timer.sequence < next.sequence)) {
        next = timer;
      }
    }
    return next;
  }
}

final class _ManualTimer implements ComposerTimer {
  _ManualTimer(this._clock, this.due, this.delay, this.sequence, this.callback);

  final ManualComposerClock _clock;
  final DateTime due;
  final Duration delay;
  final int sequence;
  final void Function() callback;

  @override
  void cancel() => _clock._timers.remove(this);
}
