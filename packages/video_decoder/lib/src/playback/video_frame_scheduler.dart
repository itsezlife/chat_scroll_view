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

/// A paintable's claim on a clip's decoded frames and where they are shown,
/// handed out by a [VideoFrameScheduler]: a slot of the video pool, or a
/// platform texture of the scheduler's [FrameTexturePool] (ADR 043).
///
/// [sprite] says where the frame on show is, or null while there is none;
/// [texture] is the texture once a first frame was posted to it. At most one
/// is non-null; with neither the paintable keeps showing its still. A lease
/// ends when its holder [release]s it or the scheduler sweeps it for being
/// unpainted; a released lease is not revived, the holder acquires again.
final class VideoFrameLease {
  VideoFrameLease._(this._scheduler, this._key, this._player, this._seq);

  final VideoFrameScheduler _scheduler;
  final Object _key;
  final _ClipPlayer _player;

  // Where frames go: a slot, a texture, or both while the lease moves from
  // its slot to a texture (the slot shows until the texture is shown).
  FrameHandle<Object>? _slot;
  FrameTextureLease? _texture;
  // Frames posted to the texture since the lease took it. A texture keeps
  // frames of the asset that held it that the engine never showed (on Android
  // the surface producer queues up to two and shows them oldest first, one a
  // frame, only while the texture is on screen), so the texture is shown only
  // once this lease's posts pushed them out; until then the slot, or the
  // still, shows.
  int _posts = 0;
  int _missedLocks = 0;
  // Whether this lease has a frame being drawn or written: it is sent no
  // other until that one ends, and no other lease waits for it.
  bool _inFlight = false;
  // Whether the write in flight names the texture: it goes back to the pool
  // only when that write ends, so no other asset's write races it.
  bool _writing = false;
  // Whether a surface that only has a canvas painted it since the last sweep
  // but one: such a lease keeps a slot.
  bool _onCanvas = false;
  bool _canvasTouched = false;

  /// Order of acquisition: the newest is served first when slots are short.
  final int _seq;

  bool _touched = true;

  /// The tick time at the last paint (the acquisition counts as one).
  Duration _wantedAt = Duration.zero;

  /// The tick time at which the clip last had a slot.
  Duration _servedAt = Duration.zero;
  bool _released = false;
  // Whether the lease ended where its clip may go on from (it left the
  // screen, or went unpainted): a lease acquired after it continues the
  // clip's position, see `VideoFrameScheduler.acquire`.
  bool _resumable = false;
  bool _holding = false;
  bool _kept = false;
  // Whether its paintable left the screen and no want came since: the lease
  // goes when the frame is over (see releaseUnlessPainted).
  bool _leaving = false;

  /// Whether the lease is kept through the sweep however long it goes
  /// unpainted, where it is (on its slot or its texture): the frame it shows
  /// is on screen under a surface that holds its playback
  /// (`AssetPaintable.keepFrame`). Its clip time stands still, as nothing
  /// paints it. Letting go leaves it to the sweep again, from the next one.
  bool get kept => _kept;
  set kept(bool value) {
    if (_kept == value) return;
    _kept = value;
    // A lease let go counts as painted up to now, so a lease that was kept
    // for minutes lives one more idle period, as a painted one does.
    if (!value) _touched = true;
  }

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
  AtlasSprite? get sprite => _released || _shown ? null : _slot?.sprite;

  /// The texture that holds the current frame, or null until a first frame
  /// was posted to it (and for a lease on a slot). Read it when compositing
  /// and never keep it.
  AssetTexture? get texture => _released || !_shown ? null : _texture?.texture;

  bool get _shown => _posts >= VideoFrameScheduler._postsBeforeShown;

  /// Stops decoding and keeps the frame on show: a pass that does not loop
  /// ended on its last frame. The slot stays leased until [release].
  void hold() => _holding = true;

  /// Ends the lease. Idempotent. The entry stays in the pool, idle. The clip
  /// starts over on the next lease: its frame is not kept.
  void release() => _scheduler._release(this);

  /// Ends the lease once the current frame is over, unless its holder wants
  /// a frame before that or the lease is [kept] by then: the holder left the
  /// screen (`AssetPaintable.leftScreen`), but a surface that hides a cell
  /// may still paint it in the frame that hid it (a cell at the edge of a
  /// scrolling window), and giving that lease back would put
  /// the cell on its still and rewind its clip.
  void releaseUnlessPainted() => _scheduler._releaseUnlessPainted(this);
}

/// The one owner of a host's video frame pool: it decodes each playing clip a
/// few frames ahead of the clock and draws the frame the clock names on each
/// tick, every clip waiting only for its own frame.
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
/// ## Half frame rate
///
/// A paintable at half rate wants with a frame step of 2 ([want]): the clip
/// keeps the first decoded frame of each pass and every second one after it,
/// so it draws or posts half as many frames, as a playing asset drawn small
/// asks (`AssetProfile.halfFrameRate`). The dropped frames are decoded, as
/// decoding is sequential, but never reach the ring.
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
/// slot until painted again.
///
/// ## Leases: given back on leaving, taken when the pool is full, swept
///
/// A paint is the only sign a paintable is on screen. A lease ends in one of
/// three ways, so the pool's slots and textures go to the clips on screen:
///
/// 1. Its paintable left the screen: every binding of its entry hid or
///    detached, and the paintable called
///    [VideoFrameLease.releaseUnlessPainted]. The lease goes when the frame
///    is over unless it was painted in it, or kept. Without this a fling
///    filled the pool with the leases of cells that had flown past (ticket
///    116).
/// 2. An [acquire] found the pool full: the leases on slots that nothing
///    painted for [visibleWindow] give theirs up, the least recently painted
///    first, until one is free. A kept lease is never taken, nor one painted
///    within the window.
/// 3. The sweep, below, the backstop for what no surface said.
///
/// ## Memory
///
/// Decoded frames outside the pool live in at most `prefetch + 4` buffers per
/// clip (the ring, the frame being decoded and the ones being drawn), and a
/// clip only fills them once it has had a slot, so the total is bounded by
/// the leases, which the pool's cells bound, plus the decoded-ahead frames
/// kept for clips that left the screen, which [keptAheadBytes] bounds: see
/// [bufferedBytes].
///
/// ## Leases and the sweep
///
/// A paint is the only sign a paintable is on screen. One sweep timer, alive
/// only while leases exist, runs every [idleRelease]: a lease not wanted
/// since the previous sweep is released, so a clip that is cached but off
/// screen frees its slot, which stays in the pool, idle.
///
/// ## Coming back
///
/// A lease that ended because its clip left the screen or went unpainted
/// (leaving, a full pool, the sweep) keeps where the clip was: the next
/// lease of the same key that names it ([acquire]'s `after`) goes on from
/// the clip's time and the decoder's position, without a rewind. Its frame
/// stays too: the texture it showed while the texture pool
/// keeps it (shown at once, see `FrameTexturePool`, *Kept frames*), or the
/// pool slot that holds it.
///
/// The clip's time stands still while it is away, whatever its paintable
/// reports: the first want of the new lease only starts its timing again.
/// The frames it had decoded ahead stay with it, as long as the frames kept
/// for every clip away fit [keptAheadBytes] (the clip away longest gives
/// its frames up first). The decoder is past them and decodes in order:
/// without them the clip would hold its frame for those frames' time and
/// then skip them. With them it shows the next frame at its time, as if it
/// had never left. A clip whose frames were given up goes on from its frame
/// all the same, after that hold.
///
/// A lease [VideoFrameLease.release]d by its holder (a restart, a
/// rewind, a pass that rests on its first frame, a disposal) starts the
/// clip over from its first frame with no frame kept.
///
/// ## Textures
///
/// With a [FrameTexturePool] and a [TextureFrameWriter] (ADR 043), a lease
/// takes a texture when one of its size class is idle and a slot otherwise,
/// exactly as without them. A lease that found none asks the pool to warm
/// its class after the lease (the pool creates off the frame path, and waits
/// while a surface scrolls), and on a later tick a lease on a slot moves to a
/// texture that is idle then, keeping its slot until the first post. A lease
/// a surface that only has a canvas paints keeps a slot.
///
/// The cap, the ring and the sweep are the same for both: a slotted clip's
/// frame goes to the writer instead of the atlas, in the same tick.
///
/// ## Each clip waits only for its own frame
///
/// The clips on slots that have a frame to show are drawn as one atlas batch
/// a tick; each clip on a texture is written on its own. A clip with a frame
/// still being drawn or written is sent nothing (its ring goes on filling,
/// and the newest ready frame wins once that one ends), so a texture is
/// posted at most once a clock frame; every other clip goes on. One write per
/// clip, not one batch per tick: a batch is answered whole, so each clip in
/// it would wait for the slowest worker, and a batch that ran past a clock
/// frame would cost every clip that frame. Batches overlap: the atlas runs
/// its own one after the other, and a clip's writes go to the worker that
/// decodes it, which answers them in order.
///
/// A frame whose texture could not be locked is dropped (the texture keeps
/// the one before); [lockFailureLimit] in a row discard the texture and send
/// the clip back to a slot for the life of the scheduler.
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
  ///
  /// [textures] and [textureWriter] together let leases take textures; with
  /// either missing every lease takes a slot. The scheduler does not own the
  /// pool.
  VideoFrameScheduler({
    required VideoEngine engine,
    required FrameAtlas<Object> atlas,
    required PlaybackClock clock,
    FrameTexturePool? textures,
    TextureFrameWriter? textureWriter,
    this.maxAdvancing = defaultMaxAdvancing,
    this.prefetch = 3,
    this.maxStaleness = const Duration(milliseconds: 250),
    this.visibleWindow = const Duration(milliseconds: 150),
    this.idleRelease = const Duration(seconds: 1),
    this.tickInterval = Duration.zero,
    this.keptAheadBytes = defaultKeptAheadBytes,
    VideoSweepTimerFactory startTimer = Timer.new,
  }) : assert(maxAdvancing > 0, 'at least one clip must have a slot'),
       assert(prefetch > 0, 'a clip needs at least one frame ahead'),
       _engine = engine,
       _atlas = atlas,
       _clock = clock,
       _textures = textureWriter == null ? null : textures,
       _writer = textureWriter,
       _startTimer = startTimer;

  /// Frames in a row whose texture could not be locked before the clip goes
  /// back to a slot.
  static const int lockFailureLimit = 3;

  /// The default of [keptAheadBytes]: about a screen of a sticker grid's
  /// clips (at most 160 px a side, a ring of three frames and the one being
  /// decoded: 0.4 MiB a clip), or three clips of 512 px.
  static const int defaultKeptAheadBytes = 12 * 1024 * 1024;

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

  /// How long since its last paint a clip still counts as visible: it is a
  /// candidate for a slot of the cap, and a full pool never takes its lease.
  final Duration visibleWindow;

  /// Decoded frames a clip keeps ahead of its clip time.
  final int prefetch;

  /// How long a lease may go unwanted before the sweep frees its slot.
  final Duration idleRelease;

  /// Shortest time between two ticks of the follow subscription.
  final Duration tickInterval;

  /// What the decoded-ahead frames kept for clips that left the screen may
  /// cost together, in bytes (see *Coming back*). Zero keeps none.
  final int keptAheadBytes;

  // Posts of a lease before its texture is shown (see `_posts`): two push
  // the previous holder's queued frames out, the third makes sure the second
  // reached the queue.
  static const _postsBeforeShown = 3;

  final VideoEngine _engine;
  final FrameAtlas<Object> _atlas;
  final PlaybackClock _clock;
  final FrameTexturePool? _textures;
  final TextureFrameWriter? _writer;
  final VideoSweepTimerFactory _startTimer;
  final Map<Object, VideoFrameLease> _leases = <Object, VideoFrameLease>{};
  // Keys whose texture failed: they keep slots.
  final Set<Object> _refused = <Object>{};
  // Size classes a lease found no texture of since the last warm.
  final Set<int> _classesToWarm = <int>{};
  // Textures leases let go of that a write in flight still names, with the
  // key whose frame each keeps (see `_release`).
  final Map<FrameTextureLease, Object?> _returnAfterWrite = {};
  // Leases whose paintable left the screen, released when the frame is over
  // unless painted meanwhile.
  final Set<VideoFrameLease> _leaving = {};
  // The players of leases that ended where their clip may go on from, with
  // the frames they decoded ahead, by key: away longest first.
  final Map<Object, _ClipPlayer> _away = {};
  PlaybackSubscription? _following;
  Timer? _sweep;
  Timer? _leave;
  bool _disposed = false;
  int _nextSeq = 0;
  int _bufferedBytes = 0;
  Duration _now = Duration.zero;

  /// Leases alive now.
  int get leaseCount => _leases.length;

  /// Whether the scheduler is following the clock.
  bool get isFollowing => _following != null;

  /// Bytes of decoded frames held outside the pool's pages (rings, frames in
  /// flight and being drawn), those kept for clips that left the screen
  /// included. Zero once every lease is released, no clip keeps frames for
  /// its return ([forget], [releaseIdle]) and the decodes that were in
  /// flight have ended.
  int get bufferedBytes => _bufferedBytes;

  /// Bytes of the pool's page images that exist.
  int get residentBytes => _atlas.residentBytes;

  /// A lease for frames of [clip] under [key]: on a texture when one is free,
  /// else on a slot, taken from the least recently painted lease when the
  /// pool is full (see the class documentation); null when there is no
  /// texture and every slot is pinned by a lease on screen or kept: the
  /// caller keeps showing its still, never an error.
  ///
  /// [onCanvas] says the lease is for a surface that only has a canvas: it
  /// takes a slot, as [want] says.
  ///
  /// [after] is the holder's previous lease of [key], if any: when it ended
  /// where the clip may go on from, the new lease continues it (see *Coming
  /// back*); otherwise the clip starts over.
  ///
  /// Throws a [StateError] when [key] already has a lease and an
  /// [ArgumentError] for a size the pool refuses.
  VideoFrameLease? acquire(
    Object key,
    VideoClip clip, {
    bool onCanvas = false,
    VideoFrameLease? after,
  }) {
    if (_disposed) return null;
    if (_leases.containsKey(key)) {
      throw StateError('$key already has a lease.');
    }
    final resumes =
        after != null &&
        after._resumable &&
        after._key == key &&
        identical(after._player._clip, clip);
    // A clip that starts over shows no frame of where it was.
    if (!resumes) forget(key);
    final player = resumes ? _comeBack(after) : _ClipPlayer(this, clip);
    final lease = VideoFrameLease._(this, key, player, _nextSeq++)
      .._wantedAt = _now
      .._servedAt = _now
      .._onCanvas = onCanvas
      .._canvasTouched = onCanvas;
    if (!onCanvas) {
      final texture = lease._texture = _textureFor(
        lease,
        showing: resumes ? key : null,
      );
      if (texture != null && texture.showsFrame) {
        lease._posts = _postsBeforeShown;
      }
    }
    if (lease._texture == null) {
      final handle = _slotFor(lease) ?? _slotFromStalest(lease);
      if (handle == null) {
        player.dispose();
        return null;
      }
      lease._slot = handle;
      _warmFor(lease);
    }
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
  ///
  /// [onCanvas] says a surface that only has a canvas asks: it cannot show a
  /// texture, so a lease on one goes back to a slot, and the lease takes no
  /// texture until a whole sweep period passes without such a want.
  ///
  /// [frameStep] is how many decoded frames the clip moves by between the
  /// ones it shows (`AssetPaintContext.frameStepFor`): 2 at half rate, so only
  /// every second decoded frame of a pass is drawn or posted. Decoding is
  /// sequential, so the frames between are still decoded, and dropped unseen.
  void want(
    VideoFrameLease lease,
    Duration played, {
    bool onCanvas = false,
    int frameStep = 1,
  }) {
    assert(frameStep > 0, 'a clip moves by at least one frame');
    if (lease._released) return;
    lease
      .._touched = true
      .._wantedAt = _now
      .._leaving = false;
    lease._player
      ..frameStep = frameStep
      ..note(played);
    if (!onCanvas) return;
    lease
      .._onCanvas = true
      .._canvasTouched = true;
    if (lease._texture != null) _toSlot(lease);
  }

  /// Forgets the frame kept for [key]'s return, on an idle texture or slot:
  /// the clip will not go on from it (its paintable was disposed, or starts
  /// over). Nothing for a key that has a lease.
  void forget(Object key) {
    if (_disposed || _leases.containsKey(key)) return;
    _textures?.forgetFrameOf(key);
    _atlas.forgetFrame(key);
    _away.remove(key)?.dispose();
  }

  /// Evicts every idle pool entry now, and drops the frames decoded ahead
  /// for clips that left the screen, as memory pressure asks.
  void releaseIdle() {
    _atlas.releaseUnpinned();
    _forgetAway();
  }

  /// Releases every lease, stops following the clock and disposes the atlas.
  /// Idempotent.
  void dispose() {
    if (_disposed) return;
    List.of(_leases.values).forEach(_release);
    _forgetAway();
    _disposed = true;
    _returnAfterWrite
      ..keys.forEach(_giveBack)
      ..clear();
    _atlas.dispose();
  }

  // --- Textures ---

  /// Whether leases may take textures; true by default. Changeable at run
  /// time (a lab switch, so both arms of a comparison share one build): off,
  /// every lease on a texture goes back to a slot now and none takes one;
  /// on, leases move to idle textures from the next tick.
  bool get texturesEnabled => _texturesEnabled;
  bool _texturesEnabled = true;
  set texturesEnabled(bool value) {
    if (value == _texturesEnabled) return;
    _texturesEnabled = value;
    if (value) return;
    for (final lease in _leases.values) {
      if (lease._texture != null) _toSlot(lease);
    }
  }

  bool _mayTakeTexture(VideoFrameLease lease) {
    final pool = _textures;
    return _texturesEnabled &&
        pool != null &&
        !_refused.contains(lease._key) &&
        pool.classOf(lease._player.width, lease._player.height) != null;
  }

  FrameTextureLease? _textureFor(VideoFrameLease lease, {Object? showing}) =>
      _mayTakeTexture(lease)
      ? _textures!.lease(
          lease._player.width,
          lease._player.height,
          showing: showing,
        )
      : null;

  FrameHandle<Object>? _slotFor(VideoFrameLease lease) => _atlas.acquire(
    lease._key,
    source: lease._player,
    width: lease._player.width,
    height: lease._player.height,
  );

  // A lease that wanted a texture and found none asks the pool for as many of
  // its class as there are clips waiting in it, from the event loop after
  // the lease (which runs at paint time); the pool creates off the frame
  // path, and the waiting leases move on a later tick.
  void _warmFor(VideoFrameLease lease) {
    if (lease._onCanvas || !_mayTakeTexture(lease)) return;
    final sizeClass = _textures!.classOf(
      lease._player.width,
      lease._player.height,
    )!;
    if (!_classesToWarm.add(sizeClass)) return;
    if (_classesToWarm.length == 1) Timer.run(_warm);
  }

  void _warm() {
    final pool = _textures!;
    final classes = List.of(_classesToWarm);
    _classesToWarm.clear();
    if (_disposed) return;
    for (final sizeClass in classes) {
      final waiting = _leases.values
          .where(
            (lease) =>
                lease._texture == null &&
                !lease._onCanvas &&
                !lease.isFailed &&
                _mayTakeTexture(lease) &&
                pool.classOf(lease._player.width, lease._player.height) ==
                    sizeClass,
          )
          .length;
      if (waiting > 0) unawaited(pool.warm(sizeClass, waiting));
    }
  }

  void _moveToTextures() {
    final pool = _textures;
    if (pool == null || pool.idleTextures == 0) return;
    for (final lease in _leases.values) {
      // A kept lease stays where its frame is on screen: a move would draw
      // that frame again into the texture. A lease with a frame in flight
      // moves once it ends, so its write always names the texture it holds.
      if (lease._texture != null ||
          lease._onCanvas ||
          lease.isFailed ||
          lease._kept ||
          lease._inFlight) {
        continue;
      }
      final texture = _textureFor(lease);
      if (texture == null) continue;
      lease
        .._texture = texture
        .._posts = 0
        .._missedLocks = 0;
      if (pool.idleTextures == 0) return;
    }
  }

  void _giveBack(FrameTextureLease texture, [Object? showing]) =>
      texture.release(showing: showing);

  // A surface that cannot show the texture paints the lease: its frames go
  // to a slot again. Without a slot to take it keeps the texture, and the
  // canvas draws the still.
  void _toSlot(VideoFrameLease lease) {
    lease._slot ??= _slotFor(lease);
    if (lease._slot == null) return;
    _dropTexture(lease, discard: false);
  }

  void _dropTexture(VideoFrameLease lease, {required bool discard}) {
    final texture = lease._texture!;
    lease
      .._texture = null
      .._posts = 0;
    if (discard) {
      texture.discard();
    } else if (lease._writing) {
      _returnAfterWrite[texture] = null;
    } else {
      _giveBack(texture);
    }
  }

  // --- Coming back ---

  // The player of a lease that continues [previous]: [previous]'s own,
  // frames decoded ahead and all, while it is kept; else a new one that
  // starts from its state.
  _ClipPlayer _comeBack(VideoFrameLease previous) {
    final away = _away.remove(previous._key);
    if (identical(away, previous._player)) return away!..comeBack();
    away?.dispose();
    return _ClipPlayer.after(previous._player);
  }

  // [player]'s lease ended where its clip may go on from: the player keeps
  // its frames decoded ahead within the budget, the clip away longest giving
  // its frames up first.
  void _keepAway(Object key, _ClipPlayer player) {
    _away.remove(key)?.dispose();
    _away[key] = player..goAway();
    var bytes = 0;
    for (final away in _away.values) {
      bytes += away.heldBytes;
    }
    while (bytes > keptAheadBytes && _away.isNotEmpty) {
      final oldest = _away.remove(_away.keys.first)!;
      bytes -= oldest.heldBytes;
      oldest.dispose();
    }
  }

  void _forgetAway() {
    for (final player in _away.values) {
      player.dispose();
    }
    _away.clear();
  }

  // --- Leases ---

  // The pool is full. The leases on slots that no surface painted for the
  // visible window are off screen whatever their bindings say (the sweep
  // would free them within two idle periods): they give their slots up, the
  // least recently painted first, until the pool has one for [lease]. One at
  // a time, because a freed cell may be of another size class or pinned by
  // a batch still drawing into it. A lease on a texture alone frees no slot,
  // and its texture could not be leased again before the texture pool's
  // reuse delay, so it is left to the sweep.
  FrameHandle<Object>? _slotFromStalest(VideoFrameLease lease) {
    final stale = [
      for (final other in _leases.values)
        if (other._slot != null &&
            !other._kept &&
            _now - other._wantedAt > visibleWindow)
          other,
    ]..sort((a, b) => a._wantedAt.compareTo(b._wantedAt));
    for (final victim in stale) {
      _release(victim, keepFrame: true);
      if (_slotFor(lease) case final handle?) return handle;
    }
    return null;
  }

  void _releaseUnlessPainted(VideoFrameLease lease) {
    if (lease._released || _disposed) return;
    lease._leaving = true;
    _leaving.add(lease);
    // A zero timer runs once the event in progress is over: after the
    // frame's paint when the paintable left at its layout.
    _leave ??= _startTimer(Duration.zero, _releaseLeaving);
  }

  void _releaseLeaving() {
    _leave = null;
    final leaving = List.of(_leaving);
    _leaving.clear();
    for (final lease in leaving) {
      // Painted after it left (a hidden cell still drawn), or held on screen
      // by a surface that keeps its frame: it stays.
      if (lease._leaving && !lease._kept) _release(lease, keepFrame: true);
      lease._leaving = false;
    }
  }

  // [keepFrame] says the clip may come back and go on from where it is (it
  // left the screen, or went unpainted): the lease is resumable and the
  // frame it shows stays, on its texture (kept by the pool for its key) or
  // its slot. Not for a lease its holder released (the clip starts over), a
  // failed one, or a texture not shown yet.
  void _release(VideoFrameLease lease, {bool keepFrame = false}) {
    if (lease._released) return;
    final keeps = keepFrame && !lease.isFailed;
    lease
      .._released = true
      .._resumable = keeps;
    if (keeps && !_disposed) {
      _keepAway(lease._key, lease._player);
    } else {
      lease._player.dispose();
    }
    // A slot whose texture is shown holds an older frame: it is let go then.
    lease._slot?.release(keepFrame: keeps && !lease._shown);
    if (lease._texture case final texture?) {
      final showing = keeps && lease._shown ? lease._key : null;
      if (lease._writing && !_disposed) {
        _returnAfterWrite[texture] = showing;
      } else {
        _giveBack(texture, showing);
      }
    }
    _leases.remove(lease._key);
    if (_leases.isNotEmpty) return;
    _following?.cancel();
    _following = null;
    _sweep?.cancel();
    _sweep = null;
    _leave?.cancel();
    _leave = null;
    _leaving.clear();
  }

  void _onTick(Duration now) {
    _now = now;
    _moveToTextures();
    final advancing = _chooseAdvancing(now);
    final onSlots = <VideoFrameLease>[];
    final onTextures = <VideoFrameLease>[];
    for (final lease in advancing) {
      lease._player.step();
      if (lease._inFlight) continue;
      if (lease._slot == null && lease._texture == null) continue;
      final ordinal = lease._player.takeFrameToShow();
      if (ordinal == null) continue;
      lease
        .._requested = ordinal
        .._inFlight = true;
      (lease._texture != null ? onTextures : onSlots).add(lease);
    }
    if (onSlots.isNotEmpty) unawaited(_drawSlots(onSlots));
    onTextures.forEach(_writeTexture);
  }

  // A frame of [lease] ended, drawn or not: its buffer is free again and the
  // lease may be sent the next.
  void _endFrame(VideoFrameLease lease) {
    lease._inFlight = false;
    lease._player.endFrame(lease._requested!);
  }

  Future<void> _drawSlots(List<VideoFrameLease> due) async {
    try {
      final batch = await _atlas.render([
        for (final lease in due)
          (handle: lease._slot!, frame: lease._requested!),
      ]);
      for (final handle in batch.failed) {
        _leases[handle.key]?._player.failed = true;
      }
    } on Object catch (error, stack) {
      _batchFailed(due, error, stack, 'while drawing a batch of frames');
    } finally {
      due.forEach(_endFrame);
    }
  }

  Future<void> _writeTexture(VideoFrameLease lease) async {
    lease._writing = true;
    final texture = lease._texture!;
    try {
      final outcomes = await _writer!.write([
        TextureFrameJob(
          texture: texture.texture,
          frame: lease._requested!,
          width: lease._player.width,
          height: lease._player.height,
          source: lease._player,
        ),
      ]);
      if (lease._released || !identical(lease._texture, texture)) return;
      switch (outcomes.single) {
        case TextureFrameOutcome.posted:
          lease
            .._posts += 1
            .._missedLocks = 0;
          // Shown now: the slot it came from goes.
          if (lease._shown) {
            lease._slot?.release();
            lease._slot = null;
          }
        case TextureFrameOutcome.notLocked:
          // The frame is dropped: the texture keeps the one before, and the
          // ring has the next.
          if (++lease._missedLocks >= lockFailureLimit) {
            _refused.add(lease._key);
            _dropTexture(lease, discard: true);
            lease._slot ??= _slotFor(lease);
          }
        case TextureFrameOutcome.failed:
          lease._player.failed = true;
      }
    } on Object catch (error, stack) {
      _batchFailed([lease], error, stack, 'while writing a texture');
    } finally {
      lease._writing = false;
      _endFrame(lease);
      if (_returnAfterWrite.containsKey(texture)) {
        _giveBack(texture, _returnAfterWrite.remove(texture));
      }
    }
  }

  void _batchFailed(
    List<VideoFrameLease> due,
    Object error,
    StackTrace stack,
    String context,
  ) {
    for (final lease in due) {
      lease._player.failed = true;
    }
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'video_decoder',
        context: ErrorDescription(context),
      ),
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
      if (lease._kept) continue;
      if (!lease._canvasTouched) lease._onCanvas = false;
      lease._canvasTouched = false;
      if (lease._touched) {
        lease._touched = false;
      } else {
        _release(lease, keepFrame: true);
        continue;
      }
      // Asked again at every sweep, not only at the lease: a lease that left
      // the canvas, or found the pool's budget spent when it began, would
      // otherwise play from a slot (a page upload on every tick) for its
      // whole life. The pool answers at once when it cannot make one.
      if (lease._texture == null && !lease.isFailed) _warmFor(lease);
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

  /// The player of a lease that continues [previous]'s once [previous] gave
  /// its frames up (see *Coming back*): the same clip time and timeline, and
  /// the decoder where it is, so no rewind unless [previous] owed one. Its
  /// ring is not carried: those
  /// frames are gone with its buffers, and the decoder is past them, so the
  /// next frame decoded is a few ahead of the clip time and shows when the
  /// clip time reaches it. A decode [previous] had in flight lands unseen,
  /// one frame more of the same.
  _ClipPlayer.after(_ClipPlayer previous)
    : _owner = previous._owner,
      _clip = previous._clip,
      _clipTime = previous._clipTime,
      _passBase = previous._passBase,
      _passLength = previous._passLength,
      _lastPts = previous._lastPts,
      _framesInPass = previous._framesInPass,
      _needsRewind = previous._needsRewind,
      _number = previous._number;

  final VideoFrameScheduler _owner;
  final VideoClip _clip;

  @override
  VideoClip get clip => _clip;

  /// Pixels of a row of a frame.
  int get width => _clip.width;

  /// Rows of a frame.
  int get height => _clip.height;

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

  /// Decoded frames of a pass the clip moves by between the ones it keeps.
  int frameStep = 1;
  bool failed = false;
  bool _dead = false;
  // Whether its lease ended and it waits for its clip to come back: it
  // starts no decode and keeps no spare buffers.
  bool _away = false;
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
  /// the frames being drawn.
  int? takeFrameToShow() {
    final frame = _toShow;
    if (frame == null) return null;
    _toShow = null;
    _drawing[frame.number] = frame;
    return frame.number;
  }

  /// The draw or write of frame [number] ended: its buffer is free again.
  /// That frame alone: a lease that came back may send a frame while the
  /// one its previous lease sent is still being written.
  void endFrame(int number) {
    if (_drawing.remove(number) case final frame?) _recycle(frame.pixels);
  }

  /// The bytes of the buffers it holds.
  int get heldBytes => _allocated * _clip.frameBytes;

  /// Its lease ended where the clip may go on from: it keeps its ring and
  /// its clip time, starts no decode and gives its spare buffers back.
  void goAway() {
    _away = true;
    slotted = false;
    for (var i = 0; i < _free.length; i++) {
      _drop();
    }
    _free.clear();
  }

  /// A new lease goes on with it. Its clip time starts again from the next
  /// played time it is told: the time it was away is not played.
  void comeBack() {
    _away = false;
    _lastPlayed = null;
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
          // A frame between two kept ones is dropped unseen: its buffer goes
          // back in `finally`. It still counts for the pass length.
          if (_framesInPass % frameStep == 0) {
            _ring.add(_Frame(_number++, _passBase + pts, buffer));
            buffer = null;
          }
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
    if (_dead || _away) {
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
