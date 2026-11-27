import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

/// The type of a file row's name and info line: the sizes and weight the
/// layout measures with and the row draws with.
///
/// The row draws on the host's chrome typography (its family and fallback)
/// at these sizes, so the two agree as long as the measure uses the same
/// family; a host with a font of its own hands the layout a
/// [MediaFileTextMeasure] over it.
@immutable
final class MediaFileText {
  /// Type of the given sizes.
  const MediaFileText({
    required this.nameSize,
    required this.infoSize,
    this.nameWeight = FontWeight.normal,
    this.tabularDigits = false,
  });

  /// The name's font size.
  final double nameSize;

  /// The name's weight.
  final FontWeight nameWeight;

  /// The info and link lines' font size.
  final double infoSize;

  /// Whether the info line's digits are monospaced, so a size that counts
  /// up while bytes arrive does not shake.
  final bool tabularDigits;

  /// The name's style over [base] (the host's chrome typography).
  TextStyle nameOver(TextStyle base) =>
      base.copyWith(fontSize: nameSize, fontWeight: nameWeight);

  /// The info line's style over [base].
  TextStyle infoOver(TextStyle base) => base.copyWith(
    fontSize: infoSize,
    fontFeatures: tabularDigits ? const [FontFeature.tabularFigures()] : null,
  );

  /// A copy with the given values replaced.
  MediaFileText copyWith({
    double? nameSize,
    FontWeight? nameWeight,
    double? infoSize,
    bool? tabularDigits,
  }) => MediaFileText(
    nameSize: nameSize ?? this.nameSize,
    nameWeight: nameWeight ?? this.nameWeight,
    infoSize: infoSize ?? this.infoSize,
    tabularDigits: tabularDigits ?? this.tabularDigits,
  );

  @override
  bool operator ==(Object other) =>
      other is MediaFileText &&
      other.nameSize == nameSize &&
      other.nameWeight == nameWeight &&
      other.infoSize == infoSize &&
      other.tabularDigits == tabularDigits;

  @override
  int get hashCode =>
      Object.hash(nameSize, nameWeight, infoSize, tabularDigits);
}

/// A measured piece of row text: its widest line, its height and its line
/// count.
@immutable
final class MediaFileTextSize {
  /// A measure of [lines] lines.
  const MediaFileTextSize({
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
      other is MediaFileTextSize &&
      other.width == width &&
      other.height == height &&
      other.lines == lines;

  @override
  int get hashCode => Object.hash(width, height, lines);

  @override
  String toString() => 'MediaFileTextSize($width × $height, $lines lines)';
}

/// How the file stack's layout measures a row's text: the name's lines at
/// the width it wraps at, and the info line's width.
///
/// The layout step is pure, but a row's height grows with its name's lines
/// and some bubbles widen to their text, so it measures. The default
/// ([MediaFileTextMeasure.painter]) lays the text out with the framework's
/// painter at [MediaFileText]'s sizes in the default family; a host that
/// draws rows in a family of its own passes a measure over that family.
abstract interface class MediaFileTextMeasure {
  /// The framework painter's measure.
  const factory MediaFileTextMeasure.painter() = _PainterFileTextMeasure;

  /// The name [text] wrapped at [maxWidth] and held to [maxLines] (a name
  /// that needs more is elided in the middle to fit them).
  MediaFileTextSize name(
    String text,
    MediaFileText type, {
    required double maxWidth,
    required int maxLines,
  });

  /// The info line [text] on one line.
  MediaFileTextSize info(String text, MediaFileText type);
}

final class _PainterFileTextMeasure implements MediaFileTextMeasure {
  const _PainterFileTextMeasure();

  @override
  MediaFileTextSize name(
    String text,
    MediaFileText type, {
    required double maxWidth,
    required int maxLines,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: type.nameOver(const TextStyle())),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
    )..layout(maxWidth: maxWidth);
    final lines = painter.computeLineMetrics().length.clamp(1, maxLines);
    final size = MediaFileTextSize(
      width: painter.width,
      height: painter.height,
      lines: lines,
    );
    painter.dispose();
    return size;
  }

  @override
  MediaFileTextSize info(String text, MediaFileText type) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: type.infoOver(const TextStyle())),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final size = MediaFileTextSize(
      width: painter.width,
      height: painter.height,
    );
    painter.dispose();
    return size;
  }
}
