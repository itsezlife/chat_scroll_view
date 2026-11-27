import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:message_media/src/chrome/media_cell_chrome.dart';
import 'package:message_media/src/chrome/media_chrome_slots.dart';
import 'package:message_media/src/layout/media_corner_radii.dart';
import 'package:message_media/src/layout/media_layout.dart';
import 'package:message_media/src/outgoing/media_send_state.dart';
import 'package:message_media/src/outgoing/media_sent_check.dart';
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
/// ## Chrome
///
/// The badge and the status control are the policy's chrome slots
/// (`MediaChromeSlots.infoBadge`, `statusControl`), given the stock part of
/// the loading stages through the asset view's skin ([skinOf]). The status
/// control fades with the cell's `MediaControlsScope` (a spoiler's reveal)
/// and takes no pointer: its taps are the view's body part hits.
///
/// ## Uploads
///
/// The status control attaches as a surface that tracks its transfer, so
/// in a scope with tracked transfers (`ContentAssetScope.withMedia
/// (tracked:)`) an item whose content is the source of an upload shows it:
/// the ring with the bytes sent and an upload's cancel while it is
/// `AssetTransfer.sending`, then the sent check (`MediaChromeSlots
/// .sentCheck`) while it is `sent`, until the content is published and the
/// transfer reads `none`. A message whose send failed shows no control.
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
    this.skin,
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
        skin: skinOf(data),
      );

  /// The asset view skin of [data]'s chrome slots: the info badge and the
  /// status control built by the slots over the stock parts, the status
  /// control faded by the cell's `MediaControlsScope`. A sent upload shows
  /// the sent check in the control's place, and a failed send no control.
  /// A slot that throws is reported (`media` / `cellFailed`) and the stock
  /// part shows.
  static AssetViewSkin skinOf(MediaCellData data) {
    final chrome = MediaChromeData(
      cell: data.cell,
      item: data.item,
      family: data.family,
      downloadContext: data.downloadContext,
    );
    final slots = data.chrome;
    Widget guarded(
      String name,
      MediaLoadSlotBuilder? slot,
      BuildContext context,
      AssetLoadState state,
      Widget stock,
    ) {
      if (slot == null) return stock;
      try {
        return slot(context, chrome, state, stock);
      } on Object catch (error, stackTrace) {
        reportMediaChromeFailure(
          builder: name,
          itemId: data.item.id,
          item: data.item,
          correlation: data.correlation,
          error: error,
          stackTrace: stackTrace,
        );
        return stock;
      }
    }

    return AssetViewSkin(
      badge: (context, state, stock) =>
          guarded('infoBadge', slots?.infoBadge, context, state, stock),
      status: (context, state, stock) =>
          switch ((data.sendState, state.transfer)) {
            (MediaSendState.failed, _) => const SizedBox.shrink(),
            (_, AssetTransfer$Sent()) => _ControlsFade(
              child: guarded(
                'sentCheck',
                slots?.sentCheck ?? MediaSentCheck.builder,
                context,
                state,
                stock,
              ),
            ),
            _ => _ControlsFade(
              child: guarded(
                'statusControl',
                slots?.statusControl,
                context,
                state,
                stock,
              ),
            ),
          },
    );
  }

  /// The preset the default box of [data] attaches its picture with: a
  /// binding the view takes for the item's status uses the same, so the two
  /// share one cache entry.
  static AssetPreset presetFor(MediaCellData data) {
    final cell = MediaBoxCell(
      item: data.item,
      size: data.cell.rect.size,
      fit: data.cell.fit ?? const MediaFit.crop(),
      autoplay: data.autoplay,
    );
    return cell.presetOf(cell._assetFit, animate: cell._animates);
  }

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

  /// The look of the picture's badge and status control; null keeps the
  /// closest loading style's.
  final AssetViewSkin? skin;

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

  bool get _animates => autoplay && _plays;

  AssetFit get _assetFit => switch (fit.drawIn(size, pictureSize)) {
    MediaFitDraw.crop => AssetFit.cover,
    MediaFitDraw.blurredBars => AssetFit.contain,
  };

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
      preset: presetOf(_assetFit, animate: _animates),
      status: MediaStatusMode.control(
        playAction: item.kind == MediaItemKind.video && !autoplay,
      ),
      badge: _plays,
      downloadContext: downloadContext,
      skin: skin,
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

// The status control at the cell's controls opacity, never taking a pointer:
// the viewport owns every tap on the media and reports it as a body part
// hit, which the view turns into the download, cancel or retry. A detector of
// the control's own would win the tap from the viewport, in message selection
// too, where the tap must toggle the message.
class _ControlsFade extends StatelessWidget {
  const _ControlsFade({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controls = MediaControlsScope.of(context);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: controls,
        builder: (context, child) =>
            Opacity(opacity: controls.value.clamp(0, 1), child: child),
        child: child,
      ),
    );
  }
}
