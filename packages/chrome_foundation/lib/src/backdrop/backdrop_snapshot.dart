import 'dart:async';
import 'dart:ui' as ui;

import 'package:chrome_foundation/src/backdrop/stack_blur.dart';
import 'package:flutter/foundation.dart';
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
/// ones on every frame its sigma animates. A still costs one small capture,
/// taken at once ([capture]), and one stack blur of its pixels on the CPU,
/// made once soon after; it is drawn stretched ([BackdropSnapshotView]), and
/// only its opacity animates. The price is that the still does not follow
/// the content: it suits a scrim over a background that is frozen while it
/// is up.
///
/// The blur is made on the CPU, not by an image filter, so the still is the
/// same on every backend: smooth, opaque and blurred evenly out to its edges.
///
/// The still is not there at once: [image] is null until it is made, and the
/// snapshot notifies its listeners then; [ready] completes then too. The
/// caller owns the snapshot and [dispose]s it when its scrim is gone.
final class BackdropSnapshot implements Listenable {
  BackdropSnapshot._();

  /// Captures what the [BackdropSnapshotSource] above [context] painted in
  /// the last frame at 1/[downscale] of its device pixels, now, and then
  /// makes the still from it: lays it over [background] (drawn opaque),
  /// stack-blurs it by [blurRadius] (in the captured pixels; 0 leaves it
  /// sharp) and applies [tone] (a colour matrix, see [toneMatrix]). Null when
  /// no source is above [context], or it has not painted yet.
  ///
  /// Called between frames, before what the caller is about to show paints,
  /// the still is of the window without it.
  static BackdropSnapshot? capture(
    BuildContext context, {
    double downscale = 15,
    int blurRadius = 0,
    List<double>? tone,
    Color background = const Color(0xFF000000),
  }) {
    assert(downscale >= 1, 'A snapshot is never larger than the window.');
    assert(blurRadius >= 0, 'A blur radius is never negative.');
    assert(tone == null || tone.length == 20, 'A colour matrix is 4 x 5.');
    final source = context
        .findAncestorRenderObjectOfType<_RenderBackdropSnapshotSource>();
    if (source == null) return null;
    final density = View.maybeOf(context)?.devicePixelRatio ?? 1;
    final raw = source._capture(density / downscale);
    if (raw == null) return null;
    final snapshot = BackdropSnapshot._();
    unawaited(
      snapshot._make(
        raw,
        _Blur(
          radius: blurRadius,
          background: background.toARGB32() & 0xFFFFFF,
          tone: tone,
        ),
      ),
    );
    return snapshot;
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

  // Never disposed: a view built over a disposed snapshot still listens,
  // and draws nothing.
  final _Changes _changes = _Changes();
  final Completer<void> _ready = Completer<void>();
  ui.Image? _image;
  bool _disposed = false;

  /// The still, once it is made; null before, and once [isDisposed].
  ui.Image? get image => _image;

  /// Completes once the still is made, or will never be (the capture could
  /// not be read, or the snapshot was disposed first).
  Future<void> get ready => _ready.future;

  /// Whether [dispose] was called.
  bool get isDisposed => _disposed;

  @override
  void addListener(VoidCallback listener) => _changes.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _changes.removeListener(listener);

  Future<void> _make(ui.Image raw, _Blur blur) async {
    try {
      final width = raw.width;
      final height = raw.height;
      final ByteData? data;
      try {
        data = await raw.toByteData();
      } finally {
        raw.dispose();
      }
      if (data == null || _disposed) return;
      // About a millisecond for a phone's window at 1/15: off the UI
      // isolate where there is another.
      final pixels = await compute(_Blur.apply, (
        pixels: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        width: width,
        height: height,
        blur: blur,
      ), debugLabel: 'BackdropSnapshot blur');
      if (_disposed) return;
      final decoded = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        pixels,
        width,
        height,
        ui.PixelFormat.rgba8888,
        decoded.complete,
      );
      final image = await decoded.future;
      if (_disposed) {
        image.dispose();
        return;
      }
      _image = image;
      _changes.notify();
    } finally {
      _ready.complete();
    }
  }

  /// Lets go of the still, or of the still being made. Further calls do
  /// nothing.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _image?.dispose();
    _image = null;
    _changes.notify();
  }
}

final class _Changes extends ChangeNotifier {
  void notify() => notifyListeners();
}

// How the still is made from the capture's pixels.
final class _Blur {
  const _Blur({
    required this.radius,
    required this.background,
    required this.tone,
  });

  final int radius;
  final int background;
  final List<double>? tone;

  /// Makes the still's pixels from the capture's, in place.
  static Uint8List apply(
    ({Uint8List pixels, int width, int height, _Blur blur}) job,
  ) {
    StackBlur.blurRgba(
      job.pixels,
      job.width,
      job.height,
      radius: job.blur.radius,
      background: job.blur.background,
      tone: job.blur.tone,
    );
    return job.pixels;
  }
}

/// Draws a [BackdropSnapshot] stretched over its box at [opacity], once its
/// still is made; nothing before.
///
/// The still is drawn with bilinear sampling; the opacity is the paint's own
/// alpha on the one image draw: no layer and no offscreen, whatever the
/// value.
class BackdropSnapshotView extends StatelessWidget {
  /// A view of [snapshot] at [opacity].
  const BackdropSnapshotView({
    required this.snapshot,
    required this.opacity,
    super.key,
  });

  /// What is drawn; nothing until its still is made, and once it is
  /// disposed.
  final BackdropSnapshot snapshot;

  /// How opaque it is drawn, from 0 to 1.
  final Animation<double> opacity;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: snapshot,
    builder: (context, _) => switch (snapshot.image) {
      final image? => SizedBox.expand(
        child: RawImage(
          image: image,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.low,
          opacity: opacity,
        ),
      ),
      null => const SizedBox.expand(),
    },
  );
}
