import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter/painting.dart';
import 'package:video_decoder/src/engine/video_engine.dart';
import 'package:video_decoder/src/paint/video_still_paintable.dart';
import 'package:video_decoder/src/playback/video_frame_scheduler.dart';

/// A video clip played by the shared clock through a [VideoFrameScheduler].
///
/// Pull-driven, like `PlayingImagePaintable`, and shared by every surface of
/// its entry. It never schedules a timer. A paint that animates adds up how
/// long the clip has played, tells the scheduler ([VideoFrameScheduler.want]),
/// and draws the sprite its lease holds; with no sprite yet, a failed lease or
/// a full pool it draws the first-frame still, so nothing is blank and a late
/// frame keeps the last sprite.
///
/// ## Drawn by the surface
///
/// [sprite] is the lease's current frame, null until one exists. A surface
/// that batches sprites calls [advancePlayback] (the first half of [paint])
/// and then draws [sprite] itself, falling back to [paint] for the still while
/// it is null.
///
/// ## Played time
///
/// The same rule as the Lottie animation: each paint adds how far the clock
/// moved since the previous one, and a step larger than [resumeGap], or
/// backwards, adds nothing, because the clock stood still while paused and then
/// jumped by the pause ("freeze and continue").
///
/// ## One pass, then a rest frame
///
/// A paint that does not loop plays the clip once. When it has played to its
/// end it holds the rest frame (`AssetPaintContext.restFrame`) and asks for
/// nothing ([isHolding]): the last frame stays in the slot, the first frame is
/// the still (the slot is given back). [restart], or a paint that loops, plays
/// another pass from the first frame.
///
/// ## Failure
///
/// A lease whose clip could not be decoded is never asked again: the paintable
/// keeps painting its still.
final class VideoAnimationPaintable extends AssetPaintable {
  /// Creates the paintable of [clip].
  ///
  /// It owns [firstFrame] from now on. [key] names its entry in the
  /// scheduler's pool (one paintable per key). [onDispose] runs once, from
  /// [dispose]: the paintable holds a clip but no engine, so whoever owns the
  /// engine closes the clip there.
  VideoAnimationPaintable({
    required Object key,
    required VideoClip clip,
    required ui.Image firstFrame,
    required VideoFrameScheduler scheduler,
    VoidCallback? onDispose,
  }) : _key = key,
       _clip = clip,
       _still = VideoStillPaintable(firstFrame),
       _scheduler = scheduler,
       _onDispose = onDispose;

  /// The largest step of the clock between two paints that counts as time
  /// played; a longer one is a pause that ended.
  static const Duration resumeGap = Duration(milliseconds: 500);

  final Object _key;
  final VideoClip _clip;
  final VideoStillPaintable _still;
  final VideoFrameScheduler _scheduler;
  final VoidCallback? _onDispose;

  VideoFrameLease? _lease;
  Duration _played = Duration.zero;
  Duration? _lastTime;
  bool _holding = false;
  bool _failed = false;
  bool _disposed = false;

  @override
  AtlasSprite? get sprite => _lease?.sprite;

  @override
  bool get isAnimated => true;

  @override
  bool get isHolding => _holding;

  @override
  bool restart() {
    if (!_holding) return false;
    _beginPass();
    return true;
  }

  void _beginPass() {
    _holding = false;
    _played = Duration.zero;
    _lastTime = null;
    // A new lease rewinds the clip: the pass starts at its first frame.
    _lease?.release();
    _lease = null;
  }

  @override
  void advancePlayback(AssetPaintContext context) {
    if (context.animate && !_failed) _ask(context);
  }

  @override
  void paint(Canvas canvas, Rect rect, AssetPaintContext context) {
    advancePlayback(context);
    final sprite = this.sprite;
    if (sprite == null) {
      _still.paint(canvas, rect, context);
      return;
    }
    final fitted = applyBoxFit(
      BoxFit.contain,
      Size(_clip.width.toDouble(), _clip.height.toDouble()),
      rect.size,
    );
    canvas.drawImageRect(
      sprite.page,
      sprite.source,
      Alignment.center.inscribe(fitted.destination, rect),
      Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(0, 0, 0, context.opacity),
    );
  }

  void _ask(AssetPaintContext context) {
    if (_holding && context.loop) _beginPass();
    if (_holding) return;
    var lease = _lease;
    if (lease != null && lease.isFailed) {
      _failed = true;
      return;
    }
    if (lease == null || lease.isReleased) {
      lease = _lease = _scheduler.acquire(_key, _clip);
      if (lease == null) return;
    }
    _scheduler.want(lease, _playedAt(context.time));
    if (!context.loop && lease.isPassComplete) {
      _holding = true;
      if (context.restFrame == AssetRestFrame.last) {
        lease.hold();
      } else {
        // The first frame is the still: nothing in the slot is worth holding.
        lease.release();
        _lease = null;
      }
    }
  }

  Duration _playedAt(Duration time) {
    final last = _lastTime;
    _lastTime = time;
    if (last != null) {
      final step = time - last;
      if (!step.isNegative && step <= resumeGap) _played += step;
    }
    return _played;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _lease?.release();
    _lease = null;
    _still.dispose();
    _onDispose?.call();
  }
}
