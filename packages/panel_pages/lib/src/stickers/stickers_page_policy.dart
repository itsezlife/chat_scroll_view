import 'package:catalog_assets/catalog_assets.dart' show AssetCacheScope;
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/src/emoji/emoji_tab_icons.dart';
import 'package:panel_pages/src/page/catalog_strip.dart';
import 'package:panel_pages/src/policy/catalog_page_policy.dart';
import 'package:panel_pages/src/stickers/sticker_pack_strip.dart';
import 'package:panel_shell/panel_shell.dart';

/// The decisions that make a catalogue page the stickers page.
///
/// The reference mobile client's sticker list (`EmojiView`'s stickers tab,
/// `StickersGridAdapter`), as far as a list of packs goes:
///
/// - **Geometry.** As many columns as the width holds at [desiredCellWidth]
///   (`stickersPerRow = width / dp(72)`), each row [rowExtent] tall, a
///   sticker drawn at most [stickerExtent] square and centred in its cell,
///   under a [headerExtent] header whose title begins [headerStartInset] in.
///   The same under either arrangement.
/// - **Sections.** One per pack, titled by the pack, the recents first and
///   unless they are known to be empty.
/// - **Picks.** A tap picks the sticker under its own kind, so a pick lands in
///   the recents of stickers (a GIF in the pack would land in those of GIFs).
/// - **The recents header.** A clear button at its end; it asks the host to
///   clear the recent stickers (`PanelPageHost.requestClearRecents`), and the
///   host confirms, as the reference client's alert does.
/// - **Strip.** The [StickerPackStrip] above the catalogue.
///
/// Not ported: the search field, trending packs, favourites, the sticker
/// preview on a long press, the group pack, the create button, and re-ordering
/// the packs by dragging their tabs.
final class StickersPagePolicy extends CatalogPagePolicy {
  /// The stickers policy; [assets] draws the covers of the strip's tabs (none
  /// are drawn when it is null).
  const StickersPagePolicy({this.assets});

  /// What the page declares to the shell: a top strip, and nothing it
  /// searches or acts on.
  static const PageCapabilities pageCapabilities = PageCapabilities(
    topStrip: true,
  );

  /// The narrowest a column is: `width / AndroidUtilities.dp(72)`.
  static const double desiredCellWidth = 72;

  /// The height of a row: `StickerEmojiCell` is measured `dp(82)`.
  static const double rowExtent = 82;

  /// The largest side a sticker is drawn at: `StickerEmojiCell.STICKER_SIZE`.
  static const double stickerExtent = 66;

  /// The height of a header: `StickerSetNameCell.onMeasure` `dp(27)`.
  static const double headerExtent = 27;

  /// Where a title begins: the left margin of `StickerSetNameCell`'s text
  /// when it is not the emoji list's (15, against 5).
  static const double headerStartInsetValue = 15;

  /// The id of the recents header's clear button.
  static const String clearRecentsActionId = 'clear-recents';

  /// Where the strip draws pack covers from.
  final AssetCacheScope? assets;

  static const SectionLayout _layout = SectionLayout.grid(
    desiredCellWidth: desiredCellWidth,
    cellExtent: rowExtent,
    glyphExtent: stickerExtent,
    headerExtent: headerExtent,
  );

  @override
  PageCapabilities get capabilities => pageCapabilities;

  @override
  double? get headerStartInset => headerStartInsetValue;

  // --- Sections -------------------------------------------------------------

  // The recents are shown until they are known to be empty: a collection that
  // is hidden is never asked to load, so one hidden for not being loaded yet
  // would stay hidden.
  @override
  List<Collection> visibleCollections(List<Collection> all) => [
    for (final collection in all)
      if (!_isEmptyRecents(collection)) collection,
  ];

  static bool _isEmptyRecents(Collection collection) =>
      collection.id == CollectionId.recent &&
      switch (collection.contents) {
        CollectionContents$Loaded(:final items) => items.isEmpty,
        _ => false,
      };

  @override
  SectionLayout? layoutOf(
    Collection collection, {
    PanelArrangement arrangement = PanelArrangement.touch,
  }) => _layout;

  // The sticker is drawn in the 66 box, not the whole cell: the glyph box is
  // the one a grid's `glyphExtent` fixes.
  @override
  CatalogContentBox? contentBoxOf(Collection collection) =>
      CatalogContentBox.glyph;

  // --- The recents header ---------------------------------------------------

  @override
  CatalogSectionAction? actionOf(
    Collection collection,
    PanelStrings strings, {
    PanelArrangement arrangement = PanelArrangement.touch,
  }) => collection.id == CollectionId.recent
      ? CatalogSectionAction(
          id: clearRecentsActionId,
          painter: _paintCross,
          semanticLabel: strings.clearRecentAction,
        )
      : null;

  // `msg_close`: two strokes crossing, in the header's colour.
  static void _paintCross(Canvas canvas, Rect box, Color color) {
    final unit = box.width / 24;
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7 * unit
      ..strokeCap = StrokeCap.round;
    Offset at(double x, double y) => box.topLeft + Offset(x, y) * unit;
    canvas
      ..drawLine(at(7.5, 7.5), at(16.5, 16.5), pen)
      ..drawLine(at(16.5, 7.5), at(7.5, 16.5), pen);
  }

  @override
  void onSectionAction(
    Collection collection,
    String actionId,
    PanelPageHost host, {
    BuildContext? context,
    Rect? bounds,
    Rect? viewportBounds,
  }) {
    if (actionId == clearRecentsActionId) {
      host.requestClearRecents(SemanticKind.sticker);
    }
  }

  // --- A fresh open ---------------------------------------------------------

  /// The page goes back to its start on a fresh open: the grid at its first
  /// section, the strip whole, its first tab (the recents, else the first
  /// pack) marked, as the reference mobile client's emoji view does each time
  /// it is shown (`onOpen` scrolls the stickers to position 0 and selects the
  /// first tab).
  @override
  bool get restartsOnFreshOpen => true;

  // --- Chrome ---------------------------------------------------------------

  @override
  double get stripExtent => StickerPackStrip.height;

  @override
  Widget? buildStrip(BuildContext context, CatalogStripHandle strip) =>
      EmojiTabIconScope(
        child: StickerPackStrip(handle: strip, assets: assets),
      );
}
