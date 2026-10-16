import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/src/viewport/catalog_leaf_paint_theme.dart';

/// A token set whose every colour is [color] and whose header is [headerColor].
PanelCatalogThemeData _flat(Color color, {Color? headerColor}) =>
    PanelCatalogThemeData(
      circleColor: color,
      thumbColor: color,
      washColor: color,
      washHighlightColor: color,
      skeletonColor: color,
      leafPressHighlightColor: color,
      sectionHeaderStyle: TextStyle(color: headerColor ?? color),
    );

void main() {
  test('selectorRadiusLogicalPx scales nominal dp by device pixel ratio', () {
    const theme = PanelCatalogThemeData.light;
    expect(theme.selectorRadiusLogicalPx(1), 2);
    expect(theme.selectorRadiusLogicalPx(2), 4);
    expect(theme.selectorRadiusLogicalPx(3), 6);
  });

  test('the presets carry a token for every placeholder style', () {
    for (final theme in [
      PanelCatalogThemeData.light,
      PanelCatalogThemeData.dark,
    ]) {
      expect(theme.circleColor.a, greaterThan(0));
      expect(theme.thumbColor.a, greaterThan(0));
      expect(theme.washColor.a, greaterThan(0));
      expect(theme.washHighlightColor.a, greaterThan(theme.washColor.a));
      expect(theme.skeletonColor.a, greaterThan(0));
      expect(theme.washPeriod, const Duration(milliseconds: 1800));
    }
    // Dark tints are light on dark, not the light preset's black on white.
    expect(PanelCatalogThemeData.dark.circleColor.r, 1);
    expect(PanelCatalogThemeData.light.circleColor.r, 0);
    expect(
      PanelCatalogThemeData.forBrightness(Brightness.dark),
      PanelCatalogThemeData.dark,
    );
  });

  test('lerp interpolates colors, radii and the wash period', () {
    const a = PanelCatalogThemeData.light;
    const b = PanelCatalogThemeData(
      circleColor: Color(0x20000000),
      thumbColor: Color(0x30000000),
      washColor: Color(0x40000000),
      washHighlightColor: Color(0x50000000),
      skeletonColor: Color(0x60000000),
      leafPressHighlightColor: Color(0x1E000000),
      sectionHeaderStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Color(0xFF333333),
      ),
      washPeriod: Duration(milliseconds: 1000),
      placeholderCornerRadius: 8,
      leafPressSelectorRadiusNominalDp: 4,
      sectionHeaderStartInset: 12,
    );
    final mid = PanelCatalogThemeData.lerp(a, b, 0.5);
    expect(mid.circleColor, Color.lerp(a.circleColor, b.circleColor, 0.5));
    expect(mid.thumbColor, Color.lerp(a.thumbColor, b.thumbColor, 0.5));
    expect(mid.washColor, Color.lerp(a.washColor, b.washColor, 0.5));
    expect(
      mid.washHighlightColor,
      Color.lerp(a.washHighlightColor, b.washHighlightColor, 0.5),
    );
    expect(
      mid.skeletonColor,
      Color.lerp(a.skeletonColor, b.skeletonColor, 0.5),
    );
    expect(
      mid.leafPressHighlightColor,
      Color.lerp(a.leafPressHighlightColor, b.leafPressHighlightColor, 0.5),
    );
    expect(
      mid.sectionHeaderStyle,
      TextStyle.lerp(a.sectionHeaderStyle, b.sectionHeaderStyle, 0.5),
    );
    expect(mid.washPeriod, const Duration(milliseconds: 1400));
    expect(mid.placeholderCornerRadius, 7);
    expect(mid.leafPressSelectorRadiusNominalDp, 3);
    expect(mid.sectionHeaderStyle.fontSize, 16.5);
    expect(mid.sectionHeaderStartInset, 10);
    expect(PanelCatalogThemeData.lerp(a, b, 0), a);
    expect(PanelCatalogThemeData.lerp(a, b, 1), b);
  });

  test('copyWith replaces only the named tokens', () {
    const base = PanelCatalogThemeData.light;
    final changed = base.copyWith(
      washColor: const Color(0xFF123456),
      washPeriod: const Duration(seconds: 2),
    );
    expect(changed.washColor, const Color(0xFF123456));
    expect(changed.washPeriod, const Duration(seconds: 2));
    expect(changed.circleColor, base.circleColor);
    expect(changed.sectionHeaderStyle, base.sectionHeaderStyle);
    expect(base.copyWith(), base);
  });

  test('resolve applies selector radius from device pixel ratio', () {
    const data = PanelCatalogThemeData.light;
    final resolved = CatalogLeafPaintTheme.resolve(data, devicePixelRatio: 3);
    expect(resolved.leafPressSelectorRadius, 6);
    expect(resolved.circleColor, data.circleColor);
    expect(resolved.thumbColor, data.thumbColor);
    expect(resolved.washColor, data.washColor);
    expect(resolved.washHighlightColor, data.washHighlightColor);
    expect(resolved.washPeriod, data.washPeriod);
    expect(resolved.skeletonColor, data.skeletonColor);
    expect(resolved.placeholderCornerRadius, data.placeholderCornerRadius);
    expect(resolved.sectionHeaderStyle, data.sectionHeaderStyle);
    expect(resolved.sectionHeaderStartInset, data.sectionHeaderStartInset);
  });

  testWidgets('maybeOf returns null when no ancestor is mounted', (
    tester,
  ) async {
    late PanelCatalogThemeData? resolved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            resolved = PanelCatalogTheme.maybeOf(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(resolved, isNull);
  });

  testWidgets('of throws when no ancestor is mounted', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            expect(
              () => PanelCatalogTheme.of(context),
              throwsA(isA<ArgumentError>()),
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
  });

  testWidgets('of with listen rebuilds when ancestor data changes', (
    tester,
  ) async {
    final initial = _flat(const Color(0xFF111111));
    final updated = _flat(const Color(0xFFAAAAAA));
    var buildCount = 0;
    late PanelCatalogThemeData resolved;

    await tester.pumpWidget(
      MaterialApp(
        home: PanelCatalogTheme(
          data: initial,
          child: Builder(
            builder: (context) {
              buildCount++;
              resolved = PanelCatalogTheme.of(context, listen: true);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(resolved, initial);
    expect(buildCount, 1);

    await tester.pumpWidget(
      MaterialApp(
        home: PanelCatalogTheme(
          data: updated,
          child: Builder(
            builder: (context) {
              buildCount++;
              resolved = PanelCatalogTheme.of(context, listen: true);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(resolved, updated);
    expect(buildCount, 2);
  });

  testWidgets('of reads PanelCatalogTheme ancestor', (tester) async {
    final custom = _flat(
      const Color(0xFF112233),
    ).copyWith(leafPressSelectorRadiusNominalDp: 3);
    late PanelCatalogThemeData resolved;
    await tester.pumpWidget(
      MaterialApp(
        home: PanelCatalogTheme(
          data: custom,
          child: Builder(
            builder: (context) {
              resolved = PanelCatalogTheme.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    expect(resolved, custom);
    expect(resolved.selectorRadiusLogicalPx(2), 6);
  });
}
