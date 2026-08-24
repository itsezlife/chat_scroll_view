import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/src/viewport/catalog_leaf_paint_theme.dart';

void main() {
  test('selectorRadiusLogicalPx scales nominal dp by device pixel ratio', () {
    const theme = PanelCatalogThemeData.light;
    expect(theme.selectorRadiusLogicalPx(1), 2);
    expect(theme.selectorRadiusLogicalPx(2), 4);
    expect(theme.selectorRadiusLogicalPx(3), 6);
  });

  test('lerp interpolates colors and radius between theme data', () {
    const a = PanelCatalogThemeData.light;
    const b = PanelCatalogThemeData(
      placeholderColor: Color(0x20000000),
      leafPressHighlightColor: Color(0x1E000000),
      sectionHeaderStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Color(0xFF333333),
      ),
      documentStandInColor: Color(0xFF2196F3),
      leafPressSelectorRadiusNominalDp: 4,
      standInCornerRadius: 8,
      sectionHeaderStartInset: 12,
    );
    final mid = PanelCatalogThemeData.lerp(a, b, 0.5);
    expect(mid.placeholderColor, Color.lerp(a.placeholderColor, b.placeholderColor, 0.5));
    expect(
      mid.leafPressHighlightColor,
      Color.lerp(a.leafPressHighlightColor, b.leafPressHighlightColor, 0.5),
    );
    expect(
      mid.sectionHeaderStyle,
      TextStyle.lerp(a.sectionHeaderStyle, b.sectionHeaderStyle, 0.5),
    );
    expect(
      mid.documentStandInColor,
      Color.lerp(a.documentStandInColor, b.documentStandInColor, 0.5),
    );
    expect(mid.leafPressSelectorRadiusNominalDp, 3);
    expect(mid.standInCornerRadius, 7);
    expect(mid.sectionHeaderStyle.fontSize, 16.5);
    expect(mid.sectionHeaderStartInset, 10);
    expect(PanelCatalogThemeData.lerp(a, b, 0), a);
    expect(PanelCatalogThemeData.lerp(a, b, 1), b);
  });

  test('resolve applies selector radius from device pixel ratio', () {
    const data = PanelCatalogThemeData.light;
    final resolved = CatalogLeafPaintTheme.resolve(data, devicePixelRatio: 3);
    expect(resolved.leafPressSelectorRadius, 6);
    expect(resolved.placeholderColor, data.placeholderColor);
    expect(resolved.sectionHeaderStyle, data.sectionHeaderStyle);
    expect(resolved.sectionHeaderStartInset, data.sectionHeaderStartInset);
    expect(resolved.standInCornerRadius, data.standInCornerRadius);
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
    const initial = PanelCatalogThemeData(
      placeholderColor: Color(0xFF111111),
      leafPressHighlightColor: Color(0xFF222222),
      sectionHeaderStyle: TextStyle(color: Color(0xFF333333)),
      documentStandInColor: Color(0xFF444444),
    );
    const updated = PanelCatalogThemeData(
      placeholderColor: Color(0xFFAAAAAA),
      leafPressHighlightColor: Color(0xFFBBBBBB),
      sectionHeaderStyle: TextStyle(color: Color(0xFFCCCCCC)),
      documentStandInColor: Color(0xFFDDDDDD),
    );
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
    const custom = PanelCatalogThemeData(
      placeholderColor: Color(0xFF112233),
      leafPressHighlightColor: Color(0xFF445566),
      sectionHeaderStyle: TextStyle(color: Color(0xFF778899)),
      documentStandInColor: Color(0xFFAABBCC),
      leafPressSelectorRadiusNominalDp: 3,
    );
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
