import 'dart:ui' as ui;

import 'package:chrome_foundation/src/glass/glass_source.dart';
import 'package:chrome_foundation/src/glass/glass_style.dart';
import 'package:chrome_foundation/src/glass/shader/glass_shaders.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The scene behind the surface, filtered with a backdrop filter: the liquid
/// shader filter when [GlassStyle.enableLiquid], [programs] are loaded and the
/// backend supports it; otherwise a blur and a saturation colour filter under
/// the fill, which need no shader.
///
/// The whole frame renders offscreen while this is on, and the first such
/// frame after a few without one allocates that target again.
class FilterGlassBackdrop extends StatelessWidget {
  /// A scene filter painted per [style].
  const FilterGlassBackdrop({
    required this.style,
    required this.programs,
    required this.shaderFilter,
    required this.devicePixelRatio,
    super.key,
  });

  /// Resolved material.
  final GlassStyle style;

  /// Device pixel ratio, which the blur radius converts with.
  final double devicePixelRatio;

  /// Loaded shaders, or null before they load or when loading failed.
  final GlassShaderPrograms? programs;

  /// Whether the backend accepts a fragment shader as a backdrop filter.
  final bool shaderFilter;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, c) => _build(c.biggest));

  Widget _build(Size size) {
    final programs = this.programs;
    final sigma = style.blurSigma(devicePixelRatio: devicePixelRatio);
    // No frost prepass: under the full-resolution blur its N×N average moves
    // sigma by a fraction of a pixel, and as a shader filter it costs a
    // full-screen pass per frame.
    final filter = style.enableLiquid && programs != null && shaderFilter
        ? GlassShaders.createFilter(
            programs: programs,
            size: size,
            style: style,
            blurSigma: sigma,
            applyFrost: false,
          )
        : null;

    if (filter != null) {
      return BackdropFilter(
        filter: filter,
        child: const ColoredBox(color: Color(0x00000000)),
      );
    }

    final blur = ui.ImageFilter.blur(
      sigmaX: sigma,
      sigmaY: sigma,
      tileMode: TileMode.clamp,
    );
    return BackdropFilter(
      filter: style.backdropSaturation == 1
          ? blur
          : ui.ImageFilter.compose(
              outer: ui.ColorFilter.matrix(
                RenderGlassSource.saturationMatrix(style.backdropSaturation),
              ),
              inner: blur,
            ),
      child: ColoredBox(color: style.fill),
    );
  }
}

/// A backdrop sampled from the [GlassSource] of the enclosing scope.
///
/// Each composited frame the scope hands this box a capture of the region
/// behind it (plus the blur and refraction reach) at 1 /
/// [GlassStyle.sourceDownscale] resolution, blurred and saturated in that
/// space, shared with nearby backdrops of the same look and kept while
/// nothing under it changed. A frosted box draws the capture scaled up under
/// its tint, with no shader; a refracting one draws it through the liquid
/// shader, and until that loads draws it frosted. Nothing reads back the
/// onscreen target, so appearing, moving or disappearing costs no more than a
/// still frame.
class SampledGlassBackdrop extends LeafRenderObjectWidget {
  /// A sampled backdrop painted per [style].
  const SampledGlassBackdrop({
    required this.link,
    required this.style,
    required this.programs,
    required this.pixelRatio,
    super.key,
  });

  /// Link of the scope holding the source.
  final GlassSourceLink link;

  /// Resolved material.
  final GlassStyle style;

  /// Loaded shaders, or null before they load.
  final GlassShaderPrograms? programs;

  /// Device pixel ratio.
  final double pixelRatio;

  @override
  RenderSampledGlass createRenderObject(BuildContext context) =>
      RenderSampledGlass(
        link: link,
        style: style,
        programs: programs,
        pixelRatio: pixelRatio,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSampledGlass renderObject,
  ) {
    renderObject
      ..link = link
      ..style = style
      ..programs = programs
      ..pixelRatio = pixelRatio;
  }
}

/// Render object of [SampledGlassBackdrop]: registers as a sampler with its
/// scope and records a fresh picture of the captured backdrop on every
/// composited frame.
class RenderSampledGlass extends RenderBox implements GlassSampler {
  /// A sampler registered with [link] while attached.
  RenderSampledGlass({
    required GlassSourceLink link,
    required GlassStyle style,
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

  GlassStyle _style;
  set style(GlassStyle value) {
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
  double get sampleBlurSigma =>
      _style.captureBlurSigma(devicePixelRatio: _pixelRatio);

  @override
  double get sampleSaturation => _style.backdropSaturation;

  Rect _glassIn(RenderGlassSource source) =>
      MatrixUtils.transformRect(getTransformTo(source), Offset.zero & size);

  @override
  Rect? sampleRegion(RenderGlassSource source) {
    if (!attached || !hasSize || size.isEmpty) return null;
    if (_layer.layer?.attached != true) return null;
    final bends = _style.enableLiquid && _programs != null;
    final reach =
        (bends ? GlassShaders.backdropReach(style: _style, size: size) : 0) +
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
    final source = _link.source;
    final capture = source == null ? null : _link.captureFor(this);
    final programs = _programs;
    if (source == null || capture == null) {
      canvas.drawRect(rect, Paint()..color = _style.fill);
    } else if (_style.enableLiquid && programs != null) {
      final shader = _liquid(programs, source, capture);
      canvas.drawRect(rect, Paint()..shader = shader);
      shader?.dispose();
    } else {
      _frost(canvas, rect, source, capture);
    }
    return recorder.endRecording();
  }

  /// The capture under the glass, scaled up from its low resolution, under
  /// the tint. Bilinear filtering of a capture blurred by several of its own
  /// px leaves no visible texel.
  void _frost(
    Canvas canvas,
    Rect rect,
    RenderGlassSource source,
    GlassCapture capture,
  ) {
    final glass = _glassIn(source).shift(-capture.region.topLeft);
    final ratio = capture.pixelRatio;
    canvas
      ..drawImageRect(
        capture.image,
        Rect.fromLTRB(
          glass.left * ratio,
          glass.top * ratio,
          glass.right * ratio,
          glass.bottom * ratio,
        ),
        rect,
        Paint()..filterQuality = FilterQuality.low,
      )
      ..drawRect(rect, Paint()..color = _style.fill);
  }

  ui.FragmentShader? _liquid(
    GlassShaderPrograms programs,
    RenderGlassSource source,
    GlassCapture capture,
  ) => GlassShaders.createBackdropShader(
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

/// Records its owner's backdrop anew on every composited frame, after paint,
/// when the [GlassSource] layer tree for that frame is complete.
class _CapturedGlassLayer extends Layer {
  _CapturedGlassLayer(this._owner);

  final RenderSampledGlass _owner;

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
