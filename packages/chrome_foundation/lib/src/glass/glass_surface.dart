import 'package:chrome_foundation/src/glass/glass_capabilities.dart';
import 'package:chrome_foundation/src/glass/glass_material.dart';
import 'package:chrome_foundation/src/glass/glass_quality.dart';
import 'package:chrome_foundation/src/glass/glass_quality_scope.dart';
import 'package:chrome_foundation/src/glass/glass_source.dart';
import 'package:chrome_foundation/src/glass/glass_style.dart';
import 'package:chrome_foundation/src/glass/shader/glass_shaders.dart';
import 'package:chrome_foundation/src/glass/strategy/glass_backdrops.dart';
import 'package:chrome_foundation/src/glass/strategy/glass_strategy.dart';
import 'package:chrome_foundation/src/theme/chrome_theme_scope.dart';
import 'package:flutter/widgets.dart';

/// A glass surface around [child]: a named [material] drawn over what is
/// behind it, as far as the host's [GlassQuality] and the backend allow.
///
/// Colours come from the **chrome theme scope** (`GlassMaterialTokens`), so a
/// brightness change or a per-surface scope restyles the glass with the rest
/// of the chrome. How the backdrop is drawn is chosen per frame from the
/// host's `GlassQualityScope`, the detected `GlassCapabilities`, whether a
/// [GlassSourceScope] is present, and route motion:
///
/// - Under a [GlassSourceScope] on a backend that can capture, the surface
///   samples the scope's [GlassSource]: it draws a downscaled, blurred and
///   saturated copy of the source region behind it, shared with nearby
///   surfaces and captured again only when something under it changed.
///   Nothing reads back the onscreen target. A frosted surface draws it with
///   no shader; a refracting one (`GlassQuality.fullLiquid`) bends it at the
///   rim with a fragment shader, frosted until the shader loads and for good
///   if it fails to.
/// - Otherwise it filters the scene behind it. While the enclosing route
///   moves (pushed, popped, dragged by a back gesture, or shifted by a route
///   transitioning above it) it paints the material's fill flat instead, since
///   a backdrop filter re-reads and re-filters everything under it on every
///   frame, which costs several frame budgets per frame on mobile GPUs. The
///   glass returns when the route settles.
/// - Under lite mode, `GlassQuality.flat` or a backend with no filters, the
///   material's tint is painted opaque; under `GlassQuality.off` nothing is
///   painted.
///
/// With no `GlassQualityScope` the surface is frosted; refraction is the
/// host's opt-in.
///
/// A chrome fade or wash painted over the content should sit outside the
/// [GlassSource], or have a cutout under the surface, so it is not sampled
/// into the glass.
class GlassSurface extends StatefulWidget {
  /// A surface of [material] around [child].
  const GlassSurface({
    required this.material,
    required this.child,
    this.cornerRadius,
    super.key,
  });

  /// The named preset: its shape of effect and its theme colours.
  final GlassMaterial material;

  /// Corner radius in logical px; defaults to [GlassMaterial.cornerRadius].
  final double? cornerRadius;

  /// Content drawn above the glass. Sizes the surface.
  final Widget child;

  @override
  State<GlassSurface> createState() => _GlassSurfaceState();
}

class _GlassSurfaceState extends State<GlassSurface> {
  Animation<double>? _routeAnimation;
  Animation<double>? _coveringAnimation;

  /// Whether the enclosing route is at rest, so the scene can be filtered.
  bool _routeSettled = true;

  GlassShaderPrograms? _programs;
  bool _shadersFailed = false;
  bool _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    _follow(route?.animation, route?.secondaryAnimation);
  }

  @override
  void dispose() {
    _follow(null, null);
    super.dispose();
  }

  void _follow(Animation<double>? animation, Animation<double>? covering) {
    if (identical(animation, _routeAnimation) &&
        identical(covering, _coveringAnimation)) {
      return;
    }
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _coveringAnimation?.removeStatusListener(_onRouteStatus);
    _routeAnimation = animation?..addStatusListener(_onRouteStatus);
    _coveringAnimation = covering?..addStatusListener(_onRouteStatus);
    _routeSettled = _settled();
  }

  bool _settled() {
    final entered = _routeAnimation?.isCompleted ?? true;
    final covering = _coveringAnimation?.status ?? AnimationStatus.dismissed;
    return entered && !covering.isAnimating;
  }

  void _onRouteStatus(AnimationStatus _) {
    final settled = _settled();
    if (settled == _routeSettled || !mounted) return;
    setState(() => _routeSettled = settled);
  }

  Future<void> _loadShaders() async {
    if (_loading) return;
    _loading = true;
    try {
      final programs = await GlassShaders.load();
      if (!mounted) return;
      setState(() => _programs = programs);
    } on Object catch (error, stackTrace) {
      // The surface keeps working on the flat path; the failure is reported,
      // not hidden, so a missing shader asset is seen.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'chrome_foundation',
          context: ErrorDescription('while loading the glass shaders'),
        ),
      );
      if (!mounted) return;
      setState(() => _shadersFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final policy = GlassQualityScope.maybeOf(context);
    var quality = policy?.quality ?? GlassQuality.frosted;
    // Shaders that failed to load take refraction away; the frosted paths
    // need none.
    if (_shadersFailed && quality == GlassQuality.fullLiquid) {
      quality = GlassQuality.frosted;
    }
    final capabilities = policy?.capabilities ?? GlassCapabilities.detect();
    final link = GlassSourceLink.of(context);
    GlassStrategy select({required bool routeMoving}) => GlassStrategy.select(
      quality: quality,
      liteMode: policy?.liteMode ?? false,
      capabilities: capabilities,
      hasSource: link != null,
      routeMoving: routeMoving,
    );
    final strategy = select(routeMoving: !_routeSettled);
    if (strategy == GlassStrategy.none) return widget.child;

    // A glass that is flat only while its route moves keeps its translucent
    // tint, so the backdrop's return is not a jump from opaque; one that is
    // flat for good (quality, lite mode, backend) is opaque, as no backdrop
    // is read for the tint to sit on.
    final finish = switch (strategy) {
      GlassStrategy.flat when select(routeMoving: false) == strategy =>
        GlassFinish.flat,
      _ when quality == GlassQuality.fullLiquid => GlassFinish.refracting,
      _ => GlassFinish.frosted,
    };
    final colors = ChromeThemeScope.glassOf(context).colorsOf(widget.material);
    final style = GlassStyle.resolve(
      material: widget.material,
      colors: colors,
      cornerRadius: widget.cornerRadius ?? widget.material.cornerRadius,
      finish: finish,
    );
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);

    final needsShaders =
        style.enableLiquid &&
        (strategy == GlassStrategy.sampledLiquid ||
            strategy == GlassStrategy.backdropFilter);
    if (needsShaders && _programs == null && !_loading) {
      _loadShaders().ignore();
    }

    final backdrop = switch (strategy) {
      GlassStrategy.sampledLiquid ||
      GlassStrategy.sampledFrost => SampledGlassBackdrop(
        link: link!,
        style: style,
        programs: _programs,
        pixelRatio: pixelRatio,
      ),
      GlassStrategy.backdropFilter => FilterGlassBackdrop(
        style: style,
        programs: _programs,
        shaderFilter: capabilities.shaderFilter,
        devicePixelRatio: pixelRatio,
      ),
      GlassStrategy.flat || GlassStrategy.none => ColoredBox(color: style.fill),
    };

    final radius = BorderRadius.circular(style.cornerRadius);
    final shadow = style.shadowColor.a > 0
        ? <BoxShadow>[
            BoxShadow(
              color: style.shadowColor,
              blurRadius: style.shadowBlur,
              offset: style.shadowOffset,
            ),
          ]
        : const <BoxShadow>[];

    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: shadow),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: <Widget>[
            Positioned.fill(child: backdrop),
            Positioned.fill(
              child: CustomPaint(painter: _GlassStrokePainter(style: style)),
            ),
            widget.child,
          ],
        ),
      ),
    );
  }
}

/// Dual top/bottom edge stroke of the glass chrome.
class _GlassStrokePainter extends CustomPainter {
  _GlassStrokePainter({required this.style});

  final GlassStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final radius = style.cornerRadius;
    final rect = Offset.zero & size;

    _paintStroke(
      canvas: canvas,
      rect: rect,
      radius: radius,
      strokeWidth: style.strokeWidthTop,
      color: style.strokeTop,
      isTop: true,
    );
    _paintStroke(
      canvas: canvas,
      rect: rect,
      radius: radius,
      strokeWidth: style.strokeWidthBottom,
      color: style.strokeBottom,
      isTop: false,
    );
  }

  // A crescent, not a stroked line: the band between the outer rounded rect
  // (one corner radius tall) and the same rect moved in by the edge's width,
  // filled even-odd. It is [strokeWidth] thick at the edge's middle and
  // thins to nothing along the corners, so it has no ends to cut. A stroked
  // rounded rect clipped to the top or bottom band was cut square where the
  // clip crossed it, which showed as broken corners.
  void _paintStroke({
    required Canvas canvas,
    required Rect rect,
    required double radius,
    required double strokeWidth,
    required Color color,
    required bool isTop,
  }) {
    if (strokeWidth <= 0 || color.a == 0 || radius <= 0) return;
    final r = radius.clamp(0.0, rect.shortestSide / 2);
    final corner = Radius.circular(r);
    final Path band;
    if (isTop) {
      final bottom = (rect.top + r).clamp(rect.top, rect.bottom);
      band = Path()
        ..fillType = PathFillType.evenOdd
        ..addRRect(
          RRect.fromLTRBAndCorners(
            rect.left,
            rect.top,
            rect.right,
            bottom,
            topLeft: corner,
            topRight: corner,
          ),
        )
        ..addRRect(
          RRect.fromLTRBAndCorners(
            rect.left,
            (rect.top + strokeWidth).clamp(rect.top, bottom),
            rect.right,
            bottom,
            topLeft: corner,
            topRight: corner,
          ),
        );
    } else {
      final top = (rect.bottom - r).clamp(rect.top, rect.bottom);
      band = Path()
        ..fillType = PathFillType.evenOdd
        ..addRRect(
          RRect.fromLTRBAndCorners(
            rect.left,
            top,
            rect.right,
            rect.bottom,
            bottomLeft: corner,
            bottomRight: corner,
          ),
        )
        ..addRRect(
          RRect.fromLTRBAndCorners(
            rect.left,
            top,
            rect.right,
            (rect.bottom - strokeWidth).clamp(top, rect.bottom),
            bottomLeft: corner,
            bottomRight: corner,
          ),
        );
    }
    canvas.drawPath(
      band,
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(covariant _GlassStrokePainter oldDelegate) =>
      oldDelegate.style != style;
}
