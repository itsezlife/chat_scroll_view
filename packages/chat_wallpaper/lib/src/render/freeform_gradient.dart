import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chat_wallpaper/chat_wallpaper_diagnostics.dart';
import 'package:chat_wallpaper/src/model/chat_wallpaper.dart';
import 'package:flutter/foundation.dart';

/// Everything one raster depends on: the wallpaper colours as ARGB integers
/// and the ring position. It is the whole message sent to a background
/// isolate, so the pixel loop never depends on the wallpaper model.
typedef _RasterInput = ({List<int> argb, int phase, double progress});

/// Deterministic raster of a [ChatWallpaper$Freeform] gradient.
///
/// ## Model
///
/// The gradient is a small [width] × [height] bitmap, meant to be drawn
/// cover-fit and upscaled with bilinear filtering; the soft upscale is part of
/// the look. Output depends only on the wallpaper's colours, [phaseCount]-slot
/// `phase` and `progress`, so equal inputs always produce equal bytes.
///
/// Colour points sit on an eight-slot ring. Colour `i` occupies slot
/// `(phase + 2i) mod 8`, so the three or four points stay evenly spread and
/// move one slot per phase step. A frame interpolates each point from its slot
/// in the previous phase (`phase + 1`) to its slot in `phase` by `progress`:
/// `progress: 0` reproduces the previous phase exactly, `progress: 1` (the
/// default) lands on `phase`. A static wallpaper is phase 0, progress 1.
///
/// Each pixel is swirled around the centre by `θ = (0.35·r)²·6.4` radians,
/// where `r` is its distance from the centre, clamped to the unit square, and
/// coloured as the mix of every point weighted by `max(0, 0.9 − distance)⁴`.
/// Channels are truncated to integers; alpha is always opaque and the
/// wallpaper colours' own alpha is ignored.
///
/// ## Cost
///
/// One raster is [width] × [height] pixel evaluations, several milliseconds
/// of pure Dart even on a fast phone: a sizeable share of a 120 Hz frame.
/// [pixels] and [image] compute on the calling isolate, so the frame they run
/// in pays for the raster. [imageInBackground] computes the same bytes on a
/// background isolate and leaves only the decode on the calling one.
abstract final class FreeformGradient {
  /// Raster width in pixels.
  static const int width = 60;

  /// Raster height in pixels.
  static const int height = 80;

  /// Number of ring slots, and therefore of distinct phases (`0` … `7`).
  static const int phaseCount = 8;

  /// Ring slot positions in unit coordinates with `y` pointing up; [pixels]
  /// flips `y` into raster space.
  static const List<(double, double)> _ring = [
    (0.80, 0.10),
    (0.60, 0.20),
    (0.35, 0.25),
    (0.25, 0.60),
    (0.20, 0.90),
    (0.40, 0.80),
    (0.65, 0.75),
    (0.75, 0.40),
  ];

  /// Distance from a colour point at which its weight reaches zero.
  static const double _reach = 0.9;

  /// Scales the distance from the centre before squaring into the swirl angle.
  static const double _swirlRadius = 0.35;

  /// Swirl angle in radians at a scaled distance of 1.
  static const double _swirlAngle = 6.4;

  /// Renders [wallpaper] as tightly packed RGBA8888 bytes, row-major from the
  /// top-left, [width] × [height] × 4 long.
  ///
  /// [phase] must be in `[0, phaseCount)` and [progress] in `[0, 1]`.
  ///
  /// The reference output: [image] and [imageInBackground] decode exactly
  /// these bytes.
  static Uint8List pixels(
    ChatWallpaper$Freeform wallpaper, {
    int phase = 0,
    double progress = 1,
  }) => _pixels(_inputOf(wallpaper, phase, progress));

  /// Decodes [pixels] into an image the caller owns and must dispose.
  ///
  /// The bytes are computed synchronously before this returns; only the
  /// decode is asynchronous.
  static Future<ui.Image> image(
    ChatWallpaper$Freeform wallpaper, {
    int phase = 0,
    double progress = 1,
  }) => _decode(pixels(wallpaper, phase: phase, progress: progress));

  /// Decodes the same bytes as [pixels] into an image the caller owns and must
  /// dispose, computing them on a background isolate.
  ///
  /// Only the colours and ring position are sent; the finished buffer comes
  /// back without a copy and is decoded on the calling isolate, so the caller
  /// pays for the decode alone. Each call spawns a short-lived isolate, which
  /// suits one raster at a time rather than a burst of parallel calls. On the
  /// web, which has no background isolates, the bytes are computed on the
  /// calling thread after this returns.
  ///
  /// An error raised while computing, including a failed argument assertion
  /// in debug builds, completes the future with that error.
  static Future<ui.Image> imageInBackground(
    ChatWallpaper$Freeform wallpaper, {
    int phase = 0,
    double progress = 1,
  }) async {
    final input = _inputOf(wallpaper, phase, progress);
    return _decode(
      await compute(
        _pixels,
        input,
        debugLabel: 'FreeformGradient.imageInBackground',
      ),
    );
  }

  /// Checks the arguments on the calling isolate and flattens them into the
  /// input [_pixels] renders.
  static _RasterInput _inputOf(
    ChatWallpaper$Freeform wallpaper,
    int phase,
    double progress,
  ) {
    assert(
      phase >= 0 && phase < phaseCount,
      'phase must be in [0, $phaseCount), got $phase',
    );
    assert(
      progress >= 0 && progress <= 1,
      'progress must be in [0, 1], got $progress',
    );
    return (
      argb: [for (final color in wallpaper.colors) color.toARGB32()],
      phase: phase,
      progress: progress,
    );
  }

  /// Renders [input] as described in [pixels]. Depends only on [input] and
  /// compile-time constants, so it runs unchanged on any isolate.
  static Uint8List _pixels(_RasterInput input) {
    final (:argb, :phase, :progress) = input;
    final points = [
      for (var i = 0; i < argb.length; i++) _point(i, phase, progress),
    ];
    final bytes = Uint8List(width * height * 4);

    var offset = 0;
    for (var y = 0; y < height; y++) {
      final dy = y / height - 0.5;
      for (var x = 0; x < width; x++) {
        final dx = x / width - 0.5;
        final swirl = _swirlRadius * math.sqrt(dx * dx + dy * dy);
        final theta = swirl * swirl * _swirlAngle;
        final sin = math.sin(theta);
        final cos = math.cos(theta);
        final px = (0.5 + dx * cos - dy * sin).clamp(0.0, 1.0);
        final py = (0.5 + dx * sin + dy * cos).clamp(0.0, 1.0);

        var weightSum = 0.0;
        var red = 0.0;
        var green = 0.0;
        var blue = 0.0;
        for (var i = 0; i < argb.length; i++) {
          final (cx, cy) = points[i];
          final ex = px - cx;
          final ey = py - cy;
          final falloff = math.max(0, _reach - math.sqrt(ex * ex + ey * ey));
          final weight = falloff * falloff * falloff * falloff;
          final color = argb[i];
          weightSum += weight;
          red += weight * ((color >> 16) & 0xFF);
          green += weight * ((color >> 8) & 0xFF);
          blue += weight * (color & 0xFF);
        }
        assert(
          weightSum > 0,
          'Pixel ($x, $y) lies beyond $_reach of every colour point',
        );

        bytes[offset++] = (red / weightSum).toInt();
        bytes[offset++] = (green / weightSum).toInt();
        bytes[offset++] = (blue / weightSum).toInt();
        bytes[offset++] = 0xFF;
      }
    }
    return bytes;
  }

  static Future<ui.Image> _decode(Uint8List bytes) {
    ChatWallpaperDiagnostics.gradientRasters++;
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bytes,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  /// Raster-space position of colour [index] at [progress] from the previous
  /// phase towards [phase].
  static (double, double) _point(int index, int phase, double progress) {
    final (fromX, fromY) = _ring[(phase + 1 + 2 * index) % phaseCount];
    final (toX, toY) = _ring[(phase + 2 * index) % phaseCount];
    return (
      fromX + (toX - fromX) * progress,
      1 - (fromY + (toY - fromY) * progress),
    );
  }
}
