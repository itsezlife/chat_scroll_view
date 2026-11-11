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
/// and one blur, made once ([capture]); it is drawn stretched
/// ([BackdropSnapshotView]), and only its opacity animates. The price is that the still does not follow the content:
/// it suits a scrim over a background that is frozen while it is up.
///
/// The caller owns the snapshot and [dispose]s it when its scrim is gone.
final class BackdropSnapshot {
  BackdropSnapshot._(this._image);

  /// Captures what the [BackdropSnapshotSource] above [context] painted in
  /// the last frame at 1/[downscale] of its device pixels, over
  /// [background], blurs it by [blurSigma] (in those captured pixels) and
  /// applies [tone] (a colour matrix, see [toneMatrix]), once. Null when no
  /// source is above [context], or it has not painted yet.
  ///
  /// The still is made at [upscale] times the captured pixels, the capture
  /// stretched and blurred there, so it is drawn stretched by
  /// [downscale] / [upscale] rather than by [downscale]. A stretch of a few
  /// pixels shows no grid of the still's pixels, however coarsely the
  /// backend samples it; a stretch of 15 does on some. The capture and the
  /// blur's strength stay as small: only the still is larger.
  ///
  /// A blurred or toned still is opaque and blurred evenly out to its edges,
  /// which hold the colour of the window's own edges: whatever is drawn
  /// under it never shows through. [background] is what it shows where the
  /// source painted nothing; it is drawn opaque.
  ///
  /// Called between frames, before what the caller is about to show paints,
  /// the still is of the window without it.
  static BackdropSnapshot? capture(
    BuildContext context, {
    double downscale = 15,
    double blurSigma = 0,
    List<double>? tone,
    Color background = const Color(0xFF000000),
    int upscale = 1,
  }) {
    assert(
      downscale >= 1 && upscale >= 1 && upscale <= downscale,
      'A snapshot is never larger than the window.',
    );
    final source = context
        .findAncestorRenderObjectOfType<_RenderBackdropSnapshotSource>();
    if (source == null) return null;
    final density = View.maybeOf(context)?.devicePixelRatio ?? 1;
    final raw = source._capture(density / downscale);
    if (raw == null) return null;
    if (blurSigma <= 0 && tone == null && upscale == 1) {
      return BackdropSnapshot._(raw);
    }
    final width = raw.width * upscale;
    final height = raw.height * upscale;
    final bounds = Offset.zero & Size(width.toDouble(), height.toDouble());
    // Blurred where it is made: that same blur also smooths away however
    // the backend sampled the stretched capture.
    final sigma = blurSigma * upscale;
    // The blur reads 3 sigma past each pixel. How a backend treats what lies
    // past the edge of a blur's input varies (some leave it clear, whatever
    // tile mode is asked for, and the edges of the still then fade to clear
    // over the window's sharp content), so the input is the still's own edge
    // pixels carried out that far, by an image shader's clamp: what the blur
    // makes of the input's own edge falls outside the still. The blur asks
    // for the clear edge itself, so every backend draws the same still.
    final margin = bounds.inflate((sigma * 3).ceilToDouble());
    final opaque = background.withAlpha(255);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, bounds)..drawColor(opaque, BlendMode.src);
    final layer = Paint();
    if (sigma > 0) {
      layer.imageFilter = ui.ImageFilter.blur(
        sigmaX: sigma,
        sigmaY: sigma,
        tileMode: TileMode.decal,
      );
    }
    if (tone != null) layer.colorFilter = ColorFilter.matrix(tone);
    final edges = ImageShader(
      raw,
      TileMode.clamp,
      TileMode.clamp,
      Matrix4.diagonal3Values(
        upscale.toDouble(),
        upscale.toDouble(),
        1,
      ).storage,
      filterQuality: FilterQuality.low,
    );
    canvas
      ..saveLayer(margin, layer)
      ..drawRect(margin, Paint()..color = opaque)
      ..drawRect(margin, Paint()..shader = edges)
      ..restore();
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    edges.dispose();
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
