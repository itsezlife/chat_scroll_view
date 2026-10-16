import 'dart:ui' show Color;

import 'package:chrome_foundation/src/palette/chrome_palette.dart';
import 'package:meta/meta.dart';

/// Colours of the catalog panel: body, category strip and search field.
///
/// Derived from a [ChromePalette] by [PanelTokens.fromPalette]; a host
/// overrides single fields with [copyWith] or supplies the whole group to a
/// `ChromeThemeScope`.
@immutable
final class PanelTokens {
  /// A panel token group with every colour given.
  const PanelTokens({
    required this.background,
    required this.categoryIcon,
    required this.categoryIconSelected,
    required this.hairline,
    required this.tabSelector,
    required this.tabSelectorLine,
    required this.sectionTitle,
    required this.searchFill,
    required this.stripFill,
    required this.searchIcon,
    required this.searchText,
  });

  /// The default mapping of [palette] roles onto panel fields.
  factory PanelTokens.fromPalette(ChromePalette palette) => PanelTokens(
    background: palette.surfaceDim,
    categoryIcon: palette.iconIdle,
    categoryIconSelected: palette.iconActive,
    hairline: palette.separator,
    tabSelector: palette.surfaceTint,
    tabSelectorLine: palette.accent,
    sectionTitle: palette.onSurfaceMuted,
    searchFill: palette.onSurface.withAlpha(0x0F),
    stripFill: palette.onSurface.withAlpha(0x0A),
    searchIcon: palette.iconIdle,
    searchText: palette.onSurface,
  );

  /// Panel body fill.
  final Color background;

  /// Idle category-strip icon.
  final Color categoryIcon;

  /// Selected category-strip icon.
  final Color categoryIconSelected;

  /// Hairline under the category strip.
  final Color hairline;

  /// Selected category tab background.
  final Color tabSelector;

  /// Selected category tab underline.
  final Color tabSelectorLine;

  /// Catalog section header text.
  final Color sectionTitle;

  /// Search pill fill, translucent over [background].
  final Color searchFill;

  /// Fill of the category strip where a page pins it at the bottom, translucent
  /// over [background]: one step off the grid above it in either brightness
  /// (the strip is the one surface that is not the body, and [background] of
  /// the dark palette is the same as its composer's).
  final Color stripFill;

  /// Search and clear icons.
  final Color searchIcon;

  /// Search input text.
  final Color searchText;

  /// A copy with the named fields replaced.
  PanelTokens copyWith({
    Color? background,
    Color? categoryIcon,
    Color? categoryIconSelected,
    Color? hairline,
    Color? tabSelector,
    Color? tabSelectorLine,
    Color? sectionTitle,
    Color? searchFill,
    Color? stripFill,
    Color? searchIcon,
    Color? searchText,
  }) => PanelTokens(
    background: background ?? this.background,
    categoryIcon: categoryIcon ?? this.categoryIcon,
    categoryIconSelected: categoryIconSelected ?? this.categoryIconSelected,
    hairline: hairline ?? this.hairline,
    tabSelector: tabSelector ?? this.tabSelector,
    tabSelectorLine: tabSelectorLine ?? this.tabSelectorLine,
    sectionTitle: sectionTitle ?? this.sectionTitle,
    searchFill: searchFill ?? this.searchFill,
    stripFill: stripFill ?? this.stripFill,
    searchIcon: searchIcon ?? this.searchIcon,
    searchText: searchText ?? this.searchText,
  );

  /// Interpolates every field between [a] and [b].
  // Flutter's `T.lerp(a, b, t)` shape; a constructor cannot take two sources.
  // ignore: prefer_constructors_over_static_methods
  static PanelTokens lerp(PanelTokens a, PanelTokens b, double t) =>
      PanelTokens(
        background: Color.lerp(a.background, b.background, t)!,
        categoryIcon: Color.lerp(a.categoryIcon, b.categoryIcon, t)!,
        categoryIconSelected: Color.lerp(
          a.categoryIconSelected,
          b.categoryIconSelected,
          t,
        )!,
        hairline: Color.lerp(a.hairline, b.hairline, t)!,
        tabSelector: Color.lerp(a.tabSelector, b.tabSelector, t)!,
        tabSelectorLine: Color.lerp(a.tabSelectorLine, b.tabSelectorLine, t)!,
        sectionTitle: Color.lerp(a.sectionTitle, b.sectionTitle, t)!,
        searchFill: Color.lerp(a.searchFill, b.searchFill, t)!,
        stripFill: Color.lerp(a.stripFill, b.stripFill, t)!,
        searchIcon: Color.lerp(a.searchIcon, b.searchIcon, t)!,
        searchText: Color.lerp(a.searchText, b.searchText, t)!,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PanelTokens &&
          background == other.background &&
          categoryIcon == other.categoryIcon &&
          categoryIconSelected == other.categoryIconSelected &&
          hairline == other.hairline &&
          tabSelector == other.tabSelector &&
          tabSelectorLine == other.tabSelectorLine &&
          sectionTitle == other.sectionTitle &&
          searchFill == other.searchFill &&
          stripFill == other.stripFill &&
          searchIcon == other.searchIcon &&
          searchText == other.searchText;

  @override
  int get hashCode => Object.hash(
    background,
    categoryIcon,
    categoryIconSelected,
    hairline,
    tabSelector,
    tabSelectorLine,
    sectionTitle,
    searchFill,
    stripFill,
    searchIcon,
    searchText,
  );

  @override
  String toString() => 'PanelTokens(background: $background)';
}
