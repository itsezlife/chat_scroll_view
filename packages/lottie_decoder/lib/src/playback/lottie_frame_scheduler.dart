import 'dart:async';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/frame_pool.dart';
import 'package:flutter/foundation.dart';

/// Starts the sweep timer; `Timer.new` by default, a manual one in tests.
typedef LottieSweepTimerFactory =
    Timer Function(Duration delay, void Function() callback);

/// A paintable's claim on where its frames go, handed out by a
/// [LottieFrameScheduler]: a [FrameAtlas] slot, or a platform texture of the
/// scheduler's [FrameTexturePool] (ADR 043).
///
/// [sprite] says where the frame the slot holds is, or null while there is
/// none to draw; [texture] is the texture once a first frame was posted to
/// it, else null. At most one of them is non-null; with neither the
/// paintable keeps showing its still. A lease ends when its holder [release]s
/// it or when the scheduler sweeps it for being unpainted; a released lease
/// is not revived, the holder [acquire]s again.
///
/// [acquire]: LottieFrameScheduler.acquire
final class LottieFrameLease {
  LottieFrameLease._(
    this._scheduler,
    this._key,
    this._source,
    this._width,
    this._height,
  );

  final LottieFrameScheduler _scheduler;
  final Object _key;
  final Object _source;
  final int _width;
  final int _height;

  // Where frames go. A lease holds a slot, a texture, or both while it moves
  // from its slot to a texture (the slot shows until the texture is
  // post); with neither (a full pool after a texture failed) it shows its
  // still.
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
  // Whether this lease has a frame in flight, on its slot or its texture: it
  // is sent nothing more until that frame ends, and no other lease waits for
  // it.
  bool _inFlight = false;
  // Whether the write in flight names the texture: it goes back to the pool
  // only when that write ends, so no other asset's write races it.
  bool _writing = false;

  // The frame the paintable wants now, the one last sent to the renderer, and
  // whether a want arrived since the last sweep.
  int? _wanted;
  int? _requested;
  bool _touched = true;
  // The scheduler's tick time at the last want (the acquisition counts as
  // one): how a full pool finds the lease painted least recently.
  Duration _wantedAt = Duration.zero;
  // Whether its paintable left the screen and no want came since: the lease
  // goes when the frame is over (see releaseUnlessPainted).
  bool _leaving = false;
  // Whether a surface that only has a canvas painted it since the last sweep
  // but one: such a lease keeps a slot, whose sprite a canvas can draw.
  bool _onCanvas = false;
  bool _canvasTouched = false;
  bool _released = false;
  bool _failed = false;
  bool _kept = false;

  /// Whether the lease is kept through the sweep however long it goes
  /// unpainted, where it is (on its slot or its texture), rendering nothing
  /// new: the frame it shows is on screen under a surface that holds its
  /// playback (`AssetPaintable.keepFrame`). Letting go leaves it to the sweep
  /// again, from the next one.
  bool get kept => _kept;
  set kept(bool value) {
    if (_kept == value) return;
    _kept = value;
    // A lease let go counts as painted up to now, so a lease that was kept
    // for minutes lives one more idle period, as a painted one does.
    if (!value) _touched = true;
  }

  /// Whether the renderer could not render this animation. The holder keeps
  /// painting its still and stops asking.
  bool get isFailed => _failed;

  /// Whether the lease ended.
  bool get isReleased => _released;

  /// Where the current frame is, or null while there is nothing to draw. Read
  /// it when painting and never keep it, as [FrameHandle.sprite] says.
  AtlasSprite? get sprite => _released || _shown ? null : _slot?.sprite;

  /// The texture that holds the current frame, or null until a first frame
  /// was posted to it (and for a lease on a slot). Read it when compositing
  /// and never keep it.
  AssetTexture? get texture => _released || !_shown ? null : _texture?.texture;

  bool get _shown => _posts >= LottieFrameScheduler._postsBeforeShown;

  bool get _needsRender =>
      !_released &&
      !_failed &&
      !_inFlight &&
      (_slot != null || _texture != null) &&
      _wanted != null &&
      _wanted != _requested;

  /// Ends the lease. Idempotent. The entry stays in the pool, idle.
  void release() => _scheduler._release(this);

  /// Ends the lease once the current frame is over, unless its holder wants
  /// a frame before that or the lease is [kept] by then: the holder left the
  /// screen (`AssetPaintable.leftScreen`), but a surface that hides a cell
  /// may still paint it in the frame that hid it (a panel's cells are hidden
  /// while a fling runs, and drawn), and giving that lease back would put
  /// the cell on its still while a new lease shows its first posts.
  void releaseUnlessPainted() => _scheduler._releaseUnlessPainted(this);
}

/// The one owner of a host's [FrameAtlas]: it works out, once per clock tick,
/// which frames the visible animations want and sends each lease its own.
///
/// Paintables are pull-driven and never schedule: at paint time one calls
/// [want] with the frame its clock time asks for. The scheduler drives itself
/// with [PlaybackClock.follow], so it is gated by the same pause layers as
/// every binding and an idle clock sleeps; a paused app renders nothing. The
/// subscription exists while a lease does.
///
/// ## A tick
///
/// Each lease that wants a frame it was not sent, and has no frame in flight,
/// is sent its latest want: the leases on slots together, as one
/// [FrameAtlas.render], each lease on a texture as a write of its own. A lease
/// waits only for its own frame: a want made while that frame runs replaces
/// the one before it and goes out on the first tick after it ends, so a slow
/// frame coalesces, it never queues, and it never holds back another lease's
/// next frame (the reference client schedules each animation's next frame on
/// its own, the same way). Batches therefore overlap: the atlas runs its own
/// one after the other, and each render isolate answers in the order it was
/// sent, an animation always on the same one, so a lease's frames land in
/// order. Of the writes of a tick the largest frame goes first, as the one
/// most in view. A want for the frame already sent is free, so a paused
/// animation costs nothing. A paintable at half frame rate
/// (`AssetProfile.halfFrameRate`) wants only every second frame, so its slot
/// or texture is rendered and posted half as often, by the same rule.
///
/// The bindings of the animated paintables are targets of the same clock and
/// repaint on their own, so no repaint signal goes out from here. The follow
/// subscription may tick before or after the bindings of the same frame
/// (registration order), so a rendered frame can show one tick later: the
/// paintable asks one frame ahead for that, which is the "one to two frames
/// ahead" budget.
///
/// ## Leases: given back on leaving, taken when the pool is full, swept
///
/// A paint is the only sign a paintable is on screen. A lease ends in one of
/// three ways, so the pool's slots and textures go to the cells on screen:
///
/// 1. Its paintable left the screen: every binding of its entry hid or
///    detached, and the paintable called
///    [LottieFrameLease.releaseUnlessPainted]. The lease goes when the frame
///    is over unless it was painted in it, or kept. Without this a fling
///    filled the pool with the leases of cells that had flown past, and the
///    cells it brought in showed their stills for seconds (ticket 116).
/// 2. An [acquire] found the pool full: the leases on slots that nothing
///    painted for [visibleWindow] give theirs up, the least recently painted
///    first, until one is free. A kept lease is never taken, nor one painted
///    within the window, which covers the current frame and a surface that
///    repaints only every few frames (a cell at half rate), so leases on
///    screen never pass a slot back and forth.
/// 3. The sweep, the backstop for what no surface said: one timer, alive only
///    while leases exist, runs every [idleRelease], and a lease that was not
///    wanted since the previous sweep is released. A lease therefore lives at
///    most twice [idleRelease] unpainted.
///
/// A released lease's slot stays in the pool idle (evictable, not evicted),
/// and its texture idles in the texture pool for its reuse delay, so a cell
/// that comes back soon finds its frame.
///
/// ## Textures
///
/// With a [FrameTexturePool] and a [TextureFrameWriter] (ADR 043), a lease
/// takes a texture when one of its size class is idle, and a slot otherwise,
/// exactly as without them: the pool never blocks and never creates on a
/// lease. A lease that found none asks the pool to warm its class (the pool
/// creates off the frame path, and waits while a surface scrolls), and on a
/// later tick a lease on a slot moves to a texture that is idle then, keeping
/// its slot until the texture is shown so nothing flashes.
///
/// Textures are asked like slots: the same wants, the same pause layers, the
/// same sweep. A tick sends a write for each lease on a texture next to the
/// batch to the atlas, and a lease is sent nothing while its frame runs, so a
/// texture is posted at most once a clock frame. One write per lease, not one
/// batch per tick: a batch is answered whole, so every lease in it would wait
/// for its slowest frame, and a batch that ran past a clock frame would cost
/// every lease that frame. A frame whose texture could not be locked is
/// skipped and asked again; [lockFailureLimit] such frames in a row discard
/// the texture and send the asset back to a page slot for the life of the
/// scheduler (ADR 043, "Failure").
///
/// One lease per key: the atlas names an entry once in a batch.
///
/// Single-threaded on the UI isolate.
final class LottieFrameScheduler {
  /// Creates a scheduler that owns [atlas] and follows [clock].
  ///
  /// [tickInterval] is the cadence floor passed to [PlaybackClock.follow]; zero
  /// asks for every clock frame. [textures] and [textureWriter] together let
  /// leases take textures; with either missing every lease takes a slot. The
  /// scheduler does not own the pool.
  LottieFrameScheduler({
    required FrameAtlas<Object> atlas,
    required PlaybackClock clock,
    FrameTexturePool? textures,
    TextureFrameWriter? textureWriter,
    this.idleRelease = const Duration(seconds: 1),
    this.visibleWindow = const Duration(milliseconds: 150),
    this.tickInterval = Duration.zero,
    LottieSweepTimerFactory startTimer = Timer.new,
  }) : _atlas = atlas,
       _clock = clock,
       _textures = textureWriter == null ? null : textures,
       _writer = textureWriter,
       _startTimer = startTimer;

  /// Frames in a row whose texture could not be locked before the asset goes
  /// back to a page slot.
  static const int lockFailureLimit = 3;

  /// How long a lease may go unwanted before the sweep frees its slot.
  final Duration idleRelease;

  /// How long since its last paint, in the clock's playback time, a lease
  /// still counts as on screen: a full pool never takes it. Several clock
  /// frames, so a surface that repaints only every few frames keeps its
  /// lease; the clock's pauses do not count.
  final Duration visibleWindow;

  /// Shortest time between two ticks of the follow subscription.
  final Duration tickInterval;

  // Posts of a lease before its texture is shown (see `_posts`): two push
  // the previous holder's queued frames out, the third makes sure the second
  // reached the queue.
  static const _postsBeforeShown = 3;

  final FrameAtlas<Object> _atlas;
  final PlaybackClock _clock;
  final FrameTexturePool? _textures;
  final TextureFrameWriter? _writer;
  final LottieSweepTimerFactory _startTimer;
  final Map<Object, LottieFrameLease> _leases = <Object, LottieFrameLease>{};
  // Keys whose texture failed: they keep slots.
  final Set<Object> _refused = <Object>{};
  // Size classes a lease found no texture of since the last warm.
  final Set<int> _classesToWarm = <int>{};
  // Textures leases let go of that a write in flight still names.
  final Set<FrameTextureLease> _returnAfterWrite = {};
  // Leases whose paintable left the screen, released when the frame is over
  // unless painted meanwhile.
  final Set<LottieFrameLease> _leaving = {};
  PlaybackSubscription? _following;
  Timer? _sweep;
  Timer? _leave;
  // The time of the last tick: what a want is stamped with.
  Duration _now = Duration.zero;
  bool _disposed = false;

  /// Leases alive now.
  int get leaseCount => _leases.length;

  /// Whether the scheduler is following the clock.
  bool get isFollowing => _following != null;

  /// A lease for frames of [width] x [height] pixels of [source] (what the
  /// renderer renders) under [key]: on a texture when one is free, else on a
  /// slot, taken from the least recently painted lease when the pool is full
  /// (see the class documentation); null when there is no texture and every
  /// slot is pinned by a lease on screen or kept: the caller keeps showing
  /// its still, never an error.
  ///
  /// Throws a [StateError] when [key] already has a lease and an
  /// [ArgumentError] for a size the pool refuses.
  ///
  /// [onCanvas] says the lease is for a surface that only has a canvas and
  /// draws [LottieFrameLease.sprite]: it takes a slot, as [want] says.
  LottieFrameLease? acquire(
    Object key,
    Object source,
    int width,
    int height, {
    bool onCanvas = false,
  }) {
    if (_disposed) return null;
    if (_leases.containsKey(key)) {
      throw StateError('$key already has a lease.');
    }
    final lease = LottieFrameLease._(this, key, source, width, height)
      .._wantedAt = _now
      .._onCanvas = onCanvas
      .._canvasTouched = onCanvas;
    if (!onCanvas) lease._texture = _textureFor(lease);
    if (lease._texture == null) {
      final handle = _slotFor(lease) ?? _slotFromStalest(lease);
      if (handle == null) return null;
      lease._slot = handle;
      _warmFor(lease);
    }
    _leases[key] = lease;
    _following ??= _clock.follow(_onTick, frameInterval: tickInterval);
    _sweep ??= _startTimer(idleRelease, _onSweep);
    return lease;
  }

  /// Says which frame [lease] wants now; called at paint time. Marks the lease
  /// as painted for the sweep. Ignored once released.
  ///
  /// [onCanvas] says a surface that only has a canvas asks: it cannot show a
  /// texture, so a lease on one goes back to a slot, and the lease takes no
  /// texture until a whole sweep period passes without such a want.
  void want(LottieFrameLease lease, int frame, {bool onCanvas = false}) {
    if (lease._released) return;
    lease
      .._wanted = frame
      .._touched = true
      .._wantedAt = _now
      .._leaving = false;
    if (!onCanvas) return;
    lease
      .._onCanvas = true
      .._canvasTouched = true;
    if (lease._texture != null) _toSlot(lease);
  }

  /// Releases every lease, stops following the clock and disposes the atlas.
  /// Idempotent.
  void dispose() {
    if (_disposed) return;
    List.of(_leases.values).forEach(_release);
    _disposed = true;
    _returnAfterWrite
      ..forEach(_giveBack)
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

  bool _mayTakeTexture(LottieFrameLease lease) {
    final pool = _textures;
    return _texturesEnabled &&
        pool != null &&
        !_refused.contains(lease._key) &&
        pool.classOf(lease._width, lease._height) != null;
  }

  FrameTextureLease? _textureFor(LottieFrameLease lease) =>
      _mayTakeTexture(lease)
      ? _textures!.lease(lease._width, lease._height)
      : null;

  // A lease that wanted a texture and found none asks the pool for as many of
  // its class as there are leases waiting in it. Not from the lease, which
  // runs at paint time: from the event loop after it, once for every class
  // that missed; the pool then creates off the frame path, and the waiting
  // leases move on a later tick.
  void _warmFor(LottieFrameLease lease) {
    if (!_mayTakeTexture(lease)) return;
    final pool = _textures!;
    if (!_classesToWarm.add(pool.classOf(lease._width, lease._height)!)) {
      return;
    }
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
                !lease._failed &&
                !lease._onCanvas &&
                _mayTakeTexture(lease) &&
                pool.classOf(lease._width, lease._height) == sizeClass,
          )
          .length;
      if (waiting > 0) unawaited(pool.warm(sizeClass, waiting));
    }
  }

  void _moveToTextures() {
    final pool = _textures;
    if (pool == null || pool.idleTextures == 0) return;
    for (final lease in _leases.values) {
      // A kept lease stays where its frame is on screen: a move would render
      // that frame again into the texture. A lease with a frame in flight
      // moves once it ends, so its write always names the texture it holds.
      if (lease._texture != null ||
          lease._failed ||
          lease._onCanvas ||
          lease._kept ||
          lease._inFlight) {
        continue;
      }
      final texture = _textureFor(lease);
      if (texture == null) continue;
      lease
        .._texture = texture
        .._posts = 0
        .._missedLocks = 0
        // The texture is blank: the frame on the slot is asked again.
        .._requested = null;
      if (pool.idleTextures == 0) return;
    }
  }

  void _giveBack(FrameTextureLease texture) => texture.release();

  // A surface that cannot show the texture paints the lease: its frames go
  // to a slot again. Without a slot to take it keeps the texture, and the
  // canvas draws the still, as for a full pool.
  void _toSlot(LottieFrameLease lease) {
    lease._slot ??= _slotFor(lease);
    if (lease._slot == null) return;
    _dropTexture(lease, discard: false);
  }

  void _dropTexture(LottieFrameLease lease, {required bool discard}) {
    final texture = lease._texture!;
    lease
      .._texture = null
      .._posts = 0
      .._requested = null;
    if (discard) {
      texture.discard();
    } else if (lease._writing) {
      _returnAfterWrite.add(texture);
    } else {
      _giveBack(texture);
    }
  }

  // The texture keeps failing to lock: it is destroyed, and the asset keeps
  // (or takes) a slot from now on.
  void _refuseTexture(LottieFrameLease lease) {
    _refused.add(lease._key);
    _dropTexture(lease, discard: true);
    lease._slot ??= _slotFor(lease);
  }

  // --- Leases ---

  FrameHandle<Object>? _slotFor(LottieFrameLease lease) => _atlas.acquire(
    lease._key,
    source: lease._source,
    width: lease._width,
    height: lease._height,
  );

  // The pool is full. The leases on slots that no surface painted for the
  // visible window are off screen whatever their bindings say (the sweep
  // would free them within two idle periods): they give their slots up, the
  // least recently painted first, until the pool has one for [lease]. One at
  // a time, because a freed cell may be of another size class or pinned by
  // a batch still rendering into it. A lease on a texture alone frees no
  // slot, and its texture could not be leased again before the texture
  // pool's reuse delay, so it is left to the sweep.
  FrameHandle<Object>? _slotFromStalest(LottieFrameLease lease) {
    final stale = [
      for (final other in _leases.values)
        if (other._slot != null &&
            !other._kept &&
            _now - other._wantedAt > visibleWindow)
          other,
    ]..sort((a, b) => a._wantedAt.compareTo(b._wantedAt));
    for (final victim in stale) {
      _release(victim);
      if (_slotFor(lease) case final handle?) return handle;
    }
    return null;
  }

  void _releaseUnlessPainted(LottieFrameLease lease) {
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
      if (lease._leaving && !lease._kept) _release(lease);
      lease._leaving = false;
    }
  }

  void _release(LottieFrameLease lease) {
    if (lease._released) return;
    lease._released = true;
    lease._slot?.release();
    final texture = lease._texture;
    if (texture != null) {
      if (lease._writing && !_disposed) {
        _returnAfterWrite.add(texture);
      } else {
        _giveBack(texture);
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

  // --- A tick ---

  void _onTick(Duration now) {
    _now = now;
    _moveToTextures();
    final onSlots = <LottieFrameLease>[];
    final onTextures = <LottieFrameLease>[];
    for (final lease in _leases.values) {
      if (!lease._needsRender) continue;
      lease
        .._requested = lease._wanted
        .._inFlight = true;
      (lease._texture != null ? onTextures : onSlots).add(lease);
    }
    if (onSlots.isNotEmpty) unawaited(_renderSlots(onSlots));
    // The largest frames go first: a render isolate answers in arrival
    // order, so this puts the surface in front (a chat sticker) ahead of the
    // small cells of a panel queued on the same isolate. The sort is stable,
    // so leases of one size keep their order.
    onTextures
      ..sort((a, b) => (b._width * b._height).compareTo(a._width * a._height))
      ..forEach(_writeTexture);
  }

  Future<void> _renderSlots(List<LottieFrameLease> due) async {
    try {
      final batch = await _atlas.render([
        for (final lease in due)
          (handle: lease._slot!, frame: lease._requested!),
      ]);
      for (final handle in batch.failed) {
        final lease = _leases[handle.key];
        if (lease != null && identical(lease._slot, handle)) {
          lease._failed = true;
        }
      }
    } on Object catch (error, stack) {
      _batchFailed(due, error, stack, 'while rendering a batch of frames');
    } finally {
      for (final lease in due) {
        lease._inFlight = false;
      }
    }
  }

  Future<void> _writeTexture(LottieFrameLease lease) async {
    lease._writing = true;
    final texture = lease._texture!;
    try {
      final outcomes = await _writer!.write([
        TextureFrameJob(
          texture: texture.texture,
          frame: lease._requested!,
          width: lease._width,
          height: lease._height,
          source: lease._source,
        ),
      ]);
      // A lease released or moved off this texture meanwhile is not told.
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
          // Skipped: the texture keeps its previous frame and the want is
          // asked again on the next tick.
          lease._requested = null;
          if (++lease._missedLocks >= lockFailureLimit) {
            _refuseTexture(lease);
          }
        case TextureFrameOutcome.failed:
          lease._failed = true;
      }
    } on Object catch (error, stack) {
      _batchFailed([lease], error, stack, 'while writing a texture');
    } finally {
      lease
        .._writing = false
        .._inFlight = false;
      if (_returnAfterWrite.remove(texture)) _giveBack(texture);
    }
  }

  void _batchFailed(
    List<LottieFrameLease> due,
    Object error,
    StackTrace stack,
    String context,
  ) {
    // A batch that threw says nothing of which job was at fault: none of them
    // is asked again, rather than failing on every tick.
    for (final lease in due) {
      lease._failed = true;
    }
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'lottie_decoder',
        context: ErrorDescription(context),
      ),
    );
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
        _release(lease);
        continue;
      }
      // Asked again at every sweep, not only at the lease: a lease that left
      // the canvas, or found the pool's budget spent when it began, would
      // otherwise play from a slot (a page upload on every tick) for its
      // whole life. The pool answers at once when it cannot make one.
      if (lease._texture == null && !lease._failed) _warmFor(lease);
    }
    if (_leases.isNotEmpty) _sweep = _startTimer(idleRelease, _onSweep);
  }
}
