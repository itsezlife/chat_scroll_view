import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';

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
      sectionHeaderColor: Color(0xFF333333),
      documentStandInColor: Color(0xFF2196F3),
      leafPressSelectorRadiusNominalDp: 4,
      standInCornerRadius: 8,
    );
    final mid = PanelCatalogThemeData.lerp(a, b, 0.5);
    expect(mid.placeholderColor, Color.lerp(a.placeholderColor, b.placeholderColor, 0.5));
    expect(
      mid.leafPressHighlightColor,
      Color.lerp(a.leafPressHighlightColor, b.leafPressHighlightColor, 0.5),
    );
    expect(
      mid.sectionHeaderColor,
      Color.lerp(a.sectionHeaderColor, b.sectionHeaderColor, 0.5),
    );
    expect(
      mid.documentStandInColor,
      Color.lerp(a.documentStandInColor, b.documentStandInColor, 0.5),
    );
    expect(mid.leafPressSelectorRadiusNominalDp, 3);
    expect(mid.standInCornerRadius, 7);
    expect(PanelCatalogThemeData.lerp(a, b, 0), a);
    expect(PanelCatalogThemeData.lerp(a, b, 1), b);
  });

  testWidgets('of falls back to light when no ancestor is mounted', (
    tester,
  ) async {
    late PanelCatalogThemeData resolved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            resolved = PanelCatalogTheme.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(resolved, PanelCatalogThemeData.light);
  });

  testWidgets('of reads PanelCatalogTheme ancestor', (tester) async {
    const custom = PanelCatalogThemeData(
      placeholderColor: Color(0xFF112233),
      leafPressHighlightColor: Color(0xFF445566),
      sectionHeaderColor: Color(0xFF778899),
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
