import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Connects the [GlassSource] and the [GlassSampler]s under one
/// [GlassSourceScope].
///
/// A glass surface is usually a sibling of the content it frosts, so the two
/// meet through a shared ancestor instead of the widget tree.
class GlassSourceScope extends StatefulWidget {
  /// Scopes one glass source over [child].
  const GlassSourceScope({required this.child, super.key});

  /// Subtree holding one [GlassSource] and the samplers that read it.
  final Widget child;

  /// Link of the nearest scope, or null outside a scope.
  static GlassSourceLink? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_GlassSourceScopeMarker>()
      ?.link;

  @override
  State<GlassSourceScope> createState() => _GlassSourceScopeState();
}

class _GlassSourceScopeState extends State<GlassSourceScope> {
  final _link = GlassSourceLink._();

  @override
  void dispose() {
    _link._releaseFrame();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _GlassSourceScopeMarker(link: _link, child: widget.child);
}

class _GlassSourceScopeMarker extends InheritedWidget {
  const _GlassSourceScopeMarker({required this.link, required super.child});

  final GlassSourceLink link;

  @override
  bool updateShouldNotify(_GlassSourceScopeMarker oldWidget) =>
      !identical(link, oldWidget.link);
}

/// A surface drawn from the [GlassSource] of its [GlassSourceScope].
abstract interface class GlassSampler {
  /// Region of [source] (its local logical px) this sampler reads in the
  /// frame being composited, or null when it draws nothing from it.
  Rect? sampleRegion(RenderGlassSource source);

  /// Capture resolution: image px per logical px.
  double get samplePixelRatio;

  /// Capture blur sigma in image px.
  double get sampleBlurSigma;
}

/// One frame's capture of a [GlassSource] region.
///
/// Owned by the [GlassSourceLink] and disposed after the frame; draw with it
/// while compositing that frame, never keep it.
@immutable
class GlassCapture {
  const GlassCapture._(this.image, this.region, this.pixelRatio);

  /// Blurred pixels of [region].
  final ui.Image image;

  /// Captured region of the source (its local logical px).
  final Rect region;

  /// Image px per logical px.
  final double pixelRatio;
}

/// Where a [GlassSourceScope] keeps its [RenderGlassSource] and samplers.
///
/// Captures once per frame for all samplers: the first [captureFor] of a
/// frame collects every sampler's region, merges the ones close enough that
/// one image is cheaper than several ([mergeGlassRegions]), and renders each
/// merged region once. Samplers with different resolution or blur never
/// share an image.
class GlassSourceLink {
  GlassSourceLink._();

  RenderGlassSource? _source;
  final _samplers = <GlassSampler>{};
  final _frame = <GlassSampler, GlassCapture?>{};
  final _images = <ui.Image>[];
  var _releaseScheduled = false;

  /// The mounted source, or null while none is attached.
  RenderGlassSource? get source => _source;

  /// Registers [sampler] for the frames it is attached in.
  void addSampler(GlassSampler sampler) => _samplers.add(sampler);

  /// Unregisters [sampler].
  void removeSampler(GlassSampler sampler) {
    _samplers.remove(sampler);
    _frame.remove(sampler);
  }

  /// This frame's capture covering [sampler]'s region, or null when there is
  /// no source, nothing painted, or the sampler reads no region.
  GlassCapture? captureFor(GlassSampler sampler) {
    if (!_frame.containsKey(sampler)) _captureFrame();
    return _frame[sampler];
  }

  void _captureFrame() {
    final source = _source;
    final pending = _samplers.where((s) => !_frame.containsKey(s)).toList();
    if (source == null || !source.attached || !source.hasSize) {
      for (final sampler in pending) {
        _frame[sampler] = null;
      }
      return;
    }

    final groups = <(double, double), List<(GlassSampler, Rect)>>{};
    for (final sampler in pending) {
      final region = sampler.sampleRegion(source);
      if (region == null || region.isEmpty) {
        _frame[sampler] = null;
        continue;
      }
      final key = (sampler.samplePixelRatio, sampler.sampleBlurSigma);
      (groups[key] ??= []).add((sampler, region));
    }

    for (final MapEntry(key: (ratio, blur), value: members) in groups.entries) {
      final merged = mergeGlassRegions([for (final (_, r) in members) r]);
      final captures = <Rect, GlassCapture?>{};
      for (final (sampler, region) in members) {
        final union = merged.firstWhere((m) => m.expandToInclude(region) == m);
        _frame[sampler] = captures.putIfAbsent(union, () {
          final image = source.capture(
            union,
            pixelRatio: ratio,
            blurSigma: blur,
          );
          if (image == null) return null;
          _images.add(image);
          return GlassCapture._(image, union, ratio);
        });
      }
    }
    _scheduleRelease();
  }

  void _scheduleRelease() {
    if (_releaseScheduled) return;
    _releaseScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _releaseScheduled = false;
      _releaseFrame();
    });
  }

  void _releaseFrame() {
    for (final image in _images) {
      image.dispose();
    }
    _images.clear();
    _frame.clear();
  }
}

/// Merges [regions] whose common bounds cost at most [slack] times their
/// summed areas, so nearby surfaces share one capture and distant ones keep
/// their own.
///
/// Every input region lies inside exactly one returned rect.
List<Rect> mergeGlassRegions(List<Rect> regions, {double slack = 2}) {
  double area(Rect r) => r.width * r.height;
  final merged = <Rect>[];
  for (final region in regions) {
    var current = region;
    var absorbed = true;
    while (absorbed) {
      absorbed = false;
      for (var i = 0; i < merged.length; i++) {
        final union = current.expandToInclude(merged[i]);
        if (area(union) > slack * (area(current) + area(merged[i]))) continue;
        current = union;
        merged.removeAt(i);
        absorbed = true;
        break;
      }
    }
    merged.add(current);
  }
  return merged;
}

/// Marks the subtree that [GlassSampler]s in the same [GlassSourceScope]
/// read.
///
/// The glass reads a downscaled, blurred copy of this subtree only, never
/// the chrome painted above it (fades, buttons, the glass itself). Keep those
/// outside.
///
/// A capture renders the requested region of this subtree into a small
/// texture of its own, so a frame never reads back its onscreen target the
/// way a [BackdropFilter] does.
class GlassSource extends SingleChildRenderObjectWidget {
  /// Wraps [child] as the sample tree of the enclosing [GlassSourceScope].
  const GlassSource({required Widget super.child, super.key});

  @override
  RenderGlassSource createRenderObject(BuildContext context) =>
      RenderGlassSource(link: _linkOf(context));

  @override
  void updateRenderObject(
    BuildContext context,
    RenderGlassSource renderObject,
  ) {
    renderObject.link = _linkOf(context);
  }

  static GlassSourceLink _linkOf(BuildContext context) {
    final link = GlassSourceScope.maybeOf(context);
    assert(link != null, 'GlassSource needs a GlassSourceScope ancestor.');
    return link!;
  }
}

/// Render object of [GlassSource]: a repaint boundary that renders regions
/// of its last painted layer tree into images.
class RenderGlassSource extends RenderProxyBox {
  /// Creates a source registered with [link] while attached.
  RenderGlassSource({required GlassSourceLink link}) : _link = link;

  GlassSourceLink _link;

  /// The scope link this source registers with.
  GlassSourceLink get link => _link;
  set link(GlassSourceLink value) {
    if (identical(value, _link)) return;
    if (attached) _release();
    _link = value;
    if (attached) _link._source = this;
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _link._source = this;
  }

  @override
  void detach() {
    _release();
    super.detach();
  }

  void _release() {
    if (identical(_link._source, this)) _link._source = null;
  }

  /// Renders [region] (local logical px) of the last painted frame at
  /// [pixelRatio], blurred by [blurSigma] image px. The caller owns the
  /// image.
  ///
  /// Callable while the frame's scene is composited: the layer tree is
  /// complete after paint, and the engine rasterizes the image before the
  /// frame that draws it. Returns null when nothing is painted yet.
  ui.Image? capture(
    Rect region, {
    required double pixelRatio,
    required double blurSigma,
  }) {
    final layer = this.layer;
    if (layer is! OffsetLayer || !layer.attached) return null;
    final width = (region.width * pixelRatio).ceil();
    final height = (region.height * pixelRatio).ceil();
    if (width <= 0 || height <= 0) return null;

    final builder = ui.SceneBuilder();
    if (blurSigma > 0) {
      builder.pushImageFilter(
        ui.ImageFilter.blur(
          sigmaX: blurSigma,
          sigmaY: blurSigma,
          tileMode: TileMode.clamp,
        ),
      );
    }
    final transform = Matrix4.diagonal3Values(pixelRatio, pixelRatio, 1)
      ..translateByDouble(
        -(region.left + layer.offset.dx),
        -(region.top + layer.offset.dy),
        0,
        1,
      );
    builder.pushTransform(transform.storage);
    final scene = layer.buildScene(builder);
    try {
      return scene.toImageSync(width, height);
    } finally {
      scene.dispose();
    }
  }
}
