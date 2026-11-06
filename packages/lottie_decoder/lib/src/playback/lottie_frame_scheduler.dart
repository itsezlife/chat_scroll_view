import 'dart:async';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/frame_pool.dart';
import 'package:flutter/foundation.dart';

/// Starts the sweep timer; `Timer.new` by default, a manual one in tests.
typedef LottieSweepTimerFactory =
    Timer Function(Duration delay, void Function() callback);

/// A paintable's claim on a [FrameAtlas] slot, handed out by a
/// [LottieFrameScheduler].
///
/// [sprite] says where the frame the slot holds is, or null while there is
/// none to draw (the paintable then keeps showing its still). A lease ends
/// when its holder [release]s it or when the scheduler sweeps it for being
/// unpainted; a released lease is not revived, the holder [acquire]s again.
///
/// [acquire]: LottieFrameScheduler.acquire
final class LottieFrameLease {
  LottieFrameLease._(this._scheduler, this._handle);

  final LottieFrameScheduler _scheduler;
  final FrameHandle<Object> _handle;

  // The frame the paintable wants now, the one last sent to the renderer, and
  // whether a want arrived since the last sweep.
  int? _wanted;
  int? _requested;
  bool _touched = true;
  bool _released = false;
  bool _failed = false;

  /// Whether the renderer could not render this animation. The holder keeps
  /// painting its still and stops asking.
  bool get isFailed => _failed;

  /// Whether the lease ended.
  bool get isReleased => _released;

  /// Where the current frame is, or null while there is nothing to draw. Read
  /// it when painting and never keep it, as [FrameHandle.sprite] says.
  AtlasSprite? get sprite => _released ? null : _handle.sprite;

  bool get _needsRender =>
      !_released && !_failed && _wanted != null && _wanted != _requested;

  /// Ends the lease. Idempotent. The entry stays in the pool, idle.
  void release() => _scheduler._release(this);
}

/// The one owner of a host's [FrameAtlas]: it works out, once per clock tick,
/// which frames the visible animations want and renders them as one batch.
///
/// Paintables are pull-driven and never schedule: at paint time one calls
/// [want] with the frame its clock time asks for. The scheduler drives itself
/// with [PlaybackClock.follow], so it is gated by the same pause layers as
/// every binding and an idle clock sleeps; a paused app renders nothing. The
/// subscription exists while a lease does.
///
/// ## A tick
///
/// If no batch is in flight and some lease wants a frame it was not sent, one
/// [FrameAtlas.render] goes out with the latest want of each. A want made while
/// a batch runs replaces the one before it and waits for the next tick: a slow
/// renderer coalesces, it never queues. A want for the frame already sent is
/// free, so a paused animation costs nothing.
///
/// The bindings of the animated paintables are targets of the same clock and
/// repaint on their own, so no repaint signal goes out from here. The follow
/// subscription may tick before or after the bindings of the same frame
/// (registration order), so a rendered frame can show one tick later: the
/// paintable asks one frame ahead for that, which is the "one to two frames
/// ahead" budget.
///
/// ## Leases and the sweep
///
/// A paint is the only sign a paintable is on screen, and nothing says when it
/// leaves. One sweep timer, alive only while leases exist, runs every
/// [idleRelease]: a lease that was not wanted since the previous sweep is
/// released, so a sticker that is cached but off screen frees its slot, which
/// stays in the pool idle (evictable, not evicted). A lease therefore lives at
/// least [idleRelease] unpainted and at most twice that.
///
/// One lease per key: the atlas names an entry once in a batch.
///
/// Single-threaded on the UI isolate.
final class LottieFrameScheduler {
  /// Creates a scheduler that owns [atlas] and follows [clock].
  ///
  /// [tickInterval] is the cadence floor passed to [PlaybackClock.follow]; zero
  /// asks for every clock frame.
  LottieFrameScheduler({
    required FrameAtlas<Object> atlas,
    required PlaybackClock clock,
    this.idleRelease = const Duration(seconds: 1),
    this.tickInterval = Duration.zero,
    LottieSweepTimerFactory startTimer = Timer.new,
  }) : _atlas = atlas,
       _clock = clock,
       _startTimer = startTimer;

  /// How long a lease may go unwanted before the sweep frees its slot.
  final Duration idleRelease;

  /// Shortest time between two ticks of the follow subscription.
  final Duration tickInterval;

  final FrameAtlas<Object> _atlas;
  final PlaybackClock _clock;
  final LottieSweepTimerFactory _startTimer;
  final Map<Object, LottieFrameLease> _leases = <Object, LottieFrameLease>{};
  PlaybackSubscription? _following;
  Timer? _sweep;
  bool _inFlight = false;
  bool _disposed = false;

  /// Leases alive now.
  int get leaseCount => _leases.length;

  /// Whether the scheduler is following the clock.
  bool get isFollowing => _following != null;

  /// A lease on [key]'s slot for frames of [width] x [height] pixels of
  /// [source] (what the renderer renders), or null when every page is open and
  /// every cell pinned: the caller keeps showing its still, never an error.
  ///
  /// Throws a [StateError] when [key] already has a lease and an
  /// [ArgumentError] for a size the pool refuses.
  LottieFrameLease? acquire(Object key, Object source, int width, int height) {
    if (_disposed) return null;
    if (_leases.containsKey(key)) {
      throw StateError('$key already has a lease.');
    }
    final handle = _atlas.acquire(
      key,
      source: source,
      width: width,
      height: height,
    );
    if (handle == null) return null;
    final lease = LottieFrameLease._(this, handle);
    _leases[key] = lease;
    _following ??= _clock.follow(_onTick, frameInterval: tickInterval);
    _sweep ??= _startTimer(idleRelease, _onSweep);
    return lease;
  }

  /// Says which frame [lease] wants now; called at paint time. Marks the lease
  /// as painted for the sweep. Ignored once released.
  void want(LottieFrameLease lease, int frame) {
    if (lease._released) return;
    lease
      .._wanted = frame
      .._touched = true;
  }

  /// Releases every lease, stops following the clock and disposes the atlas.
  /// Idempotent.
  void dispose() {
    if (_disposed) return;
    List.of(_leases.values).forEach(_release);
    _disposed = true;
    _atlas.dispose();
  }

  void _release(LottieFrameLease lease) {
    if (lease._released) return;
    lease._released = true;
    lease._handle.release();
    _leases.remove(lease._handle.key);
    if (_leases.isNotEmpty) return;
    _following?.cancel();
    _following = null;
    _sweep?.cancel();
    _sweep = null;
  }

  void _onTick(Duration now) {
    if (_inFlight) return;
    final due = [
      for (final lease in _leases.values)
        if (lease._needsRender) lease,
    ];
    if (due.isEmpty) return;
    _inFlight = true;
    final requests = <FrameRequest<Object>>[];
    for (final lease in due) {
      lease._requested = lease._wanted;
      requests.add((handle: lease._handle, frame: lease._wanted!));
    }
    _atlas
        .render(requests)
        .then(
          (batch) {
            _inFlight = false;
            for (final handle in batch.failed) {
              final lease = _leases[handle.key];
              if (lease != null && identical(lease._handle, handle)) {
                lease._failed = true;
              }
            }
          },
          onError: (Object error, StackTrace stack) {
            _inFlight = false;
            // A batch that threw says nothing of which job was at fault: none of
            // them is asked again, rather than failing on every tick.
            for (final lease in due) {
              lease._failed = true;
            }
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: error,
                stack: stack,
                library: 'lottie_decoder',
                context: ErrorDescription('while rendering a batch of frames'),
              ),
            );
          },
        );
  }

  void _onSweep() {
    _sweep = null;
    for (final lease in List.of(_leases.values)) {
      if (lease._touched) {
        lease._touched = false;
      } else {
        _release(lease);
      }
    }
    if (_leases.isNotEmpty) _sweep = _startTimer(idleRelease, _onSweep);
  }
}
