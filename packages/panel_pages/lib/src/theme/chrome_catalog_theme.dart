import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_shell/panel_shell.dart';

/// Scopes the catalogue's paint tokens, mapped from the chrome theme above, for
/// the viewport below.
///
/// `panel_catalog` takes a small theme of its own and depends on no chrome
/// package; this is the one place that knows both. The mapping changes
/// colours only. Geometry, timing and text metrics stay the viewport's
/// ([PanelCatalogThemeData.forBrightness] is the base), so a page never forks
/// them.
///
/// Requires a [ChromeThemeScope] above. A [CatalogPage] mounts this itself;
/// mount it directly only for a viewport used outside a page.
class ChromeCatalogTheme extends StatelessWidget {
  /// Provides the mapped theme to [child], with the section titles starting
  /// [headerStartInset] in, or where the viewport's own theme puts them when
  /// null.
  const ChromeCatalogTheme({
    required this.child,
    this.headerStartInset,
    this.cells = CatalogCellFeedback.emoji,
    super.key,
  });

  /// How the grid's cells answer the mouse, a press and a preview: a kind of
  /// content whose cells answer differently than an emoji's (a sticker's,
  /// a pack box's) says so here.
  final CatalogCellFeedback cells;

  /// The subtree that reads the theme.
  final Widget child;

  /// How far in from the start edge section titles begin, or null for the
  /// viewport's: a kind of content whose list sets its titles
  /// differently than another's (stickers 15, emoji 5) says so here.
  final double? headerStartInset;

  /// The wash of a hovered or focused item on a card, in [palette]: the text
  /// colour at alpha `0x12`. The one recipe the cell hover, the variant
  /// picker and the context menu share.
  static Color hoverWashOf(ChromePalette palette) =>
      palette.onSurface.withAlpha(0x12);

  /// The press feedback of a row or a button on a card, in [palette]: the
  /// text colour at alpha `0x0F`, the colour a pressed cell washes in.
  static Color pressInkOf(ChromePalette palette) =>
      palette.onSurface.withAlpha(0x0F);

  /// The hover box of a cell under the pointer arrangement, centred in it
  /// whatever its size.
  static const Size pointerHoverSize = Size(34, 32);

  /// The catalogue theme the chrome theme [chrome] stands for.
  ///
  /// - Every stand-in (circle, thumbnail silhouette, sticker wash) and the
  ///   skeleton take the placeholder tokens' `skeleton` colour.
  /// - The wash highlight and the press highlight are the palette's text
  ///   colour at fixed low alpha, the same recipe the viewport's own light
  ///   and dark themes use.
  /// - Keyboard focus is drawn in the accent.
  /// - The section title is the panel tokens' `sectionTitle`.
  /// - Under [PanelArrangement.pointer] a mouse over a cell paints the text
  ///   colour at alpha `0x12` in the box [cells] says, a press draws nothing
  ///   (the box stays on the pressed cell), and an open preview keeps the box
  ///   on the cell it shows. Under touch nothing hovers, a press draws what
  ///   [cells] says, and an open preview draws the cell it shows smaller.
  static PanelCatalogThemeData dataFor(
    ChromeThemeData chrome, {
    PanelArrangement arrangement = PanelArrangement.touch,
    double? headerStartInset,
    CatalogCellFeedback cells = CatalogCellFeedback.emoji,
  }) {
    final pointer = arrangement == PanelArrangement.pointer;
    final palette = chrome.palette;
    final base = PanelCatalogThemeData.forBrightness(palette.brightness);
    final skeleton = chrome.placeholder.skeleton;
    return base.copyWith(
      circleColor: skeleton,
      thumbColor: skeleton,
      washColor: skeleton,
      washHighlightColor: palette.onSurface.withAlpha(0x24),
      skeletonColor: skeleton,
      leafPressHighlightColor: palette.onSurface.withAlpha(0x0F),
      leafFocusHighlightColor: palette.accent.withAlpha(0x40),
      leafHoverHighlightColor: switch (arrangement) {
        PanelArrangement.pointer => hoverWashOf(palette),
        PanelArrangement.touch => null,
      },
      leafHoverHighlightSize: pointer ? cells.hoverSize : null,
      leafHoverHighlightRadius: cells.hoverRadius,
      leafHoverHighlightInset: 0,
      leafPressFeedback: pointer ? CatalogPressFeedback.none : cells.touchPress,
      leafPreviewFeedback: pointer
          ? CatalogPreviewFeedback.hover
          : CatalogPreviewFeedback.scale,
      sectionHeaderStyle: base.sectionHeaderStyle.copyWith(
        color: chrome.panel.sectionTitle,
      ),
      sectionHeaderStartInset: headerStartInset,
    );
  }

  @override
  Widget build(BuildContext context) => PanelCatalogTheme(
    data: dataFor(
      ChromeThemeScope.of(context),
      arrangement: PanelArrangementScope.of(context),
      headerStartInset: headerStartInset,
      cells: cells,
    ),
    child: child,
  );
}

/// How a grid's cells answer the mouse, a press and a preview, per kind of
/// content.
///
/// Under a pointer the hover box is [hoverSize] centred in the cell, or the
/// whole cell when null, with corners of [hoverRadius]; on touch a press
/// draws [touchPress].
@immutable
final class CatalogCellFeedback {
  /// Cells with a hover box of [hoverSize] (null: the whole cell) and
  /// [hoverRadius], whose press on touch draws [touchPress].
  const CatalogCellFeedback({
    required this.hoverRadius,
    this.hoverSize,
    this.touchPress = CatalogPressFeedback.inkAndScale,
  });

  /// An emoji cell: a 34 x 32 box of radius 8 centred in the cell; on touch
  /// a press washes and shrinks it.
  static const CatalogCellFeedback emoji = CatalogCellFeedback(
    hoverSize: ChromeCatalogTheme.pointerHoverSize,
    hoverRadius: 8,
  );

  /// A sticker cell in the panel: the whole cell, radius 6, the sticker drawn
  /// over it; on touch a press draws nothing (only an open preview scales
  /// the cell).
  static const CatalogCellFeedback sticker = CatalogCellFeedback(
    hoverRadius: 6,
    touchPress: CatalogPressFeedback.none,
  );

  /// The hover box, centred in the cell, or null for the whole cell.
  final Size? hoverSize;

  /// The hover box's corner radius.
  final double hoverRadius;

  /// What a press draws on touch.
  final CatalogPressFeedback touchPress;

  @override
  bool operator ==(Object other) =>
      other is CatalogCellFeedback &&
      other.hoverSize == hoverSize &&
      other.hoverRadius == hoverRadius &&
      other.touchPress == touchPress;

  @override
  int get hashCode => Object.hash(hoverSize, hoverRadius, touchPress);
}
