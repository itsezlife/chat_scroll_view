import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_shell/panel_shell.dart';

const _palette = ChromePalette.light();

void main() {
  group('the tokens it maps', () {
    final data = ChromeCatalogTheme.dataFor(
      ChromeThemeData.fromPalette(_palette),
    );

    test(
      'paints every stand-in and the skeleton in the placeholder skeleton',
      () {
        final skeleton = PlaceholderTokens.fromPalette(_palette).skeleton;

        expect(data.skeletonColor, skeleton);
        expect(data.circleColor, skeleton);
        expect(data.thumbColor, skeleton);
        expect(data.washColor, skeleton);
      },
    );

    test(
      'takes the wash highlight and the press highlight from the text colour',
      () {
        expect(data.washHighlightColor, _palette.onSurface.withAlpha(0x24));
        expect(
          data.leafPressHighlightColor,
          _palette.onSurface.withAlpha(0x0F),
        );
      },
    );

    test('has no hover under touch, and the text colour at 0x12 under the '
        'pointer arrangement', () {
      final chrome = ChromeThemeData.fromPalette(_palette);

      expect(data.leafHoverHighlightColor, isNull);
      expect(
        ChromeCatalogTheme.dataFor(
          chrome,
          arrangement: PanelArrangement.pointer,
        ).leafHoverHighlightColor,
        _palette.onSurface.withAlpha(0x12),
      );
    });

    test('under the pointer is the reference desktop client\'s ink: a 34 x 32 '
        'hover box, and nothing on a press', () {
      final pointer = ChromeCatalogTheme.dataFor(
        ChromeThemeData.fromPalette(_palette),
        arrangement: PanelArrangement.pointer,
      );

      expect(pointer.leafHoverHighlightSize, const Size(34, 32));
      expect(pointer.leafHoverHighlightRadius, 8);
      expect(pointer.leafPressFeedback, CatalogPressFeedback.none);
      expect(data.leafPressFeedback, CatalogPressFeedback.inkAndScale);
      expect(data.leafHoverHighlightSize, isNull);
    });

    test('draws keyboard focus in the accent', () {
      expect(data.leafFocusHighlightColor, _palette.accent.withAlpha(0x40));
    });

    test('colours the section title with the panel token and nothing else', () {
      final base = PanelCatalogThemeData.forBrightness(
        Brightness.light,
      ).sectionHeaderStyle;

      expect(data.sectionHeaderStyle.color, _palette.onSurfaceMuted);
      expect(
        data.sectionHeaderStyle,
        base.copyWith(color: _palette.onSurfaceMuted),
      );
    });

    test('leaves geometry and timing to the viewport', () {
      final base = PanelCatalogThemeData.forBrightness(Brightness.light);

      expect(data.washPeriod, base.washPeriod);
      expect(data.placeholderCornerRadius, base.placeholderCornerRadius);
      expect(data.sectionHeaderStartInset, base.sectionHeaderStartInset);
      expect(
        data.leafPressSelectorRadiusNominalDp,
        base.leafPressSelectorRadiusNominalDp,
      );
    });

    test('follows an override of a token group', () {
      const custom = PlaceholderTokens(
        emptyState: Color(0xFF111111),
        fieldHint: Color(0xFF222222),
        skeleton: Color(0xFF333333),
      );
      final mapped = ChromeCatalogTheme.dataFor(
        ChromeThemeData.fromPalette(_palette, placeholder: custom),
      );

      expect(mapped.skeletonColor, const Color(0xFF333333));
    });
  });

  group('the widget', () {
    Widget host(
      ChromePalette palette,
      void Function(PanelCatalogThemeData) read,
    ) => ChromeThemeScope(
      palette: palette,
      child: ChromeCatalogTheme(
        child: Builder(
          builder: (context) {
            read(PanelCatalogTheme.of(context));
            return const SizedBox();
          },
        ),
      ),
    );

    testWidgets('scopes the mapped theme for the viewport below', (
      tester,
    ) async {
      late PanelCatalogThemeData seen;
      await tester.pumpWidget(host(_palette, (data) => seen = data));

      expect(
        seen,
        ChromeCatalogTheme.dataFor(ChromeThemeData.fromPalette(_palette)),
      );
    });

    testWidgets('reads the arrangement the shell provides', (tester) async {
      late PanelCatalogThemeData seen;
      await tester.pumpWidget(
        PanelArrangementScope(
          arrangement: PanelArrangement.pointer,
          child: host(_palette, (data) => seen = data),
        ),
      );

      expect(seen.leafHoverHighlightColor, isNotNull);
    });

    testWidgets('follows the chrome theme when it switches', (tester) async {
      late PanelCatalogThemeData seen;
      await tester.pumpWidget(host(_palette, (data) => seen = data));
      const dark = ChromePalette.dark();

      await tester.pumpWidget(host(dark, (data) => seen = data));

      expect(seen.skeletonColor, PlaceholderTokens.fromPalette(dark).skeleton);
    });
  });
}
