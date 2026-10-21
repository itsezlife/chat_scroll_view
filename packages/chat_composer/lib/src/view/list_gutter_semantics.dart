import 'package:chat_composer/src/text/composer_text_controller.dart';
import 'package:chat_composer/src/view/list_gutter_painter.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart' show EntityListKind;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// The semantics of the markers [ComposerListGutterPainter] paints.
///
/// A marker is pixels beside the text, not text, so a screen reader meets
/// none of it. This puts one node in the gutter at each item's first line,
/// labelled from `FormattingStrings` ("Bullet list item", "Numbered list item
/// 3"), so the list is spoken as a list. The nodes are placed from the field's
/// own line geometry, the one the painter draws by.
///
/// It paints nothing: it is a [CustomPaint] whose only job is the semantics
/// builder, rebuilt with the text.
final class ComposerListGutterSemantics extends StatelessWidget {
  /// Semantics for the markers of [text] over [child], the field.
  ///
  /// [editable] and [field] are read when the semantics are built, not before
  /// the first layout: the field's render editable, and the box this widget
  /// puts the nodes in.
  const ComposerListGutterSemantics({
    required this.text,
    required this.gutter,
    required this.strings,
    required this.editable,
    required this.field,
    required this.child,
    super.key,
  });

  /// The text whose items have markers.
  final ComposerTextController text;

  /// The painter that says how much room the markers take.
  final ComposerListGutterPainter gutter;

  /// The labels.
  final FormattingStrings strings;

  /// The field's render editable, or null before it exists.
  final RenderEditable? Function() editable;

  /// The render box of this widget, or null before it exists.
  final RenderBox? Function() field;

  /// The field.
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: text,
    child: child,
    builder: (context, child) => CustomPaint(
      painter: _MarkerSemantics(
        text: text,
        extent: gutter.extent,
        strings: strings,
        editable: editable,
        field: field,
      ),
      child: child,
    ),
  );
}

class _MarkerSemantics extends CustomPainter {
  _MarkerSemantics({
    required this.text,
    required this.extent,
    required this.strings,
    required this.editable,
    required this.field,
  });

  final ComposerTextController text;
  final double extent;
  final FormattingStrings strings;
  final RenderEditable? Function() editable;
  final RenderBox? Function() field;

  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool shouldRepaint(_MarkerSemantics oldDelegate) => false;

  // Rebuilt with every new painter, which the text's change makes.
  @override
  bool shouldRebuildSemantics(_MarkerSemantics oldDelegate) => true;

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) {
    final render = editable();
    final box = field();
    if (render == null || box == null || !render.hasSize || extent <= 0) {
      return const [];
    }
    final ltr = render.textDirection == TextDirection.ltr;
    final length = render.plainText.length;
    final toField = render.getTransformTo(box);
    return [
      for (final marker in text.listMarkers)
        if (marker.offset <= length)
          if (render.getLocalRectForCaret(TextPosition(offset: marker.offset))
              case final line
              when line.bottom >= 0 && line.top <= render.size.height)
            CustomPainterSemantics(
              key: ValueKey<int>(marker.offset),
              rect: MatrixUtils.transformRect(
                toField,
                Rect.fromLTWH(
                  ltr ? -extent : render.size.width,
                  line.top,
                  extent,
                  line.height,
                ),
              ),
              properties: SemanticsProperties(
                label: switch (marker.kind) {
                  EntityListKind.bullet => strings.bulletListItem,
                  EntityListKind.ordered => strings.numberedListItem(
                    marker.number,
                  ),
                },
                textDirection: render.textDirection,
              ),
            ),
    ];
  };
}
