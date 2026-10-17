/// Copy, cut and paste of the composer's text with its entities.
///
/// **Seam:** [ComposerController] over a [FakeRichClipboard], observed
/// through the controller's rich text and what the clipboard holds.
library;

import 'dart:async';

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

/// A clipboard whose reads finish when the test says: what a platform that
/// asks the user before a paste looks like.
final class _HeldClipboard implements RichClipboard {
  _HeldClipboard(this._inner);

  final FakeRichClipboard _inner;
  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<void> write(RichText text) => _inner.write(text);

  @override
  Future<ClipboardText?> read() async {
    await _gate.future;
    return _inner.read();
  }

  @override
  Future<ClipboardContents> readWithMedia() async {
    await _gate.future;
    return _inner.readWithMedia();
  }

  @override
  void Function() attach(RichClipboardField field) => _inner.attach(field);
}

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

    test('lands nowhere when the text changed while the clipboard was '
        'read', () async {
      final held = _HeldClipboard(clipboard);
      final slow = ComposerController(clipboard: held);
      addTearDown(slow.dispose);
      clipboard.putPlainText('pasted');
      slow
        ..restore(const RichText.plain('ab'))
        ..select(const TextSelection.collapsed(offset: 1));

      final pasting = slow.paste();
      slow.insertText('typed');
      held.release();

      expect(await pasting, isFalse);
      expect(slow.richText, const RichText.plain('atypedb'));
    });

    group('keeps what fits where it lands', () {
      final codeAndRocket = _text('main()\nsee \u{1F680}', [
        ('main()', const EntityKind.codeBlock(language: 'dart')),
        ('\u{1F680}', const EntityKind.inlineContent(_rocket)),
      ]);

      test('a code block in a quote is its text, the rest kept', () async {
        await clipboard.write(codeAndRocket);
        show(
          _text('quote', [('quote', EntityKind.quote)]),
          const TextSelection.collapsed(offset: 2),
        );

        await composer.paste();

        expect(
          composer.richText,
          _text('qumain()\nsee \u{1F680}ote', [
            ('qumain()\nsee \u{1F680}ote', EntityKind.quote),
            ('\u{1F680}', const EntityKind.inlineContent(_rocket)),
          ]),
        );
      });

      test('a code block in bold text is its text, the rest kept', () async {
        await clipboard.write(codeAndRocket);
        show(
          _text('bold', [('bold', EntityKind.bold)]),
          const TextSelection.collapsed(offset: 2),
        );

        await composer.paste();

        expect(
          composer.richText,
          _text('bomain()\nsee \u{1F680}ld', [
            ('bomain()', EntityKind.bold),
            ('see \u{1F680}ld', EntityKind.bold),
            ('\u{1F680}', const EntityKind.inlineContent(_rocket)),
          ]),
        );
      });

      test('anything in a code block is plain code', () async {
        await clipboard.write(
          _text('bold \u{1F680}', [
            ('bold', EntityKind.bold),
            ('\u{1F680}', const EntityKind.inlineContent(_rocket)),
          ]),
        );
        final block = _text('ab', [('ab', const EntityKind.codeBlock())]);
        show(block, const TextSelection.collapsed(offset: 1));

        await composer.paste();

        expect(
          composer.richText,
          _text('abold \u{1F680}b', [
            ('abold \u{1F680}b', const EntityKind.codeBlock()),
          ]),
        );
      });
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

  group('the platform\'s own commands (a browser\'s)', () {
    Future<void> focus(WidgetTester tester) async {
      await tester.pumpWidget(
        Focus(focusNode: composer.focusNode, child: const SizedBox()),
      );
      composer.requestFocus();
      await tester.pump();
    }

    testWidgets('a copy puts the selection on with its entities', (
      tester,
    ) async {
      await focus(tester);
      show(boldRocket, const TextSelection(baseOffset: 5, extentOffset: 11));

      expect(clipboard.performCopy(), isTrue);

      expect(
        (await clipboard.read())!.rich,
        _text('old \u{1F680}', [
          ('old', EntityKind.bold),
          ('\u{1F680}', const EntityKind.inlineContent(_rocket)),
        ]),
      );
      expect(composer.richText, boldRocket);
    });

    testWidgets('a cut also removes the selection', (tester) async {
      await focus(tester);
      show(boldRocket, const TextSelection(baseOffset: 4, extentOffset: 9));

      expect(clipboard.performCopy(cut: true), isTrue);

      expect(
        (await clipboard.read())!.rich,
        _text('bold ', [('bold', EntityKind.bold)]),
      );
      expect(composer.richText.plain, 'say \u{1F680} now');
    });

    testWidgets('a paste inserts the rich text', (tester) async {
      await focus(tester);
      await clipboard.write(boldRocket);
      show(RichText.empty, const TextSelection.collapsed(offset: 0));

      expect(clipboard.performPaste(), isTrue);
      await tester.pump();

      expect(composer.richText, boldRocket);
    });

    testWidgets('are not the composer\'s without focus, nor once disposed', (
      tester,
    ) async {
      show(boldRocket, const TextSelection(baseOffset: 0, extentOffset: 3));

      expect(clipboard.performCopy(), isFalse);

      await focus(tester);
      composer.dispose();
      expect(clipboard.performCopy(), isFalse);
    });
  });

  group('media', () {
    final png = PastedMedia.bytes(
      Uint8List.fromList(const [1, 2, 3]),
      mimeType: 'image/png',
    );

    /// A composer whose host takes pasted media when [sends] says so.
    ComposerController withHost(
      List<List<PastedMedia>> received, {
      bool sends = true,
    }) {
      final composer = ComposerController(
        clipboard: clipboard,
        onPastedMedia: (media) async {
          received.add(media);
          return sends;
        },
      );
      addTearDown(composer.dispose);
      return composer;
    }

    test('a paste of media goes to the host, and no text goes in', () async {
      final received = <List<PastedMedia>>[];
      final composer = withHost(received);
      clipboard.putMedia([png], text: 'a range');

      expect(await composer.paste(), isTrue);

      expect(received.single.single, same(png));
      expect(composer.richText, RichText.empty);
    });

    test('media the host does not send leaves the text that came with it, '
        'pasted', () async {
      final received = <List<PastedMedia>>[];
      final composer = withHost(received, sends: false);
      clipboard.putMedia([png], text: 'a range');

      expect(await composer.paste(), isTrue);

      expect(received, hasLength(1));
      expect(composer.richText, const RichText.plain('a range'));
    });

    test('a paste as plain text leaves media alone', () async {
      final received = <List<PastedMedia>>[];
      final composer = withHost(received);
      clipboard.putMedia([png], text: 'a range');

      expect(await composer.paste(plain: true), isTrue);
      expect(received, isEmpty);
      expect(composer.richText, const RichText.plain('a range'));
    });

    test('without a host for media, a paste is text only', () async {
      clipboard.putMedia([png]);

      expect(await composer.paste(), isFalse);
      expect(composer.richText, RichText.empty);
    });

    test('media a keyboard inserts goes to the host', () {
      final received = <List<PastedMedia>>[];

      withHost(received).receiveMedia([png]);

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
