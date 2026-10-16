import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart' hide RichText;

/// Builds the span the field shows for an inline content reference.
///
/// [style] is the text style of the position (base style with the formatting
/// around it). The returned span replaces the reference's text and must lay out
/// as exactly [InlineContentRef.alternativeText]`.length` code units of
/// plain text: the field maps selection and caret by text offsets, so a span of
/// another length shifts everything after it. A debug assertion checks it.
///
/// Typical builders return a [TextSpan] of the alternative text, usually
/// painted over by the content, or a span composed so that its plain text
/// keeps that length. The default builder shows the alternative text itself,
/// which is also what remains when the content is not ready.
typedef InlineContentSpanBuilder =
    InlineSpan Function(
      BuildContext context,
      InlineContentRef reference,
      TextStyle style,
    );

/// The default [InlineContentSpanBuilder]: the alternative text in [style].
InlineSpan alternativeTextSpan(
  BuildContext context,
  InlineContentRef reference,
  TextStyle style,
) => TextSpan(text: reference.alternativeText, style: style);
