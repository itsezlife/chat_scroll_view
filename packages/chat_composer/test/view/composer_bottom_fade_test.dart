import 'package:chat_composer/chat_composer.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ComposerBottomFade.gradient', () {
    const color = Color(0xFF15191E);
    final stops = ComposerBottomFade.opacityStops(color);

    test('ramps over the fade height, then holds the wash to the bottom', () {
      final gradient = ComposerBottomFade.gradient(
        zoneHeight: 96,
        color: color,
      );

      expect(gradient.begin, Alignment.topCenter);
      expect(gradient.end, Alignment.bottomCenter);
      expect(gradient.colors, [...stops, stops.last]);
      expect(gradient.stops, [0, 1 / 6, 1 / 3, 0.5, 1]);
    });

    test(
      'ends the ramp at the bottom when the zone equals the fade height',
      () {
        final gradient = ComposerBottomFade.gradient(
          zoneHeight: ComposerBottomFade.defaultFadeHeight,
          color: color,
        );

        expect(gradient.colors, stops);
        expect(gradient.stops, [0, 1 / 3, 2 / 3, 1]);
      },
    );

    test('squeezes the ramp into a zone shorter than the fade height', () {
      final gradient = ComposerBottomFade.gradient(
        zoneHeight: 24,
        color: color,
      );

      expect(gradient.colors, stops);
      expect(gradient.stops, [0, 1 / 3, 2 / 3, 1]);
    });

    test('honours a custom fade height', () {
      final gradient = ComposerBottomFade.gradient(
        zoneHeight: 100,
        color: color,
        fadeHeight: 25,
      );

      expect(gradient.stops, [0, 0.25 / 3, 0.5 / 3, 0.25, 1]);
    });
  });

  testWidgets('paints the theme content fade colour when none is given', (
    tester,
  ) async {
    final palette = ChromePalette.light();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ChromeThemeScope(
          palette: palette,
          child: const Align(
            alignment: Alignment.bottomCenter,
            child: ComposerBottomFade(zoneHeight: 48),
          ),
        ),
      ),
    );

    final painter =
        tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: find.byType(ComposerBottomFade),
                    matching: find.byType(CustomPaint),
                  ),
                )
                .painter!
            as dynamic;
    expect(
      painter.gradient,
      ComposerBottomFade.gradient(zoneHeight: 48, color: palette.contentFade),
    );
  });

  testWidgets(
    'clears island cutout when glass unmounts without zoneHeight change',
    (tester) async {
      final glassKey = GlobalKey();
      final islandVisible = ValueNotifier<bool>(true);
      addTearDown(islandVisible.dispose);

      await tester.pumpWidget(
        _FadeHarness(glassKey: glassKey, islandVisible: islandVisible),
      );
      await tester.pump();

      final state = tester.state<ComposerBottomFadeState>(
        find.byType(ComposerBottomFade),
      );
      expect(state.debugCutout, isNotNull);

      islandVisible.value = false;
      await tester.pump();
      await tester.pump();

      expect(state.debugCutout, isNull);
      expect(find.byType(ComposerBottomFade), findsOneWidget);
    },
  );

  testWidgets('restores island cutout when glass remounts via cutoutSync', (
    tester,
  ) async {
    final glassKey = GlobalKey();
    final islandVisible = ValueNotifier<bool>(true);
    addTearDown(islandVisible.dispose);

    await tester.pumpWidget(
      _FadeHarness(glassKey: glassKey, islandVisible: islandVisible),
    );
    await tester.pump();

    final state = tester.state<ComposerBottomFadeState>(
      find.byType(ComposerBottomFade),
    );
    expect(state.debugCutout, isNotNull);

    islandVisible.value = false;
    await tester.pump();
    await tester.pump();
    expect(state.debugCutout, isNull);

    islandVisible.value = true;
    await tester.pump();
    await tester.pump();
    expect(state.debugCutout, isNotNull);
  });
}

/// Fade is **outside** [ListenableBuilder] so it does not rebuild when the
/// island unmounts — only [ComposerBottomFade.cutoutSync] fires.
class _FadeHarness extends StatelessWidget {
  const _FadeHarness({required this.glassKey, required this.islandVisible});

  final GlobalKey glassKey;
  final ValueNotifier<bool> islandVisible;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Stack(
        children: <Widget>[
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 120,
            child: ComposerBottomFade(
              zoneHeight: 120,
              color: const Color(0xFF15191E),
              glassKey: glassKey,
              cutoutSync: islandVisible,
            ),
          ),
          ListenableBuilder(
            listenable: islandVisible,
            builder: (context, _) {
              if (!islandVisible.value) return const SizedBox.shrink();
              return Positioned(
                left: 24,
                right: 24,
                bottom: 16,
                height: 48,
                child: ColoredBox(key: glassKey, color: Colors.white),
              );
            },
          ),
        ],
      ),
    ),
  );
}
