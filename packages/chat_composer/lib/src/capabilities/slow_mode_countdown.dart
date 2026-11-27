import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_composer/src/capabilities/composer_clock.dart';
import 'package:chat_composer/src/capabilities/composer_slow_mode_state.dart';
import 'package:content_model/content_model.dart';
import 'package:listen/listen.dart' as listen;

/// Slow mode's countdown behind `ComposerController.slowMode`: reads the
/// chat's [SlowMode] at the [clock], redraws while the wait runs, and
/// reports when it starts and ends.
///
/// It ticks only while tracked (a view is mounted and gave it a value) and
/// counting. Each tick is scheduled at the smaller of the refresh period and
/// the wait left, so the countdown ends at the next send time itself rather
/// than up to a period late, and no new value from the host is needed.
final class SlowModeCountdown {
  /// A countdown read at [clock], reporting under [correlation].
  SlowModeCountdown({required this.clock, required this.correlation});

  /// The time the countdown is read at and redrawn by.
  final ComposerClock clock;

  /// The chat's diagnostics correlation, read at each event.
  final ChatCorrelation Function() correlation;

  final _state = listen.ValueNotifier<ComposerSlowModeState>(
    ComposerSlowModeState.free,
  );
  var _value = SlowMode.none;
  var _refresh = Duration.zero;
  var _tracking = false;
  ComposerTimer? _tick;

  /// The countdown, changed on each redraw and each new value.
  listen.ValueListenable<ComposerSlowModeState> get state => _state;

  /// The state at this moment, read from the last value even between ticks.
  ComposerSlowModeState now() => ComposerSlowModeState.of(_value, clock.now());

  /// Takes [value], redrawing every [refresh] while it counts. A value that
  /// lifts the wait (the host cleared slow mode) ends the countdown at once.
  void track(SlowMode value, {required Duration refresh}) {
    assert(refresh > Duration.zero, 'a countdown redraws after some time');
    final previous = _value;
    _value = value;
    _refresh = refresh;
    _tracking = true;
    _update(previous);
  }

  /// Stops ticking (the view went away); the last value is kept, and the
  /// next [track] reports a countdown that ended meanwhile.
  void untrack() {
    _tracking = false;
    _cancel();
  }

  /// Stops ticking for good and releases [state].
  void dispose() {
    untrack();
    _state.dispose();
  }

  void _update(SlowMode previousValue) {
    final now = clock.now();
    final next = ComposerSlowModeState.of(_value, now);
    final before = _state.value;
    if (!before.isCounting && next.isCounting) {
      _emit(CapabilitiesOp.slowModeStarted, next);
    } else if (before.isCounting && !next.isCounting) {
      // Lifted early by a new value, the wait the old one still had.
      final left = ComposerSlowModeState.of(previousValue, now).remaining;
      _emit(
        CapabilitiesOp.slowModeEnded,
        ComposerSlowModeState(
          interval: before.interval,
          remaining: left,
          pending: next.pending,
        ),
      );
    }
    _state.value = next;
    _schedule(next);
  }

  void _schedule(ComposerSlowModeState state) {
    _cancel();
    if (!_tracking || !state.isCounting) return;
    final delay = state.remaining < _refresh ? state.remaining : _refresh;
    _tick = clock.after(delay, () {
      _tick = null;
      _update(_value);
    });
  }

  void _cancel() {
    _tick?.cancel();
    _tick = null;
  }

  void _emit(CapabilitiesOp op, ComposerSlowModeState state) =>
      ChatDiagnostics.current.emit(
        ChatEventLevel.debug,
        ChatEventCategory.capabilities,
        op,
        correlation: correlation(),
        fields: () => {
          'intervalMs': state.interval.inMilliseconds,
          'remainingMs': state.remaining.inMilliseconds,
          'pending': state.pending,
        },
      );
}
