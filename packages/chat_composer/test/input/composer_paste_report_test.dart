/// The paste report: each paste that puts text into the field is told to the
/// host with the range it landed in.
///
/// **Seam:** [ComposerController.onPaste], over a [FakeRichClipboard].
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/widgets.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeRichClipboard clipboard;
  late List<ComposerPaste> reports;
  late ComposerController composer;

  setUp(() {
    clipboard = FakeRichClipboard();
    reports = [];
    composer = ComposerController(clipboard: clipboard, onPaste: reports.add);
  });
  tearDown(() => composer.dispose());

  void show(String text, TextSelection selection) {
    composer
      ..restore(RichText.plain(text))
      ..select(selection);
  }

  test('a plain paste reports the range it landed in, not rich', () async {
    clipboard.putPlainText('**hi**');
    show('a XX b', const TextSelection(baseOffset: 2, extentOffset: 4));

    await composer.paste();

    expect(reports, [
      const ComposerPaste(
        range: TextRange(start: 2, end: 8),
        text: '**hi**',
        wasRich: false,
      ),
    ]);
    expect(composer.richText.plain, 'a **hi** b');
  });

  test('a rich paste reports wasRich', () async {
    await clipboard.write(
      RichText('bold', const [Entity(0, 4, EntityKind.bold)]),
    );
    show('ab', const TextSelection.collapsed(offset: 1));

    await composer.paste();

    expect(reports.single.wasRich, isTrue);
    expect(reports.single.range, const TextRange(start: 1, end: 5));
    expect(reports.single.text, 'bold');
  });

  test('a plain-text paste of a rich clipboard is not rich', () async {
    await clipboard.write(
      RichText('bold', const [Entity(0, 4, EntityKind.bold)]),
    );
    show('', const TextSelection.collapsed(offset: 0));

    await composer.paste(plain: true);

    expect(reports.single.wasRich, isFalse);
  });

  test('the range is where the text landed once the selection widened over '
      'an atom', () async {
    const rocket = ContentKey.document('rocket');
    composer.restore(
      RichText('a\u{1F680}b', const [
        Entity(1, 2, EntityKind.inlineContent(rocket)),
      ]),
    );
    // The selection ends inside the atom, so the paste replaces all of it.
    composer.select(const TextSelection(baseOffset: 0, extentOffset: 2));
    clipboard.putPlainText('xyz');

    await composer.paste();

    expect(composer.richText.plain, 'xyzb');
    expect(reports.single.range, const TextRange(start: 0, end: 3));
  });

  test('a paste that inserts nothing reports nothing', () async {
    show('ab', const TextSelection.collapsed(offset: 1));

    await composer.paste();

    expect(reports, isEmpty);
  });

  test('a host that throws does not lose the paste', () async {
    final errors = <FlutterErrorDetails>[];
    final original = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = original);
    final throwing = ComposerController(
      clipboard: clipboard,
      onPaste: (_) => throw StateError('host'),
    );
    addTearDown(throwing.dispose);
    clipboard.putPlainText('x');

    expect(await throwing.paste(), isTrue);

    expect(throwing.richText.plain, 'x');
    expect(errors, hasLength(1));
  });
}
