import 'dart:async';

/// A scheduled callback that can be cancelled.
abstract interface class ComposerTimer {
  /// Cancels the callback if it has not run. Idempotent.
  void cancel();
}

/// The **composer clock**: the one way the composer reads the time and
/// waits, so a test runs slow mode's countdown by hand.
///
/// [now] is wall-clock time, because the chat's capabilities give slow
/// mode's next send as a moment (`SlowMode.nextSendAt`); [after] schedules
/// the countdown's next redraw.
abstract interface class ComposerClock {
  /// The clock of the running app: `DateTime.now` and `Timer`.
  static const ComposerClock system = _SystemComposerClock();

  /// The current time.
  DateTime now();

  /// Runs [callback] once, [delay] from now.
  ComposerTimer after(Duration delay, void Function() callback);
}

final class _SystemComposerClock implements ComposerClock {
  const _SystemComposerClock();

  @override
  DateTime now() => DateTime.now();

  @override
  ComposerTimer after(Duration delay, void Function() callback) =>
      _SystemComposerTimer(Timer(delay, callback));
}

final class _SystemComposerTimer implements ComposerTimer {
  _SystemComposerTimer(this._timer);

  final Timer _timer;

  @override
  void cancel() => _timer.cancel();
}
