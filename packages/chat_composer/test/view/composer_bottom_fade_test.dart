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
    const palette = ChromePalette.light();
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

  testWidgets('washes the whole zone, with no hole for the island above it', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ChromeThemeScope(
          palette: const ChromePalette.light(),
          child: const Align(
            alignment: Alignment.bottomCenter,
            child: ComposerBottomFade(zoneHeight: 120),
          ),
        ),
      ),
    );

    final paint = find.descendant(
      of: find.byType(ComposerBottomFade),
      matching: find.byType(CustomPaint),
    );
    // One rectangle of the gradient, drawn whole.
    expect(tester.renderObject(paint), paints..rect());
  });

  test('holds no state: nothing to keep in step with an island', () {
    expect(const ComposerBottomFade(zoneHeight: 48), isA<StatelessWidget>());
  });
}
