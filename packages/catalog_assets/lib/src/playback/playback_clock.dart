import 'package:catalog_assets/src/playback/playback_policy.dart';
import 'package:catalog_assets/src/playback/playback_tick_source.dart';
import 'package:catalog_assets/src/playback/scheduler_playback_tick_source.dart';
import 'package:meta/meta.dart';

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
/// [now] is the timestamp of the last frame delivered; it does not stop
/// counting while paused, so animations resume at the live position rather
/// than where they stopped.
///
/// ## Pause layers
///
/// The host sets and clears named [PlaybackPauseLayer]s (a route moving, a
/// fast scroll, low power, a hidden surface). Playback stops while any layer
/// the [policy] pauses on is set, whatever the bindings' own wishes.
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
  bool _running = false;
  bool _disposed = false;

  /// Timestamp of the last frame delivered; zero before the first.
  Duration get now => _now;

  /// The layers currently set.
  Set<PlaybackPauseLayer> get pausedLayers => Set.unmodifiable(_layers);

  /// Whether a set layer pauses playback under the [policy].
  bool get isPaused => _layers.any(policy.pausingLayers.contains);

  /// Sets or clears [layer]. Setting a set layer or clearing a clear one does
  /// nothing.
  void setPaused(PlaybackPauseLayer layer, {required bool paused}) {
    final changed = paused ? _layers.add(layer) : _layers.remove(layer);
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
    if (shouldRun) {
      (_ticks ??= SchedulerPlaybackTickSource()).start(_onTick);
    } else {
      _ticks?.stop();
    }
  }

  void _onTick(Duration timestamp) {
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
