/// The field's copy, cut and paste go through the composer's clipboard.
///
/// **Seam:** a [ComposerView] over a [ComposerController] with a
/// [FakeRichClipboard], driven by key shortcuts and the selection toolbar.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:composer_editable/composer_editable.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/composer_harness.dart';

final _pastePlain = ChromeStringsPresets.english.composer.pastePlainAction;

final _bold = RichText('bold word', const [Entity(0, 4, EntityKind.bold)]);

void main() {
  late FakeRichClipboard clipboard;
  late ComposerController composer;

  setUp(() {
    clipboard = FakeRichClipboard();
    composer = ComposerController(clipboard: clipboard);
  });
  tearDown(() => composer.dispose());

  Future<void> show(
    WidgetTester tester, {
    ComposerController? controller,
  }) async {
    final shown = controller ?? composer;
    await tester.pumpWidget(
      composerHarness(
        ComposerView(
          controller: shown,
          spec: ComposerSpec(),
          shortcuts: const ComposerShortcutPolicy.desktop().shortcuts,
        ),
      ),
    );
    shown.requestFocus();
    await tester.pump();
  }

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool shift = false,
  }) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  group('shortcuts', () {
    testWidgets('copy puts the selection on the clipboard with its entities', (
      tester,
    ) async {
      await show(tester);
      composer
        ..restore(_bold)
        ..select(const TextSelection(baseOffset: 0, extentOffset: 6));
      await tester.pump();

      await press(tester, LogicalKeyboardKey.keyC);

      expect(
        (await clipboard.read())!.rich,
        RichText('bold w', const [Entity(0, 4, EntityKind.bold)]),
      );
    });

    testWidgets('cut removes the selection', (tester) async {
      await show(tester);
      composer
        ..restore(_bold)
        ..select(const TextSelection(baseOffset: 0, extentOffset: 5));
      await tester.pump();

      await press(tester, LogicalKeyboardKey.keyX);

      expect(composer.richText, const RichText.plain('word'));
      expect((await clipboard.read())!.plain, 'bold ');
    });

    testWidgets('paste inserts the rich text', (tester) async {
      await clipboard.write(_bold);
      await show(tester);

      await press(tester, LogicalKeyboardKey.keyV);

      expect(composer.richText, _bold);
    });

    testWidgets('Shift with paste inserts the plain text', (tester) async {
      await clipboard.write(_bold);
      await show(tester);

      await press(tester, LogicalKeyboardKey.keyV, shift: true);

      expect(composer.richText, const RichText.plain('bold word'));
    });
  });

  group('selection toolbar', () {
    setUp(() {
      // The toolbar offers Paste while the platform says it has text.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            SystemChannels.platform,
            (call) async => call.method == 'Clipboard.hasStrings'
                ? <String, Object?>{'value': true}
                : null,
          );
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    Future<void> openToolbar(WidgetTester tester) async {
      tester
          .state<ExtendedEditableTextState>(find.byType(ExtendedEditableText))
          .showToolbar();
      await tester.pumpAndSettle();
    }

    testWidgets('Copy goes through the clipboard', (tester) async {
      await show(tester);
      composer
        ..restore(_bold)
        ..select(const TextSelection(baseOffset: 0, extentOffset: 4));
      await tester.pump();
      await openToolbar(tester);

      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(
        (await clipboard.read())!.rich,
        RichText('bold', const [Entity(0, 4, EntityKind.bold)]),
      );
    });

    testWidgets('Paste and Paste as plain text go through the clipboard', (
      tester,
    ) async {
      await clipboard.write(_bold);
      await show(tester);
      await openToolbar(tester);

      await tester.tap(find.text('Paste'));
      await tester.pumpAndSettle();
      expect(composer.richText, _bold);

      composer.select(const TextSelection.collapsed(offset: 9));
      await openToolbar(tester);
      await tester.tap(find.text(_pastePlain));
      await tester.pumpAndSettle();
      expect(composer.richText.plain, 'bold wordbold word');
      expect(composer.richText.entities, hasLength(1));
    });

    testWidgets('has no plain-text paste without a clipboard', (tester) async {
      final bare = ComposerController();
      addTearDown(bare.dispose);
      await show(tester, controller: bare);
      await openToolbar(tester);

      expect(find.text('Paste'), findsOneWidget);
      expect(find.text(_pastePlain), findsNothing);
    });
  });

  testWidgets('an image a keyboard inserts goes to the host', (tester) async {
    final received = <List<PastedMedia>>[];
    final withHost = ComposerController(
      onPastedMedia: (media) async {
        received.add(media);
        return true;
      },
    );
    addTearDown(withHost.dispose);
    await show(tester, controller: withHost);

    // What the platform sends when a keyboard commits a GIF (Android).
    final message = const JSONMessageCodec().encodeMessage(<String, Object?>{
      'args': <Object?>[
        -1,
        'TextInputAction.commitContent',
        <String, Object?>{
          'mimeType': 'image/gif',
          'data': <int>[0, 1, 0, 1],
          'uri': 'content://keyboard/a.gif',
        },
      ],
      'method': 'TextInputClient.performAction',
    });
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/textinput',
      message,
      (_) {},
    );
    await tester.pump();

    final media = received.single.single as PastedMedia$Bytes;
    expect(media.mimeType, 'image/gif');
    expect(media.bytes, [0, 1, 0, 1]);
  });
}
