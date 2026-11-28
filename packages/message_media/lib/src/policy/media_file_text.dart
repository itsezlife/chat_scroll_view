import 'package:flutter/painting.dart';
import 'package:meta/meta.dart';

/// The type of a file row's name and info line: the sizes and weight the
/// layout measures with and the row draws with.
///
/// Both set these over the one base style of the layout input's text
/// (`MediaLayoutText`), under its one text scaler, so the lines the layout
/// counts are the lines the row draws.
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
