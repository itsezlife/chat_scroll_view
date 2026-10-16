import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:morphnext/morphnext.dart';

Widget _host(Widget child, {ChromeMotionSpeed? speed}) => Directionality(
  textDirection: TextDirection.ltr,
  child: ChromeMotionScope(
    speed: speed,
    child: Center(child: child),
  ),
);

void main() {
  group('ChromeIcon', () {
    testWidgets('draws the stock glyph for an id', (tester) async {
      await tester.pumpWidget(
        _host(
          const ChromeIcon(
            ChromeIconId.send,
            size: 20,
            color: Color(0xFF123456),
          ),
        ),
      );
      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon, Icons.send_rounded);
      expect(icon.size, 20);
      expect(icon.color, const Color(0xFF123456));
    });

    testWidgets('an unknown id draws the fallback glyph', (tester) async {
      await tester.pumpWidget(_host(const ChromeIcon(ChromeIconId('missing'))));
      expect(
        tester.widget<Icon>(find.byType(Icon)).icon,
        Icons.circle_outlined,
      );
    });

    testWidgets('a scope registration supplies a custom painter', (
      tester,
    ) async {
      Color? paintedWith;
      Size? paintedSize;
      await tester.pumpWidget(
        _host(
          ChromeIconScope(
            icons: {
              const ChromeIconId('host-dot'): ChromeIconPainter.paint((
                canvas,
                size,
                color,
              ) {
                paintedWith = color;
                paintedSize = size;
              }),
            },
            child: const ChromeIcon(
              ChromeIconId('host-dot'),
              size: 30,
              color: Color(0xFF00FF00),
            ),
          ),
        ),
      );
      expect(paintedWith, const Color(0xFF00FF00));
      expect(paintedSize, const Size(30, 30));
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('an inner scope adds to the outer one', (tester) async {
      await tester.pumpWidget(
        _host(
          const ChromeIconScope(
            icons: {ChromeIconId('outer'): ChromeIconPainter.font(Icons.star)},
            child: ChromeIconScope(
              icons: {ChromeIconId('inner'): ChromeIconPainter.font(Icons.add)},
              child: Column(
                children: [
                  ChromeIcon(ChromeIconId('outer')),
                  ChromeIcon(ChromeIconId('inner')),
                ],
              ),
            ),
          ),
        ),
      );
      final glyphs = tester
          .widgetList<Icon>(find.byType(Icon))
          .map((i) => i.icon);
      expect(glyphs, [Icons.star, Icons.add]);
    });

    testWidgets('without a scope the stock registry applies', (tester) async {
      late ChromeIconRegistry seen;
      await tester.pumpWidget(
        Builder(
          builder: (c) {
            seen = ChromeIconScope.of(c);
            return const SizedBox();
          },
        ),
      );
      expect(seen, ChromeIconRegistry.stock);
    });

    testWidgets('exposes a semantic label only when given', (tester) async {
      await tester.pumpWidget(
        _host(const ChromeIcon(ChromeIconId.send, semanticLabel: 'Send')),
      );
      expect(find.bySemanticsLabel('Send'), findsOneWidget);
      await tester.pumpWidget(_host(const ChromeIcon(ChromeIconId.send)));
      expect(find.bySemanticsLabel('Send'), findsNothing);
    });
  });

  group('AnimatedChromeIcon', () {
    testWidgets('morphs between two font ids without remounting', (
      tester,
    ) async {
      Widget app(ChromeIconId id) => _host(AnimatedChromeIcon(id, size: 24));
      await tester.pumpWidget(app(ChromeIconId.emoji));
      final firstState = tester.state(find.byType(AnimatedMorphIcon));
      expect(
        tester.widget<AnimatedMorphIcon>(find.byType(AnimatedMorphIcon)).icon,
        Icons.emoji_emotions_outlined,
      );

      await tester.pumpWidget(app(ChromeIconId.keyboard));
      await tester.pump(const Duration(milliseconds: 50));

      expect(
        tester.widget<AnimatedMorphIcon>(find.byType(AnimatedMorphIcon)).icon,
        Icons.keyboard_alt_outlined,
      );
      expect(
        tester.state(find.byType(AnimatedMorphIcon)),
        same(firstState),
        reason: 'the same state morphs; a remount would pop',
      );
      await tester.pumpAndSettle();
    });

    testWidgets('instant speed swaps the glyph without a morph widget', (
      tester,
    ) async {
      Widget app(ChromeIconId id) =>
          _host(AnimatedChromeIcon(id), speed: ChromeMotionSpeed.instant);
      await tester.pumpWidget(app(ChromeIconId.emoji));
      await tester.pumpWidget(app(ChromeIconId.keyboard));
      expect(find.byType(AnimatedMorphIcon), findsNothing);
      expect(
        tester.widget<Icon>(find.byType(Icon)).icon,
        Icons.keyboard_alt_outlined,
      );
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('a custom painter on either side cross-fades', (tester) async {
      var paints = 0;
      Widget app(ChromeIconId id) => _host(
        ChromeIconScope(
          icons: {
            const ChromeIconId('host-dot'): ChromeIconPainter.paint((_, _, _) {
              paints++;
            }),
          },
          child: AnimatedChromeIcon(id),
        ),
      );
      await tester.pumpWidget(app(ChromeIconId.emoji));
      await tester.pumpWidget(app(const ChromeIconId('host-dot')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(FadeTransition), findsWidgets);
      expect(
        find.byType(AnimatedMorphIcon),
        findsOneWidget,
        reason: 'the outgoing font glyph is still fading out',
      );
      await tester.pumpAndSettle();
      expect(find.byType(AnimatedMorphIcon), findsNothing);
      expect(paints, greaterThan(0));
    });

    testWidgets('the fade follows the fade motion role', (tester) async {
      Widget app(ChromeIconId id) => _host(
        ChromeIconScope(
          icons: {
            const ChromeIconId('host-dot'): ChromeIconPainter.paint(
              (_, _, _) {},
            ),
          },
          child: AnimatedChromeIcon(id),
        ),
      );
      await tester.pumpWidget(app(ChromeIconId.emoji));
      await tester.pumpWidget(app(const ChromeIconId('host-dot')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 199));
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pump(const Duration(milliseconds: 2));
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
