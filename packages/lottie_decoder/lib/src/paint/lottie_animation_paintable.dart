import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter/painting.dart';
import 'package:lottie_decoder/src/cache/frame_cache_key.dart';
import 'package:lottie_decoder/src/paint/lottie_still_paintable.dart';
import 'package:lottie_decoder/src/playback/lottie_frame_scheduler.dart';
import 'package:lottie_decoder/src/renderer/lottie_frame_size.dart';
import 'package:lottie_decoder/src/renderer/lottie_source.dart';
import 'package:lottie_native/lottie_native.dart';

/// A Lottie animation played by the shared clock through a
/// [LottieFrameScheduler].
///
/// Pull-driven, like `PlayingImagePaintable`, and shared by every surface of
/// its entry. It never schedules a timer. A paint that animates works out the
/// frame its playback time names, [LottieFrameScheduler.want]s the one after
/// it (the render lands a tick later, so the frame on screen is the one
/// asked for a tick ago), and draws the sprite its lease holds; with no sprite
/// yet, a failed lease, or a full pool, it draws the first-frame still, so
/// nothing is blank and a late frame keeps the last sprite.
///
/// ## Drawn by the surface
///
/// [sprite] is the lease's current frame, null until one exists. A surface
/// that batches sprites calls [advancePlayback] (the first half of [paint]: it
/// asks for the frame) and then draws [sprite] itself, falling back to [paint]
/// for the still while it is null.
///
/// When the scheduler gave the lease a platform texture (ADR 043), [texture]
/// is it once a first frame was posted, and [sprite] is null: a surface that
/// composites adds a texture layer. A [paint] that no [advancePlayback] of the
/// same time came before is a surface that only has a canvas: it asks the
/// scheduler for a slot, so the frames go back to a page it can draw.
///
/// ## Playback time
///
/// The frame follows the time the paints add up, not the clock's absolute
/// time: a pass starts at the first paint that animates, so a sticker that
/// appears at minute five does not start at its middle, and a pass that does
/// not loop has a start to end from. Each paint adds how far the clock moved
/// since the previous one. A step larger than [resumeGap], or backwards, adds
/// nothing: the clock stood still while paused and then jumped by the pause
/// ("freeze and continue"), and the animation goes on from where it stopped.
///
/// ## Half frame rate
///
/// A paint whose context plays at half rate (`AssetPaintContext.frameStepFor`
/// is 2 for this animation's rate) asks only for the even frames of a pass,
/// so the scheduler renders, and posts to a texture, every second frame. A
/// surface that repaints every clock frame asks again for the frame it asked
/// for, which costs nothing.
///
/// ## One pass, then a rest frame
///
/// A paint that does not loop plays the animation once. When the last frame's
/// time is over it holds the rest frame (`AssetPaintContext.restFrame`), asks
/// for nothing and says so ([isHolding]); [restart], or a paint that loops,
/// plays another pass from the first frame.
///
/// ## Failure
///
/// A lease the renderer failed on is never asked again: the paintable keeps
/// painting its still.
final class LottieAnimationPaintable extends AssetPaintable {
  /// Creates the paintable of the animation [handle] describes by [info].
  ///
  /// It owns [firstFrame] from now on. [key] names its entry in the
  /// scheduler's atlas (one paintable per key). [renderEdge] is the pixels of
  /// the longer side of a rendered frame, within the atlas's size classes.
  ///
  /// [cacheKey] names where the animation's frames are cached, null for none;
  /// it travels to the renderer in the [LottieSource] of every frame job.
  ///
  /// [onDispose] runs once, from [dispose]: the paintable holds a [handle] but
  /// no engine, so whoever owns the engine frees the handle there.
  LottieAnimationPaintable({
    required Object key,
    required LottieHandle handle,
    required LottieInfo info,
    required ui.Image firstFrame,
    required LottieFrameScheduler scheduler,
    required int renderEdge,
    FrameCacheKey? cacheKey,
    VoidCallback? onDispose,
  }) : _key = key,
       _source = LottieSource(
         handle,
         frameCount: info.frameCount,
         cacheKey: cacheKey,
       ),
       _info = info,
       _still = LottieStillPaintable(firstFrame),
       _scheduler = scheduler,
       _onDispose = onDispose,
       _size = LottieFrameSize.fitting(info, renderEdge);

  /// The largest step of the clock between two paints that counts as time
  /// played; a longer one is a pause that ended.
  static const Duration resumeGap = Duration(milliseconds: 500);

  final Object _key;
  final LottieSource _source;
  final LottieInfo _info;
  final LottieStillPaintable _still;
  final LottieFrameScheduler _scheduler;
  final VoidCallback? _onDispose;
  final LottieFrameSize _size;

  LottieFrameLease? _lease;
  Duration _played = Duration.zero;
  Duration? _lastTime;
  // The time of the last advancePlayback: a paint at the same time comes from
  // a surface that composites.
  Duration? _advancedAt;
  bool _holding = false;
  bool _failed = false;
  bool _disposed = false;

  @override
  AtlasSprite? get sprite => _lease?.sprite;

  @override
  AssetTexture? get texture => _lease?.texture;

  @override
  bool get isAnimated => true;

  @override
  bool get isHolding => _holding;

  /// The first-frame still this paintable draws while it has no frame.
  @override
  AssetPaintable get firstFrame => _still;

  // Whether a held surface shows the current frame; carried to every lease.
  bool _keep = false;

  @override
  void keepFrame({required bool keep}) {
    _keep = keep;
    _lease?.kept = keep;
  }

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
  }

  @override
  void advancePlayback(AssetPaintContext context) {
    _advancedAt = context.time;
    if (context.animate && !_failed) _ask(context, onCanvas: false);
  }

  @override
  void paint(Canvas canvas, Rect rect, AssetPaintContext context) {
    // A surface that advanced this pass composites, and paints only for the
    // still; one that did not only has a canvas and needs the sprite.
    if (_advancedAt != context.time && context.animate && !_failed) {
      _ask(context, onCanvas: true);
    }
    final sprite = this.sprite;
    if (sprite == null) {
      _still.paint(canvas, rect, context);
      return;
    }
    final fitted = applyBoxFit(
      BoxFit.contain,
      Size(_info.width.toDouble(), _info.height.toDouble()),
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

  void _ask(AssetPaintContext context, {required bool onCanvas}) {
    if (_holding && context.loop) _beginPass();
    var lease = _lease;
    if (lease != null && lease.isFailed) {
      _failed = true;
      return;
    }
    if (lease == null || lease.isReleased) {
      lease = _lease = _scheduler.acquire(
        _key,
        _source,
        _size.width,
        _size.height,
        onCanvas: onCanvas,
      );
      if (lease == null) return;
      lease.kept = _keep;
    }
    _scheduler.want(lease, _frameFor(context), onCanvas: onCanvas);
  }

  int _frameFor(AssetPaintContext context) {
    final count = _info.frameCount;
    if (_holding) return _restFrame(context.restFrame);
    final last = _lastTime;
    _lastTime = context.time;
    if (last != null) {
      final step = context.time - last;
      if (!step.isNegative && step <= resumeGap) _played += step;
    }
    final index = _played.inMicroseconds * _info.frameRate ~/ 1000000;
    final step = context.frameStepFor(_info.frameRate);
    if (context.loop) return _onStep((index % count + 1) % count, step);
    if (index >= count) {
      _holding = true;
      return _restFrame(context.restFrame);
    }
    return _onStep(math.min(index + 1, count - 1), step);
  }

  // At half rate only every second frame is asked for, counted from the
  // first of the pass, so a want changes at most every second frame of the
  // source and the scheduler renders and posts half as many (`limitFps` of
  // the reference client, which advances its frame by two). Rounding the
  // frame ahead down keeps the frame shown within one source frame of the
  // time, on either side.
  static int _onStep(int frame, int step) => frame - frame % step;

  int _restFrame(AssetRestFrame rest) =>
      rest == AssetRestFrame.last ? _info.frameCount - 1 : 0;

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
