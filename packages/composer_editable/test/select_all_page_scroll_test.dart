import 'package:composer_editable/composer_editable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<
    ({
      TextEditingController controller,
      ScrollController page,
      ExtendedEditableTextState editable,
    })
  >
  pumpFieldInPage(WidgetTester tester) async {
    final controller = TextEditingController(
      text: List<String>.generate(200, (i) => 'line $i').join('\n'),
    );
    addTearDown(controller.dispose);
    final page = ScrollController();
    addTearDown(page.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: page,
            child: Column(
              children: <Widget>[
                ExtendedTextField(controller: controller, maxLines: 5),
                const SizedBox(height: 3000),
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
      editable: tester.state<ExtendedEditableTextState>(
        find.byType(ExtendedEditableText),
      ),
    );
  }

  testWidgets('selecting all scrolls the field, not the page', (tester) async {
    final field = await pumpFieldInPage(tester);

    field.editable.userUpdateTextEditingValue(
      field.editable.textEditingValue.copyWith(
        selection: TextSelection(
          baseOffset: 0,
          extentOffset: field.controller.text.length,
        ),
      ),
      SelectionChangedCause.doubleTap,
    );
    await tester.pumpAndSettle();

    // The field itself follows the extent to the end of the text.
    expect(field.editable.renderEditable.offset.pixels, greaterThan(0));
    // The page holds still: the field is fully visible, so nothing about the
    // selection asks it to move.
    expect(field.page.offset, 0);
  });

  testWidgets('a caret below the fold still pulls the page', (tester) async {
    final field = await pumpFieldInPage(tester);

    field.page.jumpTo(field.page.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.byType(ExtendedTextField).hitTestable(), findsNothing);

    field.editable.userUpdateTextEditingValue(
      field.editable.textEditingValue.copyWith(
        selection: const TextSelection.collapsed(offset: 0),
      ),
      SelectionChangedCause.doubleTap,
    );
    await tester.pumpAndSettle();

    expect(field.page.offset, 0);
  });
}
