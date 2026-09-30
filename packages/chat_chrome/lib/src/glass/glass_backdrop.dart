import 'dart:ui' as ui;

import 'package:chat_chrome/src/glass/glass_source.dart';
import 'package:chat_chrome/src/glass/liquid_glass_shader.dart';
import 'package:chat_chrome/src/glass/telegram_glass_style.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Frosted, refracted backdrop filling its box, painted per [style].
///
/// Under a [GlassSourceScope] on Impeller it samples the scope's
/// [GlassSource]: each composited frame captures the region behind this box
/// (plus the refraction reach) at 1 / [TelegramGlassStyle.sourceDownscale]
/// resolution, blurs it by [TelegramGlassStyle.blurSigma] in that space and
/// draws it through the liquid shader. Nothing reads back the onscreen
/// target, so appearing, moving or disappearing costs no more than a still
/// frame. Until the shader loads it paints [TelegramGlassStyle.fill] flat.
///
/// Elsewhere it filters the scene behind it with a [BackdropFilter]: the
/// whole frame then renders offscreen, and the first such frame after a few
/// without one allocates that target again.
class GlassBackdrop extends StatefulWidget {
  /// Creates a backdrop painted per [style].
  const GlassBackdrop({required this.style, super.key});

  /// Material tokens (tint, blur, saturation, refraction, radius).
  final TelegramGlassStyle style;

  /// Overrides whether the backend can draw captured glass (Impeller only).
  @visibleForTesting
  static bool? debugCaptureSupported;

  static bool get _captureSupported =>
      debugCaptureSupported ?? LiquidGlassShader.isSupported;

  /// Whether a [GlassBackdrop] at [context] samples a [GlassSource] instead
  /// of filtering the scene.
  static bool capturesAt(BuildContext context) =>
      GlassSourceScope.maybeOf(context) != null && _captureSupported;

  @override
  State<GlassBackdrop> createState() => _GlassBackdropState();
}

class _GlassBackdropState extends State<GlassBackdrop> {
  GlassShaderPrograms? _programs;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final programs = await LiquidGlassShader.load();
      if (!mounted) return;
      setState(() => _programs = programs);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _loadError = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final link = GlassSourceScope.maybeOf(context);
    final programs = _loadError == null ? _programs : null;
    if (link != null && GlassBackdrop._captureSupported && _loadError == null) {
      return _CapturedGlass(
        link: link,
        style: style,
        programs: programs,
        pixelRatio: MediaQuery.devicePixelRatioOf(context),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => _SceneGlassBackdrop(
        style: style,
        size: constraints.biggest,
        programs: programs,
      ),
    );
  }
}

class _SceneGlassBackdrop extends StatelessWidget {
  const _SceneGlassBackdrop({
    required this.style,
    required this.size,
    required this.programs,
  });

  final TelegramGlassStyle style;
  final Size size;
  final GlassShaderPrograms? programs;

  @override
  Widget build(BuildContext context) {
    final programs = this.programs;
    // No frost prepass: under the full-resolution blur its N×N average moves
    // sigma by a fraction of a pixel, and as a shader filter it costs a
    // full-screen pass per frame.
    final filter =
        style.enableLiquid && programs != null && LiquidGlassShader.isSupported
        ? LiquidGlassShader.createFilter(
            programs: programs,
            size: size,
            style: style,
            applyFrost: false,
          )
        : null;

    if (filter != null) {
      return BackdropFilter(
        filter: filter,
        child: const ColoredBox(color: Color(0x00000000)),
      );
    }

    return BackdropFilter(
      filter: ui.ImageFilter.blur(
        sigmaX: style.effectiveBlurSigma,
        sigmaY: style.effectiveBlurSigma,
        tileMode: TileMode.clamp,
      ),
      child: ColoredBox(color: style.fill),
    );
  }
}

class _CapturedGlass extends LeafRenderObjectWidget {
  const _CapturedGlass({
    required this.link,
    required this.style,
    required this.programs,
    required this.pixelRatio,
  });

  final GlassSourceLink link;
  final TelegramGlassStyle style;
  final GlassShaderPrograms? programs;
  final double pixelRatio;

  @override
  _RenderCapturedGlass createRenderObject(BuildContext context) =>
      _RenderCapturedGlass(
        link: link,
        style: style,
        programs: programs,
        pixelRatio: pixelRatio,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderCapturedGlass renderObject,
  ) {
    renderObject
      ..link = link
      ..style = style
      ..programs = programs
      ..pixelRatio = pixelRatio;
  }
}

class _RenderCapturedGlass extends RenderBox {
  _RenderCapturedGlass({
    required GlassSourceLink link,
    required TelegramGlassStyle style,
    required GlassShaderPrograms? programs,
    required double pixelRatio,
  }) : _link = link,
       _style = style,
       _programs = programs,
       _pixelRatio = pixelRatio;

  final _layer = LayerHandle<_CapturedGlassLayer>();

  GlassSourceLink _link;
  set link(GlassSourceLink value) {
    if (identical(value, _link)) return;
    _link = value;
    markNeedsPaint();
  }

  TelegramGlassStyle _style;
  set style(TelegramGlassStyle value) {
    if (value == _style) return;
    _style = value;
    markNeedsPaint();
  }

  GlassShaderPrograms? _programs;
  set programs(GlassShaderPrograms? value) {
    if (identical(value, _programs)) return;
    _programs = value;
    markNeedsPaint();
  }

  double _pixelRatio;
  set pixelRatio(double value) {
    if (value == _pixelRatio) return;
    _pixelRatio = value;
    markNeedsPaint();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      constraints.biggest;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (size.isEmpty) return;
    final layer = _layer.layer ??= _CapturedGlassLayer(this);
    layer.offset = offset;
    context.addLayer(layer);
  }

  @override
  void dispose() {
    _layer.layer = null;
    super.dispose();
  }

  /// This frame's backdrop in local coordinates.
  ui.Picture record() {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = Offset.zero & size;
    final capture = _capture();
    if (capture == null) {
      canvas.drawRect(rect, Paint()..color = _style.fill);
      return recorder.endRecording();
    }
    final (image, shader) = capture;
    canvas.drawRect(rect, Paint()..shader = shader);
    final picture = recorder.endRecording();
    shader.dispose();
    image.dispose();
    return picture;
  }

  (ui.Image, ui.FragmentShader)? _capture() {
    final source = _link.source;
    final programs = _programs;
    if (source == null || programs == null || !attached) return null;
    if (!source.attached || !source.hasSize) return null;

    final style = _style;
    final ratio = _pixelRatio / style.sourceDownscale;
    final glass = MatrixUtils.transformRect(
      getTransformTo(source),
      Offset.zero & size,
    );
    final reach =
        LiquidGlassShader.backdropReach(style: style, size: size) +
        3 * style.blurSigma / ratio;
    final region = glass.inflate(reach).intersect(Offset.zero & source.size);
    if (region.isEmpty) return null;

    final image = source.capture(
      region,
      pixelRatio: ratio,
      blurSigma: style.blurSigma,
    );
    if (image == null) return null;
    final shader = LiquidGlassShader.createBackdropShader(
      programs: programs,
      size: size,
      style: style,
      image: image,
      texOrigin: (glass.topLeft - region.topLeft) * ratio,
      texScale: ratio,
    );
    if (shader == null) {
      image.dispose();
      return null;
    }
    return (image, shader);
  }
}

/// Records its owner's backdrop anew on every composited frame, after paint,
/// when the [GlassSource] layer tree for that frame is complete.
class _CapturedGlassLayer extends Layer {
  _CapturedGlassLayer(this._owner);

  final _RenderCapturedGlass _owner;

  Offset offset = Offset.zero;
  ui.Picture? _picture;

  @override
  bool get alwaysNeedsAddToScene => true;

  @override
  void addToScene(ui.SceneBuilder builder) {
    if (!_owner.attached) return;
    final picture = _owner.record();
    _picture?.dispose();
    _picture = picture;
    builder.addPicture(offset, picture);
  }

  @override
  void dispose() {
    _picture?.dispose();
    _picture = null;
    super.dispose();
  }
}
