import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/src/glass/strategy/glass_backdrops.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _glassKey = ValueKey('glass');

Widget _surface({
  GlassMaterial material = GlassMaterial.composerIsland,
  ChromePalette palette = const ChromePalette.dark(),
  GlassQuality quality = GlassQuality.fullLiquid,
  bool lite = false,
  GlassCapabilities capabilities = GlassCapabilities.all,
  bool source = false,
}) {
  Widget glass = Center(
    child: SizedBox(
      width: 200,
      height: 44,
      child: GlassSurface(
        key: _glassKey,
        material: material,
        child: const SizedBox.expand(),
      ),
    ),
  );
  if (source) {
    glass = GlassSourceScope(
      child: Stack(
        children: [
          const Positioned.fill(
            child: GlassSource(child: ColoredBox(color: Color(0xFF3366FF))),
          ),
          glass,
        ],
      ),
    );
  }
  return Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: const MediaQueryData(),
      child: ChromeThemeScope(
        palette: palette,
        child: GlassQualityScope(
          quality: quality,
          liteMode: lite,
          capabilities: capabilities,
          child: glass,
        ),
      ),
    ),
  );
}

Finder _inGlass(Finder matching) =>
    find.descendant(of: find.byKey(_glassKey), matching: matching);

bool _filters() => _inGlass(find.byType(BackdropFilter)).evaluate().isNotEmpty;

bool _samples() =>
    _inGlass(find.byType(SampledGlassBackdrop)).evaluate().isNotEmpty;

Color? _flatFill() {
  final boxes = _inGlass(find.byType(ColoredBox)).evaluate();
  return boxes.isEmpty ? null : (boxes.first.widget as ColoredBox).color;
}

void main() {
  group('GlassSurface strategy', () {
    testWidgets('samples a source under full liquid', (tester) async {
      await tester.pumpWidget(_surface(source: true));

      expect(_samples(), isTrue);
      expect(_filters(), isFalse);
    });

    testWidgets('filters the scene without a source', (tester) async {
      await tester.pumpWidget(_surface());

      expect(_filters(), isTrue);
      expect(_samples(), isFalse);
    });

    testWidgets('paints flat when the host asks for flat quality', (
      tester,
    ) async {
      await tester.pumpWidget(
        _surface(quality: GlassQuality.flat, source: true),
      );

      expect(_filters(), isFalse);
      expect(_samples(), isFalse);
      expect(_flatFill(), isNotNull);
    });

    testWidgets('paints flat in lite mode', (tester) async {
      await tester.pumpWidget(_surface(lite: true, source: true));

      expect(_samples(), isFalse);
      expect(_flatFill(), isNotNull);
    });

    testWidgets('paints nothing but the child under off', (tester) async {
      await tester.pumpWidget(_surface(quality: GlassQuality.off));

      expect(_inGlass(find.byType(DecoratedBox)), findsNothing);
      expect(_inGlass(find.byType(ColoredBox)), findsNothing);
      expect(_filters(), isFalse);
    });

    testWidgets('follows a change of policy', (tester) async {
      await tester.pumpWidget(_surface());
      expect(_filters(), isTrue);

      await tester.pumpWidget(_surface(quality: GlassQuality.flat));
      expect(_filters(), isFalse);
    });
  });

  group('GlassSurface colours', () {
    testWidgets('flat fill is the theme colour of the material', (
      tester,
    ) async {
      for (final material in GlassMaterial.values) {
        await tester.pumpWidget(
          _surface(material: material, quality: GlassQuality.flat),
        );
        final expected = GlassMaterialTokens.fromPalette(
          const ChromePalette.dark(),
        ).colorsOf(material).fill;

        expect(_flatFill(), expected, reason: '$material');
      }
    });

    testWidgets('a nested scope restyles one material', (tester) async {
      const custom = GlassMaterialColors(
        fill: Color(0xFF123456),
        strokeTop: Color(0x00000000),
        strokeBottom: Color(0x00000000),
        shadow: Color(0x00000000),
      );
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ChromeThemeScope(
            palette: const ChromePalette.dark(),
            child: ChromeThemeScope(
              glass: GlassMaterialTokens.fromPalette(
                const ChromePalette.dark(),
              ).copyWith(panelButton: custom),
              child: const GlassQualityScope(
                quality: GlassQuality.flat,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: GlassSurface(
                    key: _glassKey,
                    material: GlassMaterial.panelButton,
                    child: SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      expect(_flatFill(), const Color(0xFF123456));
    });

    testWidgets('fails without a chrome theme scope', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: GlassSurface(
            material: GlassMaterial.composerIsland,
            child: SizedBox(),
          ),
        ),
      );

      expect(tester.takeException(), isFlutterError);
    });
  });

  group('GlassMaterial', () {
    test('each named material maps to its own token colours', () {
      final tokens = GlassMaterialTokens.fromPalette(
        const ChromePalette.dark(),
      );

      expect(
        tokens.colorsOf(GlassMaterial.composerIsland),
        tokens.composerIsland,
      );
      expect(tokens.colorsOf(GlassMaterial.panelButton), tokens.panelButton);
      expect(tokens.colorsOf(GlassMaterial.topPanel), tokens.topPanel);
    });
  });
}
