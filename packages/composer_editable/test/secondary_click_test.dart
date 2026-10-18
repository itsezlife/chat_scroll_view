import 'package:composer_editable/composer_editable.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The secondary click seam: a host that asks for it hears the press and the
/// release of the secondary mouse button with the text position under the
/// pointer, and the field leaves its selection and toolbar alone.
void main() {
  late TextEditingController controller;
  late FocusNode focusNode;
  late List<ExtendedSecondaryClick> clicks;

  Future<void> pump(
    WidgetTester tester, {
    required bool listening,
    TextSelection selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 5,
    ),
  }) async {
    controller = TextEditingController(text: 'alpha beta gamma')
      ..selection = selection;
    focusNode = FocusNode();
    clicks = [];
    addTearDown(controller.dispose);
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: ExtendedTextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                maxLines: 4,
                style: const TextStyle(fontSize: 16, height: 1.25),
                onSecondaryClick: listening ? clicks.add : null,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Autofocus does not keep a set selection on every platform.
    controller.selection = selection;
    await tester.pump();
  }

  Offset caretPoint(WidgetTester tester, int offset) {
    final render = tester
        .state<ExtendedEditableTextState>(find.byType(ExtendedEditableText))
        .renderEditable;
    return render.localToGlobal(
      render.getLocalRectForCaret(TextPosition(offset: offset)).center,
    );
  }

  Future<TestGesture> rightDown(WidgetTester tester, Offset at) =>
      tester.startGesture(
        at,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );

  const desktop = TargetPlatformVariant({
    TargetPlatform.macOS,
    TargetPlatform.windows,
  });

  testWidgets(
    'the press and the release are reported with the position under the '
    'pointer',
    (tester) async {
      await pump(tester, listening: true);
      final at = caretPoint(tester, 8);

      final gesture = await rightDown(tester, at);
      await tester.pump();
      expect(clicks.map((c) => c.phase), [ExtendedSecondaryClickPhase.down]);
      expect(clicks.single.globalPosition, at);
      expect(clicks.single.textPosition.offset, closeTo(8, 1));

      await gesture.up();
      await tester.pump();
      expect(clicks.map((c) => c.phase), [
        ExtendedSecondaryClickPhase.down,
        ExtendedSecondaryClickPhase.up,
      ]);
      expect(clicks.last.globalPosition, at);
    },
    variant: desktop,
  );

  testWidgets('a click outside the selection leaves it', (tester) async {
    await pump(tester, listening: true);

    final gesture = await rightDown(tester, caretPoint(tester, 12));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      controller.selection,
      const TextSelection(baseOffset: 0, extentOffset: 5),
    );
  }, variant: desktop);

  testWidgets('a click beside a caret leaves the caret where it was', (
    tester,
  ) async {
    await pump(
      tester,
      listening: true,
      selection: const TextSelection.collapsed(offset: 3),
    );

    final gesture = await rightDown(tester, caretPoint(tester, 12));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.selection, const TextSelection.collapsed(offset: 3));
  }, variant: desktop);

  testWidgets('the field shows no toolbar of its own', (tester) async {
    await pump(tester, listening: true);
    final state = tester.state<ExtendedEditableTextState>(
      find.byType(ExtendedEditableText),
    );

    final gesture = await rightDown(tester, caretPoint(tester, 8));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(state.selectionOverlay?.toolbarIsVisible ?? false, isFalse);
  }, variant: desktop);

  testWidgets(
    'without the seam macOS still selects the word',
    (tester) async {
      await pump(
        tester,
        listening: false,
        selection: const TextSelection.collapsed(offset: 0),
      );

      final gesture = await rightDown(tester, caretPoint(tester, 8));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        controller.selection,
        const TextSelection(baseOffset: 6, extentOffset: 10),
      );
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );
}
