/// List items across the clipboard.
///
/// **Seam:** [ComposerController] over a [FakeRichClipboard], observed through
/// the controller's rich text.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';

const _bullet = EntityKind.list(listKind: EntityListKind.bullet);
const _nested = EntityKind.list(listKind: EntityListKind.bullet, depth: 1);

void main() {
  late FakeRichClipboard clipboard;
  late ComposerController composer;

  ComposerController make({required bool lists}) => ComposerController(
    clipboard: clipboard,
    text: ComposerTextController(lists: lists),
  );

  setUp(() {
    clipboard = FakeRichClipboard();
    composer = make(lists: true);
  });
  tearDown(() => composer.dispose());

  test('plain text with two marker lines pastes as two items', () async {
    clipboard.putPlainText('- a\n- b');

    expect(await composer.paste(), isTrue);

    expect(
      composer.richText,
      RichText('a\nb', const [Entity(0, 1, _bullet), Entity(2, 1, _bullet)]),
    );
  });

  test('a single marker line pastes as text', () async {
    clipboard.putPlainText('- a');

    await composer.paste();

    expect(composer.richText, const RichText.plain('- a'));
  });

  test('"paste as plain text" keeps the markers', () async {
    clipboard.putPlainText('- a\n- b');

    await composer.paste(plain: true);

    expect(composer.richText, const RichText.plain('- a\n- b'));
  });

  test('a rich payload keeps its items', () async {
    final copied = RichText('x\ny', const [
      Entity(0, 1, _bullet),
      Entity(2, 1, _nested),
    ]);
    await clipboard.write(copied);

    await composer.paste();

    expect(composer.richText, copied);
  });

  test('a field with lists off pastes the markers as text', () async {
    composer.dispose();
    composer = make(lists: false);
    clipboard.putPlainText('- a\n- b');

    await composer.paste();

    expect(composer.richText, const RichText.plain('- a\n- b'));
  });

  test('a paste into a quote keeps the markers', () async {
    composer.restore(RichText('q', const [Entity(0, 1, EntityKind.quote)]));
    clipboard.putPlainText('- a\n- b');

    await composer.paste();

    expect(composer.richText.plain, 'q- a\n- b');
  });
}
