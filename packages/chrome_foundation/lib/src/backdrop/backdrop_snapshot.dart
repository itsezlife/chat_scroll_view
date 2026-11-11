import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Where a [BackdropSnapshot] is taken from: what this widget's subtree
/// painted in the last frame.
///
/// A host places one high in its tree, above everything a scrim may be drawn
/// over (around its navigator, for one), so a surface that comes up over the
/// window can show a blurred still of it. The source is a repaint boundary
/// and costs nothing else: it captures only when a snapshot is asked for.
class BackdropSnapshotSource extends SingleChildRenderObjectWidget {
  /// A source over [child].
  const BackdropSnapshotSource({required Widget super.child, super.key});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBackdropSnapshotSource();
}

final class _RenderBackdropSnapshotSource extends RenderProxyBox {
  @override
  bool get isRepaintBoundary => true;

  // The layer of the last frame, read between frames: what the window showed
  // just before the caller's change, which has not painted yet.
  ui.Image? _capture(double pixelRatio) {
    if (layer case final OffsetLayer layer when layer.attached) {
      return layer.toImageSync(Offset.zero & size, pixelRatio: pixelRatio);
    }
    return null;
  }
}

/// A small, blurred still of what a [BackdropSnapshotSource] last painted,
/// for a scrim drawn over a window whose content holds still under it.
///
/// A full-window `BackdropFilter` blurs at full resolution on every frame it
/// is up, allocates its offscreen targets anew each time it appears, and new
/// ones on every frame its sigma animates. A still costs one small capture
/// and one small blur, made once ([capture]); drawn stretched
/// ([BackdropSnapshotView]) the upscale itself adds softness, and only its
/// opacity animates. The price is that the still does not follow the content:
/// it suits a scrim over a background that is frozen while it is up.
///
/// The caller owns the snapshot and [dispose]s it when its scrim is gone.
final class BackdropSnapshot {
  BackdropSnapshot._(this._image);

  /// Captures what the [BackdropSnapshotSource] above [context] painted in
  /// the last frame at 1/[downscale] of its device pixels, blurs it by
  /// [blurSigma] (in the snapshot's own pixels) and applies [tone] (a colour
  /// matrix, see [toneMatrix]), once. Null when no source is above
  /// [context], or it has not painted yet.
  ///
  /// Called between frames, before what the caller is about to show paints,
  /// the still is of the window without it.
  static BackdropSnapshot? capture(
    BuildContext context, {
    double downscale = 15,
    double blurSigma = 0,
    List<double>? tone,
  }) {
    assert(downscale >= 1, 'A snapshot is never larger than the window.');
    final source = context
        .findAncestorRenderObjectOfType<_RenderBackdropSnapshotSource>();
    if (source == null) return null;
    final density = View.maybeOf(context)?.devicePixelRatio ?? 1;
    final raw = source._capture(density / downscale);
    if (raw == null) return null;
    if (blurSigma <= 0 && tone == null) return BackdropSnapshot._(raw);
    final recorder = ui.PictureRecorder();
    final paint = Paint()..filterQuality = FilterQuality.low;
    if (blurSigma > 0) {
      // Clamped: the edges keep their colour instead of fading to clear.
      paint.imageFilter = ui.ImageFilter.blur(
        sigmaX: blurSigma,
        sigmaY: blurSigma,
        tileMode: TileMode.clamp,
      );
    }
    if (tone != null) paint.colorFilter = ColorFilter.matrix(tone);
    Canvas(recorder).drawImage(raw, Offset.zero, paint);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(raw.width, raw.height);
    picture.dispose();
    raw.dispose();
    return BackdropSnapshot._(image);
  }

  /// The colour matrix that changes saturation by [saturation] (0 leaves it,
  /// -1 is grey, positive is more vivid; about the luminance weights
  /// 0.3086, 0.6094 and 0.0820) and then brightness by [brightness] (a
  /// fraction of full scale added to each channel).
  static List<double> toneMatrix({
    double saturation = 0,
    double brightness = 0,
  }) {
    const lumR = 0.3086;
    const lumG = 0.6094;
    const lumB = 0.0820;
    final x = 1 + saturation;
    final offset = brightness * 255;
    return [
      lumR * (1 - x) + x, lumG * (1 - x), lumB * (1 - x), 0, offset, //
      lumR * (1 - x), lumG * (1 - x) + x, lumB * (1 - x), 0, offset, //
      lumR * (1 - x), lumG * (1 - x), lumB * (1 - x) + x, 0, offset, //
      0, 0, 0, 1, 0,
    ];
  }

  /// The colour matrix that changes nothing.
  static const List<double> identityTone = [
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0,
  ];

  ui.Image? _image;

  /// The still. Not to be read once [isDisposed].
  ui.Image get image {
    assert(!isDisposed, 'A disposed snapshot has no image.');
    return _image!;
  }

  /// Whether [dispose] was called.
  bool get isDisposed => _image == null;

  /// Lets go of the image. Further calls do nothing.
  void dispose() {
    _image?.dispose();
    _image = null;
  }
}

/// Draws a [BackdropSnapshot] stretched over its box at [opacity].
///
/// The opacity is the paint's own alpha on the one image draw: no layer and
/// no offscreen, whatever the value.
class BackdropSnapshotView extends StatelessWidget {
  /// A view of [snapshot] at [opacity].
  const BackdropSnapshotView({
    required this.snapshot,
    required this.opacity,
    super.key,
  });

  /// What is drawn; nothing once it is disposed.
  final BackdropSnapshot snapshot;

  /// How opaque it is drawn, from 0 to 1.
  final Animation<double> opacity;

  @override
  Widget build(BuildContext context) {
    if (snapshot.isDisposed) return const SizedBox.expand();
    return SizedBox.expand(
      child: RawImage(
        image: snapshot.image,
        fit: BoxFit.fill,
        // Bilinear: the upscale of a blurred still needs no more.
        filterQuality: FilterQuality.low,
        opacity: opacity,
      ),
    );
  }
}
