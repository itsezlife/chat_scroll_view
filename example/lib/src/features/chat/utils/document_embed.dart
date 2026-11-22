import 'dart:ui' as ui;

import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:listen/listen.dart' as listen;
import 'package:mpx_core/mpx_core.dart';

/// What the host knows about a document sent in a message: its content key,
/// its name, its type and its size.
@immutable
final class ChatDocument {
  /// A document of [key], called [name].
  const ChatDocument({
    required this.key,
    required this.name,
    this.mimeType,
    this.byteSize,
  });

  /// The document's content.
  final ContentKey key;

  /// The file name shown in its row.
  final String name;

  /// Its media type, when the host knows it.
  final String? mimeType;

  /// Its size in bytes, when the host knows it.
  final int? byteSize;
}

/// How a document row is laid out and set: the host's to change, the
/// reference's by default.
///
/// Two layouts, as the reference draws a document in a message:
///
/// - **Thumbnailed** (an SVG with previews on): a [thumbnailExtent] square,
///   the name [thumbnailTextGap] to its right and [thumbnailTitleTop] down,
///   the size line [thumbnailInfoGap] below the bottom of the name's last
///   line, measured from the square's top as the reference does.
/// - **Icon**: an [iconExtent] round button in a row [iconRowHeight] tall,
///   the name at [iconTextLeft] across and [iconTitleTop] down, the size line
///   at [iconInfoTop].
///
/// [text] is the base every line starts from: the chrome's text root, which
/// the host passes in; the row sets only the sizes and the weight over it.
@immutable
final class DocumentRowStyle {
  /// Creates a style; the defaults are the reference's metrics.
  const DocumentRowStyle({
    this.text = const TextStyle(),
    this.width = 240,
    this.thumbnailExtent = 86,
    this.thumbnailTextGap = 10,
    this.thumbnailTitleTop = 8,
    this.thumbnailInfoGap = 13,
    this.iconExtent = 44,
    this.iconRowHeight = 56,
    this.iconTextLeft = 53,
    this.iconTitleTop = 4,
    this.iconInfoTop = 27,
    this.nameSize = 15,
    this.infoSize = 12,
    this.outerRadius = 6,
    this.innerRadius = 4,
  });

  /// The text every line starts from.
  final TextStyle text;

  /// How wide the row is.
  final double width;

  /// The thumbnail square's edge.
  final double thumbnailExtent;

  /// From the thumbnail to the text.
  final double thumbnailTextGap;

  /// From the row's top to the name, beside a thumbnail.
  final double thumbnailTitleTop;

  /// From the name's last line to the size line, beside a thumbnail.
  final double thumbnailInfoGap;

  /// The icon button's diameter.
  final double iconExtent;

  /// How tall a row with an icon is.
  final double iconRowHeight;

  /// From the row's left to the text, beside an icon.
  final double iconTextLeft;

  /// From the row's top to the name, beside an icon.
  final double iconTitleTop;

  /// From the row's top to the size line, beside an icon.
  final double iconInfoTop;

  /// The name's font size.
  final double nameSize;

  /// The size line's font size.
  final double infoSize;

  /// The thumbnail's corners on the bubble's side.
  final double outerRadius;

  /// The thumbnail's corners on the text's side.
  final double innerRadius;

  /// This style over [text].
  DocumentRowStyle withText(TextStyle text) => DocumentRowStyle(
    text: text,
    width: width,
    thumbnailExtent: thumbnailExtent,
    thumbnailTextGap: thumbnailTextGap,
    thumbnailTitleTop: thumbnailTitleTop,
    thumbnailInfoGap: thumbnailInfoGap,
    iconExtent: iconExtent,
    iconRowHeight: iconRowHeight,
    iconTextLeft: iconTextLeft,
    iconTitleTop: iconTitleTop,
    iconInfoTop: iconInfoTop,
    nameSize: nameSize,
    infoSize: infoSize,
    outerRadius: outerRadius,
    innerRadius: innerRadius,
  );

  @override
  bool operator ==(Object other) =>
      other is DocumentRowStyle &&
      other.text == text &&
      other.width == width &&
      other.thumbnailExtent == thumbnailExtent &&
      other.thumbnailTextGap == thumbnailTextGap &&
      other.thumbnailTitleTop == thumbnailTitleTop &&
      other.thumbnailInfoGap == thumbnailInfoGap &&
      other.iconExtent == iconExtent &&
      other.iconRowHeight == iconRowHeight &&
      other.iconTextLeft == iconTextLeft &&
      other.iconTitleTop == iconTitleTop &&
      other.iconInfoTop == iconInfoTop &&
      other.nameSize == nameSize &&
      other.infoSize == infoSize &&
      other.outerRadius == outerRadius &&
      other.innerRadius == innerRadius;

  @override
  int get hashCode => Object.hash(
    text,
    width,
    thumbnailExtent,
    thumbnailTextGap,
    thumbnailTitleTop,
    thumbnailInfoGap,
    iconExtent,
    iconRowHeight,
    iconTextLeft,
    iconTitleTop,
    iconInfoTop,
    nameSize,
    infoSize,
    outerRadius,
    innerRadius,
  );
}

/// A document in message text (`![name](file:id)`): a row of a thumbnail or
/// an icon, the file's name and its size. A skin over the host's rules: what
/// the thumbnail shows is [SvgDocumentPreview]'s, the metrics and text the
/// host's [DocumentRowStyle].
///
/// The thumbnail shows the document's own drawing once its bytes are here,
/// and a file icon until then: the preview never downloads anything, so a
/// document nobody downloaded keeps its icon.
final class DocumentEmbed implements InlineEmbed {
  /// A row of [document] set as [style] says, with [preview] drawing its
  /// thumbnail, or an icon row without one.
  DocumentEmbed(
    this.document, {
    required listen.ValueListenable<DocumentRowStyle> style,
    ContentEmbed? preview,
  }) : _style = style,
       _preview = preview,
       sizeHint = Size(
         style.value.width,
         preview == null
             ? style.value.iconRowHeight
             : style.value.thumbnailExtent,
       );

  /// The document the row shows.
  final ChatDocument document;

  final listen.ValueListenable<DocumentRowStyle> _style;
  final ContentEmbed? _preview;
  bool _visible = true;
  bool _disposed = false;

  // Laid out per style and text colour.
  (DocumentRowStyle, Color)? _laidOutFor;
  TextPainter? _name;
  TextPainter? _size;

  @override
  final Size sizeHint;

  /// The binding of the thumbnail's drawing, or null for a row that shows
  /// its icon only: a host reads its stage and transfer (a download control
  /// over the row, say).
  AssetBinding? get previewBinding => _preview?.binding;

  @override
  bool get visible => _visible;

  @override
  set visible(bool value) {
    _visible = value;
    _preview?.visible = value;
  }

  /// The name's and the size line's text in [ink]: the style's text root at
  /// the row's sizes.
  ({TextStyle name, TextStyle info}) textStylesFor(Color ink) {
    final style = _style.value;
    return (
      name: style.text.copyWith(
        color: ink,
        fontSize: style.nameSize,
        fontWeight: FontWeight.bold,
      ),
      // A quieter line in the text's colour; the reference's own info
      // colour is a theme key the chat's palette has no twin of.
      info: style.text.copyWith(
        color: ink.withValues(alpha: ink.a * 0.6),
        fontSize: style.infoSize,
      ),
    );
  }

  // The preview has something of its own to draw.
  bool get _previewShows => switch (_preview) {
    final preview? => preview.binding.readiness.stage != AssetStage.none,
    null => false,
  };

  @override
  void paint(Canvas canvas, Rect rect, InlineEmbedPaintContext context) {
    if (_disposed) return;
    final style = _style.value;
    final ink = context.tint ?? const Color(0xFFFFFFFF);
    final faded = ink.withValues(alpha: ink.a * context.opacity);
    final double textLeft;
    final double titleTop;
    // From the row's top, given the name's height (its last line's bottom).
    final double Function(double nameHeight) infoTop;
    if (_preview case final preview?) {
      final square = Rect.fromLTWH(
        rect.left,
        rect.top,
        style.thumbnailExtent,
        style.thumbnailExtent,
      );
      final outer = Radius.circular(style.outerRadius);
      final inner = Radius.circular(style.innerRadius);
      final clip = RRect.fromRectAndCorners(
        square,
        topLeft: outer,
        bottomLeft: outer,
        topRight: inner,
        bottomRight: inner,
      );
      canvas.drawRRect(
        clip,
        Paint()..color = faded.withValues(alpha: faded.a * 0.12),
      );
      if (_previewShows) {
        canvas
          ..save()
          ..clipRRect(clip);
        preview.paint(
          canvas,
          square,
          InlineEmbedPaintContext(
            opacity: context.opacity,
            screen: context.screen,
          ),
        );
        canvas.restore();
      } else {
        _paintPage(canvas, square.center, style.iconExtent, faded);
      }
      textLeft = square.right + style.thumbnailTextGap;
      titleTop = style.thumbnailTitleTop;
      infoTop = (nameHeight) => nameHeight + style.thumbnailInfoGap;
    } else {
      final button = Rect.fromLTWH(
        rect.left,
        rect.top,
        style.iconExtent,
        style.iconExtent,
      );
      canvas.drawCircle(
        button.center,
        style.iconExtent / 2,
        Paint()..color = faded.withValues(alpha: faded.a * 0.12),
      );
      _paintPage(canvas, button.center, style.iconExtent, faded);
      textLeft = rect.left + style.iconTextLeft;
      titleTop = style.iconTitleTop;
      infoTop = (_) => style.iconInfoTop;
    }
    _layOut(style, faded, rect.right - textLeft);
    final name = _name!;
    name.paint(canvas, Offset(textLeft, rect.top + titleTop));
    _size!.paint(canvas, Offset(textLeft, rect.top + infoTop(name.height)));
  }

  // A page with a folded corner, centred in a button of [extent].
  static void _paintPage(
    Canvas canvas,
    Offset centre,
    double extent,
    Color ink,
  ) {
    final page = Rect.fromCenter(
      center: centre,
      width: extent * 0.4,
      height: extent * 0.5,
    );
    final fold = page.width * 0.35;
    canvas.drawPath(
      Path()
        ..moveTo(page.left, page.top)
        ..lineTo(page.right - fold, page.top)
        ..lineTo(page.right, page.top + fold)
        ..lineTo(page.right, page.bottom)
        ..lineTo(page.left, page.bottom)
        ..close(),
      Paint()..color = ink.withValues(alpha: ink.a * 0.7),
    );
  }

  void _layOut(DocumentRowStyle style, Color ink, double width) {
    if (_laidOutFor == (style, ink) && _name != null) return;
    _laidOutFor = (style, ink);
    _name?.dispose();
    _size?.dispose();
    final (:name, :info) = textStylesFor(ink);
    _name = TextPainter(
      text: TextSpan(text: document.name, style: name),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: width);
    _size = TextPainter(
      text: TextSpan(text: _sizeLabel(document.byteSize), style: info),
      textDirection: ui.TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: width);
  }

  static String _sizeLabel(int? bytes) => switch (bytes) {
    null => '',
    < 1024 => '$bytes B',
    < 1024 * 1024 => '${(bytes / 1024).round()} KB',
    _ => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB',
  };

  @override
  void addListener(VoidCallback listener) => _preview?.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _preview?.removeListener(listener);

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _preview?.dispose();
    _name?.dispose();
    _size?.dispose();
  }
}

/// Resolves `file:` targets to [DocumentEmbed]s, and hands every other
/// target to [otherwise].
///
/// A document [documents] does not know resolves to nothing, so the body
/// shows its alternative text (the file's name). With [previews] an SVG
/// document's thumbnail is its own drawing, attached with the preview's tag;
/// without, every document keeps its icon. [style] sets the rows; the host
/// feeds it the chrome's text root.
final class DocumentEmbedResolver implements InlineEmbedResolver {
  /// Creates a resolver over [scope].
  DocumentEmbedResolver({
    required ContentAssetScope scope,
    required ChatDocument? Function(String id) documents,
    required InlineEmbedResolver otherwise,
    SvgDocumentPreview? previews,
    listen.ValueListenable<DocumentRowStyle>? style,
    listen.ValueListenable<MediaStageStyle>? stages,
  }) : _scope = scope,
       _documents = documents,
       _otherwise = otherwise,
       _previews = previews,
       _style = style ?? listen.ValueNotifier(const DocumentRowStyle()),
       _stages = stages;

  /// The scheme of a document target.
  static const String scheme = 'file';

  final ContentAssetScope _scope;
  final ChatDocument? Function(String id) _documents;
  final InlineEmbedResolver _otherwise;
  final SvgDocumentPreview? _previews;
  final listen.ValueListenable<DocumentRowStyle> _style;
  final listen.ValueListenable<MediaStageStyle>? _stages;

  @override
  InlineEmbed? resolve(InlineEmbedTarget target, InlineEmbedMetrics metrics) {
    if (target.scheme != scheme) return _otherwise.resolve(target, metrics);
    final document = _documents(target.id);
    if (document == null) return null;
    final previews = _previews;
    final drawn = previews?.descriptorOf(
      document.key,
      mimeType: document.mimeType,
      name: document.name,
      byteSize: document.byteSize,
    );
    return DocumentEmbed(
      document,
      style: _style,
      preview: previews == null || drawn == null
          ? null
          : ContentEmbed(
              scope: _scope,
              content: document.key,
              preset: previews.presetOf(
                extent: _style.value.thumbnailExtent,
                devicePixelRatio: metrics.devicePixelRatio,
              ),
              downloadContext: SvgDocumentPreview.downloadContext,
              stages: _stages,
            ),
    );
  }
}
