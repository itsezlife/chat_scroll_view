import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// One decoded frame, painted centred in a rectangle.
///
/// A template image keeps only its alpha: the context's tint fills it. Without
/// a tint it keeps its own colours, as `AssetPaintContext.tint` says.
abstract final class _ImagePainter {
  static void paint(
    Canvas canvas,
    Rect rect,
    ui.Image image,
    AssetPaintContext context, {
    required bool template,
  }) {
    final source = Size(image.width.toDouble(), image.height.toDouble());
    final fitted = applyBoxFit(BoxFit.contain, source, rect.size);
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Color.fromRGBO(0, 0, 0, context.opacity);
    if (context.tint case final tint? when template) {
      paint.colorFilter = ColorFilter.mode(tint, BlendMode.srcIn);
    }
    canvas.drawImageRect(
      image,
      Alignment.center.inscribe(fitted.source, Offset.zero & source),
      Alignment.center.inscribe(fitted.destination, rect),
      paint,
    );
  }
}

/// A decoded still, or the first frame of an animation where only that is
/// wanted.
final class StillImagePaintable implements AssetPaintable {
  /// Paints [image], which it owns from now on.
  StillImagePaintable(this._image, {required bool template})
    : _template = template;

  final ui.Image _image;
  final bool _template;

  @override
  AtlasSprite? get sprite => null;

  @override
  bool get isAnimated => false;

  @override
  bool get isHolding => false;

  @override
  bool restart() => false;

  @override
  void paint(Canvas canvas, Rect rect, AssetPaintContext context) =>
      _ImagePainter.paint(canvas, rect, _image, context, template: _template);

  @override
  void dispose() => _image.dispose();
}

/// A frame sequence playing by the shared clock, decoded one frame ahead.
///
/// The frame on screen follows `AssetPaintContext.time`: each paint checks
/// whether the shown frame's duration has passed since it went up and, if the
/// next frame is decoded, shows it. It never schedules a timer; a decode for
/// the frame after is started whenever none is held or running, and the
/// clock's ticks bring the paint that shows it.
///
/// ## Timing
///
/// Frames keep their cadence while the clock runs: the next one is due at the
/// previous one's due time plus its duration, not at the paint that showed
/// it, so frames do not drift by a paint's lateness. When the clock jumps
/// (playback was paused and resumes at the live time), or a decode was late
/// by more than a frame, the next frame is shown at once and timing restarts
/// from there; frames are not skipped to catch up, because skipping means
/// decoding each one anyway. A clock that starts again behind the time the
/// shown frame went up at restarts the timing the same way.
///
/// Every paint of the image reads one clock: an entry belongs to one cache
/// scope, and the scope has one playback clock. Times from another clock
/// would read as jumps and restarts.
///
/// The image is one playback for every surface of its entry. A paint that
/// does not animate (`AssetPaintContext.animate`) shows the frame on screen
/// and changes nothing: it neither steps the image nor starts the first
/// frame's duration, which begins at the first paint that animates.
///
/// A frame of 10 ms or less is shown for 100 ms, as browsers do: GIF encoders
/// write 0 for "as fast as possible", which no viewer honours.
///
/// ## One pass, then a rest frame
///
/// A paint that does not loop (`AssetPaintContext.loop`) plays the sequence
/// once. When the last frame's time is over, the image holds its rest frame
/// (`AssetPaintContext.restFrame`), stops decoding and says so ([isHolding]);
/// later paints that do not loop change nothing. [restart] plays another pass
/// from the first frame; a paint that loops does the same, since the image is
/// one playback for every surface of its entry and a looping one wants it
/// moving. A pass is never ended early: the image holds only after the last
/// frame has been shown for its whole duration, and only once the frame after
/// it (the first, the codec wraps) is decoded, so resting on it or restarting
/// from it costs no wait. A pass in progress is never rewound.
///
/// ## Failure
///
/// A frame that fails to decode after the first is reported to
/// [FlutterError.reportError] and the image stops on the frame it shows: the
/// entry already reached its final stage, and a frozen frame is the closest
/// to the rule that a failure is never painted.
final class PlayingImagePaintable implements AssetPaintable {
  /// Plays [codec], whose frame [first] was just decoded. Owns both from now
  /// on.
  PlayingImagePaintable(
    this._codec,
    ui.FrameInfo first, {
    required bool template,
  }) : _shown = first.image,
       _shownFor = _durationOf(first),
       _template = template;

  /// The shortest time a frame is shown; see the class documentation.
  static const Duration _shortestFrame = Duration(milliseconds: 10);

  /// What a frame at or under [_shortestFrame] is shown for.
  static const Duration _defaultFrame = Duration(milliseconds: 100);

  final ui.Codec _codec;
  final bool _template;
  ui.Image _shown;
  // Null until the first paint that animates, so the first frame lasts its
  // full duration from the moment it plays.
  Duration? _shownSince;
  Duration _shownFor;
  ui.FrameInfo? _ahead;
  bool _decoding = false;
  bool _stopped = false;
  bool _disposed = false;
  // Index of the shown frame within the sequence, and whether a pass that did
  // not loop is over; see the class documentation.
  int _index = 0;
  bool _holding = false;
  bool _heldOnLast = false;

  @override
  AtlasSprite? get sprite => null;

  @override
  bool get isAnimated => true;

  @override
  bool get isHolding => _holding;

  @override
  bool restart() {
    if (!_holding) return false;
    _resume();
    return true;
  }

  // Plays another pass: from the held first frame, or from the first frame
  // that was kept decoded behind the held last one. The first frame lasts
  // its duration from the next paint that animates.
  void _resume() {
    _holding = false;
    if (_heldOnLast) {
      final first = _ahead!;
      _ahead = null;
      _shown.dispose();
      _shown = first.image;
      _shownFor = _durationOf(first);
      _index = 0;
    }
    _shownSince = null;
    _decodeAhead();
  }

  @override
  void paint(Canvas canvas, Rect rect, AssetPaintContext context) {
    if (context.animate) _advanceTo(context);
    _ImagePainter.paint(canvas, rect, _shown, context, template: _template);
  }

  void _advanceTo(AssetPaintContext context) {
    if (_holding) {
      if (!context.loop) return;
      _resume();
    }
    final now = context.time;
    // A clock started again is behind the time the frame went up at: the
    // frame counts from now, rather than freezing until the clock catches up.
    final since = _shownSince = switch (_shownSince) {
      final since? when now >= since => since,
      _ => now,
    };
    final ahead = _ahead;
    if (ahead != null && now - since >= _shownFor) {
      final passOver = _index == _codec.frameCount - 1;
      if (passOver && !context.loop) {
        _hold(ahead, context.restFrame);
        return;
      }
      _ahead = null;
      _shown.dispose();
      _shown = ahead.image;
      _index = passOver ? 0 : _index + 1;
      final due = since + _shownFor;
      _shownFor = _durationOf(ahead);
      _shownSince = now - due < _shownFor ? due : now;
    }
    _decodeAhead();
  }

  // Ends the pass: [first] is the decoded frame after the last, the first.
  void _hold(ui.FrameInfo first, AssetRestFrame rest) {
    _holding = true;
    _heldOnLast = rest == AssetRestFrame.last;
    if (_heldOnLast) return;
    _ahead = null;
    _shown.dispose();
    _shown = first.image;
    _shownFor = _durationOf(first);
    _index = 0;
  }

  void _decodeAhead() {
    if (_disposed || _stopped || _holding || _decoding || _ahead != null) {
      return;
    }
    _decoding = true;
    _codec.getNextFrame().then(
      (frame) {
        _decoding = false;
        if (_disposed) {
          frame.image.dispose();
        } else {
          _ahead = frame;
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        _decoding = false;
        _stopped = true;
        if (_disposed) return;
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'image_decoder',
            context: ErrorDescription(
              'while decoding the next frame of a playing image',
            ),
          ),
        );
      },
    );
  }

  static Duration _durationOf(ui.FrameInfo frame) =>
      frame.duration <= _shortestFrame ? _defaultFrame : frame.duration;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _shown.dispose();
    _ahead?.image.dispose();
    _ahead = null;
    _codec.dispose();
  }
}
