/// What the composer's edit menu asks of its input: undo and redo with their
/// availability, delete and select-all, and whether a paste would put
/// anything in.
///
/// **Seam:** [ComposerController] under a mounted [ComposerView] (undo needs
/// the field's history), over a [FakeRichClipboard] and the platform
/// clipboard channel.
library;

import 'dart:async';

import 'package:chat_composer/chat_composer.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';

import '../support/composer_harness.dart';

/// A clipboard whose reads never finish: a platform waiting for the user.
final class _NeverAnswers implements RichClipboard {
  @override
  Future<void> write(RichText text) => Completer<void>().future;

  @override
  Future<ClipboardText?> read() => Completer<ClipboardText?>().future;

  @override
  Future<ClipboardContents> readWithMedia() =>
      Completer<ClipboardContents>().future;

  @override
  void Function() attach(RichClipboardField field) => () {};
}

void main() {
  Future<ComposerController> mount(
    WidgetTester tester, {
    RichClipboard? clipboard,
    Future<bool> Function(List<PastedMedia>)? onPastedMedia,
  }) async {
    final composer = ComposerController(
      clipboard: clipboard,
      onPastedMedia: onPastedMedia,
    );
    addTearDown(composer.dispose);
    await tester.pumpWidget(
      composerHarness(ComposerView(controller: composer, spec: ComposerSpec())),
    );
    return composer;
  }

  group('undo and redo', () {
    testWidgets('an empty field has nothing to undo or redo', (tester) async {
      final composer = await mount(tester);

      expect(composer.canUndo, isFalse);
      expect(composer.canRedo, isFalse);
    });

    testWidgets('typing can be undone and then redone', (tester) async {
      final composer = await mount(tester);
      // A click on the field is what gives it a valid selection, and the
      // history its empty first entry.
      composer
        ..requestFocus()
        ..select(const TextSelection.collapsed(offset: 0));
      // The history records after a pause (it throttles by 500 ms).
      await tester.pump(const Duration(seconds: 1));

      await enterFieldText(tester, 'hello');
      await tester.pump(const Duration(seconds: 1));
      expect(composer.canUndo, isTrue);
      expect(composer.canRedo, isFalse);

      composer.undo();
      await tester.pump();
      expect(composer.text.text, '');
      expect(composer.canRedo, isTrue);

      composer.redo();
      await tester.pump();
      expect(composer.text.text, 'hello');
    });
  });

  group('delete', () {
    testWidgets('removes the selection and leaves a caret there', (
      tester,
    ) async {
      final composer = await mount(tester);
      composer.restore(
        const RichText.plain('one two three'),
        selection: const TextSelection(baseOffset: 4, extentOffset: 8),
      );

      composer.deleteSelection();

      expect(composer.text.text, 'one three');
      expect(composer.selection, const TextSelection.collapsed(offset: 4));
    });

    testWidgets('does nothing at a caret', (tester) async {
      final composer = await mount(tester);
      composer.restore(
        const RichText.plain('one two'),
        selection: const TextSelection.collapsed(offset: 3),
      );

      composer.deleteSelection();

      expect(composer.text.text, 'one two');
    });

    testWidgets('keeps the entities of what is left', (tester) async {
      final composer = await mount(tester);
      composer.restore(
        RichText('one two three', const [Entity(8, 5, EntityKind.bold)]),
        selection: const TextSelection(baseOffset: 3, extentOffset: 7),
      );

      composer.deleteSelection();

      expect(composer.text.text, 'one three');
      expect(composer.richText.entities.single.kind, EntityKind.bold);
      expect(composer.richText.entities.single.offset, 4);
    });
  });

  group('select all', () {
    testWidgets('selects the whole text', (tester) async {
      final composer = await mount(tester);
      composer.restore(
        const RichText.plain('one two'),
        selection: const TextSelection.collapsed(offset: 1),
      );

      composer.selectAll();

      expect(
        composer.selection,
        const TextSelection(baseOffset: 0, extentOffset: 7),
      );
    });
  });

  group('canPaste', () {
    testWidgets('is true while the rich clipboard holds text', (tester) async {
      final clipboard = FakeRichClipboard()..putPlainText('hello');
      final composer = await mount(tester, clipboard: clipboard);

      expect(await composer.canPaste(), isTrue);
    });

    testWidgets('is false while it holds nothing', (tester) async {
      final composer = await mount(tester, clipboard: FakeRichClipboard());

      expect(await composer.canPaste(), isFalse);
    });

    testWidgets('is true for media the host takes', (tester) async {
      final clipboard = FakeRichClipboard()
        ..putMedia([PastedMedia.bytes(Uint8List(4), mimeType: 'image/png')]);
      final composer = await mount(
        tester,
        clipboard: clipboard,
        onPastedMedia: (_) async => true,
      );

      expect(await composer.canPaste(), isTrue);
    });

    testWidgets('is false for media nobody takes', (tester) async {
      final clipboard = FakeRichClipboard()
        ..putMedia([PastedMedia.bytes(Uint8List(4), mimeType: 'image/png')]);
      final composer = await mount(tester, clipboard: clipboard);

      expect(await composer.canPaste(), isFalse);
    });

    testWidgets('is false when the clipboard cannot be read', (tester) async {
      final clipboard = FakeRichClipboard()
        ..putPlainText('hello')
        ..failure = Exception('no clipboard');
      final composer = await mount(tester, clipboard: clipboard);
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);

      expect(await composer.canPaste(), isFalse);
      expect(reported, hasLength(1));
    });

    testWidgets('a clipboard that never answers counts as holding something', (
      tester,
    ) async {
      final composer = await mount(tester, clipboard: _NeverAnswers());

      final answer = composer.canPaste();
      await tester.pump(PointerMenuTiming.clipboardProbe);

      expect(await answer, isTrue);
    });

    testWidgets('without a rich clipboard it asks the platform', (
      tester,
    ) async {
      var has = true;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.hasStrings') {
            return <String, Object?>{'value': has};
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final composer = await mount(tester);

      expect(await composer.canPaste(), isTrue);
      has = false;
      expect(await composer.canPaste(), isFalse);
    });
  });
}
