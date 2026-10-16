import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// Immutable paint tokens the panel catalog viewport owns.
///
/// A small, closed set on purpose: the viewport depends on no chrome or design
/// system package. A page that has foundation tokens maps them onto this class
/// in one place and scopes the result with [PanelCatalogTheme].
///
/// Does **not** own viewport layout geometry (cell pitch, header band height,
/// content insets) or resolve device density: [PanelCatalogViewport] builds a
/// density-resolved paint snapshot at the widget boundary.
///
/// ## Placeholder tokens
///
/// A leaf stands in for its content until the content can be drawn, in the
/// style its descriptor facts name ([CatalogLeaf.placeholderStyle]):
///
/// | Style | Tokens |
/// | ----- | ------ |
/// | circle (a glyph that is not baked yet) | [circleColor] |
/// | thumb-first (animated or custom content) | [thumbColor], [placeholderCornerRadius] |
/// | shaped wash (a sticker) | [washColor], [washHighlightColor], [washPeriod], [placeholderCornerRadius] |
/// | skeleton leaves of a section that is loading | [skeletonColor] |
///
/// There is no token for a failed leaf: a leaf that cannot load keeps its
/// placeholder.
///
/// ## Press and header tokens
///
/// [leafPressHighlightColor] is the list-selector wash on the **full cell
/// rect** while pressed. Opacity tracks press progress (`0` idle ... `1` held).
/// [leafPressSelectorRadiusNominalDp] scales with device density: effective
/// logical radius is `nominalDp x devicePixelRatio` ([selectorRadiusLogicalPx]).
/// Glyph scale (`0.8 + 0.2 x (1 - progress)`) applies to leaf content only,
/// not to the highlight.
///
/// [leafFocusHighlightColor] is the same wash on the cell that holds roving
/// focus, at full strength. Left null it **is** the press highlight (same
/// colour, same radius), so one token styles both; set it when the press
/// highlight is off or too faint to be the only sign of where focus is.
///
/// [leafHoverHighlightColor] is the wash a **mouse** hovering a leaf paints on
/// the cell, as a rounded rect of [leafHoverHighlightRadius] logical pixels
/// inset by [leafHoverHighlightInset] from the cell rect (the interactive area
/// of a cell is a little smaller than its pitch), or a box of
/// [leafHoverHighlightSize] centred in the cell when that is set. Instant: no
/// fade, ripple or scale. Null (the default) paints no hover at all, which is
/// what a touch arrangement wants; a page that arranges for a pointer sets it.
///
/// [leafPressFeedback] says whether a press draws the press wash and shrinks
/// the leaf ([CatalogPressFeedback.inkAndScale], the default) or neither
/// ([CatalogPressFeedback.none]: a desktop list, where the hover box stays on
/// the pressed cell until it is released).
///
/// [sectionHeaderStyle] and [sectionHeaderStartInset] control section title
/// paint inside the header band; they do not change content extent.
///
/// ## Defaults
///
/// [light] and [dark] ship reference-aligned tints. [forBrightness] picks
/// between them.
///
/// ## Animated transitions
///
/// Hosts animating light / dark (or custom palettes) SHOULD drive
/// [PanelCatalogTheme.data] with [lerp] each tick rather than swapping presets
/// in one frame.
@immutable
class PanelCatalogThemeData {
  /// Creates catalog paint tokens.
  const PanelCatalogThemeData({
    required this.circleColor,
    required this.thumbColor,
    required this.washColor,
    required this.washHighlightColor,
    required this.skeletonColor,
    required this.leafPressHighlightColor,
    required this.sectionHeaderStyle,
    this.washPeriod = _defaultWashPeriod,
    this.placeholderCornerRadius = _defaultPlaceholderCornerRadius,
    this.leafFocusHighlightColor,
    this.leafHoverHighlightColor,
    this.leafHoverHighlightRadius = _defaultHoverRadius,
    this.leafHoverHighlightInset = _defaultHoverInset,
    this.leafHoverHighlightSize,
    this.leafPressFeedback = CatalogPressFeedback.inkAndScale,
    this.leafPressSelectorRadiusNominalDp = _defaultSelectorRadiusNominalDp,
    this.sectionHeaderStartInset = _defaultSectionHeaderStartInset,
  });

  /// Picks [light] or [dark] from [brightness].
  ///
  /// Convenience when the host already knows shell brightness and does not
  /// maintain a custom [PanelCatalogThemeData] instance.
  factory PanelCatalogThemeData.forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// Linearly interpolates [a] and [b] by [t] (`0` gives [a], `1` gives [b]).
  ///
  /// [t] is not clamped. Rebuild [PanelCatalogTheme] with the result each
  /// animation tick so the viewport's paint snapshot follows. Colors use
  /// [Color.lerp], numbers [lerpDouble], the wash period its microseconds and
  /// header typography [TextStyle.lerp].
  factory PanelCatalogThemeData.lerp(
    PanelCatalogThemeData a,
    PanelCatalogThemeData b,
    double t,
  ) => PanelCatalogThemeData(
    circleColor: Color.lerp(a.circleColor, b.circleColor, t)!,
    thumbColor: Color.lerp(a.thumbColor, b.thumbColor, t)!,
    washColor: Color.lerp(a.washColor, b.washColor, t)!,
    washHighlightColor: Color.lerp(
      a.washHighlightColor,
      b.washHighlightColor,
      t,
    )!,
    washPeriod: Duration(
      microseconds: lerpDouble(
        a.washPeriod.inMicroseconds,
        b.washPeriod.inMicroseconds,
        t,
      )!.round(),
    ),
    skeletonColor: Color.lerp(a.skeletonColor, b.skeletonColor, t)!,
    placeholderCornerRadius: lerpDouble(
      a.placeholderCornerRadius,
      b.placeholderCornerRadius,
      t,
    )!,
    leafPressHighlightColor: Color.lerp(
      a.leafPressHighlightColor,
      b.leafPressHighlightColor,
      t,
    )!,
    leafFocusHighlightColor: Color.lerp(
      a.leafFocusHighlightColor,
      b.leafFocusHighlightColor,
      t,
    ),
    leafHoverHighlightColor: Color.lerp(
      a.leafHoverHighlightColor,
      b.leafHoverHighlightColor,
      t,
    ),
    leafHoverHighlightRadius: lerpDouble(
      a.leafHoverHighlightRadius,
      b.leafHoverHighlightRadius,
      t,
    )!,
    leafHoverHighlightInset: lerpDouble(
      a.leafHoverHighlightInset,
      b.leafHoverHighlightInset,
      t,
    )!,
    leafHoverHighlightSize: Size.lerp(
      a.leafHoverHighlightSize,
      b.leafHoverHighlightSize,
      t,
    ),
    leafPressFeedback: t < 0.5 ? a.leafPressFeedback : b.leafPressFeedback,
    leafPressSelectorRadiusNominalDp: lerpDouble(
      a.leafPressSelectorRadiusNominalDp,
      b.leafPressSelectorRadiusNominalDp,
      t,
    )!,
    sectionHeaderStyle: TextStyle.lerp(
      a.sectionHeaderStyle,
      b.sectionHeaderStyle,
      t,
    )!,
    sectionHeaderStartInset: lerpDouble(
      a.sectionHeaderStartInset,
      b.sectionHeaderStartInset,
      t,
    )!,
  );

  /// Light catalog paint defaults.
  ///
  /// Reference preset for [forBrightness] / [lerp] light targets.
  static const PanelCatalogThemeData light = PanelCatalogThemeData(
    circleColor: Color(0x10000000),
    thumbColor: Color(0x10000000),
    washColor: Color(0x10000000),
    washHighlightColor: Color(0x24000000),
    skeletonColor: Color(0x10000000),
    leafPressHighlightColor: Color(0x0F000000),
    sectionHeaderStyle: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w500,
      color: Color(0xFF666666),
    ),
  );

  /// Dark catalog paint defaults.
  static const PanelCatalogThemeData dark = PanelCatalogThemeData(
    circleColor: Color(0x10FFFFFF),
    thumbColor: Color(0x10FFFFFF),
    washColor: Color(0x10FFFFFF),
    washHighlightColor: Color(0x24FFFFFF),
    skeletonColor: Color(0x10FFFFFF),
    leafPressHighlightColor: Color(0x0FFFFFFF),
    sectionHeaderStyle: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w500,
      color: Color(0xFF999999),
    ),
  );

  /// One sweep of the wash highlight, from the reference placeholder.
  static const Duration _defaultWashPeriod = Duration(milliseconds: 1800);

  /// Default corner radius for rounded-rect placeholders (logical px).
  static const double _defaultPlaceholderCornerRadius = 6;

  /// Default nominal selector corner in dp before density scaling.
  static const double _defaultSelectorRadiusNominalDp = 2;

  /// Default corner radius of the hover wash (logical px).
  static const double _defaultHoverRadius = 8;

  /// Default inset of the hover wash from the cell rect (logical px).
  static const double _defaultHoverInset = 2;

  /// Default extra start inset after the viewport's left padding.
  static const double _defaultSectionHeaderStartInset = 8;

  /// Fill of the circle that stands in for a glyph that is not baked yet.
  final Color circleColor;

  /// Fill of the silhouette that stands in for animated or custom content
  /// until its thumbnail or media arrives.
  final Color thumbColor;

  /// Base fill of the shaped wash that stands in for a sticker.
  final Color washColor;

  /// Colour of the moving band the wash is swept with.
  final Color washHighlightColor;

  /// Time one sweep of the wash highlight takes across the viewport.
  final Duration washPeriod;

  /// Fill of the skeleton leaves of a section that is loading.
  final Color skeletonColor;

  /// Corner radius of the thumb-first and wash placeholders.
  final double placeholderCornerRadius;

  /// List-selector wash on pressed leaf cells.
  ///
  /// Fully transparent alpha disables highlight paint (scale-only feedback).
  /// Non-zero alpha is multiplied by clamped press progress each frame.
  final Color leafPressHighlightColor;

  /// List-selector wash on the leaf cell that holds roving focus, or null to
  /// paint it with [leafPressHighlightColor].
  ///
  /// Painted on the full cell rect, under the leaf, with the press highlight's
  /// radius. Unlike the press highlight it is not scaled by progress: a focused
  /// cell shows it at full alpha. Fully transparent disables it.
  final Color? leafFocusHighlightColor;

  /// Wash a mouse hovering a leaf paints on its cell, or null for none.
  ///
  /// Painted under the leaf, instantly, for the mouse only: a finger and a
  /// stylus in contact never hover. Fully transparent disables it.
  final Color? leafHoverHighlightColor;

  /// Corner radius of the hover wash, in logical pixels.
  final double leafHoverHighlightRadius;

  /// How far the hover wash is inset from the cell rect on every side, in
  /// logical pixels.
  final double leafHoverHighlightInset;

  /// The size of the hover wash, centred in the cell (held to it), or null to
  /// inset the cell by [leafHoverHighlightInset].
  final Size? leafHoverHighlightSize;

  /// What a press draws.
  final CatalogPressFeedback leafPressFeedback;

  /// Nominal corner radius in dp for [selectorRadiusLogicalPx].
  ///
  /// Some hosts apply density twice (nominal dp passed into a callee that
  /// scales by DPR again). Model that as `nominal x DPR` logical pixels when
  /// resolving paint, not a fixed logical px radius on all devices.
  final double leafPressSelectorRadiusNominalDp;

  /// Section header title style.
  ///
  /// Paint-only: it does not affect the header band height. The label is
  /// vertically centred inside the band. Host shells typically [copyWith] color
  /// and size from a brightness preset.
  final TextStyle sectionHeaderStyle;

  /// Extra start inset applied after horizontal padding when painting section
  /// titles.
  final double sectionHeaderStartInset;

  /// Effective list-selector corner radius in logical pixels.
  ///
  /// [devicePixelRatio] is typically `MediaQuery.devicePixelRatioOf`.
  double selectorRadiusLogicalPx(double devicePixelRatio) =>
      leafPressSelectorRadiusNominalDp * devicePixelRatio;

  /// Returns a copy with the given fields replaced.
  ///
  /// Omitted arguments retain the current value. Does not mutate `this`.
  PanelCatalogThemeData copyWith({
    Color? circleColor,
    Color? thumbColor,
    Color? washColor,
    Color? washHighlightColor,
    Duration? washPeriod,
    Color? skeletonColor,
    double? placeholderCornerRadius,
    Color? leafPressHighlightColor,
    Color? leafFocusHighlightColor,
    Color? leafHoverHighlightColor,
    double? leafHoverHighlightRadius,
    double? leafHoverHighlightInset,
    Size? leafHoverHighlightSize,
    CatalogPressFeedback? leafPressFeedback,
    double? leafPressSelectorRadiusNominalDp,
    TextStyle? sectionHeaderStyle,
    double? sectionHeaderStartInset,
  }) => PanelCatalogThemeData(
    circleColor: circleColor ?? this.circleColor,
    thumbColor: thumbColor ?? this.thumbColor,
    washColor: washColor ?? this.washColor,
    washHighlightColor: washHighlightColor ?? this.washHighlightColor,
    washPeriod: washPeriod ?? this.washPeriod,
    skeletonColor: skeletonColor ?? this.skeletonColor,
    placeholderCornerRadius:
        placeholderCornerRadius ?? this.placeholderCornerRadius,
    leafPressHighlightColor:
        leafPressHighlightColor ?? this.leafPressHighlightColor,
    leafFocusHighlightColor:
        leafFocusHighlightColor ?? this.leafFocusHighlightColor,
    leafHoverHighlightColor:
        leafHoverHighlightColor ?? this.leafHoverHighlightColor,
    leafHoverHighlightRadius:
        leafHoverHighlightRadius ?? this.leafHoverHighlightRadius,
    leafHoverHighlightInset:
        leafHoverHighlightInset ?? this.leafHoverHighlightInset,
    leafHoverHighlightSize:
        leafHoverHighlightSize ?? this.leafHoverHighlightSize,
    leafPressFeedback: leafPressFeedback ?? this.leafPressFeedback,
    leafPressSelectorRadiusNominalDp:
        leafPressSelectorRadiusNominalDp ??
        this.leafPressSelectorRadiusNominalDp,
    sectionHeaderStyle: sectionHeaderStyle ?? this.sectionHeaderStyle,
    sectionHeaderStartInset:
        sectionHeaderStartInset ?? this.sectionHeaderStartInset,
  );

  @override
  bool operator ==(Object other) =>
      other is PanelCatalogThemeData &&
      other.circleColor == circleColor &&
      other.thumbColor == thumbColor &&
      other.washColor == washColor &&
      other.washHighlightColor == washHighlightColor &&
      other.washPeriod == washPeriod &&
      other.skeletonColor == skeletonColor &&
      other.placeholderCornerRadius == placeholderCornerRadius &&
      other.leafPressHighlightColor == leafPressHighlightColor &&
      other.leafFocusHighlightColor == leafFocusHighlightColor &&
      other.leafHoverHighlightColor == leafHoverHighlightColor &&
      other.leafHoverHighlightRadius == leafHoverHighlightRadius &&
      other.leafHoverHighlightInset == leafHoverHighlightInset &&
      other.leafHoverHighlightSize == leafHoverHighlightSize &&
      other.leafPressFeedback == leafPressFeedback &&
      other.leafPressSelectorRadiusNominalDp ==
          leafPressSelectorRadiusNominalDp &&
      other.sectionHeaderStyle == sectionHeaderStyle &&
      other.sectionHeaderStartInset == sectionHeaderStartInset;

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
    leafHoverHighlightColor,
    leafHoverHighlightRadius,
    leafHoverHighlightInset,
    leafHoverHighlightSize,
    leafPressFeedback,
    leafPressSelectorRadiusNominalDp,
    sectionHeaderStyle,
    sectionHeaderStartInset,
  );
}

/// What a press on a leaf draws.
enum CatalogPressFeedback {
  /// The press wash on the cell, and the leaf shrinking while held (a touch
  /// grid).
  inkAndScale,

  /// Nothing: the leaf is chosen on release, as a desktop list does.
  none,
}
