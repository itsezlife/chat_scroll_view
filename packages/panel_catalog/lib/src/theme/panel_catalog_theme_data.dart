import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Immutable paint tokens for the panel catalog viewport paint leaves.
///
/// Hosts supply an instance to the package [PanelCatalogTheme] inherited
/// widget above the catalog subtree. [PanelCatalogViewport] reads resolved
/// values in [createRenderObject] / [updateRenderObject] — not via per-widget
/// ctor args.
///
/// ## Press highlight
///
/// [leafPressHighlightColor] is the list-selector wash on the **full cell
/// rect** while pressed. Opacity tracks press progress (`0` idle … `1` held).
/// [leafPressSelectorRadiusNominalDp] scales with device density: effective
/// logical radius ≈ `nominalDp × devicePixelRatio` ([selectorRadiusLogicalPx]).
///
/// Glyph scale (`0.8 + 0.2 × (1 − progress)`) applies to leaf content only —
/// not the highlight mask.
///
/// ## Section headers and stand-ins
///
/// [sectionHeaderColor] tints projected section titles. [standInCornerRadius]
/// rounds non-circle placeholder rects (thumb-first, wash, failed) and the
/// document ready-path stub. [documentStandInColor] fills that document stub
/// when media decode is not yet painted by the host.
///
/// ## Defaults
///
/// [light] and [dark] ship reference-aligned tints. [forBrightness] picks
/// between them. [PanelCatalogTheme.of] falls back to [light] when no ancestor
/// is mounted.
///
/// ## Animated transitions
///
/// Hosts animating light ↔ dark (or custom palettes) SHOULD drive
/// [PanelCatalogTheme.data] with [lerp] each tick rather than swapping const
/// presets in one frame.
@immutable
class PanelCatalogThemeData {
  /// Creates catalog paint tokens.
  const PanelCatalogThemeData({
    required this.placeholderColor,
    required this.leafPressHighlightColor,
    required this.sectionHeaderColor,
    required this.documentStandInColor,
    this.leafPressSelectorRadiusNominalDp = _defaultSelectorRadiusNominalDp,
    this.standInCornerRadius = _defaultStandInCornerRadius,
  });

  /// Light catalog paint defaults.
  static const PanelCatalogThemeData light = PanelCatalogThemeData(
    placeholderColor: Color(0x10000000),
    leafPressHighlightColor: Color(0x0F000000),
    sectionHeaderColor: Color(0xFF666666),
    documentStandInColor: Color(0xFF90CAF9),
  );

  /// Dark catalog paint defaults.
  static const PanelCatalogThemeData dark = PanelCatalogThemeData(
    placeholderColor: Color(0x10FFFFFF),
    leafPressHighlightColor: Color(0x0FFFFFFF),
    sectionHeaderColor: Color(0xFF999999),
    documentStandInColor: Color(0xFF64B5F6),
  );

  /// Picks [light] or [dark] from [brightness].
  factory PanelCatalogThemeData.forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// Default nominal selector corner in dp before density scaling.
  static const double _defaultSelectorRadiusNominalDp = 2;

  /// Default corner radius for rounded-rect stand-ins (logical px).
  static const double _defaultStandInCornerRadius = 6;

  /// Fill for circle / stand-in placeholders ([CatalogLeafPresentation]
  /// loading paths). Paint-only — does not affect layout extent.
  final Color placeholderColor;

  /// List-selector wash on pressed leaf cells.
  ///
  /// Fully transparent alpha disables highlight paint (scale-only feedback).
  /// Non-zero alpha is multiplied by clamped press progress each frame.
  final Color leafPressHighlightColor;

  /// Section header title color ([CatalogHeaderSlot] labels).
  final Color sectionHeaderColor;

  /// Fill for document [CatalogLeafPresentation.content] ready-path stand-in
  /// when media bytes are not yet painted by the host pipeline.
  final Color documentStandInColor;

  /// Corner radius for rounded-rect stand-ins (thumb-first, wash, failed,
  /// document stub). Distinct from [leafPressSelectorRadiusNominalDp], which
  /// applies to the full-cell press highlight only.
  final double standInCornerRadius;

  /// Nominal corner radius in dp for [selectorRadiusLogicalPx].
  ///
  /// Some hosts apply density twice (nominal dp passed into a callee that
  /// scales by DPR again). Model that as `nominal × DPR` logical pixels when
  /// resolving paint, not a fixed logical px radius on all devices.
  final double leafPressSelectorRadiusNominalDp;

  /// Effective list-selector corner radius in logical pixels.
  ///
  /// [devicePixelRatio] is typically [MediaQuery.devicePixelRatioOf].
  double selectorRadiusLogicalPx(double devicePixelRatio) =>
      leafPressSelectorRadiusNominalDp * devicePixelRatio;

  /// Linearly interpolates [a] and [b] by [t] (`0` → [a], `1` → [b]).
  static PanelCatalogThemeData lerp(
    PanelCatalogThemeData a,
    PanelCatalogThemeData b,
    double t,
  ) {
    return PanelCatalogThemeData(
      placeholderColor: Color.lerp(a.placeholderColor, b.placeholderColor, t)!,
      leafPressHighlightColor: Color.lerp(
        a.leafPressHighlightColor,
        b.leafPressHighlightColor,
        t,
      )!,
      sectionHeaderColor: Color.lerp(
        a.sectionHeaderColor,
        b.sectionHeaderColor,
        t,
      )!,
      documentStandInColor: Color.lerp(
        a.documentStandInColor,
        b.documentStandInColor,
        t,
      )!,
      leafPressSelectorRadiusNominalDp: lerpDouble(
        a.leafPressSelectorRadiusNominalDp,
        b.leafPressSelectorRadiusNominalDp,
        t,
      )!,
      standInCornerRadius: lerpDouble(
        a.standInCornerRadius,
        b.standInCornerRadius,
        t,
      )!,
    );
  }

  /// Returns a copy with the given fields replaced.
  PanelCatalogThemeData copyWith({
    Color? placeholderColor,
    Color? leafPressHighlightColor,
    Color? sectionHeaderColor,
    Color? documentStandInColor,
    double? leafPressSelectorRadiusNominalDp,
    double? standInCornerRadius,
  }) {
    return PanelCatalogThemeData(
      placeholderColor: placeholderColor ?? this.placeholderColor,
      leafPressHighlightColor:
          leafPressHighlightColor ?? this.leafPressHighlightColor,
      sectionHeaderColor: sectionHeaderColor ?? this.sectionHeaderColor,
      documentStandInColor:
          documentStandInColor ?? this.documentStandInColor,
      leafPressSelectorRadiusNominalDp:
          leafPressSelectorRadiusNominalDp ??
          this.leafPressSelectorRadiusNominalDp,
      standInCornerRadius: standInCornerRadius ?? this.standInCornerRadius,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PanelCatalogThemeData &&
      other.placeholderColor == placeholderColor &&
      other.leafPressHighlightColor == leafPressHighlightColor &&
      other.sectionHeaderColor == sectionHeaderColor &&
      other.documentStandInColor == documentStandInColor &&
      other.leafPressSelectorRadiusNominalDp ==
          leafPressSelectorRadiusNominalDp &&
      other.standInCornerRadius == standInCornerRadius;

  @override
  int get hashCode => Object.hash(
    placeholderColor,
    leafPressHighlightColor,
    sectionHeaderColor,
    documentStandInColor,
    leafPressSelectorRadiusNominalDp,
    standInCornerRadius,
  );
}
