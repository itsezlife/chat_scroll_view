import 'dart:async';
import 'dart:ui' show AppLifecycleState;

import 'package:catalog_assets/src/playback/playback_clock.dart';
import 'package:catalog_assets/src/playback/playback_lifecycle_source.dart';
import 'package:catalog_assets/src/playback/playback_policy.dart';
import 'package:flutter/foundation.dart';

/// Starts a timer that calls [callback] once after [delay]. The default is
/// `Timer.new`; tests inject `ManualRetentionTimers.start`.
typedef PlaybackTimerFactory =
    Timer Function(Duration delay, void Function() callback);

/// How long a change of focus must hold before a [PlaybackActivity] acts on it.
///
/// Both default to zero, because that is what the reference desktop client
/// does: it recomputes whether its window is active one event-loop turn after
/// the window event, and the paint after that already skips the animations.
/// Its 1 s and 5 s timers only back that up and feed the server's "online"
/// status; they never delay the pause. The fields exist for a host that wants
/// a short debounce, for example against a focus hand-off between two windows
/// of its own.
@immutable
final class PlaybackActivityPolicy {
  /// Creates a policy.
  const PlaybackActivityPolicy({
    this.unfocusedGrace = Duration.zero,
    this.focusedGrace = Duration.zero,
  });

  /// How long the app must stay without focus before
  /// [PlaybackPauseLayer.appInactive] is set. Losing visibility (`hidden`) does
  /// not wait.
  final Duration unfocusedGrace;

  /// How long the app must stay focused before [PlaybackPauseLayer.appInactive]
  /// is cleared.
  final Duration focusedGrace;
}

/// One claim on the chat being covered, released exactly once.
///
/// Returned by [PlaybackActivity.holdOverlay].
final class PlaybackOverlayHold {
  PlaybackOverlayHold._(this._onRelease);

  void Function()? _onRelease;

  /// Whether [release] has run (or the activity was already gone).
  bool get isReleased => _onRelease == null;

  /// Gives the claim back. Idempotent.
  void release() {
    final onRelease = _onRelease;
    _onRelease = null;
    onRelease?.call();
  }
}

/// Maps what the app and the platform report onto the pause layers of one
/// [PlaybackClock]: the one host-facing seam of the pause policies.
///
/// A host creates one per asset cache scope (the clock of
/// `AssetCacheScope.clock` is shared by the bindings and the spoiler dust, so
/// both follow), feeds it, and disposes it with the shell. No widget takes a
/// pause flag of its own.
///
/// ## Inputs and the layers they drive
///
/// | Input | Layer |
/// |---|---|
/// | [lifecycle] `inactive` | [PlaybackPauseLayer.appInactive] |
/// | [lifecycle] `hidden`, `paused`, `detached` | `appInactive` and [PlaybackPauseLayer.surfaceHidden] |
/// | `lowPower` | [PlaybackPauseLayer.lowPower] |
/// | `reducedMotion` | [PlaybackPauseLayer.reducedMotion] |
/// | [holdOverlay] | [PlaybackPauseLayer.overlayShown] |
///
/// A state the source has not reported yet (`null`) is "unknown" and pauses
/// nothing; so is a first state of `detached`, which some embedders report
/// before the first real one. The platform delivers `resumed -> hidden` as
/// `inactive` then `hidden`; the clock stops its frames once, on the first.
///
/// This object owns those five layers. [PlaybackPauseLayer.routeMoving] and
/// [PlaybackPauseLayer.fastScroll] stay the host's to set directly on the
/// clock, and [dispose] leaves them alone.
///
/// ## What it does not decide
///
/// Whether `reducedMotion` stops playback is the clock's policy
/// ([PlaybackPolicy.pausingLayers]); this only reports it. Detecting low power
/// and the system's reduced-motion setting is the host's: the SDK reports
/// neither for every desktop platform, and a library that picked a battery
/// plugin would impose it on every host.
///
/// Single-threaded: every call is on the UI isolate.
final class PlaybackActivity {
  /// Starts driving [clock]'s layers from the inputs it is given.
  ///
  /// [lifecycle] is `WidgetsPlaybackLifecycleSource` in production. [lowPower]
  /// and [reducedMotion] are host-fed: the activity reads their value now and
  /// follows them, and disposes neither. [startTimer] is for tests.
  PlaybackActivity({
    required PlaybackClock clock,
    PlaybackLifecycleSource? lifecycle,
    ValueListenable<bool>? lowPower,
    ValueListenable<bool>? reducedMotion,
    this.policy = const PlaybackActivityPolicy(),
    PlaybackTimerFactory startTimer = Timer.new,
  }) : _clock = clock,
       _lifecycle = lifecycle,
       _lowPower = lowPower,
       _reducedMotion = reducedMotion,
       _startTimer = startTimer {
    lifecycle?.addListener(_onLifecycle);
    lowPower?.addListener(_onLowPower);
    reducedMotion?.addListener(_onReducedMotion);
    _onLifecycle();
    _onLowPower();
    _onReducedMotion();
  }

  /// How long a change of focus must hold before it counts.
  final PlaybackActivityPolicy policy;

  final PlaybackClock _clock;
  final PlaybackLifecycleSource? _lifecycle;
  final ValueListenable<bool>? _lowPower;
  final ValueListenable<bool>? _reducedMotion;
  final PlaybackTimerFactory _startTimer;

  // The layers this object has set and not yet cleared: what dispose gives
  // back, so it never clears one the host raised itself.
  final Set<PlaybackPauseLayer> _held = {};

  bool _seenRealState = false;
  Timer? _graceTimer;
  bool? _graceTarget;
  int _overlays = 0;
  bool _disposed = false;

  /// Whether [dispose] has run.
  bool get isDisposed => _disposed;

  /// Claims that something covers the chat until the returned hold is
  /// released: a dialog, a sheet, a full-screen route. While any hold is open
  /// [PlaybackPauseLayer.overlayShown] is set, so two overlays on top of each
  /// other do not clear it when the first closes.
  ///
  /// After [dispose] it returns a hold that is already released.
  PlaybackOverlayHold holdOverlay() {
    if (_disposed) return PlaybackOverlayHold._(null);
    _overlays++;
    _set(PlaybackPauseLayer.overlayShown, on: true);
    return PlaybackOverlayHold._(_releaseOverlay);
  }

  void _releaseOverlay() {
    if (_disposed) return;
    _overlays--;
    if (_overlays == 0) _set(PlaybackPauseLayer.overlayShown, on: false);
  }

  // --- Lifecycle ------------------------------------------------------------

  void _onLifecycle() {
    final source = _lifecycle;
    if (source == null || _disposed) return;
    final state = source.state;
    // Detached before any real state is the embedder's "nothing yet", not a
    // window that went away.
    final unknown =
        state == null ||
        (state == AppLifecycleState.detached && !_seenRealState);
    if (unknown) {
      _set(PlaybackPauseLayer.surfaceHidden, on: false);
      _followFocus(inactive: false);
      return;
    }
    _seenRealState = true;
    switch (state) {
      case AppLifecycleState.resumed:
        _set(PlaybackPauseLayer.surfaceHidden, on: false);
        _followFocus(inactive: false);
      case AppLifecycleState.inactive:
        _set(PlaybackPauseLayer.surfaceHidden, on: false);
        _followFocus(inactive: true);
      case AppLifecycleState.hidden ||
          AppLifecycleState.paused ||
          AppLifecycleState.detached:
        // Not visible is not a matter of debate: no grace.
        _set(PlaybackPauseLayer.surfaceHidden, on: true);
        _followFocus(inactive: true, immediately: true);
    }
  }

  // Moves appInactive to [inactive], after the policy's grace unless
  // [immediately]. The opposite change before the grace ends cancels it.
  void _followFocus({required bool inactive, bool immediately = false}) {
    if (_held.contains(PlaybackPauseLayer.appInactive) == inactive) {
      _cancelGrace();
      return;
    }
    if (_graceTarget == inactive) return;
    _cancelGrace();
    final grace = immediately
        ? Duration.zero
        : (inactive ? policy.unfocusedGrace : policy.focusedGrace);
    if (grace == Duration.zero) {
      _set(PlaybackPauseLayer.appInactive, on: inactive);
      return;
    }
    _graceTarget = inactive;
    _graceTimer = _startTimer(grace, () {
      _graceTimer = null;
      _graceTarget = null;
      _set(PlaybackPauseLayer.appInactive, on: inactive);
    });
  }

  void _cancelGrace() {
    _graceTimer?.cancel();
    _graceTimer = null;
    _graceTarget = null;
  }

  // --- Host-fed inputs ------------------------------------------------------

  void _onLowPower() {
    final input = _lowPower;
    if (input != null && !_disposed) {
      _set(PlaybackPauseLayer.lowPower, on: input.value);
    }
  }

  void _onReducedMotion() {
    final input = _reducedMotion;
    if (input != null && !_disposed) {
      _set(PlaybackPauseLayer.reducedMotion, on: input.value);
    }
  }

  // Touches the clock only when this object's own claim on [layer] changes, so
  // a layer the host raised itself is never cleared by a state that merely
  // repeats "off".
  void _set(PlaybackPauseLayer layer, {required bool on}) {
    final changed = on ? _held.add(layer) : _held.remove(layer);
    if (changed) _clock.setPaused(layer, paused: on);
  }

  /// Stops listening and clears every layer it set, so a disposed activity
  /// cannot leave the clock paused. Idempotent. Inputs it was given are not
  /// disposed.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelGrace();
    _lifecycle?.removeListener(_onLifecycle);
    _lowPower?.removeListener(_onLowPower);
    _reducedMotion?.removeListener(_onReducedMotion);
    for (final layer in _held.toList()) {
      _clock.setPaused(layer, paused: false);
    }
    _held.clear();
  }
}
