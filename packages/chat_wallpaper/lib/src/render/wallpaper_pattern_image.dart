import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chat_wallpaper/chat_wallpaper_diagnostics.dart';
import 'package:chat_wallpaper/src/model/chat_wallpaper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:vector_graphics/vector_graphics.dart';

/// A [WallpaperPattern]'s artwork rasterized to an alpha mask [width]
/// pixels wide.
///
/// ## Raster
///
/// Loads [artwork] (compiled vector graphics or an SVG loader) and draws it
/// scaled to [width], keeping its aspect ratio, into an image the height
/// that ratio gives. Only the image's alpha is meaningful: compositing
/// recolours it or uses it as a mask, so the artwork's own colours never
/// show.
///
/// ## Cache
///
/// Providers are equal when their [slug] and [width] are, so the framework
/// [ImageCache] rasterizes each pattern once per width and shares the image
/// between every consumer resolving an equal provider. [artwork] stays out
/// of equality because a slug names one artwork everywhere
/// ([WallpaperPattern.slug]). Picking one width per display, such as its
/// shorter side in physical pixels, keeps every surface on one cache entry
/// and the raster stable across window resizes and rotation.
///
/// ## Failures
///
/// A loader or decode failure, or artwork without a size, fails the image
/// stream; with no error listener attached, the framework reports it
/// through [FlutterError.reportError].
@immutable
final class WallpaperPatternImage extends ImageProvider<WallpaperPatternImage> {
  /// Creates the raster of [slug]'s [artwork] at [width] pixels.
  const WallpaperPatternImage({
    required this.slug,
    required this.artwork,
    required this.width,
  }) : assert(width > 0, 'width must be positive, got $width');

  /// Pattern the artwork belongs to; with [width], the cache identity.
  final String slug;

  /// Vector source of the pattern.
  final BytesLoader artwork;

  /// Raster width in physical pixels.
  final int width;

  @override
  Future<WallpaperPatternImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    WallpaperPatternImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(
    key._rasterize(),
    informationCollector: () => [
      DiagnosticsProperty<WallpaperPatternImage>('Wallpaper pattern', key),
    ],
  );

  Future<ImageInfo> _rasterize() async {
    ChatWallpaperDiagnostics.patternRasterizations++;
    final artwork = await vg.loadPicture(this.artwork, null);
    try {
      final PictureInfo(:picture, :size) = artwork;
      if (size.isEmpty)
        throw StateError('Pattern "$slug" artwork has no size: $size');
      final scale = width / size.width;
      final recorder = ui.PictureRecorder();
      Canvas(recorder)
        ..scale(scale)
        ..drawPicture(picture);
      final scaled = recorder.endRecording();
      try {
        final height = math.max(1, (size.height * scale).round());
        return ImageInfo(
          image: await scaled.toImage(width, height),
          debugLabel: 'wallpaper pattern $slug',
        );
      } finally {
        scaled.dispose();
      }
    } finally {
      artwork.picture.dispose();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is WallpaperPatternImage &&
      other.slug == slug &&
      other.width == width;

  @override
  int get hashCode => Object.hash(slug, width);

  @override
  String toString() =>
      '${objectRuntimeType(this, 'WallpaperPatternImage')}("$slug", width: $width)';
}
