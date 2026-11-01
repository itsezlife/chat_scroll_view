import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chat_wallpaper/src/model/chat_wallpaper.dart';
import 'package:chat_wallpaper/src/motion/chat_wallpaper_motion_controller.dart';
import 'package:chat_wallpaper/src/render/freeform_gradient.dart';
import 'package:chat_wallpaper/src/render/wallpaper_pattern_image.dart';
import 'package:chat_wallpaper/src/widget/chat_wallpaper_patterns.dart';
import 'package:chat_wallpaper/src/widget/freeform_frames.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// [fill] with [pattern] over it, painted in one pass by a fragment shader.
///
/// ## Raster
///
/// Resolves [pattern]'s raster from [ChatWallpaperPatterns.imageOf]: the
/// artwork in the nearest registry, as a [WallpaperPatternImage] at the
/// display's shorter side in physical pixels ([MediaQuery] must be an
/// ancestor). Until the raster and the shader program have both landed, and
/// for good when no artwork is registered or the program fails to load,
/// [child] (the bare fill) paints alone.
///
/// ## Late raster
///
/// A raster the image stream delivers synchronously (already in the cache,
/// such as one a `ChatWallpaperWarmUp` keeps live) to a box whose program is
/// loaded composites at full strength on the first frame. One that becomes
/// ready later fades in from invisible to full strength over [fadeDuration],
/// starting from the frame that painted [child] alone. With
/// [MediaQuery.disableAnimationsOf] set when it lands, it appears at full
/// strength at once.
///
/// Every delivery decides afresh: a raster that lands late after a new slug
/// fades in again; a cached one cuts a running fade short.
///
/// ## Compositing
///
/// The raster is drawn cover-fit and centred, but never smaller than
/// cover-fit into the window ([MediaQuery.sizeOf]): a box smaller than the
/// window (a thumbnail) shows a centred crop, with shapes at the size a
/// full-window thread shows them. A window resize only rescales the draw.
///
/// - [WallpaperPatternBlend.softLight]: the fill under black (over a light
///   fill) or white (over a dark one, [darkFill]) where the pattern is, at
///   [WallpaperPattern.opacity], with the W3C soft-light formula.
/// - [WallpaperPatternBlend.mask]: the fill kept at [WallpaperPattern.opacity]
///   where the pattern is opaque, black where it is transparent.
///
/// The fade scales how far each blend departs from the bare fill. Any
/// [pattern] change applies in place, mid-fade included, without restarting
/// the fade; a new slug resolves its artwork again.
///
/// ## Cost
///
/// Both blends depend on the fill under them. Blending the pattern onto a
/// painted fill needs an offscreen layer every frame the box paints, and the
/// first such frame after a still period allocates it: a 30 to 45 ms frame at
/// the start of every gradient motion on a 120 Hz phone. Snapshotting the
/// composite instead moved that cost to every settle and resize (one full-box
/// GPU pass each). The shader computes the fill and the blend together, so
/// every frame, still, moving, resized or under a page transition, is one
/// draw of the box with nothing offscreen and nothing cached.
///
/// A freeform [fill] under [motion] paints from the keyframes the controller
/// shares with every other holder of the value, so the composite moves frame
/// for frame with the bare fill and the service fills.
@internal
class PatternedFill extends StatefulWidget {
  /// Composites [pattern] over [fill], showing [child] until it can.
  const PatternedFill({
    required this.pattern,
    required this.darkFill,
    required this.fadeDuration,
    required this.fill,
    required this.child,
    this.motion,
    super.key,
  });

  /// Pattern to draw.
  final WallpaperPattern pattern;

  /// Whether the fill under the pattern is dark ([ChatWallpaper.isDark]).
  final bool darkFill;

  /// Length of the fade-in of a pattern that becomes ready after the first
  /// frame.
  final Duration fadeDuration;

  /// The colour fill the shader paints under the pattern.
  final ChatWallpaper$ColorFill fill;

  /// Phase source of a freeform [fill]; `null` paints phase 0.
  final ChatWallpaperMotionController? motion;

  /// [fill] painted alone; shown until the pattern is ready.
  final Widget child;

  /// Key of the box that paints the composite, present exactly while the
  /// pattern shows.
  @visibleForTesting
  static const Key compositeKey = ValueKey<String>('PatternedFill.composite');

  @override
  State<PatternedFill> createState() => _PatternedFillState();
}

class _PatternedFillState extends State<PatternedFill>
    with SingleTickerProviderStateMixin {
  late final ImageStreamListener _listener = ImageStreamListener(_onPattern);
  ImageStream? _stream;

  /// This state's handle on the shared raster; disposed on replacement.
  ImageInfo? _pattern;

  ui.FragmentProgram? _program = PatternedFillProgram.loaded;

  /// Frames of a freeform [PatternedFill.fill]; `null` for other fills.
  FreeformFrames? _frames;

  /// Progress of the late-pattern fade; rests at 1 whenever no fade runs.
  late final AnimationController _fade;

  /// How far the pattern departs from the bare fill.
  late final Animation<double> _strength;

  bool get _ready => _pattern != null && _program != null;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: widget.fadeDuration,
      value: 1,
    );
    _strength = CurvedAnimation(parent: _fade, curve: Curves.easeInOutSine);
    _holdFrames();
    if (_program == null) unawaited(_loadProgram());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(PatternedFill oldWidget) {
    super.didUpdateWidget(oldWidget);
    _fade.duration = widget.fadeDuration;
    if (oldWidget.pattern.slug != widget.pattern.slug) _resolve();
    if (oldWidget.fill != widget.fill ||
        !identical(oldWidget.motion, widget.motion)) {
      _frames?.dispose();
      _holdFrames();
    }
  }

  void _holdFrames() => _frames = switch (widget.fill) {
    final ChatWallpaper$Freeform freeform => FreeformFrames(
      freeform,
      motion: widget.motion,
    ),
    ChatWallpaper$Solid() || ChatWallpaper$Linear() => null,
  };

  Future<void> _loadProgram() async {
    final ui.FragmentProgram program;
    try {
      program = await PatternedFillProgram.load();
    } on Object {
      // The loader has reported it, once for every box; the bare fill stays.
      return;
    }
    if (!mounted) return;
    _becomeReady(() => _program = program, synchronous: false);
  }

  /// Follows the registry to the provider that applies, switching streams
  /// only when its key changes.
  void _resolve() {
    final image = ChatWallpaperPatterns.imageOf(context, widget.pattern.slug);
    if (image == null) {
      _stopListening();
      _replacePattern(null);
      return;
    }
    final stream = image.resolve(ImageConfiguration.empty);
    if (stream.key == _stream?.key) return;
    _stopListening();
    _replacePattern(null);
    _stream = stream..addListener(_listener);
  }

  void _onPattern(ImageInfo pattern, bool synchronousCall) => _becomeReady(
    () => _replacePattern(pattern),
    synchronous: synchronousCall,
  );

  /// Applies [change] and, when it completes what the composite needs,
  /// shows the pattern at once ([synchronous], or reduced motion) or fades
  /// it in.
  void _becomeReady(VoidCallback change, {required bool synchronous}) {
    setState(change);
    if (!_ready) return;
    if (synchronous || MediaQuery.disableAnimationsOf(context)) {
      _fade.value = 1;
      return;
    }
    unawaited(_fade.forward(from: 0));
  }

  void _replacePattern(ImageInfo? pattern) {
    _pattern?.dispose();
    _pattern = pattern;
  }

  void _stopListening() {
    _stream?.removeListener(_listener);
    _stream = null;
  }

  @override
  void dispose() {
    _stopListening();
    _replacePattern(null);
    _frames?.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => switch ((_pattern?.image, _program)) {
    (final image?, final program?) => CustomPaint(
      key: PatternedFill.compositeKey,
      size: Size.infinite,
      painter: _PatternedFillPainter(
        shader: program.fragmentShader(),
        pattern: image,
        fill: widget.fill,
        frames: _frames,
        window: MediaQuery.sizeOf(context),
        blend: widget.pattern.blend,
        opacity: widget.pattern.opacity,
        whiteInk: widget.darkFill,
        strength: _strength,
      ),
    ),
    _ => widget.child,
  };
}

/// The compiled patterned-fill shader, loaded once per process.
@internal
abstract final class PatternedFillProgram {
  static ui.FragmentProgram? _program;
  static Future<ui.FragmentProgram>? _loading;

  /// The program, once [load] has completed; `null` before.
  static ui.FragmentProgram? get loaded => _program;

  /// Loads the program, once; a failure is reported through
  /// [FlutterError.reportError] and returned to every caller.
  static Future<ui.FragmentProgram> load() => _loading ??= _fromAssets().then(
    (program) => _program = program,
    onError: (Object error, StackTrace stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'chat_wallpaper',
          context: ErrorDescription('while loading the patterned fill'),
        ),
      );
      Error.throwWithStackTrace(error, stack);
    },
  );

  /// The asset key carries the package prefix in an app; in the package's own
  /// tests the package is the app and the key has none.
  static Future<ui.FragmentProgram> _fromAssets() async {
    const asset = 'shaders/patterned_fill.frag';
    try {
      return await ui.FragmentProgram.fromAsset(
        'packages/chat_wallpaper/$asset',
      );
    } on Exception {
      return ui.FragmentProgram.fromAsset(asset);
    }
  }
}

/// Paints the fill and the pattern over it with the patterned-fill shader.
///
/// Repaints, without rebuilding, on every fade tick and, for a freeform fill,
/// every motion tick and landed keyframe.
class _PatternedFillPainter extends CustomPainter {
  _PatternedFillPainter({
    required this.shader,
    required this.pattern,
    required this.fill,
    required this.frames,
    required this.window,
    required this.blend,
    required this.opacity,
    required this.whiteInk,
    required this.strength,
  }) : super(repaint: Listenable.merge([strength, ?frames]));

  final ui.FragmentShader shader;
  final ui.Image pattern;
  final ChatWallpaper$ColorFill fill;
  final FreeformFrames? frames;
  final Size window;
  final WallpaperPatternBlend blend;
  final double opacity;
  final bool whiteInk;
  final Animation<double> strength;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    var i = 0;
    void floats(List<double> values) {
      for (final value in values) {
        shader.setFloat(i++, value);
      }
    }

    void rgba(Color color) => floats([color.r, color.g, color.b, 1]);

    final frame = frames?.frame;
    final box = Offset.zero & size;
    floats([size.width, size.height]);
    floats(_coverUv(box, FreeformGradient.width, FreeformGradient.height));
    floats(_coverUv(box, pattern.width, pattern.height, cover: window));
    switch ((fill, frame)) {
      case (
        ChatWallpaper$Freeform(),
        (base: _, :final overlay, :final overlayOpacity),
      ):
        final mix = overlay == null ? 0.0 : overlayOpacity;
        floats([0, mix]);
        rgba(const Color(0xFF000000));
        rgba(const Color(0xFF000000));
        floats([0, 0, 0, 0]);
      case (
        ChatWallpaper$Linear(:final top, :final bottom, :final rotation),
        _,
      ):
        final start = rotation.startAlignment;
        final from = start.withinRect(box);
        final to = (-start).withinRect(box);
        floats([1, 0]);
        rgba(top);
        rgba(bottom);
        floats([from.dx, from.dy, to.dx, to.dy]);
      case (ChatWallpaper$Solid(:final color), _):
        floats([2, 0]);
        rgba(color);
        rgba(color);
        floats([0, 0, 0, 0]);
      case (final ChatWallpaper$Freeform freeform, null):
        // Before the first keyframe lands: the gradient's tone, as the bare
        // fill paints it.
        floats([2, 0]);
        rgba(freeform.averageColor);
        rgba(freeform.averageColor);
        floats([0, 0, 0, 0]);
    }
    final mask = blend == WallpaperPatternBlend.mask ? 1.0 : 0.0;
    final ink = whiteInk ? 1.0 : 0.0;
    floats([mask, opacity, strength.value, ink]);
    // Every sampler must be bound; fills without rasters bind the pattern.
    final base = frame?.base ?? pattern;
    shader
      ..setImageSampler(0, base, filterQuality: FilterQuality.low)
      ..setImageSampler(
        1,
        frame?.overlay ?? base,
        filterQuality: FilterQuality.low,
      )
      ..setImageSampler(2, pattern, filterQuality: FilterQuality.low);
    canvas.drawRect(box, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_PatternedFillPainter oldDelegate) =>
      !identical(pattern, oldDelegate.pattern) ||
      fill != oldDelegate.fill ||
      !identical(frames, oldDelegate.frames) ||
      window != oldDelegate.window ||
      blend != oldDelegate.blend ||
      opacity != oldDelegate.opacity ||
      whiteInk != oldDelegate.whiteInk ||
      !identical(strength, oldDelegate.strength);
}

/// The 2 × 3 map, as its two rows, from a position in [box] to the uv of a
/// [width] × [height] raster drawn cover-fit and centred in [box], never
/// smaller than cover-fit into [cover] when given.
///
/// The pattern is the display's width ([ChatWallpaperPatterns.imageOf]), so
/// the scale, not the raster, follows the window: a resize rescales the map
/// on the next paint and rasterizes nothing.
List<double> _coverUv(Rect box, int width, int height, {Size? cover}) {
  double fit(Size size) => math.max(size.width / width, size.height / height);
  final scale = math.max(fit(box.size), cover == null ? 0.0 : fit(cover));
  final (w, h) = (width * scale, height * scale);
  final left = box.left + (box.width - w) / 2;
  final top = box.top + (box.height - h) / 2;
  return [1 / w, 0, -left / w, 0, 1 / h, -top / h];
}

/// Where a linear fill's colours sit in the box it covers.
@internal
extension WallpaperRotationAlignment on WallpaperRotation {
  /// Where a linear gradient's first colour sits; the second sits opposite.
  Alignment get startAlignment => switch (this) {
    WallpaperRotation.deg0 => Alignment.topCenter,
    WallpaperRotation.deg45 => Alignment.topRight,
    WallpaperRotation.deg90 => Alignment.centerRight,
    WallpaperRotation.deg135 => Alignment.bottomRight,
    WallpaperRotation.deg180 => Alignment.bottomCenter,
    WallpaperRotation.deg225 => Alignment.bottomLeft,
    WallpaperRotation.deg270 => Alignment.centerLeft,
    WallpaperRotation.deg315 => Alignment.topLeft,
  };
}
