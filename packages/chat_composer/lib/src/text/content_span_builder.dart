import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_composer/src/text/inline_content_span_builder.dart';
import 'package:flutter/widgets.dart';

/// An [InlineContentSpanBuilder] that shows each inline content reference
/// through `ContentView`, so the field draws it from the host's asset cache
/// like any other surface.
///
/// The span is a [WidgetSpan] holding the view, followed by zero-width word
/// joiners that make up the rest of the reference's alternative text. A
/// widget span is one code unit of text; the joiners bring the span to the
/// exact length of the alternative text, which the field needs to map
/// selection and caret by text offsets. They have no width and no glyph, and
/// forbid a line break inside the reference.
///
/// The content's size follows the text: `AssetPresets.inlineMessage` at the
/// style's font size (the field's size when the style has none) and the
/// display density. [scope] is the cache to attach to; null looks up the
/// closest `AssetCacheProvider` above the field and throws a [FlutterError]
/// when there is none.
InlineContentSpanBuilder contentSpanBuilder({
  AssetCacheScope? scope,
  double fallbackFontSize = _defaultFontSize,
}) => (context, reference, style) {
  final padding = reference.alternativeText.length - 1;
  final preset = AssetPresets.inlineMessage(
    fontSize: style.fontSize ?? fallbackFontSize,
    devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
  );
  return TextSpan(
    style: style,
    children: [
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        style: style,
        child: ContentView(
          content: reference.key,
          preset: preset,
          scope: scope,
          semanticLabel: reference.alternativeText,
        ),
      ),
      if (padding > 0) TextSpan(text: _joiner * padding, style: style),
    ],
  );
};

const double _defaultFontSize = 18;

// U+2060 WORD JOINER: no width, no glyph, no line break.
const String _joiner = '⁠';
