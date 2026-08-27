import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Captures chat (wallpaper + messages) for liquid-glass sampling.
///
/// Mirrors Telegram `glassBackgroundSourceRenderNode` + `DRAW_GLASS`: the
/// island does **not** sample on-screen fade / chrome. Those stay outside
/// [GlassBackdropHost]'s [RepaintBoundary].
///
/// Capture uses [sourceDownscale] (default 4) like
/// `DownscaledRenderNode.setScale(4, 4)`, then a blur pass matching glass σ.
class GlassBackdropController extends ChangeNotifier {
  /// Creates a glass sample-source controller.
  GlassBackdropController({this.sourceDownscale = 4, this.blurSigma = 8});

  /// Glass path downscale (`DownscaledRenderNode` scale).
  final double sourceDownscale;

  /// Blur applied in capture space after downscale (glass `dpf2(6)` σ ≈ 4).
  final double blurSigma;

  /// Key for the [RepaintBoundary] that owns the sample tree.
  final GlobalKey boundaryKey = GlobalKey(debugLabel: 'GlassBackdrop');

  ui.Image? _image;

  /// Last captured frame (device pixels, already blurred). May be null.
  ui.Image? get image => _image;

  Size _logicalSize = Size.zero;

  /// Logical size of the boundary when [_image] was taken.
  Size get logicalSize => _logicalSize;

  double _pixelRatio = 1;

  /// Pixel ratio of [image] relative to [logicalSize].
  double get pixelRatio => _pixelRatio;

  Offset _globalOrigin = Offset.zero;

  /// Top-left of the boundary in global coordinates at capture time.
  Offset get globalOrigin => _globalOrigin;

  var _dirty = true;
  var _scheduled = false;
  var _disposed = false;
  var _capturing = false;

  /// Marks the sample stale (scroll, layout, theme). Captures next frame.
  void markNeedsCapture() {
    if (_disposed) return;
    _dirty = true;
    _schedule();
  }

  void _schedule() {
    if (_scheduled || _disposed || !_dirty) return;
    _scheduled = true;
    // After layout/paint so island resize and list content are current.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (_disposed) return;
      _captureSync();
      if (_dirty) _schedule();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _captureSync() {
    if (!_dirty || _disposed || _capturing) return;
    final context = boundaryKey.currentContext;
    if (context == null) return;
    final box = context.findRenderObject();
    if (box is! RenderRepaintBoundary) return;
    if (!box.hasSize || box.size.isEmpty) return;
    if (box.debugNeedsPaint) {
      _dirty = true;
      _schedule();
      return;
    }

    final view = View.maybeOf(context);
    final dpr = view?.devicePixelRatio ?? 1.0;
    final ratio = (dpr / sourceDownscale).clamp(0.25, dpr);

    _capturing = true;
    try {
      final raw = box.toImageSync(pixelRatio: ratio);
      final sigma = blurSigma * ratio;
      final next = sigma > 0.5 ? _blurSync(raw, sigma) : raw;
      if (!identical(next, raw)) {
        raw.dispose();
      }

      final origin = box.localToGlobal(Offset.zero);
      _image?.dispose();
      _image = next;
      _logicalSize = box.size;
      _pixelRatio = ratio;
      _globalOrigin = origin;
      _dirty = false;
      notifyListeners();
    } on Object {
      _dirty = true;
      _schedule();
    } finally {
      _capturing = false;
    }
  }

  /// Blur [src] into a new image (Telegram blur-before-liquid).
  ///
  /// Uses [Canvas.saveLayer] so [Paint.imageFilter] actually applies (plain
  /// `drawImage` + imageFilter is unreliable on some backends).
  static ui.Image _blurSync(ui.Image src, double sigma) {
    final w = src.width;
    final h = src.height;
    final bounds = Offset.zero & Size(w.toDouble(), h.toDouble());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.saveLayer(
      bounds,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: sigma,
          sigmaY: sigma,
          tileMode: TileMode.clamp,
        ),
    );
    canvas.drawImage(src, Offset.zero, Paint());
    canvas.restore();
    return recorder.endRecording().toImageSync(w, h);
  }

  /// Island top-left in capture pixels for a global island rect.
  Offset? texOriginForGlobal(Rect globalRect) {
    if (_image == null || _logicalSize.isEmpty) return null;
    final local = globalRect.topLeft - _globalOrigin;
    return Offset(local.dx * _pixelRatio, local.dy * _pixelRatio);
  }

  @override
  void dispose() {
    _disposed = true;
    _image?.dispose();
    _image = null;
    super.dispose();
  }
}

/// Places [child] inside the glass sample [RepaintBoundary].
///
/// Keep fade / side chrome / composer **outside** this host so they are not
/// baked into the glass source.
class GlassBackdropHost extends StatefulWidget {
  /// Wraps [child] as the liquid-glass sample tree.
  const GlassBackdropHost({
    required this.controller,
    required this.child,
    super.key,
  });

  /// Capture controller (same instance as [GlassBackdropScope]).
  final GlassBackdropController controller;

  /// Chat / wallpaper subtree only.
  final Widget child;

  @override
  State<GlassBackdropHost> createState() => _GlassBackdropHostState();
}

class _GlassBackdropHostState extends State<GlassBackdropHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.controller.markNeedsCapture();
    });
  }

  @override
  void didUpdateWidget(covariant GlassBackdropHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      widget.controller.markNeedsCapture();
    }
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        widget.controller.markNeedsCapture();
        return false;
      },
      child: RepaintBoundary(
        key: widget.controller.boundaryKey,
        child: widget.child,
      ),
    );
  }
}

/// Provides [GlassBackdropController] to [TelegramGlass] descendants.
class GlassBackdropScope extends InheritedNotifier<GlassBackdropController> {
  /// Creates a scope for [controller].
  const GlassBackdropScope({
    required GlassBackdropController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  /// Nearest glass sample controller, if any.
  static GlassBackdropController? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<GlassBackdropScope>()
        ?.notifier;
  }
}
