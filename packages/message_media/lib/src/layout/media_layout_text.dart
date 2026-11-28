import 'dart:math' as math;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';

/// A measured piece of text: its widest line, its height and its line
/// count.
@immutable
final class MediaTextSize {
  /// A measure of [lines] lines.
  const MediaTextSize({
    required this.width,
    required this.height,
    this.lines = 1,
  });

  /// The widest line.
  final double width;

  /// The height of every line together.
  final double height;

  /// The line count.
  final int lines;

  @override
  bool operator ==(Object other) =>
      other is MediaTextSize &&
      other.width == width &&
      other.height == height &&
      other.lines == lines;

  @override
  int get hashCode => Object.hash(width, height, lines);

  @override
  String toString() => 'MediaTextSize($width × $height, $lines lines)';
}

/// How the layout step measures text: a span wrapped at a width within a
/// line limit, under a text scaler.
///
/// The layout step is pure, but a file row grows with its name's lines and a
/// card with its text, so it measures. The default
/// ([MediaTextMeasure.painter]) lays the text out with the framework's
/// painter, which is what the cells paint with; a test or a host with a
/// text engine of its own passes another.
abstract interface class MediaTextMeasure {
  /// The framework painter's measure.
  const factory MediaTextMeasure.painter() = _PainterTextMeasure;

  /// [text] scaled by [scaler], at [maxWidth] within [maxLines] (the last
  /// line ending in an ellipsis where [ellipsis] says the paint draws one).
  MediaTextSize measure(
    InlineSpan text, {
    required TextScaler scaler,
    double maxWidth = double.infinity,
    int maxLines = 1,
    bool ellipsis = false,
  });
}

final class _PainterTextMeasure implements MediaTextMeasure {
  const _PainterTextMeasure();

  @override
  MediaTextSize measure(
    InlineSpan text, {
    required TextScaler scaler,
    double maxWidth = double.infinity,
    int maxLines = 1,
    bool ellipsis = false,
  }) {
    final painter = TextPainter(
      text: text,
      textDirection: TextDirection.ltr,
      textScaler: scaler,
      maxLines: maxLines,
      ellipsis: ellipsis ? '…' : null,
    )..layout(maxWidth: math.max(0, maxWidth));
    final size = MediaTextSize(
      width: painter.width,
      height: painter.height,
      lines: painter.computeLineMetrics().length.clamp(1, maxLines),
    );
    painter.dispose();
    return size;
  }
}

/// What the layout step measures text with, and the cells paint it with:
/// one base style, one text scaler, the host's media strings and the
/// measure.
///
/// The layout and the paint agree only when both read the same style and
/// scaler, so a host builds the input's text with [MediaLayoutText.of] at
/// the context the media view is built in, and the cells read the same
/// [MediaLayoutText.of] there. The style is the host's chrome typography
/// (`ChromeTypography`), each piece setting its own size and weight over
/// it; the scaler is the platform's (`MediaQuery.textScalerOf`); the strings
/// come from the chrome strings scope (`ChromeStringsScope.mediaOf`).
@immutable
final class MediaLayoutText {
  /// Text of the given parts.
  const MediaLayoutText({
    required this.style,
    required this.scaler,
    required this.strings,
    this.measure = const MediaTextMeasure.painter(),
  });

  /// The text at [context]: the chrome typography, the platform's text
  /// scaler (none where no `MediaQuery` is above), the chrome strings
  /// scope's media strings, measured by [measure].
  factory MediaLayoutText.of(
    BuildContext context, {
    MediaTextMeasure measure = const MediaTextMeasure.painter(),
  }) => MediaLayoutText(
    style: ChromeTypography.of(context),
    scaler: MediaQuery.maybeTextScalerOf(context) ?? TextScaler.noScaling,
    strings: ChromeStringsScope.mediaOf(context),
    measure: measure,
  );

  /// The base style every piece of text sets its size and weight over.
  final TextStyle style;

  /// The text scaler the text is measured and painted under.
  final TextScaler scaler;

  /// The host's words: the file rows' sizes and labels, what a screen
  /// reader hears.
  final MediaStrings strings;

  /// How the layout measures.
  final MediaTextMeasure measure;

  /// [text] measured under [scaler]; see [MediaTextMeasure.measure].
  MediaTextSize measureOf(
    InlineSpan text, {
    double maxWidth = double.infinity,
    int maxLines = 1,
    bool ellipsis = false,
  }) => measure.measure(
    text,
    scaler: scaler,
    maxWidth: maxWidth,
    maxLines: maxLines,
    ellipsis: ellipsis,
  );

  /// A copy with the given parts replaced.
  MediaLayoutText copyWith({
    TextStyle? style,
    TextScaler? scaler,
    MediaStrings? strings,
    MediaTextMeasure? measure,
  }) => MediaLayoutText(
    style: style ?? this.style,
    scaler: scaler ?? this.scaler,
    strings: strings ?? this.strings,
    measure: measure ?? this.measure,
  );

  @override
  bool operator ==(Object other) =>
      other is MediaLayoutText &&
      other.style == style &&
      other.scaler == scaler &&
      identical(other.strings, strings) &&
      identical(other.measure, measure);

  @override
  int get hashCode => Object.hash(style, scaler, strings, measure);
}
