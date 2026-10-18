import 'package:flutter/foundation.dart';

/// Geometry of the composer's selection menu, in logical pixels.
///
/// The numbers are the reference client's floating toolbar, traced from where
/// it measures and draws, not from the call sites that name them (each carries
/// the Java it comes from, in `FloatingToolbar.java`). Every `dp(N)` there is a
/// final single conversion, so N dp is N logical pixels at any density. They
/// are component constants, not theme tokens ([ADR 027]: geometry is not
/// themed, ADR 027); the colours and the card's elevation and radius are
/// `SelectionMenuTokens`.
///
/// What differs between touch and pointer is [belowClearance], so the shape is
/// the same pure-Dart strategy pair the shortcut policy uses.
sealed class SelectionMenuMetrics {
  const SelectionMenuMetrics();

  /// Touch platforms: the selection hangs its handles under the text.
  const factory SelectionMenuMetrics.mobile() = SelectionMenuMetrics$Mobile;

  /// Pointer platforms: no handles under the selection.
  const factory SelectionMenuMetrics.desktop() = SelectionMenuMetrics$Desktop;

  /// The metrics for [platform]; the web counts as desktop.
  factory SelectionMenuMetrics.forPlatform(
    TargetPlatform platform, {
    bool isWeb = false,
  }) {
    if (isWeb) return const SelectionMenuMetrics.desktop();
    return switch (platform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.fuchsia => const SelectionMenuMetrics.mobile(),
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => const SelectionMenuMetrics.desktop(),
    };
  }

  /// How far below the selection's bottom edge the menu starts when it is
  /// placed under the selection.
  ///
  /// The reference's content rect is the selection plus the handle that hangs
  /// under it (Android's `Editor`, not in the local checkout, so this is an
  /// inference); a menu below a selection has to clear the handle. A pointer
  /// platform draws none.
  double get belowClearance;

  // --- Rows ---

  /// Height of a main-row item and of the back row. `mLineHeight = dp(48)`
  /// (FloatingToolbar.java:415); the item's minimum height is `dp(48)` (:1417).
  static const double rowHeight = 48;

  /// Height of an overflow-page item. `dp(42)` when `overflow` (:1417, :1448).
  static const double overflowRowHeight = 42;

  /// Horizontal padding of an item: `dp(16)` each side (:1418).
  static const double itemPadding = 16;

  /// Padding at the outer end of the first and the last item: 1.5 times
  /// [itemPadding] (:1025). The text view's own start padding is reset to zero
  /// (:1475).
  static const double outerItemPadding = 24;

  /// Narrowest an item gets: `setMinimumWidth(dp(48))` (:1416).
  static const double itemMinWidth = 48;

  /// Horizontal padding of an overflow-page item: `mSidePadding = dp(18)`
  /// (:1384).
  static const double overflowPadding = 18;

  /// Text size of every item: `TypedValue.COMPLEX_UNIT_DIP, 14` (:1425). The
  /// weight is `AndroidUtilities.bold()`, 500. The unit is dip, which the
  /// system font scale does not touch; the composer's labels follow the
  /// platform text scale up to [maxTextScale] instead (ADR 026).
  static const double itemTextSize = 14;

  /// Text size of the back row's label: 16 regular (:448).
  static const double backTextSize = 16;

  /// Largest text scale the menu follows. The rows are fixed-height and the
  /// card is sized to its items, so an unbounded scale would only widen the
  /// card past the screen; the shell's fixed-height controls clamp at the same
  /// 1.3 (ADR 031).
  static const double maxTextScale = 1.3;

  // --- More button and back row ---

  /// Width of the More button, flush at the card's end: `dp(56)` (:442).
  static const double moreWidth = 56;

  /// Height of the More button and of the back row (:442).
  static const double moreHeight = 48;

  /// Side of the icon in the More button and the back row: the 24 dp vector
  /// (`ft_avd_tooverflow.xml`) in a 56 by 48 frame padded 16 / 12 (:443).
  static const double iconSize = 24;

  /// Radius of the More button's splash: `RIPPLE_MASK_CIRCLE_20DP` (:454).
  static const double splashRadius = 20;

  /// Distance of the back row's arrow from its start edge: the frame's
  /// 16 dp padding (:443).
  static const double backIconInset = 16;

  /// Distance of the back row's label from its start edge: the label's start
  /// margin `56` (:475).
  static const double backLabelInset = 56;

  // --- Overflow page ---

  /// Fewest item rows the overflow page is sized to (`MIN_OVERFLOW_SIZE`,
  /// :329).
  static const int minOverflowRows = 2;

  /// Most item rows the overflow page is sized to (`MAX_OVERFLOW_SIZE`, :330).
  static const int maxOverflowRows = 4;

  /// Extra height that shows half a row when the page scrolls:
  /// `mLineHeight * 0.5` (:1147).
  static const double overflowPeek = 24;

  /// Space above the first overflow row: `setPadding(0, dp(4), 0, dp(2))`
  /// (:1205).
  static const double overflowListPaddingTop = 4;

  /// Space below the last overflow row (:1205).
  static const double overflowListPaddingBottom = 2;

  /// Height of the gradient that fades the overflow rows at the page's top and
  /// bottom edges (`fadeH = 16`, :1295).
  static const double edgeFade = 16;

  // --- Placement ---

  /// Gap between the card and the screen edge: `mMarginHorizontal = dp(16)`
  /// (:413). The window clamps so the card keeps it.
  static const double screenMargin = 16;

  /// Widest the card is allowed: `dp(400)` when no width is suggested
  /// (:954).
  static const double maxWidth = 400;

  /// Gap between the card and the selection: `mMarginVertical = dp(8)` (:414).
  static const double verticalMargin = 8;

  /// Height of the card's hairline above the back row, in physical pixels: one
  /// (`1f / density` dp, :476).
  static const double dividerPhysicalPixels = 1;
}

/// The metrics of touch platforms; see [SelectionMenuMetrics.mobile].
final class SelectionMenuMetrics$Mobile extends SelectionMenuMetrics {
  /// Creates the metrics.
  const SelectionMenuMetrics$Mobile();

  /// The size of Material's selection handle.
  @override
  double get belowClearance => 22;
}

/// The metrics of pointer platforms; see [SelectionMenuMetrics.desktop].
final class SelectionMenuMetrics$Desktop extends SelectionMenuMetrics {
  /// Creates the metrics.
  const SelectionMenuMetrics$Desktop();

  @override
  double get belowClearance => 0;
}
