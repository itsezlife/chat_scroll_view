import 'dart:async';

/// A scheduled callback that can be cancelled.
abstract interface class BulletinTimer {
  /// Cancels the callback if it has not run. Idempotent.
  void cancel();
}

/// The **bulletin clock**: the one way a bulletin controller reads time and
/// waits, so a test can run time by hand.
///
/// [now] is monotonic time since an arbitrary origin, used for the time left
/// on a bulletin; [after] schedules its timeout.
abstract interface class BulletinClock {
  /// The clock of the running app, backed by a `Stopwatch` and `Timer`.
  static final BulletinClock system = _SystemBulletinClock();

  /// Time since the clock's origin; never decreases.
  Duration get now;

  /// Runs [callback] once, [delay] from now.
  BulletinTimer after(Duration delay, void Function() callback);
}

final class _SystemBulletinClock implements BulletinClock {
  _SystemBulletinClock() : _watch = Stopwatch()..start();

  final Stopwatch _watch;

  @override
  Duration get now => _watch.elapsed;

  @override
  BulletinTimer after(Duration delay, void Function() callback) =>
      _SystemBulletinTimer(Timer(delay, callback));
}

final class _SystemBulletinTimer implements BulletinTimer {
  _SystemBulletinTimer(this._timer);

  final Timer _timer;

  @override
  void cancel() => _timer.cancel();
}
