import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => Directionality(
  textDirection: TextDirection.ltr,
  child: MediaQuery(
    data: const MediaQueryData(),
    child: ChromeThemeScope(
      palette: const ChromePalette.light(),
      child: Center(child: child),
    ),
  ),
);

void main() {
  testWidgets('draws the text in the tooltip colours and the chrome face', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const ChromeTooltip(text: 'Sticker')));
    final context = tester.element(find.byType(ChromeTooltip));
    final panel = ChromeThemeScope.panelOf(context);
    final text = tester.widget<Text>(find.text('Sticker'));
    expect(text.style?.color, panel.tooltipText);
    expect(text.style?.fontSize, 13);
    final box = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(ChromeTooltip),
        matching: find.byType(DecoratedBox),
      ),
    );
    expect((box.decoration as BoxDecoration).color, panel.tooltipFill);
    expectChromeText(tester);
  });

  testWidgets('the hint is centred, wider padded and a live region', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        const ChromeTooltip(
          text: 'Not allowed here',
          metrics: ChromeTooltipMetrics.hint,
          liveRegion: true,
        ),
      ),
    );
    final text = tester.widget<Text>(find.text('Not allowed here'));
    expect(text.textAlign, TextAlign.center);
    expect(text.style?.fontSize, 14);
    expect(
      tester.getSemantics(find.text('Not allowed here')),
      isSemantics(label: 'Not allowed here', isLiveRegion: true),
    );
    semantics.dispose();
  });

  testWidgets('a long pointer tooltip stops at its widest and its lines', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(ChromeTooltip(text: List.filled(400, 'word').join(' '))),
    );
    expect(
      tester.getSize(find.byType(ChromeTooltip)).width,
      lessThanOrEqualTo(ChromeTooltipMetrics.pointer.maxWidth),
    );
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.maxLines, 12);
    expect(text.overflow, TextOverflow.ellipsis);
  });

  testWidgets('takes no pointer', (tester) async {
    await tester.pumpWidget(_host(const ChromeTooltip(text: 'x')));
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      tester.getCenter(find.byType(ChromeTooltip)),
      tester.view.viewId,
    );
    expect(
      result.path.any((entry) => entry.target is RenderParagraph),
      isFalse,
    );
  });
}
