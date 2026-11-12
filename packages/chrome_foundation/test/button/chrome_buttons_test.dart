/// The chrome's buttons and their glyphs: the press colours they derive from
/// the palette, their geometry from their metrics, and what they take.
///
/// **Seam:** each widget under a `ChromeThemeScope` of the light palette,
/// observed through its render boxes, its semantics and the taps it reports.
library;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _palette = ChromePalette.light();

Widget _scoped(Widget child, {ChromeMotionSpeed? speed}) => Directionality(
  textDirection: TextDirection.ltr,
  child: ChromeThemeScope(
    palette: _palette,
    child: ChromeMotionScope(
      speed: speed ?? ChromeMotionSpeed.normal,
      child: Align(alignment: Alignment.topLeft, child: child),
    ),
  ),
);

void main() {
  test('the inks wash in the text colour, or the colour on the accent', () {
    expect(
      ChromeButtonInks.pressOf(_palette),
      _palette.onSurface.withAlpha(0x0F),
    );
    expect(
      ChromeButtonInks.hoverOf(_palette),
      _palette.onSurface.withAlpha(0x12),
    );
    expect(
      ChromeButtonInks.pressOnAccentOf(_palette),
      _palette.onAccent.withAlpha(0x24),
    );
    expect(
      ChromeButtonInks.hoverOnAccentOf(_palette),
      _palette.onAccent.withAlpha(0x12),
    );
  });

  group('the icon button', () {
    testWidgets('is a 40 square button named by its label, in a circle of '
        'ink', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _scoped(
          ChromeIconButton(
            label: 'Close',
            painter: const ChromeCrossPainter(Color(0xFF000000)),
            onPressed: () => taps++,
          ),
        ),
      );

      expect(tester.getSize(find.byType(ChromeIconButton)), const Size(40, 40));
      expect(tester.widget<ChromeInk>(find.byType(ChromeInk)).circleRadius, 20);
      expect(find.bySemanticsLabel('Close'), findsOneWidget);
      await tester.tap(find.byType(ChromeIconButton));
      expect(taps, 1);
    });
  });

  group('the pill button', () {
    testWidgets('is 28 tall, its padding at either side, filled when given a '
        'fill', (tester) async {
      await tester.pumpWidget(
        _scoped(
          // In a row, as beside a title: its width is its content's.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ChromePillButton(
                onPressed: () {},
                padding: 18,
                fill: _palette.accent,
                child: const SizedBox(width: 50, height: 10),
              ),
            ],
          ),
        ),
      );

      expect(
        tester.getSize(find.byType(ChromePillButton)),
        const Size(50 + 2 * 18, 28),
      );
      final ink = tester.widget<ChromeInk>(find.byType(ChromeInk));
      expect(ink.color, ChromeButtonInks.pressOnAccentOf(_palette));
    });

    testWidgets('a plain pill presses in the text colour', (tester) async {
      await tester.pumpWidget(
        _scoped(
          ChromePillButton(
            onPressed: () {},
            padding: 12,
            child: const SizedBox(width: 50, height: 10),
          ),
        ),
      );

      final ink = tester.widget<ChromeInk>(find.byType(ChromeInk));
      expect(ink.color, ChromeButtonInks.pressOf(_palette));
    });

    testWidgets('one that is not enabled takes no press', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _scoped(
          ChromePillButton(
            enabled: false,
            onPressed: () => taps++,
            padding: 12,
            child: const SizedBox(width: 50, height: 10),
          ),
        ),
      );

      await tester.tap(find.byType(ChromePillButton), warnIfMissed: false);
      expect(taps, 0);
    });
  });

  group('the bar button', () {
    test('takes its extent and a margin above and below when filled', () {
      const metrics = ChromeBarButtonMetrics.standard;
      expect(metrics.barExtentOf(destructive: false), 48 + 2 * 8);
      expect(metrics.barExtentOf(destructive: true), 48);
    });

    testWidgets('an addition is a filled pill inset by its margin', (
      tester,
    ) async {
      await tester.pumpWidget(
        _scoped(
          SizedBox(
            width: 300,
            child: ChromeBarButton(label: 'Add', onPressed: () {}),
          ),
        ),
      );

      expect(tester.getSize(find.byType(ChromeBarButton)), const Size(300, 64));
      expect(tester.getSize(find.byType(ChromeInk)), const Size(284, 48));
      final text = tester.widget<Text>(find.text('Add'));
      expect(text.style?.color, _palette.onAccent);
      expect(text.style?.fontSize, 14);
    });

    testWidgets('a destructive one is a flat bar the full width', (
      tester,
    ) async {
      await tester.pumpWidget(
        _scoped(
          SizedBox(
            width: 300,
            child: ChromeBarButton(
              label: 'Remove',
              destructive: true,
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(tester.getSize(find.byType(ChromeBarButton)), const Size(300, 48));
      final text = tester.widget<Text>(find.text('Remove'));
      expect(text.style?.color, _palette.destructive);
    });
  });

  group('the badge button', () {
    test('takes its extent and its padding above and below', () {
      expect(ChromeBadgeButtonMetrics.standard.barExtent, 42 + 12 + 12);
    });

    testWidgets('shows a positive count in a badge after its words and says '
        'both', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _scoped(
          SizedBox(
            width: 300,
            child: ChromeBadgeButton(
              label: 'Add stickers',
              count: 20,
              onPressed: () => taps++,
            ),
          ),
        ),
      );

      expect(find.byKey(ChromeBadgeButton.countKey), findsOneWidget);
      expect(tester.getSize(find.byKey(ChromeBadgeButton.countKey)).height, 18);
      expect(find.bySemanticsLabel('Add stickers 20'), findsOneWidget);
      expect(tester.getSize(find.byType(ChromeInk)).height, 42);
      await tester.tap(find.byType(ChromeInk));
      expect(taps, 1);
    });

    testWidgets('shows no badge for no count or none', (tester) async {
      for (final count in [null, 0]) {
        await tester.pumpWidget(
          _scoped(
            SizedBox(
              width: 300,
              child: ChromeBadgeButton(
                label: 'Remove',
                count: count,
                destructive: true,
                onPressed: () {},
              ),
            ),
          ),
        );
        expect(find.byKey(ChromeBadgeButton.countKey), findsNothing);
      }
    });
  });

  group('the spinner', () {
    testWidgets('is a 40 square that turns', (tester) async {
      await tester.pumpWidget(_scoped(const ChromeSpinner()));

      expect(tester.getSize(find.byType(ChromeSpinner)), const Size(40, 40));
      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets('stands still under an instant speed', (tester) async {
      await tester.pumpWidget(
        _scoped(const ChromeSpinner(), speed: ChromeMotionSpeed.instant),
      );

      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('the glyphs', () {
    test('repaint when a value changes', () {
      const cross = ChromeCrossPainter(Color(0xFF000000));
      expect(
        cross.shouldRepaint(const ChromeCrossPainter(Color(0xFF000000))),
        isFalse,
      );
      expect(
        cross.shouldRepaint(
          const ChromeCrossPainter(Color(0xFF000000), extent: 14),
        ),
        isTrue,
      );
      const dots = ChromeDotsPainter(Color(0xFF000000));
      expect(
        dots.shouldRepaint(const ChromeDotsPainter(Color(0xFF000000))),
        isFalse,
      );
      expect(
        dots.shouldRepaint(const ChromeDotsPainter(Color(0xFFFFFFFF))),
        isTrue,
      );
    });
  });
}
