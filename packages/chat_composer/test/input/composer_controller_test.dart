import 'package:chat_composer/chat_composer.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';

const _smile = InlineContentRef(
  key: ContentKey.document('smile'),
  alternativeText: '\u{1F642}',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ComposerController composer;

  setUp(() => composer = ComposerController());
  tearDown(() => composer.dispose());

  group('commands', () {
    test('insertText writes at the caret', () {
      composer.insertText('ab');
      composer.insertText('c');

      expect(composer.text.text, 'abc');
    });

    test('insertText replaces a selection', () {
      composer.insertText('abcd');
      composer.select(const TextSelection(baseOffset: 1, extentOffset: 3));

      composer.insertText('X');

      expect(composer.text.text, 'aXd');
    });

    test('insertContent embeds the reference', () {
      composer.insertText('a');

      composer.insertContent(_smile);

      expect(composer.richText.entities, hasLength(1));
      expect(composer.richText.plain, 'a\u{1F642}');
    });

    test('backspace takes a whole reference, then a character', () {
      composer.insertText('a');
      composer.insertContent(_smile);

      composer.backspace();
      expect(composer.richText, RichText('a'));

      composer.backspace();
      expect(composer.text.text, isEmpty);
    });

    test('clear empties the text and the entities', () {
      composer.restore(RichText('x', const [Entity(0, 1, EntityKind.bold)]));

      composer.clear();

      expect(composer.richText, RichText.empty);
    });

    test('restore loads a draft with a caret at its end', () {
      final draft = RichText('hi', const [Entity(0, 2, EntityKind.bold)]);

      composer.restore(draft);

      expect(composer.richText, draft);
      expect(composer.selection, const TextSelection.collapsed(offset: 2));
    });

    test('commands after dispose are ignored', () {
      composer.dispose();

      composer.insertText('x');
      composer.backspace();
      composer.clear();

      expect(composer.isDisposed, isTrue);
      expect(composer.text.text, isEmpty);
    });
  });

  group('focus', () {
    testWidgets('requestFocus and unfocus drive the focus node', (
      tester,
    ) async {
      await tester.pumpWidget(
        Focus(focusNode: composer.focusNode, child: const SizedBox()),
      );

      composer.requestFocus();
      await tester.pump();
      expect(composer.hasFocus, isTrue);

      composer.unfocus();
      await tester.pump();
      expect(composer.hasFocus, isFalse);
    });
  });

  group('soft keyboard', () {
    test('is automatic until the host suppresses it', () {
      expect(composer.softKeyboard.value, SoftKeyboardMode.auto);

      composer.setSoftKeyboard(SoftKeyboardMode.suppressed);

      expect(composer.softKeyboard.value, SoftKeyboardMode.suppressed);
    });

    test('signals only on a change', () {
      var signals = 0;
      composer.softKeyboard.addListener(() => signals++);

      composer.setSoftKeyboard(SoftKeyboardMode.auto);
      composer.setSoftKeyboard(SoftKeyboardMode.suppressed);
      composer.setSoftKeyboard(SoftKeyboardMode.suppressed);

      expect(signals, 1);
    });

    test('can start suppressed', () {
      final suppressed = ComposerController(
        softKeyboard: SoftKeyboardMode.suppressed,
      );
      addTearDown(suppressed.dispose);

      expect(suppressed.softKeyboard.value, SoftKeyboardMode.suppressed);
    });
  });

  group('field height', () {
    test('is zero until the field reports it, then published', () {
      expect(composer.fieldHeight.value, 0);
      var signals = 0;
      composer.fieldHeight.addListener(() => signals++);

      composer.reportFieldHeight(44);
      composer.reportFieldHeight(44);

      expect(composer.fieldHeight.value, 44);
      expect(signals, 1);
    });
  });

  group('ownership', () {
    test('disposes what it created', () {
      final owned = ComposerController();
      final text = owned.text;
      final focus = owned.focusNode;

      owned.dispose();

      expect(() => text.addListener(() {}), throwsFlutterError);
      expect(() => focus.addListener(() {}), throwsFlutterError);
    });

    test('leaves alone what the host handed in', () {
      final text = ComposerTextController(initial: RichText('kept'));
      final focus = FocusNode();
      final scroll = ScrollController();
      final borrowed = ComposerController(
        text: text,
        focusNode: focus,
        fieldScroll: scroll,
      );

      borrowed.dispose();

      expect(text.text, 'kept');
      text.dispose();
      focus.dispose();
      scroll.dispose();
    });

    test('dispose is idempotent', () {
      composer.dispose();
      composer.dispose();
    });
  });
}
