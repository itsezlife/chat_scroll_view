import 'dart:async';
import 'dart:math' as math;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/frame_pool.dart';
import 'package:flutter/foundation.dart';
import 'package:video_decoder/src/engine/video_engine.dart';
import 'package:video_decoder/src/renderer/video_frame_source.dart';
import 'package:video_native/video_native.dart';

/// Starts the sweep timer; `Timer.new` by default, a manual one in tests.
typedef VideoSweepTimerFactory =
    Timer Function(Duration delay, void Function() callback);

/// A paintable's claim on a clip's slot and decoded frames, handed out by a
/// [VideoFrameScheduler].
///
/// [sprite] says where the frame on show is, or null while there is none (the
/// paintable then keeps showing its still). A lease ends when its holder
/// [release]s it or the scheduler sweeps it for being unpainted; a released
/// lease is not revived, the holder acquires again.
final class VideoFrameLease {
  VideoFrameLease._(this._scheduler, this._handle, this._player, this._seq);

  final VideoFrameScheduler _scheduler;
  final FrameHandle<Object> _handle;
  final _ClipPlayer _player;

  /// Order of acquisition: the newest is served first when slots are short.
  final int _seq;

  bool _touched = true;

  /// The tick time at the last paint (the acquisition counts as one).
  Duration _wantedAt = Duration.zero;

  /// The tick time at which the clip last had a slot.
  Duration _servedAt = Duration.zero;
  bool _released = false;
  bool _holding = false;

  // The frame number the handle was last asked to show.
  int? _requested;

  /// Whether the clip could not be decoded. The holder keeps painting its
  /// still and stops asking.
  bool get isFailed => _player.failed;

  /// Whether the lease ended.
  bool get isReleased => _released;

  /// Whether the clip has played to its end once, in clip time: a pass that
  /// does not loop is over. False while the length is unknown (a container
  /// that declares no duration, before the stream first ends).
  bool get isPassComplete => _player.isPassComplete;

  /// Where the current frame is, or null while there is none to draw. Read it
  /// when painting and never keep it, as [FrameHandle.sprite] says.
  AtlasSprite? get sprite => _released ? null : _handle.sprite;

  /// Stops decoding and keeps the frame on show: a pass that does not loop
  /// ended on its last frame. The slot stays leased until [release].
  void hold() => _holding = true;

  /// Ends the lease. Idempotent. The entry stays in the pool, idle.
  void release() => _scheduler._release(this);
}

/// The one owner of a host's video frame pool: it decodes each playing clip a
/// few frames ahead of the clock and draws the frame the clock names, one
/// batch per tick.
///
/// Paintables are pull-driven and never schedule: at paint time one calls
/// [want] with how long it has played. The scheduler drives itself with
/// [PlaybackClock.follow], so it is gated by the same pause layers as every
/// binding and an idle clock sleeps; a paused app decodes nothing. The
/// subscription exists while a lease does.
///
/// ## Decoding is sequential, so the scheduler keeps a ring
///
/// A video has no seek to a time ([VideoEngine]): frames come in order, and
/// looping is a rewind. Each advancing clip therefore keeps a small ring of
/// decoded frames, [prefetch] of them ahead of its clip time, filled by at
/// most one `nextFrame` in flight per clip (never queued). The frame on show
/// is the one with the latest presentation time at or before the clip time.
/// When decoding runs behind, the newest frame that is ready wins and the
/// older ones are dropped unshown: the UI never waits, and nothing queues.
///
/// ## Looping
///
/// A clip loops forever. At the end of the stream the scheduler rewinds and
/// goes on with presentation times shifted by the length of the pass (the
/// container's duration, or the last frame's time plus one frame when it
/// declares none), so the ring holds one timeline across passes.
///
/// ## Clip time
///
/// The scheduler integrates the played time its paintables report, for every
/// clip that is neither held ([VideoFrameLease.hold]) nor failed. A held clip
/// stops where it was. A clip the cap passed over this tick still keeps its
/// time: its frame is chosen by its own clock, it only updates less often.
///
/// ## The cap: time-slicing, never freezing
///
/// A visible clip keeps playing. At most [maxAdvancing] clips get a slot per
/// tick: only a slot starts a decode or draws a frame. Up to the cap every
/// clip has one, every tick. Above it the slots rotate:
///
/// 1. a clip that wants service and was last served [maxStaleness] ago or
///    more goes first, the one served longest ago first: the fairness bound;
/// 2. then the foreground: the `maxAdvancing ~/ 2` most recently leased
///    clips (at least one) that want service, the surface that just came to
///    the front: a panel opening, a cell scrolling in;
/// 3. then the other clips that want service, the one served longest ago
///    first: round-robin, so the background keeps moving at more than the
///    bound's rate;
/// 4. then the rest, which have nothing to do anyway.
///
/// A clip wants service when a frame is ready to show or its ring has room
/// and no decode is in flight. So the slots go where work is, a clip waiting
/// on a slow decode never holds one, and the foreground cannot starve the
/// others: every one is served at least once per [maxStaleness], as far as
/// the cap allows (more overdue clips than slots are served oldest first).
/// A decode a slot started runs on to the ring's depth, so a served clip
/// catches its own clock up in one go.
///
/// A clip that was not painted for [visibleWindow] is not a candidate: its
/// cell is off screen or covered, its clock is not moving, and it takes no
/// slot until painted again (the sweep then frees its lease).
///
/// ## Memory
///
/// Decoded frames outside the pool live in at most `prefetch + 4` buffers per
/// clip (the ring, the frame being decoded and the ones being drawn), and a
/// clip only fills them once it has had a slot, so the total is bounded by
/// the leases, which the pool's cells bound: see [bufferedBytes].
///
/// ## Leases and the sweep
///
/// A paint is the only sign a paintable is on screen. One sweep timer, alive
/// only while leases exist, runs every [idleRelease]: a lease not wanted
/// since the previous sweep is released, so a clip that is cached but off
/// screen frees its slot, which stays in the pool, idle. A lease that starts
/// again (after a sweep, a restart) rewinds the clip and plays from its
/// first frame.
///
/// One lease per key: the atlas names an entry once in a batch.
///
/// Single-threaded on the UI isolate; the engine decodes elsewhere.
final class VideoFrameScheduler {
  /// Creates a scheduler that decodes with [engine], owns [atlas] and follows
  /// [clock].
  ///
  /// [atlas] should come from `VideoFrameAtlas.create`. [tickInterval] is the
  /// cadence floor passed to [PlaybackClock.follow]; zero asks for every clock
  /// frame.
  VideoFrameScheduler({
    required VideoEngine engine,
    required FrameAtlas<Object> atlas,
    required PlaybackClock clock,
    this.maxAdvancing = defaultMaxAdvancing,
    this.prefetch = 3,
    this.maxStaleness = const Duration(milliseconds: 250),
    this.visibleWindow = const Duration(milliseconds: 150),
    this.idleRelease = const Duration(seconds: 1),
    this.tickInterval = Duration.zero,
    VideoSweepTimerFactory startTimer = Timer.new,
  }) : assert(maxAdvancing > 0, 'at least one clip must have a slot'),
       assert(prefetch > 0, 'a clip needs at least one frame ahead'),
       _engine = engine,
       _atlas = atlas,
       _clock = clock,
       _startTimer = startTimer;

  /// Slots per tick when [maxAdvancing] is not given.
  ///
  /// Measured on an Apple M1 Pro through the real binding, one worker
  /// decodes 1400 to 3700 frames a second (H.264 and VP9, 128 to 512 px), so
  /// two workers carry about 90 clips at 30 fps and decode is not what limits
  /// a screen of clips there; a phone is several times slower. A screen is
  /// about a dozen clips (a few in the chat, a panel page of GIFs), so 12
  /// serves all of them every tick on a desktop and, above it, the slots
  /// rotate instead of freezing the oldest.
  static const int defaultMaxAdvancing = 12;

  /// How many clips get a slot per tick: may start a decode or draw a frame.
  /// Changeable at run time (a lab switch); it applies from the next tick.
  int maxAdvancing;

  /// The longest a clip that wants service waits for a slot while others are
  /// served ahead of it.
  final Duration maxStaleness;

  /// How long since its last paint a clip still counts as visible.
  final Duration visibleWindow;

  /// Decoded frames a clip keeps ahead of its clip time.
  final int prefetch;

  /// How long a lease may go unwanted before the sweep frees its slot.
  final Duration idleRelease;

  /// Shortest time between two ticks of the follow subscription.
  final Duration tickInterval;

  final VideoEngine _engine;
  final FrameAtlas<Object> _atlas;
  final PlaybackClock _clock;
  final VideoSweepTimerFactory _startTimer;
  final Map<Object, VideoFrameLease> _leases = <Object, VideoFrameLease>{};
  PlaybackSubscription? _following;
  Timer? _sweep;
  bool _inFlight = false;
  bool _disposed = false;
  int _nextSeq = 0;
  int _bufferedBytes = 0;
  Duration _now = Duration.zero;

  /// Leases alive now.
  int get leaseCount => _leases.length;

  /// Whether the scheduler is following the clock.
  bool get isFollowing => _following != null;

  /// Bytes of decoded frames held outside the pool's pages (rings, frames in
  /// flight and being drawn). Zero once every lease is released and the
  /// decodes that were in flight have ended.
  int get bufferedBytes => _bufferedBytes;

  /// Bytes of the pool's page images that exist.
  int get residentBytes => _atlas.residentBytes;

  /// A lease on [key]'s slot for frames of [clip], or null when every page is
  /// open and every cell pinned: the caller keeps showing its still, never an
  /// error.
  ///
  /// Throws a [StateError] when [key] already has a lease and an
  /// [ArgumentError] for a size the pool refuses.
  VideoFrameLease? acquire(Object key, VideoClip clip) {
    if (_disposed) return null;
    if (_leases.containsKey(key)) {
      throw StateError('$key already has a lease.');
    }
    final player = _ClipPlayer(this, clip);
    final handle = _atlas.acquire(
      key,
      source: player,
      width: clip.width,
      height: clip.height,
    );
    if (handle == null) return null;
    final lease = VideoFrameLease._(this, handle, player, _nextSeq++)
      .._wantedAt = _now
      .._servedAt = _now;
    _leases[key] = lease;
    _following ??= _clock.follow(_onTick, frameInterval: tickInterval);
    _sweep ??= _startTimer(idleRelease, _onSweep);
    return lease;
  }

  /// Says how long [lease]'s paintable has played; called at paint time.
  /// Marks the lease as painted for the sweep. Ignored once released.
  ///
  /// [played] only grows within a pass; its steps are what the clip advances
  /// by, while the clip advances.
  void want(VideoFrameLease lease, Duration played) {
    if (lease._released) return;
    lease._touched = true;
    lease._wantedAt = _now;
    lease._player.note(played);
  }

  /// Evicts every idle pool entry now, as memory pressure asks.
  void releaseIdle() => _atlas.releaseUnpinned();

  /// Releases every lease, stops following the clock and disposes the atlas.
  /// Idempotent.
  void dispose() {
    if (_disposed) return;
    List.of(_leases.values).forEach(_release);
    _disposed = true;
    _atlas.dispose();
  }

  void _release(VideoFrameLease lease) {
    if (lease._released) return;
    lease._released = true;
    lease._player.dispose();
    lease._handle.release();
    _leases.remove(lease._handle.key);
    if (_leases.isNotEmpty) return;
    _following?.cancel();
    _following = null;
    _sweep?.cancel();
    _sweep = null;
  }

  void _onTick(Duration now) {
    _now = now;
    final advancing = _chooseAdvancing(now);
    final due = <VideoFrameLease>[];
    for (final lease in advancing) {
      lease._player.step();
      if (_inFlight) continue;
      final ordinal = lease._player.takeFrameToShow();
      if (ordinal == null) continue;
      lease._requested = ordinal;
      due.add(lease);
    }
    if (due.isEmpty || _inFlight) return;
    _inFlight = true;
    _atlas
        .render([
          for (final lease in due)
            (handle: lease._handle, frame: lease._requested!),
        ])
        .then(
          (batch) {
            _inFlight = false;
            for (final lease in due) {
              lease._player.endBatch();
            }
            for (final handle in batch.failed) {
              _leases[handle.key]?._player.failed = true;
            }
          },
          onError: (Object error, StackTrace stack) {
            _inFlight = false;
            for (final lease in due) {
              lease._player
                ..endBatch()
                ..failed = true;
            }
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: error,
                stack: stack,
                library: 'video_decoder',
                context: ErrorDescription('while drawing a batch of frames'),
              ),
            );
          },
        );
  }

  /// The leases that get a slot this tick, and marks every lease's player
  /// as slotted or not. Held, failed and unpainted clips are not candidates.
  List<VideoFrameLease> _chooseAdvancing(Duration now) {
    final candidates = <VideoFrameLease>[];
    for (final lease in _leases.values) {
      final player = lease._player;
      player.slotted = false;
      player.playing = !lease._holding && !player.failed;
      if (player.playing && now - lease._wantedAt <= visibleWindow) {
        candidates.add(lease);
      }
    }
    if (candidates.length > maxAdvancing) {
      // Rotation: see the class doc. Each lease's tier is read once.
      final seqs = [for (final lease in candidates) lease._seq]
        ..sort((a, b) => b.compareTo(a));
      final foregroundFrom = seqs[math.max(1, maxAdvancing ~/ 2) - 1];
      final tiers = {
        for (final lease in candidates)
          lease: _tierOf(lease, now, foregroundFrom),
      };
      candidates.sort((a, b) {
        final byTier = tiers[a]!.compareTo(tiers[b]!);
        if (byTier != 0) return byTier;
        // Foreground: the newest. Otherwise the longest unserved.
        return tiers[a] == 1
            ? b._seq.compareTo(a._seq)
            : a._servedAt.compareTo(b._servedAt);
      });
      candidates.length = maxAdvancing;
    }
    for (final lease in candidates) {
      lease._player.slotted = true;
      lease._servedAt = now;
    }
    return candidates;
  }

  int _tierOf(VideoFrameLease lease, Duration now, int foregroundFrom) {
    if (!lease._player.wantsService) return 3;
    if (now - lease._servedAt >= maxStaleness) return 0;
    return lease._seq >= foregroundFrom ? 1 : 2;
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

/// One decoded frame: a buffer and where it sits on the clip's timeline.
final class _Frame {
  _Frame(this.number, this.time, this.pixels);

  /// Counts frames decoded since the lease began; the renderer's handle on it.
  final int number;

  /// Presentation time on the unwrapped timeline (passes added up).
  final Duration time;
  final Uint8List pixels;
}

/// The decode state of one leased clip: its ring, its clip time and the one
/// `nextFrame` in flight. Private to the scheduler, which is its only caller.
final class _ClipPlayer implements VideoFrameSource {
  _ClipPlayer(this._owner, this._clip) : _passLength = _clip.info.duration {
    final declared = _passLength;
    if (declared != null && declared <= Duration.zero) _passLength = null;
  }

  final VideoFrameScheduler _owner;
  final VideoClip _clip;

  /// Sorted by time. Frames at or before the clip time are shown (the newest)
  /// or dropped; the rest are the prefetch.
  final List<_Frame> _ring = [];
  final List<Uint8List> _free = [];
  final Map<int, _Frame> _drawing = {};
  _Frame? _toShow;

  /// Whether the clip's time runs: neither held nor failed.
  bool playing = true;

  /// Whether the clip had a slot at the last tick: only a slotted clip
  /// starts decodes.
  bool slotted = true;
  bool failed = false;
  bool _dead = false;
  bool _inFlight = false;
  bool _needsRewind = true;
  int _allocated = 0;
  int _number = 0;

  Duration _clipTime = Duration.zero;
  Duration? _lastPlayed;
  Duration _passBase = Duration.zero;
  Duration? _passLength;
  Duration _lastPts = Duration.zero;
  int _framesInPass = 0;

  bool get isPassComplete {
    final length = _passLength;
    return length != null && _clipTime >= length;
  }

  /// Takes the paintable's played time: its steps are clip time while this
  /// clip advances.
  void note(Duration played) {
    final last = _lastPlayed;
    _lastPlayed = played;
    if (last == null || !playing) return;
    final step = played - last;
    if (!step.isNegative) _clipTime += step;
  }

  /// Whether a slot would do something now: a frame is ready to show, or the
  /// ring has room and no decode is in flight.
  bool get wantsService {
    if (_dead || failed) return false;
    if (_toShow != null) return true;
    var ahead = 0;
    for (final frame in _ring) {
      if (frame.time <= _clipTime) return true;
      ahead++;
    }
    if (_inFlight || ahead >= _owner.prefetch) return false;
    return !(_free.isEmpty && _allocated >= _owner.prefetch + 4);
  }

  /// Picks the frame to show and starts the next decode.
  void step() {
    if (_dead || failed) return;
    _pickFrame();
    _pump();
  }

  void _pickFrame() {
    var best = -1;
    for (var i = 0; i < _ring.length; i++) {
      if (_ring[i].time <= _clipTime) best = i;
    }
    if (best < 0) return;
    for (var i = 0; i < best; i++) {
      _recycle(_ring[i].pixels);
    }
    final shown = _ring[best];
    _ring.removeRange(0, best + 1);
    final stale = _toShow;
    if (stale != null) _recycle(stale.pixels);
    _toShow = shown;
  }

  /// The number of the frame that should be drawn now, or null; moves it to
  /// the frames a batch is drawing.
  int? takeFrameToShow() {
    final frame = _toShow;
    if (frame == null) return null;
    _toShow = null;
    _drawing[frame.number] = frame;
    return frame.number;
  }

  /// A batch ended: the frames it drew are free again.
  void endBatch() {
    for (final frame in _drawing.values) {
      _recycle(frame.pixels);
    }
    _drawing.clear();
  }

  @override
  Uint8List? pixelsOf(int frame) => _drawing[frame]?.pixels;

  void _pump() {
    if (_inFlight || !slotted) return;
    final ahead = _ring.where((f) => f.time > _clipTime).length;
    if (ahead >= _owner.prefetch) return;
    // The ring, the frame in flight and the frames being drawn share a bound.
    if (_free.isEmpty && _allocated >= _owner.prefetch + 4) return;
    _inFlight = true;
    unawaited(_decodeOne());
  }

  Future<void> _decodeOne() async {
    Uint8List? buffer;
    try {
      if (_needsRewind) {
        final rewound = await _owner._engine.rewind(_clip);
        if (_dead) return;
        if (!rewound) {
          failed = true;
          return;
        }
        _needsRewind = false;
      }
      buffer = _take();
      final result = await _owner._engine.nextFrame(_clip, destination: buffer);
      if (_dead) return;
      switch (result.status) {
        case VideoFrameStatus.frame:
          final pts = Duration(milliseconds: result.ptsMs);
          _ring.add(_Frame(_number++, _passBase + pts, buffer));
          buffer = null;
          _lastPts = pts;
          _framesInPass++;
        case VideoFrameStatus.endOfStream:
          _endPass();
        case VideoFrameStatus.badArgument ||
            VideoFrameStatus.badSize ||
            VideoFrameStatus.failed:
          failed = true;
      }
    } on Object catch (error, stack) {
      failed = true;
      // The engine ended under the clip (disposed, or its worker): the host
      // is shutting down or the clip is gone, and there is nothing to report.
      if (error is! VideoEngineClosed && error is! VideoClipLost) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'video_decoder',
            context: ErrorDescription('while decoding a frame'),
          ),
        );
      }
    } finally {
      if (buffer != null) _recycle(buffer);
      _inFlight = false;
      // A decode that finishes goes straight on while the ring wants frames,
      // so a clock that ran ahead of a slow decode is caught up in one go.
      if (!_dead && !failed && _owner._leases.isNotEmpty) _pump();
    }
  }

  /// The stream ended: the next pass continues the timeline after this one.
  void _endPass() {
    final declared = _clip.info.duration;
    final interval = _frameInterval();
    final measured = _lastPts + interval;
    final length = declared != null && declared > _lastPts
        ? declared
        : measured;
    _passLength = length;
    _passBase += length;
    _lastPts = Duration.zero;
    _framesInPass = 0;
    _needsRewind = true;
  }

  Duration _frameInterval() {
    final rate = _clip.info.frameRate;
    if (rate > 0) return Duration(microseconds: (1000000 / rate).round());
    if (_framesInPass > 1) return _lastPts ~/ (_framesInPass - 1);
    return const Duration(milliseconds: 40);
  }

  Uint8List _take() {
    if (_free.isNotEmpty) return _free.removeLast();
    _allocated++;
    _owner._bufferedBytes += _clip.frameBytes;
    return Uint8List(_clip.frameBytes);
  }

  void _recycle(Uint8List buffer) {
    if (_dead) {
      _drop();
    } else {
      _free.add(buffer);
    }
  }

  void _drop() {
    _allocated--;
    _owner._bufferedBytes -= _clip.frameBytes;
  }

  void dispose() {
    if (_dead) return;
    _dead = true;
    // Buffers at rest are dropped now; the one in flight, if any, when it ends.
    final atRest =
        _ring.length +
        _free.length +
        _drawing.length +
        (_toShow == null ? 0 : 1);
    for (var i = 0; i < atRest; i++) {
      _drop();
    }
    _ring.clear();
    _free.clear();
    _drawing.clear();
    _toShow = null;
  }
}
