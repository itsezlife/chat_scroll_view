import 'package:chat_composer/chat_composer.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';

const _smile = InlineContentRef(
  key: ContentKey.document('smile'),
  alternativeText: '\u{1F642}',
);

Future<void> _pumpField(WidgetTester tester, ComposerController composer) =>
    tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: EditableText(
          controller: composer.text,
          focusNode: composer.focusNode,
          style: const TextStyle(fontSize: 16),
          cursorColor: const Color(0xFF000000),
          backgroundCursorColor: const Color(0xFF888888),
          maxLines: null,
        ),
      ),
    );

void main() {
  late ComposerController composer;

  setUp(() => composer = ComposerController());
  tearDown(() => composer.dispose());

  testWidgets('text entered through the platform input keeps its entities', (
    tester,
  ) async {
    await _pumpField(tester, composer);
    composer.restore(RichText('bold', const [Entity(0, 4, EntityKind.bold)]));
    composer.select(const TextSelection.collapsed(offset: 2));
    composer.requestFocus();
    await tester.pump();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'boXld',
        selection: TextSelection.collapsed(offset: 3),
      ),
    );
    await tester.pump();

    expect(
      composer.richText,
      RichText('boXld', const [Entity(0, 5, EntityKind.bold)]),
    );
  });

  testWidgets('an inline reference lays out as one unit in the field', (
    tester,
  ) async {
    await _pumpField(tester, composer);
    composer.requestFocus();
    await tester.pump();

    composer.insertText('a');
    composer.insertContent(_smile);
    composer.insertText('b');
    await tester.pump();

    expect(composer.text.text, 'a\u{1F642}b');
    expect(composer.richText.entities, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an input method composition is committed once it ends', (
    tester,
  ) async {
    await _pumpField(tester, composer);
    composer.restore(RichText('word', const [Entity(0, 4, EntityKind.bold)]));
    composer.requestFocus();
    await tester.pump();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'wor',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 0, end: 3),
      ),
    );
    await tester.pump();
    expect(composer.text.isComposing, isTrue);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'words',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 5),
      ),
    );
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'words',
        selection: TextSelection.collapsed(offset: 5),
      ),
    );
    await tester.pump();

    expect(
      composer.richText,
      RichText('words', const [Entity(0, 4, EntityKind.bold)]),
    );
  });

  testWidgets('a query opens as the user types a registered trigger', (
    tester,
  ) async {
    composer.registerQueryKind(
      const ComposerQueryKind(id: 'mention', trigger: '@'),
    );
    await _pumpField(tester, composer);
    composer.requestFocus();
    await tester.pump();

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'hi @al',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    await tester.pump();

    expect(composer.query.value!.text, 'al');
  });
}
