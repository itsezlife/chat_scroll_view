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
///   samples the scope's [GlassSource]: each frame it draws a downscaled,
///   blurred copy of the source region behind it, shared with nearby surfaces.
///   Nothing reads back the onscreen target.
/// - Otherwise it filters the scene behind it. While the enclosing route
///   moves (pushed, popped, dragged by a back gesture, or shifted by a route
///   transitioning above it) it paints the material's fill flat instead, since
///   a backdrop filter re-reads and re-filters everything under it on every
///   frame, which costs several frame budgets per frame on mobile GPUs. The
///   glass returns when the route settles.
/// - Under lite mode, `GlassQuality.flat` or a backend with no filters, the
///   fill is painted flat; under `GlassQuality.off` nothing is painted.
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
    } on Object {
      if (!mounted) return;
      setState(() => _shadersFailed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final policy = GlassQualityScope.maybeOf(context);
    final quality = policy?.quality ?? GlassQuality.fullLiquid;
    var capabilities = policy?.capabilities ?? GlassCapabilities.detect();
    // Shaders that failed to load take every shader path away.
    if (_shadersFailed) {
      capabilities = capabilities.copyWith(
        sampledBackdrop: false,
        shaderFilter: false,
      );
    }
    final link = glassSourceLinkOf(context);
    final strategy = selectGlassStrategy(
      quality: quality,
      liteMode: policy?.liteMode ?? false,
      capabilities: capabilities,
      hasSource: link != null,
      routeMoving: !_routeSettled,
    );
    if (strategy == GlassStrategy.none) return widget.child;

    final colors = ChromeThemeScope.glassOf(context).colorsOf(widget.material);
    final style = GlassStyle.resolve(
      material: widget.material,
      colors: colors,
      cornerRadius: widget.cornerRadius ?? widget.material.cornerRadius,
      liquid: quality == GlassQuality.fullLiquid,
    );

    final needsShaders =
        strategy == GlassStrategy.sampledLiquid ||
        strategy == GlassStrategy.sampledFrost ||
        (strategy == GlassStrategy.backdropFilter && style.enableLiquid);
    if (needsShaders && _programs == null && !_loading) {
      _loadShaders().ignore();
    }

    final backdrop = switch (strategy) {
      GlassStrategy.sampledLiquid ||
      GlassStrategy.sampledFrost => SampledGlassBackdrop(
        link: link!,
        style: style,
        programs: _programs,
        pixelRatio: MediaQuery.devicePixelRatioOf(context),
      ),
      GlassStrategy.backdropFilter => FilterGlassBackdrop(
        style: style,
        programs: _programs,
        shaderFilter: capabilities.shaderFilter,
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

  void _paintStroke({
    required Canvas canvas,
    required Rect rect,
    required double radius,
    required double strokeWidth,
    required Color color,
    required bool isTop,
  }) {
    if (strokeWidth <= 0 || color.a == 0) return;
    final half = strokeWidth / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..isAntiAlias = true;

    canvas.save();
    if (isTop) {
      canvas.clipRect(
        Rect.fromLTRB(
          rect.left,
          rect.top,
          rect.right,
          (rect.top + radius * 2).clamp(rect.top, rect.bottom),
        ),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            rect.left - half,
            rect.top + half,
            rect.right + half,
            rect.bottom + half,
          ),
          Radius.circular(radius),
        ),
        paint,
      );
    } else {
      canvas.clipRect(
        Rect.fromLTRB(
          rect.left,
          (rect.bottom - radius * 2).clamp(rect.top, rect.bottom),
          rect.right,
          rect.bottom,
        ),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            rect.left - half,
            rect.top - half,
            rect.right + half,
            rect.bottom - half,
          ),
          Radius.circular(radius),
        ),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GlassStrokePainter oldDelegate) =>
      oldDelegate.style != style;
}
