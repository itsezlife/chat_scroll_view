import 'dart:ui' as ui;

import 'package:chrome_foundation/src/glass/glass_layer_watch.dart';
import 'package:chrome_foundation/src/glass/glass_style.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

// [DBG-141] Ticket 141's device log, behind --dart-define=DBG_141=true.
const bool _dbg141 = bool.fromEnvironment('DBG_141');

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

  @override
  State<GlassSourceScope> createState() => _GlassSourceScopeState();
}

class _GlassSourceScopeState extends State<GlassSourceScope> {
  final _link = GlassSourceLink._();

  @override
  void dispose() {
    _link._releaseAll();
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

  /// Saturation the capture is rendered with (1 leaves the colours).
  double get sampleSaturation;
}

/// How a capture is rendered: resolution, blur and saturation. Samplers that
/// agree on all three share captures.
typedef _CaptureSpec = ({
  double pixelRatio,
  double blurSigma,
  double saturation,
});

/// A capture of a [GlassSource] region.
///
/// Owned by the [GlassSourceLink], which keeps it over the frames in which
/// nothing under [region] changed and disposes it when it recaptures or no
/// sampler reads it any more. Draw with it while compositing the frame it was
/// handed out for; never keep it.
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
/// Captures at most once per frame for all samplers: the first [captureFor]
/// of a frame collects every sampler's region, snaps it out to the capture
/// grid ([gridPixels] image px), merges the ones close enough that one image
/// is cheaper than several ([mergeRegions]), and renders each merged region
/// once. Samplers with different resolution, blur or saturation never share
/// an image.
///
/// The grid keeps a capture's size and its pixel phase against the source
/// still while a surface moves by less than a grid step (an island growing
/// with its text, a button's press scale), so such a move neither recaptures
/// nor shifts the sampled pixels.
///
/// A merged region is rendered again only when something under it changed
/// since its last capture: the source's composited layer tree is diffed
/// against the last frame's ([GlassLayerWatch]), and a capture is kept while
/// the change misses its region. A region that moves or resizes is a new
/// capture. A playing texture under a region recaptures it every frame.
class GlassSourceLink {
  GlassSourceLink._();

  /// The link of the nearest [GlassSourceScope] at [context], or null outside
  /// one. Depends on the scope. Not exported: surfaces reach the link, hosts
  /// only place the scope.
  static GlassSourceLink? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_GlassSourceScopeMarker>()
      ?.link;

  /// The capture grid, in image px: a captured region's edges lie on
  /// multiples of it in the source's coordinates. At an eighth of device
  /// resolution it is 16 device px.
  static const int gridPixels = 2;

  /// [region] grown out to the capture grid at [pixelRatio] image px per
  /// logical px.
  static Rect snapRegion(Rect region, double pixelRatio) {
    final step = gridPixels / pixelRatio;
    double down(double v) => (v / step).floorToDouble() * step;
    double up(double v) => (v / step).ceilToDouble() * step;
    return Rect.fromLTRB(
      down(region.left),
      down(region.top),
      up(region.right),
      up(region.bottom),
    );
  }

  /// Merges [regions] whose common bounds cost at most [slack] times their
  /// summed areas, so nearby surfaces share one capture and distant ones keep
  /// their own.
  ///
  /// Every input region lies inside exactly one returned rect.
  static List<Rect> mergeRegions(List<Rect> regions, {double slack = 2}) {
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

  RenderGlassSource? _source;
  final _samplers = <GlassSampler>{};
  final _frame = <GlassSampler, GlassCapture?>{};
  final _watch = GlassLayerWatch();

  /// Captures kept across frames, by spec and merged region.
  final _kept = <(_CaptureSpec, Rect), GlassCapture>{};

  /// The keys of [_kept] read since the last release.
  final _read = <(_CaptureSpec, Rect)>{};

  /// The source [_kept] and [_watch] describe.
  RenderGlassSource? _watched;
  var _watchedThisFrame = false;
  var _releaseScheduled = false;

  /// The mounted source, or null while none is attached.
  RenderGlassSource? get source => _source;

  /// Registers [sampler] for the frames it is attached in.
  void addSampler(GlassSampler sampler) => _samplers.add(sampler);

  /// Unregisters [sampler].
  void removeSampler(GlassSampler sampler) {
    _samplers.remove(sampler);
    _frame.remove(sampler);
    // A capture only it read goes at the end of the next frame another
    // sampler captures in; with none left, there is no such frame.
    if (_samplers.isEmpty) _disposeKept((_) => true);
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
    final root = source?._composited;
    if (source == null ||
        !source.attached ||
        !source.hasSize ||
        root is! OffsetLayer ||
        !root.attached) {
      for (final sampler in pending) {
        _frame[sampler] = null;
      }
      return;
    }
    _invalidate(source, root);

    final groups = <_CaptureSpec, List<(GlassSampler, Rect)>>{};
    for (final sampler in pending) {
      final region = sampler.sampleRegion(source);
      final ratio = sampler.samplePixelRatio;
      if (region == null || region.isEmpty || ratio <= 0) {
        _frame[sampler] = null;
        continue;
      }
      final spec = (
        pixelRatio: ratio,
        blurSigma: sampler.sampleBlurSigma,
        saturation: sampler.sampleSaturation,
      );
      // Kept inside the source: past its edge there is nothing to capture,
      // and the blur would pull that transparency into the glass.
      final snapped = snapRegion(
        region,
        ratio,
      ).intersect(Offset.zero & source.size);
      if (snapped.isEmpty) {
        _frame[sampler] = null;
        continue;
      }
      (groups[spec] ??= []).add((sampler, snapped));
    }

    for (final MapEntry(key: spec, value: members) in groups.entries) {
      final merged = mergeRegions([for (final (_, r) in members) r]);
      final captures = <Rect, GlassCapture?>{};
      for (final (sampler, region) in members) {
        final union = merged.firstWhere((m) => m.expandToInclude(region) == m);
        _frame[sampler] = captures.putIfAbsent(union, () {
          final key = (spec, union);
          _read.add(key);
          if (_kept[key] case final kept?) return kept;
          final image = source.capture(
            union,
            pixelRatio: spec.pixelRatio,
            blurSigma: spec.blurSigma,
            saturation: spec.saturation,
          );
          if (image == null) return null;
          return _kept[key] = GlassCapture._(image, union, spec.pixelRatio);
        });
      }
    }
    _scheduleRelease();
  }

  /// Drops the kept captures this frame's changes reach, once per frame.
  ///
  /// The watch compares against the last frame a sampler read the source in,
  /// so a change in a frame without one is still seen in the next.
  void _invalidate(RenderGlassSource source, OffsetLayer root) {
    if (_watchedThisFrame) return;
    _watchedThisFrame = true;
    if (!identical(source, _watched)) {
      _watched = source;
      _watch.reset();
      _disposeKept((_) => true);
    }
    final change = _watch.changeSince(root);
    if (!change.changed) return;
    if (_dbg141) debugPrint('[DBG-141] glass source changed');
    _disposeKept((capture) => change.touches(capture.region));
  }

  void _disposeKept(bool Function(GlassCapture capture) where) {
    _kept.removeWhere((key, capture) {
      if (!where(capture)) return false;
      capture.image.dispose();
      return true;
    });
  }

  void _scheduleRelease() {
    if (_releaseScheduled) return;
    _releaseScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _releaseScheduled = false;
      _releaseFrame();
    });
  }

  /// Ends a frame: drops the captures no sampler read since the last one.
  void _releaseFrame() {
    _kept.removeWhere((key, capture) {
      if (_read.contains(key)) return false;
      capture.image.dispose();
      return true;
    });
    _read.clear();
    _frame.clear();
    _watchedThisFrame = false;
  }

  void _releaseAll() {
    _disposeKept((_) => true);
    _read.clear();
    _frame.clear();
    _watch.reset();
    _watched = null;
  }
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

  /// The scale, relative to the frame, at which a frosted glass captures
  /// this subtree: its content is drawn a second time at that scale.
  ///
  /// Caches keyed by scale fill for the capture separately, the engine's
  /// glyph atlas among them. A host that warms one before a glass first
  /// shows warms it at this scale as well as at 1, and at
  /// [refractingCaptureScale] too when it allows `GlassQuality.fullLiquid`.
  static const double captureScale = 1 / GlassStyle.frostedSourceDownscale;

  /// The scale at which a refracting glass captures this subtree.
  static const double refractingCaptureScale =
      1 / GlassStyle.refractingSourceDownscale;

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
    final link = GlassSourceLink.of(context);
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

  /// The layer this source composites into, for its link's watch.
  ContainerLayer? get _composited => layer;

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
  /// [pixelRatio], blurred by [blurSigma] image px, with its saturation
  /// scaled by [saturation] (1 leaves it). Only what lies inside
  /// [region] is rendered: the edges blur against their own pixels, not the
  /// content beyond them. The caller owns the image.
  ///
  /// Callable while the frame's scene is composited: the layer tree is
  /// complete after paint, and the engine rasterizes the image before the
  /// frame that draws it. Returns null when nothing is painted yet.
  ui.Image? capture(
    Rect region, {
    required double pixelRatio,
    required double blurSigma,
    required double saturation,
  }) {
    final layer = this.layer;
    if (layer is! OffsetLayer || !layer.attached) return null;
    // A snapped region is a whole number of image px; the slack keeps a
    // product like 52.000000001 from growing the image by one.
    final width = (region.width * pixelRatio - 1e-6).ceil();
    final height = (region.height * pixelRatio - 1e-6).ceil();
    if (width <= 0 || height <= 0) return null;

    final builder = ui.SceneBuilder();
    final blur = blurSigma > 0
        ? builder.pushImageFilter(
            ui.ImageFilter.blur(
              sigmaX: blurSigma,
              sigmaY: blurSigma,
              tileMode: TileMode.clamp,
            ),
          )
        : null;
    // Blur and saturation commute (both are linear in colour), so one pass
    // of each over the small image is the whole colour treatment.
    final saturate = saturation != 1
        ? builder.pushColorFilter(
            ui.ColorFilter.matrix(saturationMatrix(saturation)),
          )
        : null;
    final transform = Matrix4.diagonal3Values(pixelRatio, pixelRatio, 1)
      ..translateByDouble(
        -(region.left + layer.offset.dx),
        -(region.top + layer.offset.dy),
        0,
        1,
      );
    final root = builder.pushTransform(transform.storage);
    // Inside the blur, so the blur's input is the region alone: what the
    // source draws outside it is culled before it reaches the display list,
    // instead of rendered and then blurred into the edges.
    final cull = builder.pushClipRect(
      region.shift(layer.offset),
      clipBehavior: Clip.hardEdge,
    );
    final scene = layer.buildScene(builder);
    if (_dbg141) debugPrint('[DBG-141] glass capture $region');
    try {
      return scene.toImageSync(width, height);
    } finally {
      // The pushed layers retain this frame's whole layer tree. Left to the
      // garbage collector, every captured frame's tree is torn down at once
      // inside a scavenge on the UI thread.
      scene.dispose();
      cull.dispose();
      root.dispose();
      saturate?.dispose();
      blur?.dispose();
    }
  }

  /// The colour matrix that scales saturation by [s] about Rec. 709 luma,
  /// the luma weights of a platform saturation matrix.
  static List<double> saturationMatrix(double s) {
    const r = 0.213, g = 0.715, b = 0.072;
    final i = 1 - s;
    return <double>[
      r * i + s, g * i, b * i, 0, 0, //
      r * i, g * i + s, b * i, 0, 0, //
      r * i, g * i, b * i + s, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }
}
