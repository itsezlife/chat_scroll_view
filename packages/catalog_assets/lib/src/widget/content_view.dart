import 'package:catalog_assets/src/asset/asset_binding.dart';
import 'package:catalog_assets/src/asset/asset_cache_scope.dart';
import 'package:catalog_assets/src/asset/asset_fade.dart';
import 'package:catalog_assets/src/asset/asset_paintable.dart';
import 'package:catalog_assets/src/asset/asset_preset.dart';
import 'package:catalog_assets/src/asset/asset_readiness.dart';
import 'package:catalog_assets/src/asset/asset_texture_layer.dart';
import 'package:catalog_assets/src/asset/radial_progress.dart';
import 'package:catalog_assets/src/widget/asset_cache_provider.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Shows cache content: attaches `(content, preset.spec, preset.profile)` to
/// the host's [AssetCacheScope], paints the binding's paintable and detaches
/// when it leaves the tree.
///
/// It is the widget for a surface that draws one piece of content outside the
/// catalogue viewport (a composer field, a message, a header). Stages, the
/// budget, the shared playback clock and the host's pause layers all come
/// from the binding; the view only repaints when the binding says something
/// changed, and never rebuilds for it.
///
/// ## Lifetime
///
/// The view attaches once and keeps its binding across rebuilds. It attaches
/// again only when [content], the preset's spec or the scope change, giving
/// the old attach back first, so a parent that rebuilds every frame costs no
/// attach. A unicode glyph on a platform that bakes holds the atlas page of
/// its glyph for as long as the view is attached.
///
/// ## Arrival
///
/// Content that arrives after the view attached (fetched or decoded, not a
/// memory hit) fades in over 150 ms, over the thumbnail the binding kept
/// (`AssetBinding.paintStandIn`), which stays opaque beneath, or else over the
/// placeholder (the view's own, or else the scope's), which fades out as the
/// content rises. Content there at
/// the attach shows at once, so a view built again over loaded content does
/// not flicker. A glyph is never faded.
///
/// ## Playback
///
/// The view shows its binding only while a [TickerMode] above it is enabled,
/// so a hidden route or an offstage page stops its animation. An animated
/// preset gets its own repaint boundary, because every frame repaints it.
///
/// ## Texture
///
/// The view composites: a playing asset whose frames go to a platform
/// texture (`AssetPaintable.texture`, ADR 043) is a texture layer at the box,
/// placed as the profile's fit says and clipped to the box for a cover fit or
/// a corner radius, and is not painted. The view advances an animated
/// paintable before it reads the texture, which is what tells the paintable
/// that a surface that composites shows it.
///
/// ## Placeholder
///
/// Until the content has anything to show (`AssetStage.none`) the view
/// paints the scope's placeholder, which every surface of the scope shares
/// whatever its content is. A view given its own [placeholder] paints that
/// instead, as `ContentEmbed.placeholder` does: the surface knows what its
/// content is (a sticker, a pack's cover) and the colour its stand-in takes
/// from the theme around it, the scope knows neither. A thumbnail is the
/// binding's to paint.
///
/// ## Scope
///
/// [scope] if given, otherwise the closest [AssetCacheProvider]; a view with
/// neither throws a [FlutterError].
class ContentView extends StatefulWidget {
  /// Shows [content] as [preset] says.
  const ContentView({
    required this.content,
    required this.preset,
    this.tint,
    this.opacity = 1,
    this.semanticLabel,
    this.scope,
    this.loadingRadius,
    this.placeholder,
    this.placeholderTint,
    super.key,
  }) : assert(opacity >= 0 && opacity <= 1, 'opacity must be within 0..1');

  /// Which content to show.
  final ContentKey content;

  /// The size, decode and use of the content. The view is as large as the
  /// preset's size allows its constraints.
  final AssetPreset preset;

  /// The colour a template asset (and a placeholder) is drawn in; null keeps
  /// the asset's own colours.
  final Color? tint;

  /// Opacity of the whole paint, 0 to 1.
  final double opacity;

  /// What a screen reader says for the content, for example its alternative
  /// text. Null leaves the view out of the semantics tree.
  final String? semanticLabel;

  /// The cache to attach to, instead of the one an [AssetCacheProvider]
  /// provides.
  final AssetCacheScope? scope;

  /// Radius of the reference client's download indicator (`RadialProgress`)
  /// drawn over the centre of the view while the content downloads and has
  /// no frame to show, or null for none.
  ///
  /// It shows only while the binding reports a download
  /// (`AssetBinding.downloadProgress`), so content served from a cache
  /// (memory or disk) never shows it, and its arc follows the fraction
  /// downloaded from where the view first saw it. The view asks for a frame
  /// after each one it paints the indicator in, and stops when the first
  /// frame exists, the download ends or a [TickerMode] above it is off. A
  /// grid GIF cell uses 12 (`ContextLinkCell.onMeasure`).
  final double? loadingRadius;

  /// What the view paints before the content has a stage, and fades out
  /// under arriving content, instead of the scope's placeholder; null paints
  /// the scope's.
  final AssetPaintable? placeholder;

  /// The colour [placeholder] is drawn in, or null for [tint].
  final Color? placeholderTint;

  @override
  State<ContentView> createState() => _ContentViewState();
}

class _ContentViewState extends State<ContentView> {
  AssetBinding? _binding;
  AssetCacheScope? _attachedScope;
  ContentKey? _attachedContent;
  AssetPreset? _attachedPreset;
  bool _shown = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _shown = TickerMode.valuesOf(context).enabled;
    _sync();
    _binding!.visible = _shown;
  }

  @override
  void didUpdateWidget(ContentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _binding?.detach();
    super.dispose();
  }

  // Attaches when nothing is attached yet or the scope, content or preset
  // changed. The profile is per attach, so a changed preset attaches again as
  // a whole; the entry itself is shared when the spec is the same.
  void _sync() {
    final scope = widget.scope ?? AssetCacheProvider.of(context);
    if (identical(scope, _attachedScope) &&
        widget.content == _attachedContent &&
        widget.preset == _attachedPreset) {
      return;
    }
    // Attach first, so an entry (or glyph page) both attaches share is never
    // left without a holder in between.
    final previous = _binding;
    _attachedScope = scope;
    _attachedContent = widget.content;
    _attachedPreset = widget.preset;
    _binding = scope.attach(
      widget.content,
      widget.preset.spec,
      widget.preset.profile,
    )..visible = _shown;
    previous?.detach();
  }

  @override
  Widget build(BuildContext context) {
    final preset = widget.preset;
    Widget view = _ContentLeaf(
      binding: _binding!,
      placeholder: widget.placeholder ?? _attachedScope!.mediaPlaceholder,
      standsIn: widget.placeholder != null,
      placeholderTint: widget.placeholderTint,
      size: preset.size,
      tint: widget.tint,
      opacity: widget.opacity,
      loadingRadius: widget.loadingRadius,
      ticking: _shown,
    );
    if (preset.profile.animate) view = RepaintBoundary(child: view);
    final label = widget.semanticLabel;
    if (label == null) return view;
    return Semantics(label: label, image: true, child: view);
  }
}

class _ContentLeaf extends LeafRenderObjectWidget {
  const _ContentLeaf({
    required this.binding,
    required this.placeholder,
    required this.standsIn,
    required this.placeholderTint,
    required this.size,
    required this.tint,
    required this.opacity,
    required this.loadingRadius,
    required this.ticking,
  });

  final AssetBinding binding;
  final AssetPaintable placeholder;
  final bool standsIn;
  final Color? placeholderTint;
  final Size size;
  final Color? tint;
  final double opacity;
  final double? loadingRadius;
  final bool ticking;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderContent(
    binding: binding,
    placeholder: placeholder,
    standsIn: standsIn,
    placeholderTint: placeholderTint,
    preferredSize: size,
    tint: tint,
    opacity: opacity,
    loadingRadius: loadingRadius,
    ticking: ticking,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderContent renderObject) {
    renderObject
      ..binding = binding
      ..placeholder = placeholder
      ..standsIn = standsIn
      ..placeholderTint = placeholderTint
      ..preferredSize = size
      ..tint = tint
      ..opacity = opacity
      ..loadingRadius = loadingRadius
      ..ticking = ticking;
  }
}

class _RenderContent extends RenderBox {
  _RenderContent({
    required AssetBinding binding,
    required AssetPaintable placeholder,
    required bool standsIn,
    required Color? placeholderTint,
    required Size preferredSize,
    required Color? tint,
    required double opacity,
    required double? loadingRadius,
    required bool ticking,
  }) : _binding = binding,
       _fade = AssetFade(binding),
       _placeholder = placeholder,
       _standsIn = standsIn,
       _placeholderTint = placeholderTint,
       _preferredSize = preferredSize,
       _tint = tint,
       _opacity = opacity,
       _loadingRadius = loadingRadius,
       _ticking = ticking;

  AssetBinding _binding;
  AssetFade _fade;
  // What the content fades in over when the binding kept no thumbnail.
  AssetPaintable _placeholder;
  // Whether [_placeholder] is the view's own, painted before any stage in
  // place of the scope's, in [_placeholderTint].
  bool _standsIn;
  Color? _placeholderTint;
  // Whether the paintable plays, so that it may come as a texture layer: the
  // view then needs compositing, so a clip or an opacity above it applies to
  // the layer.
  bool _playing = false;
  Size _preferredSize;
  Color? _tint;
  double _opacity;
  double? _loadingRadius;
  bool _ticking;
  // The download indicator while one shows: made when the binding's download
  // starts, dropped when it ends or the first frame exists.
  RadialProgress? _indicator;

  set binding(AssetBinding value) {
    if (identical(_binding, value)) return;
    _indicator = null;
    if (attached) _binding.removeListener(_bindingChanged);
    _binding = value;
    _fade = AssetFade(value);
    if (attached) _binding.addListener(_bindingChanged);
    _bindingChanged();
  }

  set placeholder(AssetPaintable value) {
    if (identical(_placeholder, value)) return;
    _placeholder = value;
    markNeedsPaint();
  }

  set standsIn(bool value) {
    if (_standsIn == value) return;
    _standsIn = value;
    markNeedsPaint();
  }

  set placeholderTint(Color? value) {
    if (_placeholderTint == value) return;
    _placeholderTint = value;
    markNeedsPaint();
  }

  Color? get _placeholderColor => _standsIn ? _placeholderTint ?? _tint : _tint;

  set preferredSize(Size value) {
    if (_preferredSize == value) return;
    _preferredSize = value;
    markNeedsLayout();
  }

  set tint(Color? value) {
    if (_tint == value) return;
    _tint = value;
    markNeedsPaint();
  }

  set opacity(double value) {
    if (_opacity == value) return;
    _opacity = value;
    markNeedsPaint();
  }

  set loadingRadius(double? value) {
    if (_loadingRadius == value) return;
    _loadingRadius = value;
    markNeedsPaint();
  }

  set ticking(bool value) {
    if (_ticking == value) return;
    _ticking = value;
    // Only the indicator reads it; a view without one must not repaint when a
    // ticker mode flips.
    if (_loadingRadius != null) markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _binding.addListener(_bindingChanged);
    _playing = _binding.paintable.isAnimated;
  }

  @override
  void detach() {
    _binding.removeListener(_bindingChanged);
    super.detach();
  }

  void _bindingChanged() {
    markNeedsPaint();
    final playing = _binding.paintable.isAnimated;
    if (playing == _playing) return;
    _playing = playing;
    markNeedsCompositingBitsUpdate();
  }

  @override
  bool get alwaysNeedsCompositing => _playing;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_preferredSize);

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final box = offset & size;
    // Before anything exists the view's own placeholder replaces the scope's;
    // nothing plays yet, so there is no texture to composite either.
    if (_standsIn && _binding.readiness.stage == AssetStage.none) {
      _placeholder.paint(
        context.canvas,
        box,
        AssetPaintContext(tint: _placeholderColor, opacity: _opacity),
      );
      _paintLoading(context.canvas, box);
      return;
    }
    final fade = _fade.opacityAt(_frameTime);
    if (fade < 1) _paintUnderContent(context.canvas, box, fade);
    final opacity = _opacity * fade;
    if (AssetTextureLayer.composite(context, _binding, box, opacity: opacity)) {
      return;
    }
    _binding.paint(context.canvas, box, tint: _tint, opacity: opacity);
    _paintLoading(context.canvas, box);
  }

  static Duration get _frameTime {
    final scheduler = SchedulerBinding.instance;
    return scheduler.schedulerPhase == SchedulerPhase.idle
        ? Duration.zero
        : scheduler.currentFrameTimeStamp;
  }

  // What the content rises over while it fades in: the thumbnail the binding
  // kept, opaque, or the placeholder fading out. The fade is a function of
  // the frame time, so the next frame is asked for, as for the indicator.
  void _paintUnderContent(Canvas canvas, Rect box, double fade) {
    if (!_binding.paintStandIn(canvas, box)) {
      _placeholder.paint(
        canvas,
        box,
        AssetPaintContext(
          tint: _placeholderColor,
          opacity: _opacity * (1 - fade),
          fit: _binding.profile.fit,
        ),
      );
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (attached) markNeedsPaint();
    });
  }

  // Over the stand-in and the thumbnail, while the content downloads and has
  // no frame. The indicator steps once per frame it is painted in, so it
  // turns by being painted in every frame: the next one is asked for after
  // this one is done (a paint may not mark itself dirty). A view whose ticker
  // mode is off holds the arc where it is.
  void _paintLoading(Canvas canvas, Rect box) {
    final radius = _loadingRadius;
    final downloaded = _binding.downloadProgress;
    if (radius == null ||
        downloaded == null ||
        _binding.readiness.stage.index >= AssetStage.firstFrame.index) {
      _indicator = null;
      return;
    }
    final indicator = switch (_indicator) {
      final shown? => shown..setProgress(downloaded),
      null => _indicator = RadialProgress(progress: downloaded),
    };
    final scheduler = SchedulerBinding.instance;
    if (_ticking && scheduler.schedulerPhase != SchedulerPhase.idle) {
      indicator.advance(scheduler.currentFrameTimeStamp);
    }
    indicator.paint(canvas, box.center, radius: radius, opacity: _opacity);
    if (_ticking) {
      scheduler.addPostFrameCallback((_) {
        if (attached) markNeedsPaint();
      });
    }
  }
}
