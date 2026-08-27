import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:panel_catalog/src/theme/panel_catalog_theme_data.dart';

/// Density-resolved paint snapshot for [CatalogLeafPainter].
///
/// Engine-facing counterpart to [PanelCatalogThemeData]: colors, section header
/// [TextStyle], and [leafPressSelectorRadius] already multiplied by device pixel
/// ratio. Constructed only at the [PanelCatalogViewport] boundary via [resolve];
/// the render object stores one instance on [RenderPanelCatalog.paintTheme].
///
/// Does **not** participate in host [lerp] directly — interpolate
/// [PanelCatalogThemeData], then [resolve] each frame.
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
    required this.placeholderColor,
    required this.leafPressHighlightColor,
    required this.sectionHeaderStyle,
    required this.sectionHeaderStartInset,
    required this.documentStandInColor,
    required this.leafPressSelectorRadius,
    required this.standInCornerRadius,
  });

  /// Builds a paint snapshot from [data] and [devicePixelRatio].
  ///
  /// Copies color and typography fields verbatim; applies
  /// [PanelCatalogThemeData.selectorRadiusLogicalPx] for
  /// [leafPressSelectorRadius]. [devicePixelRatio] is typically from
  /// [MediaQuery.devicePixelRatioOf] at the viewport.
  factory CatalogLeafPaintTheme.resolve(
    PanelCatalogThemeData data, {
    required double devicePixelRatio,
  }) {
    return CatalogLeafPaintTheme(
      placeholderColor: data.placeholderColor,
      leafPressHighlightColor: data.leafPressHighlightColor,
      sectionHeaderStyle: data.sectionHeaderStyle,
      sectionHeaderStartInset: data.sectionHeaderStartInset,
      documentStandInColor: data.documentStandInColor,
      leafPressSelectorRadius: data.selectorRadiusLogicalPx(devicePixelRatio),
      standInCornerRadius: data.standInCornerRadius,
    );
  }

  /// Fill for circle / stand-in placeholders ([CatalogLeafPresentation]
  /// loading paths).
  final Color placeholderColor;

  /// List-selector wash on the full cell rect while pressed.
  ///
  /// Fully transparent alpha disables highlight paint. Non-zero alpha is
  /// multiplied by clamped press progress each frame.
  final Color leafPressHighlightColor;

  /// Section header title style ([CatalogHeaderSlot] labels).
  final TextStyle sectionHeaderStyle;

  /// Extra start inset after horizontal content padding for header titles.
  final double sectionHeaderStartInset;

  /// Fill for document [CatalogLeafPresentation.content] ready-path stand-in.
  final Color documentStandInColor;

  /// Press-highlight corner radius in logical pixels (density-resolved).
  final double leafPressSelectorRadius;

  /// Corner radius for rounded-rect stand-ins in logical pixels.
  final double standInCornerRadius;

  @override
  bool operator ==(Object other) =>
      other is CatalogLeafPaintTheme &&
      other.placeholderColor == placeholderColor &&
      other.leafPressHighlightColor == leafPressHighlightColor &&
      other.sectionHeaderStyle == sectionHeaderStyle &&
      other.sectionHeaderStartInset == sectionHeaderStartInset &&
      other.documentStandInColor == documentStandInColor &&
      other.leafPressSelectorRadius == leafPressSelectorRadius &&
      other.standInCornerRadius == standInCornerRadius;

  @override
  int get hashCode => Object.hash(
    placeholderColor,
    leafPressHighlightColor,
    sectionHeaderStyle,
    sectionHeaderStartInset,
    documentStandInColor,
    leafPressSelectorRadius,
    standInCornerRadius,
  );
}
