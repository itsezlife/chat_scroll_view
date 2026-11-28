import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart';

/// When the link page's size row shows.
enum DraftLinkSizeRow {
  /// Only when the page has a photo or a video that can shrink.
  whenShrinkable,

  /// Always, inert without shrinkable media; hidden only for a single link
  /// with no media at all.
  inertWithoutShrinkable,
}

/// How the link page sets its rows apart from the position and size rows.
enum DraftLinkSeparator {
  /// A filled gap between the size row and the apply row.
  gap,

  /// A filled skip above all the rows.
  skipAbove,
}

/// What the remove row says.
enum DraftLinkRemoveLabel {
  /// "Do not preview", in the destructive colour.
  doNotPreview,

  /// "Remove preview", in the attention style.
  removePreview,
}

/// The size and placement of one row of the link page.
@immutable
final class DraftLinkRowMetrics {
  /// Row metrics; every value in logical pixels.
  const DraftLinkRowMetrics({
    required this.height,
    required this.iconSize,
    required this.iconStart,
    required this.labelStart,
    required this.fontSize,
    required this.minWidthBeyondLabel,
  });

  /// The row's height.
  final double height;

  /// The icon's size.
  final double iconSize;

  /// From the row's start edge to the icon's.
  final double iconStart;

  /// From the row's start edge to the label's.
  final double labelStart;

  /// The label's font size.
  final double fontSize;

  /// The rows are at least this much wider than the widest label.
  final double minWidthBeyondLabel;

  @override
  bool operator ==(Object other) =>
      other is DraftLinkRowMetrics &&
      other.height == height &&
      other.iconSize == iconSize &&
      other.iconStart == iconStart &&
      other.labelStart == labelStart &&
      other.fontSize == fontSize &&
      other.minWidthBeyondLabel == minWidthBeyondLabel;

  @override
  int get hashCode => Object.hash(
    height,
    iconSize,
    iconStart,
    labelStart,
    fontSize,
    minWidthBeyondLabel,
  );
}

/// The link page's rows on one platform family: which rows show and when,
/// what they say, how they look, press and animate.
///
/// A pure-Dart value carried by `DraftOptionsPolicy.linkPage`; each preset
/// is a platform's default, and a host overrides a field with [copyWith].
@immutable
final class DraftLinkPagePolicy {
  /// A link page policy with every field given.
  const DraftLinkPagePolicy({
    required this.sizeRow,
    required this.inertOpacity,
    required this.positionNeedsText,
    required this.separator,
    required this.separatorExtent,
    required this.separatorOpacity,
    required this.applyRow,
    required this.removeLabel,
    required this.removePressOpacity,
    required this.linkHint,
    required this.removeFallsBackToNextLink,
    required this.rowMetrics,
    required this.labelChange,
    required this.ink,
    this.rowGuard = ChromeTapTiming.repeatGuard,
  });

  /// The Android rows: position, size (always, inert at 50 % without
  /// shrinkable media), an 8 gap, apply, remove; ripples; the label
  /// cross-fades over 300 ms ease-out-quint; remove falls back to the next
  /// link.
  static const DraftLinkPagePolicy android = DraftLinkPagePolicy(
    sizeRow: DraftLinkSizeRow.inertWithoutShrinkable,
    inertOpacity: 0.5,
    positionNeedsText: false,
    separator: DraftLinkSeparator.gap,
    separatorExtent: 8,
    separatorOpacity: 0.06,
    applyRow: true,
    removeLabel: DraftLinkRemoveLabel.doNotPreview,
    removePressOpacity: 0.12,
    linkHint: false,
    removeFallsBackToNextLink: true,
    rowMetrics: _rowMetrics,
    labelChange: ChromeMenuRowTiming.labelCrossFade,
    ink: ChromeInkKind.ripple,
  );

  /// The iOS rows: position, size (only with shrinkable media), a
  /// separator, apply, remove; highlights; the label changes at once.
  static const DraftLinkPagePolicy ios = DraftLinkPagePolicy(
    sizeRow: DraftLinkSizeRow.whenShrinkable,
    inertOpacity: 0.5,
    positionNeedsText: false,
    separator: DraftLinkSeparator.gap,
    separatorExtent: 8,
    separatorOpacity: 0.06,
    applyRow: true,
    removeLabel: DraftLinkRemoveLabel.doNotPreview,
    removePressOpacity: 0.12,
    linkHint: false,
    removeFallsBackToNextLink: false,
    rowMetrics: _rowMetrics,
    labelChange: ChromeMenuRowTiming.labelInstant,
    ink: ChromeInkKind.highlight,
  );

  /// The desktop rows: a 4 skip above, position (only with text), size (only
  /// with shrinkable media), remove; no apply row (Save is a button); the
  /// "click a link to choose" hint with more than one link; pointer presses;
  /// the change is instant.
  static const DraftLinkPagePolicy desktop = DraftLinkPagePolicy(
    sizeRow: DraftLinkSizeRow.whenShrinkable,
    inertOpacity: 0.5,
    positionNeedsText: true,
    separator: DraftLinkSeparator.skipAbove,
    separatorExtent: 4,
    separatorOpacity: 0.06,
    applyRow: false,
    removeLabel: DraftLinkRemoveLabel.removePreview,
    removePressOpacity: 0.12,
    linkHint: true,
    removeFallsBackToNextLink: false,
    rowMetrics: _rowMetrics,
    labelChange: ChromeMenuRowTiming.labelInstant,
    ink: ChromeInkKind.pointer,
  );

  /// The web's menu rows: the iOS rows with no apply row, since each choice
  /// applies at once. The web menu's own values are its presentation's.
  static const DraftLinkPagePolicy web = DraftLinkPagePolicy(
    sizeRow: DraftLinkSizeRow.whenShrinkable,
    inertOpacity: 0.5,
    positionNeedsText: false,
    separator: DraftLinkSeparator.gap,
    separatorExtent: 8,
    separatorOpacity: 0.06,
    applyRow: false,
    removeLabel: DraftLinkRemoveLabel.doNotPreview,
    removePressOpacity: 0.12,
    linkHint: false,
    removeFallsBackToNextLink: false,
    rowMetrics: _rowMetrics,
    labelChange: ChromeMenuRowTiming.labelInstant,
    ink: ChromeInkKind.highlight,
  );

  // The Android anatomy; the other families keep it until their
  // presentation sets their own.
  static const _rowMetrics = DraftLinkRowMetrics(
    height: 48,
    iconSize: 24,
    iconStart: 17,
    labelStart: 59,
    fontSize: 16,
    minWidthBeyondLabel: 77,
  );

  /// When the size row shows.
  final DraftLinkSizeRow sizeRow;

  /// The opacity of an inert row; a touch on it is ignored.
  final double inertOpacity;

  /// Whether the position row shows only when the draft has text.
  final bool positionNeedsText;

  /// How the rows are set apart.
  final DraftLinkSeparator separator;

  /// The separator's height.
  final double separatorExtent;

  /// The separator's fill: the row text colour at this opacity.
  final double separatorOpacity;

  /// Whether an "Apply changes" row closes the overlay (live apply); false
  /// where Save is a button.
  final bool applyRow;

  /// What the remove row says.
  final DraftLinkRemoveLabel removeLabel;

  /// The remove row's press: the destructive colour at this opacity.
  final double removePressOpacity;

  /// Whether a hint says a link can be chosen when the text has more than
  /// one.
  final bool linkHint;

  /// Whether removing the preview takes the text's next link the dismissal
  /// still allows.
  final bool removeFallsBackToNextLink;

  /// Each row's size and placement.
  final DraftLinkRowMetrics rowMetrics;

  /// How a row's label changes to its next state: a cross-fade over the
  /// duration, or at once for a zero one.
  final MotionSpec labelChange;

  /// How a row answers a press.
  final ChromeInkKind ink;

  /// Within this of an accepted tap on a row, another tap is dropped.
  final Duration rowGuard;

  /// This policy with the fields given replaced.
  DraftLinkPagePolicy copyWith({
    DraftLinkSizeRow? sizeRow,
    double? inertOpacity,
    bool? positionNeedsText,
    DraftLinkSeparator? separator,
    double? separatorExtent,
    double? separatorOpacity,
    bool? applyRow,
    DraftLinkRemoveLabel? removeLabel,
    double? removePressOpacity,
    bool? linkHint,
    bool? removeFallsBackToNextLink,
    DraftLinkRowMetrics? rowMetrics,
    MotionSpec? labelChange,
    ChromeInkKind? ink,
    Duration? rowGuard,
  }) => DraftLinkPagePolicy(
    sizeRow: sizeRow ?? this.sizeRow,
    inertOpacity: inertOpacity ?? this.inertOpacity,
    positionNeedsText: positionNeedsText ?? this.positionNeedsText,
    separator: separator ?? this.separator,
    separatorExtent: separatorExtent ?? this.separatorExtent,
    separatorOpacity: separatorOpacity ?? this.separatorOpacity,
    applyRow: applyRow ?? this.applyRow,
    removeLabel: removeLabel ?? this.removeLabel,
    removePressOpacity: removePressOpacity ?? this.removePressOpacity,
    linkHint: linkHint ?? this.linkHint,
    removeFallsBackToNextLink:
        removeFallsBackToNextLink ?? this.removeFallsBackToNextLink,
    rowMetrics: rowMetrics ?? this.rowMetrics,
    labelChange: labelChange ?? this.labelChange,
    ink: ink ?? this.ink,
    rowGuard: rowGuard ?? this.rowGuard,
  );

  @override
  bool operator ==(Object other) =>
      other is DraftLinkPagePolicy &&
      other.sizeRow == sizeRow &&
      other.inertOpacity == inertOpacity &&
      other.positionNeedsText == positionNeedsText &&
      other.separator == separator &&
      other.separatorExtent == separatorExtent &&
      other.separatorOpacity == separatorOpacity &&
      other.applyRow == applyRow &&
      other.removeLabel == removeLabel &&
      other.removePressOpacity == removePressOpacity &&
      other.linkHint == linkHint &&
      other.removeFallsBackToNextLink == removeFallsBackToNextLink &&
      other.rowMetrics == rowMetrics &&
      other.labelChange == labelChange &&
      other.ink == ink &&
      other.rowGuard == rowGuard;

  @override
  int get hashCode => Object.hash(
    sizeRow,
    inertOpacity,
    positionNeedsText,
    separator,
    separatorExtent,
    separatorOpacity,
    applyRow,
    removeLabel,
    removePressOpacity,
    linkHint,
    removeFallsBackToNextLink,
    rowMetrics,
    labelChange,
    ink,
    rowGuard,
  );
}
