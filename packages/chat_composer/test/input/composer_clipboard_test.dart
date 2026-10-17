/// Copy, cut and paste of the composer's text with its entities.
///
/// **Seam:** [ComposerController] over a [FakeRichClipboard], observed
/// through the controller's rich text and what the clipboard holds.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:flutter/widgets.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';

/// [plain] with [kind] over each of [parts], found in order.
RichText _text(String plain, List<(String, EntityKind)> parts) {
  var from = 0;
  return RichText(plain, [
    for (final (part, kind) in parts)
      () {
        from = plain.indexOf(part, from);
        return Entity(from, part.length, kind);
      }(),
  ]);
}

const _rocket = ContentKey.document('rocket');

void main() {
  late FakeRichClipboard clipboard;
  late ComposerController composer;

  setUp(() {
    clipboard = FakeRichClipboard();
    composer = ComposerController(clipboard: clipboard);
  });
  tearDown(() => composer.dispose());

  void show(RichText text, TextSelection selection) {
    composer
      ..restore(text)
      ..select(selection);
  }

  final boldRocket = _text('say bold \u{1F680} now', [
    ('bold', EntityKind.bold),
    ('\u{1F680}', const EntityKind.inlineContent(_rocket)),
  ]);

  group('copy', () {
    test('puts the selection on the clipboard with its entities', () async {
      // "old 🚀": part of the bold word and the custom emoji.
      show(boldRocket, const TextSelection(baseOffset: 5, extentOffset: 11));

      expect(await composer.copySelection(), isTrue);

      expect(
        (await clipboard.read())!.rich,
        _text('old \u{1F680}', [
          ('old', EntityKind.bold),
          ('\u{1F680}', const EntityKind.inlineContent(_rocket)),
        ]),
      );
      expect(composer.richText, boldRocket);
    });

    test('copies nothing for a collapsed selection', () async {
      show(boldRocket, const TextSelection.collapsed(offset: 3));

      expect(await composer.copySelection(), isFalse);
      expect(clipboard.writeCount, 0);
    });
  });

  test('cut puts the selection on the clipboard and removes it', () async {
    show(boldRocket, const TextSelection(baseOffset: 4, extentOffset: 9));

    expect(await composer.cutSelection(), isTrue);

    expect(
      (await clipboard.read())!.rich,
      _text('bold ', [('bold', EntityKind.bold)]),
    );
    expect(
      composer.richText,
      _text('say \u{1F680} now', [
        ('\u{1F680}', const EntityKind.inlineContent(_rocket)),
      ]),
    );
    expect(composer.selection, const TextSelection.collapsed(offset: 4));
  });

  group('paste', () {
    test('replaces the selection with the rich text, caret after it', () async {
      await clipboard.write(boldRocket);
      show(
        const RichText.plain('a XX b'),
        const TextSelection(baseOffset: 2, extentOffset: 4),
      );

      expect(await composer.paste(), isTrue);

      expect(
        composer.richText,
        _text('a say bold \u{1F680} now b', [
          ('bold', EntityKind.bold),
          ('\u{1F680}', const EntityKind.inlineContent(_rocket)),
        ]),
      );
      expect(
        composer.selection,
        TextSelection.collapsed(offset: 2 + boldRocket.length),
      );
    });

    test('as plain text drops the entities', () async {
      await clipboard.write(boldRocket);
      show(RichText.empty, const TextSelection.collapsed(offset: 0));

      await composer.paste(plain: true);

      expect(composer.richText, RichText.plain(boldRocket.plain));
    });

    test('reads plain text another app copied', () async {
      clipboard.putPlainText('from elsewhere');
      show(RichText.empty, const TextSelection.collapsed(offset: 0));

      await composer.paste();

      expect(composer.richText, const RichText.plain('from elsewhere'));
    });

    test('inside a quote unwraps the quotes it brings', () async {
      await clipboard.write(
        _text('quoted\nbold', [
          ('quoted', EntityKind.quote),
          ('bold', EntityKind.bold),
        ]),
      );
      final quote = _text('in a quote', [('in a quote', EntityKind.quote)]);
      show(quote, const TextSelection.collapsed(offset: 4));

      await composer.paste();

      expect(
        composer.richText,
        _text('in aquoted\nbold quote', [
          ('in aquoted\nbold quote', EntityKind.quote),
          ('bold', EntityKind.bold),
        ]),
      );
    });

    test('changes nothing when the clipboard holds no text', () async {
      show(boldRocket, const TextSelection.collapsed(offset: 0));

      expect(await composer.paste(), isFalse);

      expect(composer.richText, boldRocket);
    });

    test('changes nothing and reports when the clipboard fails', () async {
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);
      await clipboard.write(boldRocket);
      clipboard.failure = Exception('no clipboard');
      show(RichText.empty, const TextSelection.collapsed(offset: 0));

      expect(await composer.paste(), isFalse);
      expect(await composer.copySelection(), isFalse);

      expect(composer.richText, RichText.empty);
      expect(reported, hasLength(1));
      expect(reported.single.library, 'chat_composer');
    });
  });

  group('media', () {
    final png = PastedMedia.bytes(
      Uint8List.fromList(const [1, 2, 3]),
      mimeType: 'image/png',
    );

    test('a paste of media goes to the host, and no text goes in', () async {
      final received = <List<PastedMedia>>[];
      final withHost = ComposerController(
        clipboard: clipboard,
        onPastedMedia: received.add,
      );
      addTearDown(withHost.dispose);
      clipboard.putMedia([png]);

      expect(await withHost.paste(), isTrue);

      expect(received.single.single, same(png));
      expect(withHost.richText, RichText.empty);
    });

    test('a paste as plain text leaves media alone', () async {
      final received = <List<PastedMedia>>[];
      final withHost = ComposerController(
        clipboard: clipboard,
        onPastedMedia: received.add,
      );
      addTearDown(withHost.dispose);
      clipboard.putMedia([png]);

      expect(await withHost.paste(plain: true), isFalse);
      expect(received, isEmpty);
    });

    test('without a host for media, a paste is text only', () async {
      clipboard.putMedia([png]);

      expect(await composer.paste(), isFalse);
      expect(composer.richText, RichText.empty);
    });

    test('media a keyboard inserts goes to the host', () {
      final received = <List<PastedMedia>>[];
      final withHost = ComposerController(onPastedMedia: received.add);
      addTearDown(withHost.dispose);

      withHost.receiveMedia([png]);

      expect(received.single.single, same(png));
    });
  });

  test('without a clipboard every command answers false', () async {
    final bare = ComposerController();
    addTearDown(bare.dispose);
    bare
      ..restore(boldRocket)
      ..select(const TextSelection(baseOffset: 0, extentOffset: 3));

    expect(bare.clipboard, isNull);
    expect(await bare.copySelection(), isFalse);
    expect(await bare.cutSelection(), isFalse);
    expect(await bare.paste(), isFalse);
    expect(bare.richText, boldRocket);
  });
}
