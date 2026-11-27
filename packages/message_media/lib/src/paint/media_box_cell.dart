import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:message_media/src/layout/media_corner_radii.dart';
import 'package:message_media/src/layout/media_layout.dart';
import 'package:message_media/src/paint/media_cell_builders.dart';
import 'package:mpx_core/mpx_core.dart';

/// The default box cell: a photo, video or animation drawn through the
/// asset pipeline in its rounded rect.
///
/// The picture is a `ContentAssetView` of the item's content, so it shows the
/// loading stages (preview, thumbnail, content), the status control and the
/// badge of the media core; this package draws no placeholder of its own.
/// A failed load keeps the best stage it reached, and the status control
/// offers download again.
///
/// ## Fit
///
/// The cell's fit is decided for the picture's size ([MediaFit.drawIn]):
/// cropped to the box, or drawn whole over bars filled with a blur of the
/// same picture, which shows its preview or thumbnail stage blurred until
/// the content arrives. The bars draw the same cache entry as the picture,
/// so they cost no second decode.
///
/// ## Binding
///
/// The decode does not follow the cell's size: a photo decodes at its own
/// size fitted into [decodeExtent], a video or animation at the core's
/// animation size. A cell that moves or resizes keeps its binding; only
/// another item does not.
///
/// ## Press
///
/// The picture has no press visual; the status control's own feedback is
/// the control's.
class MediaBoxCell extends StatelessWidget {
  /// A box of [item] sized [size], rounded by [radii], drawn as [fit] says.
  const MediaBoxCell({
    required this.item,
    required this.size,
    this.radii = MediaCornerRadii.zero,
    this.fit = const MediaFit.crop(),
    this.autoplay = false,
    this.downloadContext,
    this.barsBlurSigma = 24,
    super.key,
  });

  /// The [MediaCellBuilder] of the default box.
  static Widget builder(BuildContext context, MediaCellData data) =>
      MediaBoxCell(
        item: data.item,
        size: data.cell.rect.size,
        radii: data.cell.radii,
        fit: data.cell.fit ?? const MediaFit.crop(),
        autoplay: data.autoplay,
        downloadContext: data.downloadContext,
      );

  /// The longest side, in pixels, a photo is decoded at.
  static const int decodeExtent = 1280;

  /// The item drawn.
  final MediaItem item;

  /// The box's size.
  final Size size;

  /// The box's corners.
  final MediaCornerRadii radii;

  /// How a picture of another aspect is drawn.
  final MediaFit fit;

  /// Whether a video or animation plays inline, muted.
  final bool autoplay;

  /// The class of conversation the media is shown in.
  final AutoDownloadContext? downloadContext;

  /// The blur of the bars of a whole fit, in logical pixels.
  final double barsBlurSigma;

  /// The picture's own size, when its descriptor knows it.
  Size? get pictureSize => switch (item.descriptor.size) {
    ContentSize(:final width, :final height) => Size(
      width.toDouble(),
      height.toDouble(),
    ),
    null => null,
  };

  bool get _plays =>
      item.kind == MediaItemKind.video || item.kind == MediaItemKind.animation;

  /// The preset the picture attaches with, drawn as [assetFit].
  AssetPreset presetOf(AssetFit assetFit, {required bool animate}) {
    final profile = AssetProfile(animate: animate, fit: assetFit);
    if (_plays) return AssetPresets.animation(size: size, profile: profile);
    final picture = pictureSize;
    final spec = switch (picture) {
      final picture? when !picture.isEmpty => _specOf(picture),
      _ => const AssetSpec(pixelWidth: decodeExtent, pixelHeight: decodeExtent),
    };
    return AssetPreset(size: size, spec: spec, profile: profile);
  }

  static AssetSpec _specOf(Size picture) {
    final scale = math.min(1, decodeExtent / picture.longestSide);
    return AssetSpec(
      pixelWidth: math.max(1, (picture.width * scale).round()),
      pixelHeight: math.max(1, (picture.height * scale).round()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draw = fit.drawIn(size, pictureSize);
    final key = item.descriptor.key;
    final picture = ContentAssetView(
      content: key,
      preset: presetOf(switch (draw) {
        MediaFitDraw.crop => AssetFit.cover,
        MediaFitDraw.blurredBars => AssetFit.contain,
      }, animate: autoplay && _plays),
      status: MediaStatusMode.control(
        playAction: item.kind == MediaItemKind.video && !autoplay,
      ),
      badge: _plays,
      downloadContext: downloadContext,
    );
    return ClipRRect(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(radii.topLeft),
        topRight: Radius.circular(radii.topRight),
        bottomLeft: Radius.circular(radii.bottomLeft),
        bottomRight: Radius.circular(radii.bottomRight),
      ),
      child: SizedBox.fromSize(
        size: size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Keyed, so the picture keeps its element (and binding) when
            // the bars come or go.
            if (draw == MediaFitDraw.blurredBars)
              KeyedSubtree(
                key: const ValueKey('bars'),
                child: ImageFiltered(
                  imageFilter: ui.ImageFilter.blur(
                    sigmaX: barsBlurSigma,
                    sigmaY: barsBlurSigma,
                    tileMode: TileMode.mirror,
                  ),
                  child: ContentAssetView(
                    content: key,
                    preset: presetOf(AssetFit.cover, animate: false),
                    downloadContext: downloadContext,
                  ),
                ),
              ),
            KeyedSubtree(key: const ValueKey('picture'), child: picture),
          ],
        ),
      ),
    );
  }
}
