import 'package:catalog_assets/src/asset/asset_binding.dart';
import 'package:catalog_assets/src/asset/asset_cache_scope.dart';
import 'package:catalog_assets/src/asset/asset_preset.dart';
import 'package:catalog_assets/src/widget/asset_cache_provider.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/rendering.dart';
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
/// ## Playback
///
/// The view shows its binding only while a [TickerMode] above it is enabled,
/// so a hidden route or an offstage page stops its animation. An animated
/// preset gets its own repaint boundary, because every frame repaints it.
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
      size: preset.size,
      tint: widget.tint,
      opacity: widget.opacity,
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
    required this.size,
    required this.tint,
    required this.opacity,
  });

  final AssetBinding binding;
  final Size size;
  final Color? tint;
  final double opacity;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderContent(
    binding: binding,
    preferredSize: size,
    tint: tint,
    opacity: opacity,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderContent renderObject) {
    renderObject
      ..binding = binding
      ..preferredSize = size
      ..tint = tint
      ..opacity = opacity;
  }
}

class _RenderContent extends RenderBox {
  _RenderContent({
    required AssetBinding binding,
    required Size preferredSize,
    required Color? tint,
    required double opacity,
  }) : _binding = binding,
       _preferredSize = preferredSize,
       _tint = tint,
       _opacity = opacity;

  AssetBinding _binding;
  Size _preferredSize;
  Color? _tint;
  double _opacity;

  set binding(AssetBinding value) {
    if (identical(_binding, value)) return;
    if (attached) _binding.removeListener(markNeedsPaint);
    _binding = value;
    if (attached) _binding.addListener(markNeedsPaint);
    markNeedsPaint();
  }

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

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _binding.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _binding.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_preferredSize);

  @override
  void performLayout() {
    size = computeDryLayout(constraints);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _binding.paint(
      context.canvas,
      offset & size,
      tint: _tint,
      opacity: _opacity,
    );
  }
}
