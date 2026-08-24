import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Immutable host-facing paint tokens for the panel catalog viewport.
///
/// Does **not** own viewport layout geometry ([PanelCatalogViewport.headerExtent],
/// cell pitch, content [EdgeInsets]) or resolve device density for press
/// selector radius — [PanelCatalogViewport] builds [CatalogLeafPaintTheme] at
/// the widget boundary and passes one snapshot to the engine.
///
/// Hosts supply an instance to [PanelCatalogTheme] above the catalog subtree.
/// [PanelCatalogTheme.of] throws when no ancestor is mounted.
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
/// [sectionHeaderStyle] and [sectionHeaderStartInset] control projected section
/// title paint inside [CatalogHeaderSlot] bands — vertical centering uses the
/// slot height from the viewport; these tokens do not change content extent.
/// [standInCornerRadius] rounds non-circle placeholder rects (thumb-first, wash,
/// failed) and the document ready-path stub. [documentStandInColor] fills that
/// document stub when media decode is not yet painted by the host.
///
/// ## Defaults
///
/// [light] and [dark] ship reference-aligned tints. [forBrightness] picks
/// between them.
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
    required this.sectionHeaderStyle,
    required this.documentStandInColor,
    this.leafPressSelectorRadiusNominalDp = _defaultSelectorRadiusNominalDp,
    this.standInCornerRadius = _defaultStandInCornerRadius,
    this.sectionHeaderStartInset = _defaultSectionHeaderStartInset,
  });

  /// Light catalog paint defaults.
  ///
  /// Reference preset for [forBrightness] / [lerp] light targets.
  static const PanelCatalogThemeData light = PanelCatalogThemeData(
    placeholderColor: Color(0x10000000),
    leafPressHighlightColor: Color(0x0F000000),
    sectionHeaderStyle: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w500,
      color: Color(0xFF666666),
    ),
    documentStandInColor: Color(0xFF90CAF9),
  );

  /// Dark catalog paint defaults.
  static const PanelCatalogThemeData dark = PanelCatalogThemeData(
    placeholderColor: Color(0x10FFFFFF),
    leafPressHighlightColor: Color(0x0FFFFFFF),
    sectionHeaderStyle: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w500,
      color: Color(0xFF999999),
    ),
    documentStandInColor: Color(0xFF64B5F6),
  );

  /// Picks [light] or [dark] from [brightness].
  ///
  /// Convenience when the host already knows shell brightness and does not
  /// maintain a custom [PanelCatalogThemeData] instance.
  factory PanelCatalogThemeData.forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// Default nominal selector corner in dp before density scaling.
  static const double _defaultSelectorRadiusNominalDp = 2;

  /// Default corner radius for rounded-rect stand-ins (logical px).
  static const double _defaultStandInCornerRadius = 6;

  /// Default extra start inset after [PanelCatalogViewport.padding.left].
  static const double _defaultSectionHeaderStartInset = 8;

  /// Fill for circle / stand-in placeholders ([CatalogLeafPresentation]
  /// loading paths). Paint-only — does not affect layout extent.
  final Color placeholderColor;

  /// List-selector wash on pressed leaf cells.
  ///
  /// Fully transparent alpha disables highlight paint (scale-only feedback).
  /// Non-zero alpha is multiplied by clamped press progress each frame.
  final Color leafPressHighlightColor;

  /// Section header title style ([CatalogHeaderSlot] labels).
  ///
  /// Paint-only — does not affect [PanelCatalogViewport.headerExtent]. The
  /// label is vertically centered inside the header band. Host shells typically
  /// [copyWith] color and size from a brightness preset.
  final TextStyle sectionHeaderStyle;

  /// Extra start inset applied after horizontal [PanelCatalogViewport.padding]
  /// when painting [CatalogHeaderSlot] titles.
  final double sectionHeaderStartInset;

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
  ///
  /// [t] is not clamped. Rebuild [PanelCatalogTheme] with the result each
  /// animation tick so [CatalogLeafPaintTheme] updates through the viewport.
  /// Color channels use [Color.lerp]; radii use [lerpDouble]; header typography
  /// uses [TextStyle.lerp]. When a color lerp is undefined, that channel keeps
  /// [a]'s value ([Color.lerp] contract).
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
      sectionHeaderStyle: TextStyle.lerp(
        a.sectionHeaderStyle,
        b.sectionHeaderStyle,
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
      sectionHeaderStartInset: lerpDouble(
        a.sectionHeaderStartInset,
        b.sectionHeaderStartInset,
        t,
      )!,
    );
  }

  /// Returns a copy with the given fields replaced.
  ///
  /// Omitted arguments retain the current value. Does not mutate `this`.
  PanelCatalogThemeData copyWith({
    Color? placeholderColor,
    Color? leafPressHighlightColor,
    TextStyle? sectionHeaderStyle,
    Color? documentStandInColor,
    double? leafPressSelectorRadiusNominalDp,
    double? standInCornerRadius,
    double? sectionHeaderStartInset,
  }) {
    return PanelCatalogThemeData(
      placeholderColor: placeholderColor ?? this.placeholderColor,
      leafPressHighlightColor:
          leafPressHighlightColor ?? this.leafPressHighlightColor,
      sectionHeaderStyle: sectionHeaderStyle ?? this.sectionHeaderStyle,
      documentStandInColor:
          documentStandInColor ?? this.documentStandInColor,
      leafPressSelectorRadiusNominalDp:
          leafPressSelectorRadiusNominalDp ??
          this.leafPressSelectorRadiusNominalDp,
      standInCornerRadius: standInCornerRadius ?? this.standInCornerRadius,
      sectionHeaderStartInset:
          sectionHeaderStartInset ?? this.sectionHeaderStartInset,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PanelCatalogThemeData &&
      other.placeholderColor == placeholderColor &&
      other.leafPressHighlightColor == leafPressHighlightColor &&
      other.sectionHeaderStyle == sectionHeaderStyle &&
      other.documentStandInColor == documentStandInColor &&
      other.leafPressSelectorRadiusNominalDp ==
          leafPressSelectorRadiusNominalDp &&
      other.standInCornerRadius == standInCornerRadius &&
      other.sectionHeaderStartInset == sectionHeaderStartInset;

  @override
  int get hashCode => Object.hash(
    placeholderColor,
    leafPressHighlightColor,
    sectionHeaderStyle,
    documentStandInColor,
    leafPressSelectorRadiusNominalDp,
    standInCornerRadius,
    sectionHeaderStartInset,
  );
}
