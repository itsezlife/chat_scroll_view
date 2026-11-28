import 'dart:math' as math;
import 'dart:ui' show Offset, Rect, Size, lerpDouble;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart';

/// Where the Android card and its menu stand in the overlay's area: the
/// result of [DraftOptionsCardLayout.resolve].
///
/// The card's whole rect is [card]; its visible part starts [topOffset]
/// below the card's top, where the header sits and the clip begins. The
/// menu's box ([menu]) holds the menu's padding around its glass.
@immutable
final class DraftOptionsCardGeometry {
  /// A placement; see the fields.
  const DraftOptionsCardGeometry({
    required this.landscape,
    required this.card,
    required this.topOffset,
    required this.menu,
    required this.menuOverlap,
  });

  /// The placement part way from [a] to [b] at [t]: the card's top and its
  /// visible top lerp, which is what a change of content moves; the sizes
  /// and the landscape flag are [b]'s, and a portrait menu follows the
  /// card's bottom.
  factory DraftOptionsCardGeometry.lerp(
    DraftOptionsCardGeometry a,
    DraftOptionsCardGeometry b,
    double t,
  ) {
    if (a.landscape != b.landscape || t >= 1) return b;
    final top = lerpDouble(a.card.top, b.card.top, t)!;
    final card = Rect.fromLTWH(b.card.left, top, b.card.width, b.card.height);
    return DraftOptionsCardGeometry(
      landscape: b.landscape,
      card: card,
      topOffset: lerpDouble(a.topOffset, b.topOffset, t)!,
      menu: b.landscape
          ? b.menu
          : Rect.fromLTWH(
              b.menu.left,
              card.bottom - b.menuOverlap,
              b.menu.width,
              b.menu.height,
            ),
      menuOverlap: b.menuOverlap,
    );
  }

  /// Whether the area is wider than tall: the card at full height, the menu
  /// beside it.
  final bool landscape;

  /// The card's rect in the area, header and list included, its hidden top
  /// too.
  final Rect card;

  /// From the card's top to its visible top: the header and the clip start
  /// here, and the band above passes presses through.
  final double topOffset;

  /// The menu's box in the area, its padding included.
  final Rect menu;

  /// How far the menu's box overlaps the card's bottom in portrait; kept so
  /// a lerp places the menu as the layout does.
  final double menuOverlap;

  /// The visible top of the card in the area.
  double get visibleTop => card.top + topOffset;

  @override
  bool operator ==(Object other) =>
      other is DraftOptionsCardGeometry &&
      other.landscape == landscape &&
      other.card == card &&
      other.topOffset == topOffset &&
      other.menu == menu &&
      other.menuOverlap == menuOverlap;

  @override
  int get hashCode =>
      Object.hash(landscape, card, topOffset, menu, menuOverlap);

  @override
  String toString() =>
      'DraftOptionsCardGeometry(card: $card, topOffset: $topOffset, '
      'menu: $menu${landscape ? ', landscape' : ''})';
}

/// The Android card's metrics and the rule that places it: a pure value on
/// `DraftOptionsPolicy$Android.card`.
///
/// Portrait: the card spans the width less [sideMargin] a side; its height
/// is the area's less [menuGap] and the menu's box, never under
/// [minHeightFraction] of the area. Its list starts under the header
/// ([headerHeight]) and holds the preview at its bottom with [listPadding].
/// The visible top follows the preview's top less [firstMessageInset], but
/// the visible card and the menu never take less than [displayFraction] of
/// the display less [displayInset] (the card shrinks to short content only
/// so far). The visible card and menu are centred in the area, the card's
/// top at most [maxCentringOffset] down. The menu's box, its glass inside
/// [menuPadding], stands at the end, overlapping the card's bottom by
/// [menuOverlap].
///
/// Landscape (wider than tall): the card at full height less
/// [landscapeMargin] top and bottom, [landscapeWidthFraction] of the width
/// but at least [landscapeMinWidth] (never over the width), the menu's box
/// at its end plus [landscapeMenuGap], at the top.
@immutable
final class DraftOptionsCardLayout {
  /// A layout; every value is the Android default unless given.
  const DraftOptionsCardLayout({
    this.sideMargin = 8,
    this.cornerRadius = 8,
    this.elevation = 4,
    this.headerHeight = 56,
    this.headerPadding = 18,
    this.titleSize = 18,
    this.subtitleSize = 14,
    this.listPadding = 4,
    this.menuGap = 6,
    this.minHeightFraction = 0.5,
    this.firstMessageInset = 4,
    this.displayFraction = 0.8,
    this.displayInset = 8,
    this.maxCentringOffset = 8,
    this.menuRadius = 12,
    this.menuPadding = 8,
    this.menuOverlap = 2,
    this.landscapeMargin = 8,
    this.landscapeMinWidth = 340,
    this.landscapeWidthFraction = 0.6,
    this.landscapeMenuGap = 8,
  });

  /// The Android defaults.
  static const android = DraftOptionsCardLayout();

  /// The card's inset from each side of the area in portrait.
  final double sideMargin;

  /// The radius of the card's visible top corners and its bottom ones.
  final double cornerRadius;

  /// The card's elevation shadow.
  final double elevation;

  /// The header bar's height; the list starts under it.
  final double headerHeight;

  /// The header's start and end padding.
  final double headerPadding;

  /// The header title's size (bold).
  final double titleSize;

  /// The header subtitle's size.
  final double subtitleSize;

  /// The list's top and bottom padding around the preview.
  final double listPadding;

  /// What the card's height leaves under it besides the menu.
  final double menuGap;

  /// The least card height, as a fraction of the area.
  final double minHeightFraction;

  /// How far above the preview's top the visible top stands.
  final double firstMessageInset;

  /// The least share of the display the visible card and menu take.
  final double displayFraction;

  /// Taken off [displayFraction] of the display.
  final double displayInset;

  /// The furthest down the centring puts the card's top.
  final double maxCentringOffset;

  /// The menu glass's corner radius.
  final double menuRadius;

  /// The space around the menu's glass in its box.
  final double menuPadding;

  /// How far the menu's box overlaps the card's bottom.
  final double menuOverlap;

  /// The card's top and bottom margin in landscape.
  final double landscapeMargin;

  /// The least card width in landscape.
  final double landscapeMinWidth;

  /// The card's share of the width in landscape.
  final double landscapeWidthFraction;

  /// From the card's list width to the menu's box in landscape.
  final double landscapeMenuGap;

  /// Places the card and the menu in [area] (the overlay's area, below the
  /// system bars), on a [display] that tall, for a [menu] glass that size
  /// (its padding not included; zero for no menu) and a preview [content]
  /// that tall.
  DraftOptionsCardGeometry resolve({
    required Size area,
    required double display,
    required Size menu,
    required double content,
  }) {
    final box = menu == Size.zero
        ? Size.zero
        : Size(menu.width + 2 * menuPadding, menu.height + 2 * menuPadding);
    if (area.width > area.height) {
      final width = math.min(
        area.width,
        math.max(landscapeMinWidth, area.width * landscapeWidthFraction),
      );
      return DraftOptionsCardGeometry(
        landscape: true,
        card: Rect.fromLTWH(
          sideMargin,
          landscapeMargin,
          width,
          math.max(0, area.height - 2 * landscapeMargin),
        ),
        topOffset: 0,
        menu: Offset(width + landscapeMenuGap, 0) & box,
        menuOverlap: menuOverlap,
      );
    }
    final height = math.max(
      area.height - menuGap - box.height,
      area.height * minHeightFraction,
    );
    final list = math.max(0, height - headerHeight);
    // The preview sits at the list's bottom; above the list, it scrolls.
    final contentTop = list - listPadding - content;
    final floor = display * displayFraction - box.height - displayInset;
    final topOffset = math
        .min(list - floor, math.max(0, contentTop - firstMessageInset))
        .clamp(0, list)
        .toDouble();
    final group = box.height - displayInset + (height - topOffset);
    final top = math.min(
      maxCentringOffset +
          (area.height - 2 * maxCentringOffset - group) / 2 -
          topOffset,
      maxCentringOffset,
    );
    final card = Rect.fromLTWH(
      sideMargin,
      top,
      math.max(0, area.width - 2 * sideMargin),
      height,
    );
    return DraftOptionsCardGeometry(
      landscape: false,
      card: card,
      topOffset: topOffset,
      menu: Offset(area.width - box.width, card.bottom - menuOverlap) & box,
      menuOverlap: menuOverlap,
    );
  }

  /// A copy with the given values replaced.
  DraftOptionsCardLayout copyWith({
    double? sideMargin,
    double? cornerRadius,
    double? elevation,
    double? headerHeight,
    double? headerPadding,
    double? titleSize,
    double? subtitleSize,
    double? listPadding,
    double? menuGap,
    double? minHeightFraction,
    double? firstMessageInset,
    double? displayFraction,
    double? displayInset,
    double? maxCentringOffset,
    double? menuRadius,
    double? menuPadding,
    double? menuOverlap,
    double? landscapeMargin,
    double? landscapeMinWidth,
    double? landscapeWidthFraction,
    double? landscapeMenuGap,
  }) => DraftOptionsCardLayout(
    sideMargin: sideMargin ?? this.sideMargin,
    cornerRadius: cornerRadius ?? this.cornerRadius,
    elevation: elevation ?? this.elevation,
    headerHeight: headerHeight ?? this.headerHeight,
    headerPadding: headerPadding ?? this.headerPadding,
    titleSize: titleSize ?? this.titleSize,
    subtitleSize: subtitleSize ?? this.subtitleSize,
    listPadding: listPadding ?? this.listPadding,
    menuGap: menuGap ?? this.menuGap,
    minHeightFraction: minHeightFraction ?? this.minHeightFraction,
    firstMessageInset: firstMessageInset ?? this.firstMessageInset,
    displayFraction: displayFraction ?? this.displayFraction,
    displayInset: displayInset ?? this.displayInset,
    maxCentringOffset: maxCentringOffset ?? this.maxCentringOffset,
    menuRadius: menuRadius ?? this.menuRadius,
    menuPadding: menuPadding ?? this.menuPadding,
    menuOverlap: menuOverlap ?? this.menuOverlap,
    landscapeMargin: landscapeMargin ?? this.landscapeMargin,
    landscapeMinWidth: landscapeMinWidth ?? this.landscapeMinWidth,
    landscapeWidthFraction:
        landscapeWidthFraction ?? this.landscapeWidthFraction,
    landscapeMenuGap: landscapeMenuGap ?? this.landscapeMenuGap,
  );

  List<Object> get _props => [
    sideMargin,
    cornerRadius,
    elevation,
    headerHeight,
    headerPadding,
    titleSize,
    subtitleSize,
    listPadding,
    menuGap,
    minHeightFraction,
    firstMessageInset,
    displayFraction,
    displayInset,
    maxCentringOffset,
    menuRadius,
    menuPadding,
    menuOverlap,
    landscapeMargin,
    landscapeMinWidth,
    landscapeWidthFraction,
    landscapeMenuGap,
  ];

  @override
  bool operator ==(Object other) =>
      other is DraftOptionsCardLayout && listEquals(other._props, _props);

  @override
  int get hashCode => Object.hashAll(_props);
}

/// How the Android card moves: a pure value on
/// `DraftOptionsPolicy$Android.cardMotion`. The scope's motion speed scales
/// every duration; under an instant speed (reduce motion) each motion lands
/// on its end at once.
@immutable
final class DraftOptionsCardMotion {
  /// A motion; every value is the Android default unless given.
  const DraftOptionsCardMotion({
    this.open = ChromeCardOverlayTiming.show,
    this.close = ChromeCardOverlayTiming.hide,
    this.openScale = 0.95,
    this.offsets = ChromeCardOverlayTiming.offsets,
    this.offsetsDelay = ChromeCardOverlayTiming.offsetsDelay,
    this.scroll = ChromeCardOverlayTiming.listScroll,
  });

  /// The Android defaults.
  static const android = DraftOptionsCardMotion();

  /// The open: the whole overlay's opacity from 0 and its scale from
  /// [openScale] to 1, about its centre. It does not grow from the strip.
  final MotionSpec open;

  /// The close: the reverse of [open], then the overlay is removed (once
  /// the scrim's fade is done too).
  final MotionSpec close;

  /// The scale the overlay opens from and closes to.
  final double openScale;

  /// A changed preview: the card's visible top and centring move to the new
  /// content.
  final MotionSpec offsets;

  /// How far [offsets] starts behind the change.
  final Duration offsetsDelay;

  /// After a change of position or size, the card's list scrolls to the
  /// top (card above the text) or the bottom, when it scrolls at all.
  final MotionSpec scroll;

  @override
  bool operator ==(Object other) =>
      other is DraftOptionsCardMotion &&
      other.open == open &&
      other.close == close &&
      other.openScale == openScale &&
      other.offsets == offsets &&
      other.offsetsDelay == offsetsDelay &&
      other.scroll == scroll;

  @override
  int get hashCode =>
      Object.hash(open, close, openScale, offsets, offsetsDelay, scroll);
}
