/// The selection menu's geometry, in logical pixels.
///
/// Row sizes, paddings, label sizes and the page's sizing rule are Telegram
/// Android's floating toolbar (`ui/ActionBar/FloatingToolbar.java`), traced to
/// the site that lays each one out; `dp(N)` there is a final single conversion,
/// so N dp is N logical pixels. The line numbers are the local checkout's.
/// What the port keeps from elsewhere (the swipe-back page turn, the 150 ms /
/// 220 ms motion, the card's elevation) is not here and is recorded in ADR 026.
///
/// One set of constants: nothing differs between platforms, and the colours and
/// durations are tokens and motion roles (ADR 027).
abstract final class SelectionMenuMetrics {
  // --- Main row ---

  /// Height of a main-row button: `mLineHeight = dp(48)` (`FloatingToolbar`
  /// 415), the button's minimum height (1417) and its text view's (1448).
  static const double rowHeight = 48;

  /// Padding each side of a main-row button: `setPaddingRelative(dp(16), 0,
  /// dp(16), 0)` (1418).
  static const double buttonPadding = 16;

  /// The factor the first button's start padding and the last button's end
  /// padding take: `1.5 * getPaddingStart()` (1025).
  static const double outerPaddingFactor = 1.5;

  /// Narrowest a main-row button is: `setMinimumWidth(dp(48))` (1416).
  static const double buttonMinWidth = 48;

  /// Width of the More button, which the row keeps free at its end while
  /// anything is left for the page: `ImageButton` 56 by 48 (442),
  /// `setPaddingRelative(16, 12, 16, 12)` (443), reserved as the panel's end
  /// padding (1045).
  static const double moreButtonWidth = 56;

  /// Diameter of the disc the More button lights when pressed:
  /// `RIPPLE_MASK_CIRCLE_20DP`, a 20 dp radius.
  static const double moreButtonInkDiameter = 40;

  /// Widest the main row may be: the toolbar's default `dp(400)` (952) before
  /// the screen's own limit.
  static const double rowMaxWidth = 400;

  // --- More page ---

  /// Height of a More-page row: the same item at `overflow == true`, 42 (1417,
  /// 1448).
  static const double tileHeight = 42;

  /// Padding each side of a More-page row: `mSidePadding = dp(18)` (1384,
  /// 1406), which replaces the main row's 16.
  static const double tilePadding = 18;

  /// What the page counts a row as when it sizes its list: `mLineHeight`
  /// (1144-1150). The rows are [tileHeight] tall; the 6 dp apiece is slack.
  static const double pageLineHeight = 48;

  /// The list's padding above its first row: `setPadding(0, dp(4), 0, dp(2))`
  /// (1205).
  static const double listPaddingTop = 4;

  /// The list's padding under its last row (1205).
  static const double listPaddingBottom = 2;

  /// Fewest rows the page shows before it scrolls: `MIN_OVERFLOW_SIZE`
  /// (329), kept even where the room is short.
  static const int pageMinRows = 2;

  /// Most rows the page shows before it scrolls: `MAX_OVERFLOW_SIZE` (330).
  static const int pageMaxRows = 4;

  /// How much of the next row shows past a full page, to say it scrolls: half
  /// a [pageLineHeight] (1147).
  static const double pagePeek = pageLineHeight / 2;

  /// Height of the Back row: the More button's frame (477).
  static const double backHeight = 48;

  /// Where the Back row's icon starts: the button's 16 dp padding (443).
  static const double backIconInset = 16;

  /// Where the Back row's label starts: `createFrame(..., 56, 0, 0, 0)` (475).
  static const double backLabelInset = 56;

  /// Size of the More and Back icons: the 16 dp padding leaves 24 of the 56
  /// by 48 button (443).
  static const double iconSize = 24;

  /// Width of the leading column of a list tile, so a bullet and a number keep
  /// their labels aligned. The port's own addition: Telegram has no list items.
  static const double listMarkerWidth = 16;

  /// Space between a list marker and its label.
  static const double listMarkerGap = 8;

  /// How far the list's edges fade where a row runs under them: `fadeH = 16`
  /// (1295).
  static const double listFadeHeight = 16;

  /// The tallest the whole menu asks to be: [pageMaxRows] rows, the Back row
  /// and the peek of the next one. It takes less where the room is short.
  static const double maxHeight =
      pageMaxRows * pageLineHeight + backHeight + pagePeek;

  // --- Labels ---

  /// Font size of a row's label: `setTextSize(COMPLEX_UNIT_DIP, 14)` (1425),
  /// the same builder for both pages. DIP, so Android does not scale it by the
  /// system font size; the menu follows the app's text scale up to
  /// [maxTextScale] instead (ADR 031).
  static const double labelFontSize = 14;

  /// Font size of the Back row's label: `setTextSize(COMPLEX_UNIT_DIP, 16)`
  /// (448), in the regular weight.
  static const double backFontSize = 16;

  /// The text scale the menu follows. Its rows are fixed-height, so past this
  /// the glyphs would clip; a deliberate deviation from an unclamped scale.
  static const double maxTextScale = 1.3;

  // --- Placement ---

  /// Room kept between the card and the screen's left and right edges: the
  /// popup's `mMarginHorizontal = dp(16)` (413), which also takes the width
  /// the toolbar may have (952).
  static const double edgeMargin = 16;

  /// Room kept between the menu and the safe area's top and the keyboard or
  /// bottom inset.
  static const double regionMargin = 12;

  /// Space between the card and the selection when it sits above it.
  static const double gapAbove = 8;

  /// Space between the card and the selection when it sits below it: the
  /// platform toolbar's content distance, which leaves room for a handle.
  static const double gapBelow = 20;

  /// Room under which a side is "cramped": the menu goes to the other side if
  /// that has more.
  static const double minUsableHeight = 96;

  /// How far the card drifts, in the direction away from the selection, while
  /// it leaves.
  static const double leaveDrift = 5;

  /// The swipe speed, in logical pixels per second, from which a drag across
  /// the More page closes it whatever its position.
  static const double flingVelocity = 600;
}
