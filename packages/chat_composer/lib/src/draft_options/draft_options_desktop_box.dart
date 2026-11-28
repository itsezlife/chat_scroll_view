import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show FontWeight, MouseCursor;
import 'package:flutter/services.dart' show SystemMouseCursors;

/// The desktop modal box the draft options open as: its size, title, Save
/// and Cancel buttons and motion.
///
/// A pure-Dart value carried by `DraftOptionsPolicy$Desktop.box`;
/// [standard] is the default, and a host overrides a field with [copyWith].
/// Every length is in logical pixels.
///
/// The box stacks, top to bottom, the title (one part), the live preview
/// (the host's bubble on its wallpaper, as tall as its messages and their
/// margins, scrolling when the window is short), the link page's rows
/// pinned under it, and the buttons: Save at the end, Cancel before it.
@immutable
final class DraftOptionsDesktopBox {
  /// A box with every field given.
  const DraftOptionsDesktopBox({
    required this.width,
    required this.radius,
    required this.shadowBlur,
    required this.windowInset,
    required this.titleHeight,
    required this.titleStart,
    required this.titleTop,
    required this.titleFontSize,
    required this.titleWeight,
    required this.buttonHeight,
    required this.buttonFontSize,
    required this.buttonWeight,
    required this.buttonRadius,
    required this.buttonPadding,
    required this.buttonGap,
    required this.buttonBandPadding,
    required this.fadeIn,
    required this.fadeOut,
    required this.optionChange,
    required this.linkCursor,
  });

  /// The desktop default: 364 wide, radius 8; a 16 semibold title 48 tall,
  /// 24 from the start and 13 from the top; Save and Cancel 34 tall, 14
  /// semibold, radius 4, 15 inside either side, 6 apart in a band 10 in
  /// from its edges; the box fades in and out over 200 ms ease-out-circ
  /// with the scrim's dim; an option change re-lays the box out at once;
  /// links in the preview take the click cursor.
  static const DraftOptionsDesktopBox standard = DraftOptionsDesktopBox(
    width: 364,
    radius: 8,
    shadowBlur: 8,
    windowInset: 16,
    titleHeight: 48,
    titleStart: 24,
    titleTop: 13,
    titleFontSize: 16,
    titleWeight: FontWeight.w600,
    buttonHeight: 34,
    buttonFontSize: 14,
    buttonWeight: FontWeight.w600,
    buttonRadius: 4,
    buttonPadding: 15,
    buttonGap: 6,
    buttonBandPadding: 10,
    fadeIn: ScrimMotion.desktop,
    fadeOut: ScrimMotion.desktop,
    optionChange: ChromeMenuRowTiming.labelInstant,
    linkCursor: SystemMouseCursors.click,
  );

  /// The box's width.
  final double width;

  /// The box's corner radius.
  final double radius;

  /// The blur of the box's shadow, in the palette's shadow colour.
  final double shadowBlur;

  /// The least room between the box and the window's edges; a short window
  /// scrolls the preview, never the rows or the buttons.
  final double windowInset;

  /// The title band's height.
  final double titleHeight;

  /// From the box's start edge to the title.
  final double titleStart;

  /// From the box's top to the title.
  final double titleTop;

  /// The title's font size.
  final double titleFontSize;

  /// The title's weight.
  final FontWeight titleWeight;

  /// A button's height.
  final double buttonHeight;

  /// A button's font size.
  final double buttonFontSize;

  /// A button's weight.
  final FontWeight buttonWeight;

  /// A button's corner radius.
  final double buttonRadius;

  /// The room either side of a button's label.
  final double buttonPadding;

  /// The room between the two buttons.
  final double buttonGap;

  /// The room around the buttons' band: above, below and at the end.
  final double buttonBandPadding;

  /// The box's fade in, beside the scrim's dim.
  final MotionSpec fadeIn;

  /// The box's fade out, beside the scrim's dim.
  final MotionSpec fadeOut;

  /// How an option change re-lays the box out: at once for a zero duration.
  /// The bubble's own change is the host builder's; it reads this from
  /// `DraftOptionsPreview.change`.
  final MotionSpec optionChange;

  /// The cursor over a link of the preview, which the host builder sets on
  /// its links (`DraftOptionsPreview.linkCursor`).
  final MouseCursor linkCursor;

  /// This box with the fields given replaced.
  DraftOptionsDesktopBox copyWith({
    double? width,
    double? radius,
    double? shadowBlur,
    double? windowInset,
    double? titleHeight,
    double? titleStart,
    double? titleTop,
    double? titleFontSize,
    FontWeight? titleWeight,
    double? buttonHeight,
    double? buttonFontSize,
    FontWeight? buttonWeight,
    double? buttonRadius,
    double? buttonPadding,
    double? buttonGap,
    double? buttonBandPadding,
    MotionSpec? fadeIn,
    MotionSpec? fadeOut,
    MotionSpec? optionChange,
    MouseCursor? linkCursor,
  }) => DraftOptionsDesktopBox(
    width: width ?? this.width,
    radius: radius ?? this.radius,
    shadowBlur: shadowBlur ?? this.shadowBlur,
    windowInset: windowInset ?? this.windowInset,
    titleHeight: titleHeight ?? this.titleHeight,
    titleStart: titleStart ?? this.titleStart,
    titleTop: titleTop ?? this.titleTop,
    titleFontSize: titleFontSize ?? this.titleFontSize,
    titleWeight: titleWeight ?? this.titleWeight,
    buttonHeight: buttonHeight ?? this.buttonHeight,
    buttonFontSize: buttonFontSize ?? this.buttonFontSize,
    buttonWeight: buttonWeight ?? this.buttonWeight,
    buttonRadius: buttonRadius ?? this.buttonRadius,
    buttonPadding: buttonPadding ?? this.buttonPadding,
    buttonGap: buttonGap ?? this.buttonGap,
    buttonBandPadding: buttonBandPadding ?? this.buttonBandPadding,
    fadeIn: fadeIn ?? this.fadeIn,
    fadeOut: fadeOut ?? this.fadeOut,
    optionChange: optionChange ?? this.optionChange,
    linkCursor: linkCursor ?? this.linkCursor,
  );

  @override
  bool operator ==(Object other) =>
      other is DraftOptionsDesktopBox &&
      other.width == width &&
      other.radius == radius &&
      other.shadowBlur == shadowBlur &&
      other.windowInset == windowInset &&
      other.titleHeight == titleHeight &&
      other.titleStart == titleStart &&
      other.titleTop == titleTop &&
      other.titleFontSize == titleFontSize &&
      other.titleWeight == titleWeight &&
      other.buttonHeight == buttonHeight &&
      other.buttonFontSize == buttonFontSize &&
      other.buttonWeight == buttonWeight &&
      other.buttonRadius == buttonRadius &&
      other.buttonPadding == buttonPadding &&
      other.buttonGap == buttonGap &&
      other.buttonBandPadding == buttonBandPadding &&
      other.fadeIn == fadeIn &&
      other.fadeOut == fadeOut &&
      other.optionChange == optionChange &&
      other.linkCursor == linkCursor;

  @override
  int get hashCode => Object.hashAll([
    width,
    radius,
    shadowBlur,
    windowInset,
    titleHeight,
    titleStart,
    titleTop,
    titleFontSize,
    titleWeight,
    buttonHeight,
    buttonFontSize,
    buttonWeight,
    buttonRadius,
    buttonPadding,
    buttonGap,
    buttonBandPadding,
    fadeIn,
    fadeOut,
    optionChange,
    linkCursor,
  ]);
}
