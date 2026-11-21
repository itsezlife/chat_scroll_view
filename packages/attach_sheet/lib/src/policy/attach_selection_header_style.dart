import 'dart:math' as math;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

/// Where the selected-items preview opens from.
enum AttachPreviewEntry {
  /// A tap on the selection header ("3 photos selected").
  header,

  /// A tap on the send button's count.
  sendCount,
}

/// The selection header's rules and look, per platform: whether the
/// selected-items preview exists and where it opens from, where the album
/// switcher stands, and the header's motion.
///
/// A host takes a preset ([AttachSelectionHeaderStyle.android],
/// [AttachSelectionHeaderStyle.switcherHeader]) and adjusts it with [copyWith], from
/// its own `AttachSheetPolicy.selectionHeader`.
@immutable
final class AttachSelectionHeaderStyle {
  /// A style; every field is a host choice.
  const AttachSelectionHeaderStyle({
    required this.previewEnabled,
    required this.previewFrom,
    required this.previewEntries,
    required this.showsSelection,
    required this.switcherPinned,
    required this.closeInPinnedBar,
    required this.shown,
    required this.band,
    required this.rise,
    required this.previewSwitch,
    required this.previewSlide,
    required this.switcherFade,
    required this.pinnedBarHeight,
  });

  /// The header of the reference's Android sheet:
  /// - with nothing selected the band over the grid is 24, the handle's;
  /// - with something selected, "N photos selected" (videos, media) stands
  ///   in the header, rising 26 into place as it fades in over 180 ms, the
  ///   band growing by as much and the handle fading out;
  /// - from two picks on it carries an arrow, and a tap on it opens the
  ///   preview (and closes it); the send button's count only sends;
  /// - the album switcher stands only in the bar pinned at the sheet's
  ///   top, beside the close button and the menu, and fades out over
  ///   150 ms while the preview shows;
  /// - the header and the preview title swap on a critically damped
  ///   spring of stiffness 1000, sliding 16.
  static const AttachSelectionHeaderStyle android = AttachSelectionHeaderStyle(
    previewEnabled: true,
    previewFrom: 2,
    previewEntries: {AttachPreviewEntry.header},
    showsSelection: true,
    switcherPinned: true,
    closeInPinnedBar: true,
    shown: MotionSpec(Duration(milliseconds: 180), accelerateDecelerate),
    band: 24,
    rise: 26,
    previewSwitch: _criticalSpring,
    previewSlide: 16,
    switcherFade: MotionSpec(
      Duration(milliseconds: 150),
      Cubic(0.42, 0, 0.58, 1),
    ),
    pinnedBarHeight: 56,
  );

  /// A header that always carries the album switcher, with the send
  /// button's count opening the preview from one pick: the sheet's header
  /// on the platforms whose own has not been traced.
  static const AttachSelectionHeaderStyle switcherHeader =
      AttachSelectionHeaderStyle(
        previewEnabled: true,
        previewFrom: 1,
        previewEntries: {AttachPreviewEntry.sendCount},
        showsSelection: false,
        switcherPinned: false,
        closeInPinnedBar: false,
        shown: MotionSpec(Duration(milliseconds: 180), Curves.easeInOut),
        band: 44,
        rise: 0,
        previewSwitch: null,
        previewSlide: 0,
        switcherFade: MotionSpec(Duration(milliseconds: 150), Curves.easeInOut),
        pinnedBarHeight: 0,
      );

  static const SpringDescription _criticalSpring = SpringDescription(
    mass: 1,
    stiffness: 1000,
    // A damping ratio of 1: 2 * sqrt(1000).
    damping: 63.245553203367585,
  );

  /// The platform's ease in and out: cos((t + 1)π) / 2 + 0.5.
  static const Curve accelerateDecelerate = _AccelerateDecelerate();

  /// Whether the selected-items preview exists at all.
  final bool previewEnabled;

  /// The fewest picks the preview opens for.
  final int previewFrom;

  /// Where the preview opens from.
  final Set<AttachPreviewEntry> previewEntries;

  /// Whether the header shows the selection ("3 photos selected") in place
  /// of the album switcher while something is selected.
  final bool showsSelection;

  /// Whether the album switcher stands only in the pinned bar (the sheet at
  /// its top), not in the resting header.
  final bool switcherPinned;

  /// Whether the pinned bar leads with the sheet's close button.
  final bool closeInPinnedBar;

  /// The selection header's fade in and out.
  final MotionSpec shown;

  /// The band between the sheet's top and the grid with nothing selected
  /// (the handle's).
  final double band;

  /// How far the selection header rises into place as it fades in; the
  /// band grows by as much.
  final double rise;

  /// The spring the header and the preview title swap on; null for an
  /// instant swap.
  final SpringDescription? previewSwitch;

  /// How far the header and the preview title slide as they swap.
  final double previewSlide;

  /// The pinned album switcher's fade while the preview shows.
  final MotionSpec switcherFade;

  /// The pinned bar's height, under the status bar.
  final double pinnedBarHeight;

  /// Whether a tap on [entry] opens the preview.
  bool opensFrom(AttachPreviewEntry entry) =>
      previewEnabled && previewEntries.contains(entry);

  /// A copy with the named fields replaced.
  AttachSelectionHeaderStyle copyWith({
    bool? previewEnabled,
    int? previewFrom,
    Set<AttachPreviewEntry>? previewEntries,
    bool? showsSelection,
    bool? switcherPinned,
    bool? closeInPinnedBar,
    MotionSpec? shown,
    double? band,
    double? rise,
    SpringDescription? previewSwitch,
    bool clearPreviewSwitch = false,
    double? previewSlide,
    MotionSpec? switcherFade,
    double? pinnedBarHeight,
  }) => AttachSelectionHeaderStyle(
    previewEnabled: previewEnabled ?? this.previewEnabled,
    previewFrom: previewFrom ?? this.previewFrom,
    previewEntries: previewEntries ?? this.previewEntries,
    showsSelection: showsSelection ?? this.showsSelection,
    switcherPinned: switcherPinned ?? this.switcherPinned,
    closeInPinnedBar: closeInPinnedBar ?? this.closeInPinnedBar,
    shown: shown ?? this.shown,
    band: band ?? this.band,
    rise: rise ?? this.rise,
    previewSwitch: clearPreviewSwitch
        ? null
        : previewSwitch ?? this.previewSwitch,
    previewSlide: previewSlide ?? this.previewSlide,
    switcherFade: switcherFade ?? this.switcherFade,
    pinnedBarHeight: pinnedBarHeight ?? this.pinnedBarHeight,
  );
}

final class _AccelerateDecelerate extends Curve {
  const _AccelerateDecelerate();

  @override
  double transformInternal(double t) => (1 - math.cos(t * math.pi)) / 2;
}
