/// Edits a host makes through the controller (a panel's emoji, its backspace)
/// keep the caret in view once the field scrolls, as typing does.
///
/// **Seam:** a [ComposerView] whose text is past the field's maximum lines,
/// its field scrolled away from the caret, edited through the
/// [ComposerController], observed through where the field lays out its last
/// line (the caret's): its glyphs inside the field's box.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';

import '../support/composer_harness.dart';

const _smile = InlineContentRef(
  key: ContentKey.document('smile'),
  alternativeText: '\u{1F642}',
);

void main() {
  late ComposerController controller;

  setUp(() => controller = ComposerController());
  tearDown(() => controller.dispose());

  // Whether the glyphs of the last line lie inside the field's box.
  bool lastLineShown(WidgetTester tester) {
    final render = tester
        .state<EditableTextState>(find.byType(EditableText))
        .renderEditable;
    final text = controller.text.text;
    final boxes = render.getBoxesForSelection(
      TextSelection(
        baseOffset: text.lastIndexOf('\n') + 1,
        extentOffset: text.length,
      ),
    );
    return boxes.isNotEmpty &&
        boxes.every((box) => box.top >= 0 && box.bottom <= render.size.height);
  }

  // Twelve lines with the caret after the last, the field focused and then
  // scrolled back to its first line.
  Future<void> scrolledAway(WidgetTester tester) async {
    await tester.pumpWidget(
      composerHarness(
        ComposerView(controller: controller, spec: ComposerSpec()),
      ),
    );
    final text = List.generate(12, (i) => 'line $i').join('\n');
    controller
      ..restore(
        RichText(text, const []),
        selection: TextSelection.collapsed(offset: text.length),
      )
      ..requestFocus();
    await tester.pumpAndSettle();
    final position = controller.fieldScroll.position;
    expect(position.maxScrollExtent, greaterThan(0), reason: 'past max lines');
    position.jumpTo(0);
    await tester.pump();
    expect(lastLineShown(tester), isFalse);
  }

  testWidgets('inserted text brings the caret line into view', (tester) async {
    await scrolledAway(tester);

    controller.insertText('\u{1F600}');
    await tester.pump();
    await tester.pump();

    expect(lastLineShown(tester), isTrue);
  });

  testWidgets('inserted inline content brings the caret line into view', (
    tester,
  ) async {
    await scrolledAway(tester);

    controller.insertContent(_smile);
    await tester.pump();
    await tester.pump();

    expect(lastLineShown(tester), isTrue);
  });

  testWidgets('a backspace brings the caret line into view', (tester) async {
    await scrolledAway(tester);

    controller.backspace();
    await tester.pump();
    await tester.pump();

    expect(lastLineShown(tester), isTrue);
  });

  testWidgets('a backspace that empties the field, and one on an empty field, '
      'reveal without an error', (tester) async {
    await tester.pumpWidget(
      composerHarness(
        ComposerView(controller: controller, spec: ComposerSpec()),
      ),
    );
    controller
      ..insertText('a')
      ..requestFocus();
    await tester.pumpAndSettle();

    controller.backspace();
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(controller.text.text, isEmpty);

    controller.backspace();
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
