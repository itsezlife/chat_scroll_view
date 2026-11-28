/// A bottom sheet's drag owner as a widget: a short pull springs the sheet
/// back from where the finger left it.
///
/// **Seams:** [ChromeSheetDrag] and its sink ([ChromeSheetDrag.maybeOf]).
library;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChromeSheetDrag', () {
    const spec = ChromeSheetDragSpec(
      dismissDistance: 50,
      dismissVelocity: 3500,
      springBack: Duration(milliseconds: 250),
    );
    const sheetKey = ValueKey('sheet');

    Future<ChromeSheetDragSink> pump(WidgetTester tester) async {
      late ChromeSheetDragSink sink;
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Navigator(
            onGenerateRoute: (_) => PageRouteBuilder<void>(
              pageBuilder: (_, _, _) => Align(
                alignment: Alignment.topLeft,
                child: ChromeSheetDrag(
                  spec: spec,
                  child: Builder(
                    builder: (context) {
                      sink = ChromeSheetDrag.maybeOf(context)!;
                      return const SizedBox(
                        key: sheetKey,
                        width: 100,
                        height: 100,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return sink;
    }

    double top(WidgetTester tester) =>
        tester.getTopLeft(find.byKey(sheetKey)).dy;

    testWidgets('springs back from the whole pull, not from one pixel', (
      tester,
    ) async {
      final sink = await pump(tester);
      sink
        ..start()
        ..take(40);
      await tester.pump();
      expect(top(tester), 40);

      expect(sink.release(0), isTrue);
      await tester.pump();
      // The first frame of the return still holds the pull.
      expect(top(tester), closeTo(40, 0.5));

      // 40 of the 50 distance: 200 ms, on the default ease.
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        top(tester),
        closeTo(40 * (1 - const Cubic(0.25, 0.1, 0.25, 1).transform(0.5)), 0.5),
      );

      await tester.pumpAndSettle();
      expect(top(tester), 0);
    });

    testWidgets('a drag that starts again catches the sheet where it is', (
      tester,
    ) async {
      final sink = await pump(tester);
      sink
        ..start()
        ..take(40)
        ..release(0);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final caught = top(tester);
      expect(caught, greaterThan(1));

      sink.start();
      await tester.pump(const Duration(milliseconds: 100));
      expect(top(tester), caught);
    });
  });
}
