import 'dart:ui' as ui;

import 'package:chat_chrome/src/glass/glass_source.dart';
import 'package:chat_chrome/src/glass/liquid_glass_shader.dart';
import 'package:chat_chrome/src/glass/liquid_glass_style.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Frosted, refracted backdrop filling its box, painted per [style].
///
/// Under a [GlassSourceScope] on Impeller it samples the scope's
/// [GlassSource]: each composited frame the scope captures the region behind
/// this box (plus the refraction reach) at 1 /
/// [LiquidGlassStyle.sourceDownscale] resolution, blurred by
/// [LiquidGlassStyle.blurSigma] in that space — shared with nearby backdrops
/// of the same resolution and blur — and this box draws it through the
/// liquid shader. Nothing reads back the onscreen
/// target, so appearing, moving or disappearing costs no more than a still
/// frame. Until the shader loads it paints [LiquidGlassStyle.fill] flat.
///
/// Elsewhere it filters the scene behind it with a [BackdropFilter]: the
/// whole frame then renders offscreen, and the first such frame after a few
/// without one allocates that target again.
class GlassBackdrop extends StatefulWidget {
  /// Creates a backdrop painted per [style].
  const GlassBackdrop({required this.style, super.key});

  /// Material tokens (tint, blur, saturation, refraction, radius).
  final LiquidGlassStyle style;

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

  final LiquidGlassStyle style;
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
  final LiquidGlassStyle style;
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

class _RenderCapturedGlass extends RenderBox implements GlassSampler {
  _RenderCapturedGlass({
    required GlassSourceLink link,
    required LiquidGlassStyle style,
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
    if (attached) _link.removeSampler(this);
    _link = value;
    if (attached) _link.addSampler(this);
    markNeedsPaint();
  }

  LiquidGlassStyle _style;
  set style(LiquidGlassStyle value) {
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
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _link.addSampler(this);
  }

  @override
  void detach() {
    _link.removeSampler(this);
    super.detach();
  }

  /// Paints through a layer of its own, which an ancestor clip or transform
  /// only reaches as a layer too.
  @override
  bool get alwaysNeedsCompositing => true;

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

  @override
  double get samplePixelRatio => _pixelRatio / _style.sourceDownscale;

  @override
  double get sampleBlurSigma => _style.blurSigma;

  Rect _glassIn(RenderGlassSource source) =>
      MatrixUtils.transformRect(getTransformTo(source), Offset.zero & size);

  @override
  Rect? sampleRegion(RenderGlassSource source) {
    if (_programs == null || !attached || !hasSize || size.isEmpty) {
      return null;
    }
    if (_layer.layer?.attached != true) return null;
    final reach =
        LiquidGlassShader.backdropReach(style: _style, size: size) +
        3 * sampleBlurSigma / samplePixelRatio;
    final region = _glassIn(
      source,
    ).inflate(reach).intersect(Offset.zero & source.size);
    return region.isEmpty ? null : region;
  }

  /// This frame's backdrop in local coordinates.
  ui.Picture record() {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = Offset.zero & size;
    final shader = _shader();
    canvas.drawRect(
      rect,
      shader == null
          ? (Paint()..color = _style.fill)
          : (Paint()..shader = shader),
    );
    final picture = recorder.endRecording();
    shader?.dispose();
    return picture;
  }

  ui.FragmentShader? _shader() {
    final programs = _programs;
    final source = _link.source;
    if (programs == null || source == null) return null;
    final capture = _link.captureFor(this);
    if (capture == null) return null;
    return LiquidGlassShader.createBackdropShader(
      programs: programs,
      size: size,
      style: _style,
      image: capture.image,
      texOrigin:
          (_glassIn(source).topLeft - capture.region.topLeft) *
          capture.pixelRatio,
      texScale: capture.pixelRatio,
    );
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
