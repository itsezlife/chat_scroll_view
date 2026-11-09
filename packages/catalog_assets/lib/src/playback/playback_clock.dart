import 'package:catalog_assets/src/playback/playback_policy.dart';
import 'package:catalog_assets/src/playback/playback_tick_source.dart';
import 'package:catalog_assets/src/playback/scheduler_playback_tick_source.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:meta/meta.dart';

// [DBG-141] Ticket 141's device log, behind --dart-define=DBG_141=true.
const bool _dbg141 = bool.fromEnvironment('DBG_141');

void _dbg(String message) => debugPrint('[DBG-141] clock $message');

/// Something the [PlaybackClock] advances: in practice a playing binding.
@internal
abstract interface class PlaybackTarget {
  /// The shortest time between two [tick]s, from the fps cap of its spec.
  Duration get frameInterval;

  /// Called on a frame at least [frameInterval] (less the policy's slack)
  /// after the previous call.
  void tick(Duration now);
}

/// The one clock every animated asset of a scope advances by.
///
/// It exists so N visible animations cost one frame request and advance
/// together (a paintable derives its frame from [now]), instead of each
/// scheduling its own. Paintables never schedule timers.
///
/// The clock asks the engine for frames only while at least one target is
/// registered and no pause layer is set, so idle it keeps the engine asleep.
/// [now] is playback time: it advances only while the clock delivers frames.
/// While paused (or idle, with no target) no frame is delivered and [now]
/// stands still; the first frame after it advances [now] by one display frame
/// (the last frame-to-frame step seen), not by the length of the pause. So
/// every animation freezes and continues from where it stopped, whatever the
/// pause's length: a panel sliding in for 300 ms used to show as a 300 ms jump
/// in every sticker, because a paintable can only drop a step it recognises
/// as a pause by its size (`resumeGap`), and a short pause looks like a slow
/// frame.
///
/// ## Pause layers
///
/// The host sets and clears named [PlaybackPauseLayer]s (a route moving, a
/// fast scroll, low power, a hidden surface, a window without focus, an
/// overlay over the chat). Playback stops while any layer the [policy] pauses
/// on is set, whatever the bindings' own wishes. A `PlaybackActivity` drives
/// the ones that follow the app and the platform, so a host does not call
/// [setPaused] for them by hand.
///
/// Single-threaded: every call and every tick is on the UI isolate.
final class PlaybackClock {
  /// Creates a clock. [ticks] defaults to the scheduler's frame callbacks,
  /// created when the first target needs them; tests pass a manual source.
  PlaybackClock({
    PlaybackTickSource? ticks,
    this.policy = const PlaybackPolicy(),
  }) : _ticks = ticks;

  /// Which layers pause playback and the fps caps.
  final PlaybackPolicy policy;

  PlaybackTickSource? _ticks;
  final Map<PlaybackTarget, Duration?> _lastTick = {};
  final Set<PlaybackPauseLayer> _layers = {};
  Duration _now = Duration.zero;
  // The engine's timestamp of the last frame delivered, and the step between
  // the last two; null before the first frame.
  Duration? _rawLast;
  Duration _rawStep = _defaultDisplayFrame;
  // Engine time the clock did not run (pauses, idle), taken out of [now].
  Duration _stopped = Duration.zero;
  // Set when the frames start again; the next frame's gap is not playback.
  bool _resuming = false;

  static const Duration _defaultDisplayFrame = Duration(microseconds: 16667);
  bool _running = false;
  bool _disposed = false;

  /// Playback time of the last frame delivered: the engine's frame time less
  /// the time the clock was stopped; zero before the first frame.
  Duration get now => _now;

  /// The layers currently set.
  Set<PlaybackPauseLayer> get pausedLayers => Set.unmodifiable(_layers);

  /// Whether a set layer pauses playback under the [policy].
  bool get isPaused => _layers.any(policy.pausingLayers.contains);

  /// Sets or clears [layer]. Setting a set layer or clearing a clear one does
  /// nothing.
  void setPaused(PlaybackPauseLayer layer, {required bool paused}) {
    final changed = paused ? _layers.add(layer) : _layers.remove(layer);
    if (_dbg141 && changed) _dbg('${layer.name}=$paused layers=$_layers');
    if (changed) _sync();
  }

  /// Starts advancing [target]. Registering twice does nothing.
  @internal
  void register(PlaybackTarget target) {
    if (_disposed || _lastTick.containsKey(target)) return;
    _lastTick[target] = null;
    _sync();
  }

  /// Stops advancing [target]; an unknown one is ignored. Safe from inside a
  /// tick.
  @internal
  void unregister(PlaybackTarget target) {
    _lastTick.remove(target);
    _sync();
  }

  /// Calls [onTick] on the frames of this clock, at most every
  /// [frameInterval], for something that animates but is not an asset binding
  /// (the dust over a hidden spoiler in a markdown body).
  ///
  /// It runs on the same frames as the bindings and is gated by the same
  /// pause layers, so a host that pauses the clock pauses it too, and an idle
  /// clock stays asleep once it is [PlaybackSubscription.cancel]led. [onTick]
  /// receives the time of the frame, which only grows.
  PlaybackSubscription follow(
    void Function(Duration now) onTick, {
    required Duration frameInterval,
  }) {
    final target = _FollowingTarget(frameInterval, onTick);
    register(target);
    return PlaybackSubscription._(this, target);
  }

  /// Stops the frames and forgets every target. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _lastTick.clear();
    _sync();
  }

  void _sync() {
    final shouldRun = !_disposed && _lastTick.isNotEmpty && !isPaused;
    if (shouldRun == _running) return;
    _running = shouldRun;
    if (_dbg141) _dbg(shouldRun ? 'runs' : 'stops');
    if (shouldRun) {
      _resuming = true;
      (_ticks ??= SchedulerPlaybackTickSource()).start(_onTick);
    } else {
      _ticks?.stop();
    }
  }

  void _onTick(Duration raw) {
    final rawLast = _rawLast;
    if (rawLast != null) {
      final gap = raw - rawLast;
      if (_resuming) {
        // The clock stood still for all but one display frame of the gap.
        if (gap > _rawStep) _stopped += gap - _rawStep;
        // The first frame back is every target's: one tick each, at once,
        // as after any stop, whatever its own interval.
        _lastTick.updateAll((_, _) => null);
      } else if (!gap.isNegative) {
        _rawStep = gap;
      }
    }
    _resuming = false;
    _rawLast = raw;
    final timestamp = raw - _stopped;
    _now = timestamp;
    for (final target in List<PlaybackTarget>.of(_lastTick.keys)) {
      // Unregistered by an earlier target in this same frame.
      if (!_lastTick.containsKey(target)) continue;
      final last = _lastTick[target];
      final due =
          last == null ||
          timestamp - last >= target.frameInterval - policy.cadenceSlack;
      if (!due) continue;
      _lastTick[target] = timestamp;
      target.tick(timestamp);
    }
  }
}

/// A live [PlaybackClock.follow]: cancel it when the follower stops needing
/// frames.
final class PlaybackSubscription {
  PlaybackSubscription._(this._clock, this._target);

  final PlaybackClock _clock;
  final PlaybackTarget _target;

  /// Stops the frames for this subscription. Idempotent.
  void cancel() => _clock.unregister(_target);
}

final class _FollowingTarget implements PlaybackTarget {
  _FollowingTarget(this.frameInterval, this._onTick);

  @override
  final Duration frameInterval;

  final void Function(Duration now) _onTick;

  @override
  void tick(Duration now) => _onTick(now);
}
