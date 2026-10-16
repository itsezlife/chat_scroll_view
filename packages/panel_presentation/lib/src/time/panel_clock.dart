import 'dart:async';

/// A scheduled callback that can be cancelled.
abstract interface class PanelTimer {
  /// Cancels the callback if it has not run. Idempotent.
  void cancel();
}

/// The **presentation clock**: the one way presentation code waits, so a test
/// can run time by hand and no strategy reads the wall clock.
///
/// Strategies schedule their timeouts (the hover leave delay, the idle
/// delay, the keyboard hand-off fallback) here, never with `Timer` or
/// `DateTime.now`.
abstract interface class PanelClock {
  /// The clock of the running app, backed by `Timer`.
  static const PanelClock system = _SystemPanelClock();

  /// Runs [callback] once, [delay] from now.
  PanelTimer after(Duration delay, void Function() callback);
}

final class _SystemPanelClock implements PanelClock {
  const _SystemPanelClock();

  @override
  PanelTimer after(Duration delay, void Function() callback) =>
      _SystemPanelTimer(Timer(delay, callback));
}

final class _SystemPanelTimer implements PanelTimer {
  _SystemPanelTimer(this._timer);

  final Timer _timer;

  @override
  void cancel() => _timer.cancel();
}
