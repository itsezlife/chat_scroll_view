import 'package:content_assets/src/identity/content_media.dart';
import 'package:content_assets/src/scope/content_asset_scope.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:mpx_core/mpx_core.dart';

/// Hands a [ContentAssetScope] down to the content views below.
class ContentAssetProvider extends InheritedWidget {
  /// Provides [scope] to [child].
  const ContentAssetProvider({
    required this.scope,
    required super.child,
    super.key,
  });

  /// The scope every content view below attaches to.
  final ContentAssetScope scope;

  /// The closest scope, or null.
  static ContentAssetScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ContentAssetProvider>()?.scope;

  /// The closest scope; throws a [FlutterError] without one.
  static ContentAssetScope of(BuildContext context) {
    final scope = maybeOf(context);
    if (scope != null) return scope;
    throw FlutterError.fromParts([
      ErrorSummary('No ContentAssetProvider found above this widget.'),
      ErrorDescription(
        '${context.widget.runtimeType} draws content through the host\'s '
        'ContentAssetScope, which it looks up with ContentAssetProvider.',
      ),
      ErrorHint(
        'Wrap the app (or the subtree) in ContentAssetProvider(scope: ...), '
        'or pass the scope to the widget directly.',
      ),
    ]);
  }

  @override
  bool updateShouldNotify(ContentAssetProvider oldWidget) =>
      !identical(scope, oldWidget.scope);
}

/// Shows any content by [ContentKey]: media through `mpx_core`'s
/// [AssetView] on the scope's media cache, a unicode glyph from the glyph
/// atlas (or as text).
///
/// The parameters are [AssetView]'s, every one forwarded to it; for a
/// glyph, which is a still with nothing to download, [status], [badge],
/// [onPlay], [statusBuilder], [placeholderUntil], [placeholderTint],
/// [holdsWhileTickersOff], [loadingStyle], [downloadContext],
/// [requestsDownload] and [underlay] change nothing.
class ContentAssetView extends StatelessWidget {
  /// Shows [content] as [preset] says.
  const ContentAssetView({
    required this.content,
    required this.preset,
    this.tint,
    this.opacity = 1,
    this.semanticLabel,
    this.scope,
    this.status = MediaStatusMode.none,
    this.badge = false,
    this.onPlay,
    this.statusBuilder,
    this.placeholder,
    this.placeholderUntil = AssetStage.none,
    this.placeholderTint,
    this.inView = true,
    this.visibleFraction = 1,
    this.holdsWhileTickersOff = false,
    this.loadingStyle,
    this.downloadContext,
    this.requestsDownload = false,
    this.underlay,
    super.key,
  }) : assert(opacity >= 0 && opacity <= 1, 'opacity must be within 0..1'),
       assert(
         visibleFraction >= 0 && visibleFraction <= 1,
         'visibleFraction must be within 0..1',
       );

  /// Which content to show.
  final ContentKey content;

  /// The size, decode and use of the content.
  final AssetPreset preset;

  /// See [AssetView.tint].
  final Color? tint;

  /// See [AssetView.opacity].
  final double opacity;

  /// See [AssetView.semanticLabel].
  final String? semanticLabel;

  /// The scope to attach to, instead of the one a [ContentAssetProvider]
  /// provides.
  final ContentAssetScope? scope;

  /// See [AssetView.status].
  final MediaStatusMode status;

  /// See [AssetView.badge].
  final bool badge;

  /// See [AssetView.onPlay].
  final VoidCallback? onPlay;

  /// See [AssetView.statusBuilder].
  final MediaStatusBuilder? statusBuilder;

  /// See [AssetView.placeholder].
  final AssetPaintable? placeholder;

  /// See [AssetView.placeholderUntil].
  final AssetStage placeholderUntil;

  /// See [AssetView.placeholderTint].
  final Color? placeholderTint;

  /// See [AssetView.inView].
  final bool inView;

  /// See [AssetView.visibleFraction]. A glyph is hidden at 0.
  final double visibleFraction;

  /// See [AssetView.holdsWhileTickersOff].
  final bool holdsWhileTickersOff;

  /// See [AssetView.loadingStyle].
  final MediaLoadingStyle? loadingStyle;

  /// The class of conversation or surface the content is shown in, which the
  /// media scope's auto-download policy weighs. See
  /// [AssetView.downloadContext].
  final AutoDownloadContext? downloadContext;

  /// See [AssetView.requestsDownload].
  final bool requestsDownload;

  /// See [AssetView.underlay].
  final Color? underlay;

  @override
  Widget build(BuildContext context) {
    final scope = this.scope ?? ContentAssetProvider.of(context);
    if (content is ContentKey$Unicode) {
      return _GlyphView(
        content: content,
        preset: preset,
        scope: scope,
        tint: tint,
        opacity: opacity,
        semanticLabel: semanticLabel,
        placeholder: placeholder,
        inView: inView && visibleFraction > 0,
      );
    }
    return AssetView(
      content: content.mediaKey,
      preset: preset,
      scope: scope.media,
      tint: tint,
      opacity: opacity,
      semanticLabel: semanticLabel,
      status: status,
      badge: badge,
      onPlay: onPlay,
      statusBuilder: statusBuilder,
      placeholder: placeholder,
      placeholderUntil: placeholderUntil,
      placeholderTint: placeholderTint,
      inView: inView,
      visibleFraction: visibleFraction,
      holdsWhileTickersOff: holdsWhileTickersOff,
      loadingStyle: loadingStyle,
      downloadContext: downloadContext,
      requestsDownload: requestsDownload,
      underlay: underlay,
    );
  }
}

class _GlyphView extends StatefulWidget {
  const _GlyphView({
    required this.content,
    required this.preset,
    required this.scope,
    required this.tint,
    required this.opacity,
    required this.semanticLabel,
    required this.placeholder,
    required this.inView,
  });

  final ContentKey content;
  final AssetPreset preset;
  final ContentAssetScope scope;
  final Color? tint;
  final double opacity;
  final String? semanticLabel;
  final AssetPaintable? placeholder;
  final bool inView;

  @override
  State<_GlyphView> createState() => _GlyphViewState();
}

class _GlyphViewState extends State<_GlyphView> {
  late AssetBinding _binding;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(_GlyphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.content != widget.content ||
        oldWidget.preset != widget.preset ||
        !identical(oldWidget.scope, widget.scope)) {
      _detach();
      _attach();
    }
    _binding.visible = widget.inView;
  }

  void _attach() {
    _binding = widget.scope.attach(
      widget.content,
      widget.preset.spec,
      widget.preset.profile,
    )..visible = widget.inView;
    _binding.addListener(_changed);
  }

  void _detach() {
    _binding
      ..removeListener(_changed)
      ..detach();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = SizedBox.fromSize(
      size: widget.preset.size,
      child: CustomPaint(
        painter: _GlyphPainter(
          binding: _binding,
          placeholder: widget.placeholder,
          tint: widget.tint,
          opacity: widget.opacity,
        ),
      ),
    );
    final label = widget.semanticLabel;
    if (label == null) return ExcludeSemantics(child: view);
    return Semantics(label: label, image: true, child: view);
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter({
    required this.binding,
    required this.placeholder,
    required this.tint,
    required this.opacity,
  });

  final AssetBinding binding;
  final AssetPaintable? placeholder;
  final Color? tint;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (placeholder case final own?
        when binding.readiness.stage == AssetStage.none) {
      own.paint(canvas, rect, AssetPaintContext(tint: tint, opacity: opacity));
      return;
    }
    binding.paint(canvas, rect, tint: tint, opacity: opacity);
  }

  // Always: the binding's signal (a page that landed, fonts that changed) may
  // leave its stage as it was.
  @override
  bool shouldRepaint(_GlyphPainter oldDelegate) => true;
}
