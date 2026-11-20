import 'dart:async';

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/src/glass/shader/glass_shaders.dart';
import 'package:chrome_foundation/src/glass/strategy/glass_backdrops.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/missing_shaders.dart';

const _glassKey = ValueKey('glass');

Widget _surface({
  GlassMaterial material = GlassMaterial.island,
  ChromePalette palette = const ChromePalette.dark(),
  GlassQuality quality = GlassQuality.fullLiquid,
  bool lite = false,
  GlassCapabilities capabilities = GlassCapabilities.all,
  bool source = false,
  double opacity = 1,
}) {
  Widget glass = Center(
    child: SizedBox(
      width: 200,
      height: 44,
      child: GlassSurface(
        key: _glassKey,
        material: material,
        opacity: opacity,
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
  group('GlassSurface shader loading', () {
    testWidgets('reports a failure instead of swallowing it and keeps '
        'the glass frosted', (tester) async {
      failGlassShaders(StateError('shader asset missing'));
      await tester.pumpWidget(_surface(source: true));
      await tester.pump();

      final reported = tester.takeException();
      expect(reported, isStateError);
      expect(tester.takeException(), isNull, reason: 'reported once');
      expect(_samples(), isTrue, reason: 'the frosted sample needs no shader');
      expect(
        tester
            .widget<SampledGlassBackdrop>(
              _inGlass(find.byType(SampledGlassBackdrop)),
            )
            .style
            .enableLiquid,
        isFalse,
      );
    });

    testWidgets('a frosted surface never loads the shaders', (tester) async {
      var loads = 0;
      GlassShaders.loader = () {
        loads++;
        return Completer<GlassShaderPrograms>().future;
      };
      addTearDown(GlassShaders.debugReset);

      await tester.pumpWidget(
        _surface(quality: GlassQuality.frosted, source: true),
      );
      await tester.pumpWidget(_surface(quality: GlassQuality.frosted));

      expect(loads, 0);
    });
  });

  group('GlassSurface strategy', () {
    testGlassWidgets('is frosted without a quality scope', (tester) async {
      // No source, so the detected backend's scene filter draws it on any
      // test host.
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ChromeThemeScope(
            palette: const ChromePalette.dark(),
            child: const SizedBox(
              width: 200,
              height: 44,
              child: GlassSurface(
                key: _glassKey,
                material: GlassMaterial.island,
                child: SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      final style = tester
          .widget<FilterGlassBackdrop>(
            _inGlass(find.byType(FilterGlassBackdrop)),
          )
          .style;

      expect(style.enableLiquid, isFalse);
      expect(style.fill.a, closeTo(0.76, 1e-6));
    });

    testGlassWidgets('samples a source under full liquid', (tester) async {
      await tester.pumpWidget(_surface(source: true));

      expect(_samples(), isTrue);
      expect(_filters(), isFalse);
    });

    testGlassWidgets('filters the scene without a source', (tester) async {
      await tester.pumpWidget(_surface());

      expect(_filters(), isTrue);
      expect(_samples(), isFalse);
    });

    testGlassWidgets('paints flat when the host asks for flat quality', (
      tester,
    ) async {
      await tester.pumpWidget(
        _surface(quality: GlassQuality.flat, source: true),
      );

      expect(_filters(), isFalse);
      expect(_samples(), isFalse);
      expect(_flatFill(), isNotNull);
    });

    testGlassWidgets('paints flat in lite mode', (tester) async {
      await tester.pumpWidget(_surface(lite: true, source: true));

      expect(_samples(), isFalse);
      expect(_flatFill(), isNotNull);
    });

    testGlassWidgets('paints nothing but the child under off', (tester) async {
      await tester.pumpWidget(_surface(quality: GlassQuality.off));

      expect(_inGlass(find.byType(DecoratedBox)), findsNothing);
      expect(_inGlass(find.byType(ColoredBox)), findsNothing);
      expect(_filters(), isFalse);
    });

    testGlassWidgets('follows a change of policy', (tester) async {
      await tester.pumpWidget(_surface());
      expect(_filters(), isTrue);

      await tester.pumpWidget(_surface(quality: GlassQuality.flat));
      expect(_filters(), isFalse);
    });
  });

  group('GlassSurface colours', () {
    testGlassWidgets('a flat fill is the opaque theme tint of the material', (
      tester,
    ) async {
      for (final material in const [
        GlassMaterial.island,
        GlassMaterial.button,
        GlassMaterial.bar,
        GlassMaterial.menu,
        GlassMaterial.panel,
        GlassMaterial.bubble,
      ]) {
        await tester.pumpWidget(
          _surface(material: material, quality: GlassQuality.flat),
        );
        final expected = GlassMaterialTokens.fromPalette(
          const ChromePalette.dark(),
        ).colorsOf(material).tint;

        expect(_flatFill(), expected, reason: '$material');
        expect(_flatFill()!.a, 1, reason: '$material');
      }
    });

    testGlassWidgets('a nested scope restyles one material', (tester) async {
      const custom = GlassMaterialColors(
        tint: Color(0xFF123456),
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
              ).copyWith(button: custom),
              child: const GlassQualityScope(
                quality: GlassQuality.flat,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: GlassSurface(
                    key: _glassKey,
                    material: GlassMaterial.button,
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

    testGlassWidgets('fails without a chrome theme scope', (tester) async {
      await tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: GlassSurface(
            material: GlassMaterial.island,
            child: SizedBox(),
          ),
        ),
      );

      expect(tester.takeException(), isFlutterError);
    });
  });

  group('GlassSurface opacity', () {
    // The opacity layers between [layer] and the root that are not opaque.
    List<OpacityLayer> fadingAbove(Layer layer) => [
      for (Layer? l = layer.parent; l != null; l = l.parent)
        if (l is OpacityLayer && (l.alpha ?? 255) < 255) l,
    ];

    testGlassWidgets('a scene filter fades without an opacity layer over it, '
        'so it reads the scene from its first frame', (tester) async {
      await tester.pumpWidget(_surface(quality: GlassQuality.frosted));
      await tester.pumpWidget(
        _surface(quality: GlassQuality.frosted, opacity: 0.5),
      );

      final filters = tester.layers.whereType<BackdropFilterLayer>().toList();
      expect(filters, hasLength(1));
      expect(fadingAbove(filters.single), isEmpty);
      final backdrop = tester.widget<FilterGlassBackdrop>(
        _inGlass(find.byType(FilterGlassBackdrop)),
      );
      expect(backdrop.opacity, 0.5);
      final tint = tester
          .widget<ColoredBox>(
            find.descendant(
              of: find.byType(BackdropFilter),
              matching: find.byType(ColoredBox),
            ),
          )
          .color;
      expect(tint.a, closeTo(0.76 * 0.5, 1e-6));
    });

    testGlassWidgets('the child and the edges fade with the glass', (
      tester,
    ) async {
      await tester.pumpWidget(
        _surface(quality: GlassQuality.frosted, opacity: 0.25),
      );

      final fades = tester
          .widgetList<Opacity>(_inGlass(find.byType(Opacity)))
          .map((o) => o.opacity);
      expect(fades, contains(0.25));
    });

    testGlassWidgets('a hidden glass reads no backdrop', (tester) async {
      await tester.pumpWidget(
        _surface(quality: GlassQuality.frosted, opacity: 0),
      );

      expect(
        tester.widget<BackdropFilter>(_inGlass(find.byType(BackdropFilter))),
        isA<BackdropFilter>().having((f) => f.enabled, 'enabled', isFalse),
      );
    });

    testGlassWidgets('a sampled glass fades its capture', (tester) async {
      await tester.pumpWidget(
        _surface(quality: GlassQuality.frosted, source: true, opacity: 0.5),
      );

      expect(
        find.ancestor(
          of: find.byType(SampledGlassBackdrop),
          matching: find.byWidgetPredicate(
            (w) => w is Opacity && w.opacity == 0.5,
          ),
        ),
        findsOneWidget,
      );
    });

    testGlassWidgets('a flat glass fades its fill', (tester) async {
      await tester.pumpWidget(
        _surface(quality: GlassQuality.flat, opacity: 0.5),
      );

      expect(_flatFill()!.a, closeTo(0.5, 1e-6));
    });
  });

  group('GlassMaterial', () {
    test('each named material maps to its own token colours', () {
      final tokens = GlassMaterialTokens.fromPalette(
        const ChromePalette.dark(),
      );

      expect(tokens.colorsOf(GlassMaterial.island), tokens.island);
      expect(tokens.colorsOf(GlassMaterial.button), tokens.button);
      expect(tokens.colorsOf(GlassMaterial.bar), tokens.bar);
    });
  });
}
