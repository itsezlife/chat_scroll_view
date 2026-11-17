import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:mpx_core/mpx_core.dart' show MediaLoadingStyle;
import 'package:panel_catalog/src/theme/panel_catalog_theme_data.dart';

/// Density-resolved paint snapshot for [CatalogLeafPainter].
///
/// Engine-facing counterpart to [PanelCatalogThemeData]: the same colours and
/// section header [TextStyle], with [leafPressSelectorRadius] already
/// multiplied by device pixel ratio. Constructed only at the
/// [PanelCatalogViewport] boundary via [resolve]; the render object stores one
/// instance on [RenderPanelCatalog.paintTheme].
///
/// Does **not** participate in host [PanelCatalogThemeData.lerp] directly:
/// interpolate [PanelCatalogThemeData], then [resolve] each frame.
///
/// ## Equality
///
/// Value-based `==` / [hashCode]. [RenderPanelCatalog.paintTheme] and
/// [CatalogLeafPainter.theme] no-op when the snapshot is unchanged (paint-only
/// update skipped).
@immutable
class CatalogLeafPaintTheme {
  /// Creates a resolved paint theme.
  ///
  /// Prefer [resolve] from [PanelCatalogThemeData] so
  /// [leafPressSelectorRadius] stays consistent with host nominal dp.
  const CatalogLeafPaintTheme({
    required this.circleColor,
    required this.thumbColor,
    required this.washColor,
    required this.washHighlightColor,
    required this.washPeriod,
    required this.skeletonColor,
    required this.placeholderCornerRadius,
    required this.leafPressHighlightColor,
    required this.leafFocusHighlightColor,
    required this.leafPressSelectorRadius,
    required this.sectionHeaderStyle,
    required this.sectionHeaderStartInset,
    this.leafHoverHighlightColor,
    this.leafHoverHighlightRadius = 8,
    this.leafHoverHighlightInset = 2,
    this.leafHoverHighlightSize,
    this.leafPressFeedback = CatalogPressFeedback.inkAndScale,
    this.leafPreviewFeedback = CatalogPreviewFeedback.scale,
    this.loading = MediaLoadingStyle.$Android,
  });

  /// Builds a paint snapshot from [data] and [devicePixelRatio].
  ///
  /// Copies colour and typography fields verbatim; applies
  /// [PanelCatalogThemeData.selectorRadiusLogicalPx] for
  /// [leafPressSelectorRadius]. [devicePixelRatio] is typically from
  /// `MediaQuery.devicePixelRatioOf` at the viewport. [loading] is the media
  /// loading style at the viewport (`MediaLoadingStyleScope.resolve`).
  factory CatalogLeafPaintTheme.resolve(
    PanelCatalogThemeData data, {
    required double devicePixelRatio,
    MediaLoadingStyle loading = MediaLoadingStyle.$Android,
  }) => CatalogLeafPaintTheme(
    circleColor: data.circleColor,
    thumbColor: data.thumbColor,
    washColor: data.washColor,
    washHighlightColor: data.washHighlightColor,
    washPeriod: data.washPeriod,
    skeletonColor: data.skeletonColor,
    placeholderCornerRadius: data.placeholderCornerRadius,
    leafPressHighlightColor: data.leafPressHighlightColor,
    leafFocusHighlightColor:
        data.leafFocusHighlightColor ?? data.leafPressHighlightColor,
    leafPressSelectorRadius: data.selectorRadiusLogicalPx(devicePixelRatio),
    leafHoverHighlightColor: data.leafHoverHighlightColor,
    leafHoverHighlightRadius: data.leafHoverHighlightRadius,
    leafHoverHighlightInset: data.leafHoverHighlightInset,
    leafHoverHighlightSize: data.leafHoverHighlightSize,
    leafPressFeedback: data.leafPressFeedback,
    leafPreviewFeedback: data.leafPreviewFeedback,
    sectionHeaderStyle: data.sectionHeaderStyle,
    sectionHeaderStartInset: data.sectionHeaderStartInset,
    loading: loading,
  );

  /// Fill of the circle placeholder of an unbaked glyph.
  final Color circleColor;

  /// Fill of the thumb-first silhouette.
  final Color thumbColor;

  /// Base fill of the sticker wash.
  final Color washColor;

  /// Colour of the band swept across the wash.
  final Color washHighlightColor;

  /// Time one sweep of the wash takes.
  final Duration washPeriod;

  /// Fill of skeleton leaves.
  final Color skeletonColor;

  /// Corner radius of rounded-rect placeholders, in logical pixels.
  final double placeholderCornerRadius;

  /// List-selector wash on the full cell rect while pressed.
  ///
  /// Fully transparent alpha disables highlight paint. Non-zero alpha is
  /// multiplied by clamped press progress each frame.
  final Color leafPressHighlightColor;

  /// List-selector wash on the cell that holds roving focus: the theme's focus
  /// token, or the press highlight when it has none. Drawn at full alpha, with
  /// the press highlight's radius.
  final Color leafFocusHighlightColor;

  /// Press-highlight corner radius in logical pixels (density-resolved).
  final double leafPressSelectorRadius;

  /// Wash under a hovering mouse, or null for none.
  final Color? leafHoverHighlightColor;

  /// Corner radius of the hover wash, in logical pixels.
  final double leafHoverHighlightRadius;

  /// Inset of the hover wash from the cell rect, in logical pixels.
  final double leafHoverHighlightInset;

  /// Size of the hover wash centred in the cell, or null for the inset cell.
  final Size? leafHoverHighlightSize;

  /// What a press draws.
  final CatalogPressFeedback leafPressFeedback;

  /// How the previewed cell is told apart.
  final CatalogPreviewFeedback leafPreviewFeedback;

  /// Section header title style.
  final TextStyle sectionHeaderStyle;

  /// Extra start inset after horizontal content padding for header titles.
  final double sectionHeaderStartInset;

  /// How media rise through their stages in the cells: the fade of a
  /// thumbnail over its preview (`stages.stageFade`), the fill and sweep of
  /// an outline preview (`stages.outlineFill`, `stages.outlineShimmer`), and
  /// the spinner of a download of unknown size (`status.spinner`).
  final MediaLoadingStyle loading;

  @override
  bool operator ==(Object other) =>
      other is CatalogLeafPaintTheme &&
      other.circleColor == circleColor &&
      other.thumbColor == thumbColor &&
      other.washColor == washColor &&
      other.washHighlightColor == washHighlightColor &&
      other.washPeriod == washPeriod &&
      other.skeletonColor == skeletonColor &&
      other.placeholderCornerRadius == placeholderCornerRadius &&
      other.leafPressHighlightColor == leafPressHighlightColor &&
      other.leafFocusHighlightColor == leafFocusHighlightColor &&
      other.leafPressSelectorRadius == leafPressSelectorRadius &&
      other.leafHoverHighlightColor == leafHoverHighlightColor &&
      other.leafHoverHighlightRadius == leafHoverHighlightRadius &&
      other.leafHoverHighlightInset == leafHoverHighlightInset &&
      other.leafHoverHighlightSize == leafHoverHighlightSize &&
      other.leafPressFeedback == leafPressFeedback &&
      other.leafPreviewFeedback == leafPreviewFeedback &&
      other.sectionHeaderStyle == sectionHeaderStyle &&
      other.sectionHeaderStartInset == sectionHeaderStartInset &&
      other.loading == loading;

  @override
  int get hashCode => Object.hash(
    circleColor,
    thumbColor,
    washColor,
    washHighlightColor,
    washPeriod,
    skeletonColor,
    placeholderCornerRadius,
    leafPressHighlightColor,
    leafFocusHighlightColor,
    leafPressSelectorRadius,
    leafHoverHighlightColor,
    leafHoverHighlightRadius,
    leafHoverHighlightInset,
    leafHoverHighlightSize,
    leafPressFeedback,
    leafPreviewFeedback,
    sectionHeaderStyle,
    sectionHeaderStartInset,
    loading,
  );
}
