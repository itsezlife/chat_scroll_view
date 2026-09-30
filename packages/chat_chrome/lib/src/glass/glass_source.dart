import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Connects the [GlassSource] and the [GlassBackdrop]s under one
/// [GlassSourceScope].
///
/// A glass surface is usually a sibling of the content it frosts, so the two
/// meet through a shared ancestor instead of the widget tree.
class GlassSourceScope extends StatefulWidget {
  /// Scopes one glass source over [child].
  const GlassSourceScope({required this.child, super.key});

  /// Subtree holding one [GlassSource] and the backdrops that sample it.
  final Widget child;

  /// Source of the nearest scope, or null outside a scope.
  static GlassSourceLink? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_GlassSourceScopeMarker>()
      ?.link;

  @override
  State<GlassSourceScope> createState() => _GlassSourceScopeState();
}

class _GlassSourceScopeState extends State<GlassSourceScope> {
  final _link = GlassSourceLink._();

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

/// Where a [GlassSourceScope] keeps its mounted [RenderGlassSource].
class GlassSourceLink {
  GlassSourceLink._();

  RenderGlassSource? _source;

  /// The mounted source, or null while none is attached.
  RenderGlassSource? get source => _source;
}

/// Marks the subtree that [GlassBackdrop]s in the same [GlassSourceScope]
/// sample.
///
/// Mirrors Telegram's glass source: the glass reads a downscaled, blurred
/// copy of this subtree only, never the chrome painted above it (fades,
/// buttons, the glass itself). Keep those outside.
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
  /// [pixelRatio], blurred by [blurSigma] image px.
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
