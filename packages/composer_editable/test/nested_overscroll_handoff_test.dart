import 'package:composer_editable/composer_editable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<
    ({
      TextEditingController controller,
      ScrollController page,
      ScrollableState fieldScrollable,
    })
  >
  pumpNestedField(
    WidgetTester tester, {
    bool delegateOverscrollToParent = true,
  }) async {
    final TextEditingController controller = TextEditingController(
      text: List<String>.generate(40, (int i) => 'line $i').join('\n'),
    );
    addTearDown(controller.dispose);
    final ScrollController page = ScrollController();
    addTearDown(page.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: page,
            child: Column(
              children: <Widget>[
                // Room above so the page can scroll up while the field stays
                // on-screen.
                const SizedBox(height: 400),
                ExtendedTextField(
                  controller: controller,
                  maxLines: 5,
                  delegateOverscrollToParent: delegateOverscrollToParent,
                ),
                const SizedBox(height: 2000),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(ExtendedTextField));
    await tester.pumpAndSettle();

    return (
      controller: controller,
      page: page,
      fieldScrollable: tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(ExtendedEditableText),
          matching: find.byType(Scrollable),
        ),
      ),
    );
  }

  testWidgets('overscroll at the bottom scrolls the page further down', (
    WidgetTester tester,
  ) async {
    final field = await pumpNestedField(tester);

    // Keep the field on-screen while leaving room for the page to move down.
    field.page.jumpTo(200);
    field.fieldScrollable.position.jumpTo(
      field.fieldScrollable.position.maxScrollExtent,
    );
    await tester.pumpAndSettle();
    final double pageBefore = field.page.offset;

    // Finger up → field would overscroll past max → page should take it.
    await tester.drag(find.byType(ExtendedTextField), const Offset(0, -240));
    await tester.pumpAndSettle();

    expect(field.page.offset, greaterThan(pageBefore));
  });

  testWidgets('overscroll at the top scrolls the page back up', (
    WidgetTester tester,
  ) async {
    final field = await pumpNestedField(tester);

    // Field stays visible (top at ~200) while the page can still scroll up.
    field.page.jumpTo(200);
    field.fieldScrollable.position.jumpTo(0);
    await tester.pumpAndSettle();

    // Finger down → field would overscroll past 0 → page should take it.
    await tester.drag(find.byType(ExtendedTextField), const Offset(0, 240));
    await tester.pumpAndSettle();

    expect(field.page.offset, lessThan(200));
  });

  testWidgets('a fling at the bottom ballistically scrolls the page', (
    WidgetTester tester,
  ) async {
    final field = await pumpNestedField(tester);

    field.page.jumpTo(200);
    field.fieldScrollable.position.jumpTo(
      field.fieldScrollable.position.maxScrollExtent,
    );
    await tester.pumpAndSettle();
    final double pageBefore = field.page.offset;

    // Strong upward fling must become parent goBallistic.
    await tester.fling(
      find.byType(ExtendedTextField),
      const Offset(0, -400),
      3000,
    );
    await tester.pumpAndSettle();

    expect(field.page.offset, greaterThan(pageBefore + 100));
  });

  testWidgets('a mid-content drag still scrolls the field, not the page', (
    WidgetTester tester,
  ) async {
    final field = await pumpNestedField(tester);

    field.page.jumpTo(200);
    final double mid = field.fieldScrollable.position.maxScrollExtent / 2;
    field.fieldScrollable.position.jumpTo(mid);
    await tester.pumpAndSettle();
    final double pageBefore = field.page.offset;

    await tester.drag(find.byType(ExtendedTextField), const Offset(0, -80));
    await tester.pumpAndSettle();

    expect(field.page.offset, pageBefore);
    expect(field.fieldScrollable.position.pixels, greaterThan(mid));
  });

  testWidgets('opt-out keeps edge overscroll inside the field', (
    WidgetTester tester,
  ) async {
    final field = await pumpNestedField(
      tester,
      delegateOverscrollToParent: false,
    );

    field.page.jumpTo(200);
    field.fieldScrollable.position.jumpTo(
      field.fieldScrollable.position.maxScrollExtent,
    );
    await tester.pumpAndSettle();
    final double pageBefore = field.page.offset;

    await tester.drag(find.byType(ExtendedTextField), const Offset(0, -240));
    await tester.pumpAndSettle();

    expect(field.page.offset, pageBefore);
  });
}
