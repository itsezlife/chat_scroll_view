import 'dart:math' as math;
import 'dart:ui' show Size, lerpDouble;

import 'package:meta/meta.dart';
import 'package:panel_pages/src/pack_sheet/pack_sheet_view.dart';

/// The top of a pack sheet's background and the radius of its top corners.
typedef PackSheetBackdrop = ({double top, double radius});

/// Where a pack sheet's card sits in the sheet's box, and how its top follows
/// the grid, by the reference mobile client's rules.
///
/// A sheet whose content fits under 3.2/5 of the screen wraps it
/// (`StickersAlert.onMeasure`: `contentSize < height / 5 * 3.2`). A taller one
/// takes the whole height it needs, up to the screen, and opens part-way: the
/// grid starts [lead] further down than its content, so the card's top is two
/// fifths down the screen for stickers (`height / 5 * 2`) and 0.56 of it for
/// emoji (0.3 in landscape; `EmojiPacksAlert`'s padding row). Scrolling the
/// grid takes up the lead first, raising the card, which then stays under
/// the status bar while the grid scrolls under its header.
///
/// The card's top, [cardTopAt], is in the sheet's box: the box of a tall
/// sheet starts at the top of the screen when its content fills it, and
/// [topInset] is the status bar's band in it, which the card never covers
/// but its background may.
@immutable
final class PackSheetFrame {
  const PackSheetFrame._({
    required this.height,
    required this.topInset,
    required this.lead,
    required this.fillsScreen,
  });

  /// The frame of a bottom sheet on a [screen] whose status bar is
  /// [statusBar] tall, around [content]: the card's own height (header,
  /// grid, button and the bottom inset) with every row of the grid in it.
  factory PackSheetFrame.touch({
    required Size screen,
    required double statusBar,
    required double content,
    required PackSheetGrid grid,
  }) {
    final total = content + statusBar;
    if (total < screen.height * wrapLimit) return PackSheetFrame.fixed(content);
    final openTop = switch (grid) {
      PackSheetGrid.stickers => screen.height * stickersOpenShare,
      PackSheetGrid.emoji || PackSheetGrid.severalEmoji =>
        screen.height *
            (screen.width < screen.height
                ? emojiOpenShare
                : emojiLandscapeOpenShare),
    };
    final height = math.min(total, screen.height);
    return PackSheetFrame._(
      height: height,
      topInset: statusBar,
      // `padding -= (height - contentSize)`: the box of a sheet shorter than
      // the screen starts lower, and the lead is that much shorter.
      lead: math.max(0, openTop - (screen.height - height)),
      fillsScreen: total >= screen.height,
    );
  }

  /// The frame of a sheet [height] tall that wraps its content: a short
  /// bottom sheet, or the box under a pointer, whose grid scrolls inside it.
  const PackSheetFrame.fixed(this.height)
    : topInset = 0,
      lead = 0,
      fillsScreen = false;

  /// The grid wraps its content while the sheet is under this share of the
  /// screen's height (`contentSize < height / 5 * 3.2`).
  static const double wrapLimit = 3.2 / 5;

  /// Where a tall sticker sheet's card opens: two fifths down the screen
  /// (`(int) (height / 5f * 2)`).
  static const double stickersOpenShare = 2 / 5;

  /// Where a tall emoji sheet's card opens on a portrait screen: its padding
  /// row is `displaySize.y * .56f`.
  static const double emojiOpenShare = 0.56;

  /// Where it opens on a landscape screen (`.3f`).
  static const double emojiLandscapeOpenShare = 0.3;

  /// The sticker card's top corners (`dp(12)`), squared on the status bar.
  static const double stickersRadius = 12;

  /// The emoji card's top corners (`dp((1f - statusBarT) * 14)`).
  static const double emojiRadius = 14;

  /// The height of the sheet's box.
  final double height;

  /// The status bar's band at the top of the box, or 0 for a sheet that
  /// wraps its content.
  final double topInset;

  /// How much further down than its content the grid starts, and so how far
  /// it scrolls before the card stops rising; 0 for a sheet that wraps.
  final double lead;

  /// Whether the sheet takes the whole screen, its status bar included
  /// (`fullHeight = contentSize >= height`): only such a sheet's background
  /// reaches the status bar.
  final bool fillsScreen;

  /// The card's top in the box under the grid's scroll [offset]: it rises
  /// with the grid until the lead is scrolled away (`StickersAlert`
  /// `updateLayout`: the first row's top, or 0 once it is above the grid).
  double cardTopAt(double offset) => topInset + math.max(0, lead - offset);

  /// Whether rows have scrolled under the pinned header at [offset], which
  /// is when the header's shadow line shows (`runShadowAnimation(0, true)`
  /// once the first row's top is above the grid).
  bool scrolledUnderHeaderAt(double offset) => offset > lead;

  /// The sticker card's background under a card top of [cardTop]
  /// (`StickersAlert` `onDraw`): within two status bars of the top of a
  /// sheet that fills the screen, the background grows up by the distance
  /// in, at most a status bar, and its corners square twice as fast, so the
  /// card meets the status bar square.
  PackSheetBackdrop stickersBackdrop(double cardTop) {
    final bar = topInset;
    if (!fillsScreen || bar <= 0 || cardTop >= 2 * bar) {
      return (top: cardTop, radius: stickersRadius);
    }
    final diff = math.min(bar, 2 * bar - cardTop);
    return (
      top: cardTop - diff,
      radius: stickersRadius * (1 - math.min(1, diff * 2 / bar)),
    );
  }

  /// Whether the emoji card's background closes over the status bar at a
  /// card top of [cardTop] (`statusBarT.set(y <= containerView
  /// .getPaddingTop())`), which only a sheet that fills the screen reaches;
  /// the sheet animates [emojiBackdrop]'s progress toward it.
  bool closesAt(double cardTop) => fillsScreen && cardTop <= topInset;

  /// The emoji card's background at a card top of [cardTop] and a closing
  /// progress [closed] from 0 to 1 (`EmojiPacksAlert` `dispatchDraw`: the top
  /// lerps to the screen's, the radius from 14 to 0).
  PackSheetBackdrop emojiBackdrop(double cardTop, double closed) => (
    top: lerpDouble(cardTop, 0, closed)!,
    radius: emojiRadius * (1 - closed),
  );
}
