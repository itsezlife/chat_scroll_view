/// A host that writes the clipboard itself is handed what the viewport copies.
///
/// **Seam:** [ChatSelectionController] with a `copyWriter`, driven by
/// `copyTextSelection` and `handleInlineHit`, observed through what the writer
/// receives and the platform clipboard staying untouched.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> platformClipboard;
  late List<ChatTextCopy> written;
  late ChatSelectionController selection;

  setUp(() {
    platformClipboard = [];
    written = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') platformClipboard.add(call);
          return null;
        });
    selection = ChatSelectionController(
      policy: const ChatSelectionPolicy.mobile(),
      copyWriter: (copy) async => written.add(copy),
    );
  });
  tearDown(() {
    selection.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('a text selection copy goes to the writer with its structure', () async {
    selection
      ..putBody(1, Markdown.fromString('Hello **bold** world'))
      ..startSelection(1);
    expect(selection.enterTextSelection(1), isTrue);

    expect(await selection.copyTextSelection(), isTrue);

    final copy = written.single;
    expect(copy.plainText, 'Hello bold world');
    expect(copy.origin, ChatCopyOrigin.textSelection);
    expect(copy.messageId, 1);
    final document = copy.content!.documents.single;
    expect(document.documentId, 1);
    expect(document.blocks.single.text, 'Hello bold world');
    expect(platformClipboard, isEmpty);
    // The copy still succeeds as a copy does: selection cleared, notified.
    expect(selection.isTextSelectionActive, isFalse);
  });

  group('a writer that fails', () {
    late List<FlutterErrorDetails> reported;
    late List<ChatSelectionInteraction> interactions;
    late ChatSelectionController failing;

    setUp(() {
      reported = [];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);
      interactions = [];
      failing = ChatSelectionController(
        policy: const ChatSelectionPolicy.mobile(),
        copyWriter: (copy) async => throw Exception('no clipboard'),
      )..addInteractionListener(interactions.add);
      addTearDown(failing.dispose);
    });

    test('makes a text selection copy no copy, reported', () async {
      failing
        ..putBody(1, Markdown.fromString('Some text'))
        ..startSelection(1);
      failing.enterTextSelection(1);

      expect(await failing.copyTextSelection(), isFalse);

      expect(interactions.whereType<ChatCopied>(), isEmpty);
      expect(failing.isTextSelectionActive, isTrue);
      expect(reported.single.library, 'chat_scroll_view');
    });

    test('makes a code tap no copy, reported', () async {
      failing.handleInlineHit(
        const ChatInlineHit.code(messageId: 42, code: 'flutter run'),
      );
      await pumpEventQueue();

      expect(interactions.whereType<ChatCopied>(), isEmpty);
      expect(reported, hasLength(1));
    });
  });

  test('a code tap goes to the writer with its language', () async {
    final interactions = <ChatSelectionInteraction>[];
    selection.addInteractionListener(interactions.add);

    expect(
      selection.handleInlineHit(
        const ChatInlineHit.code(
          messageId: 42,
          code: 'flutter run',
          language: 'bash',
        ),
      ),
      isTrue,
    );

    final copy = written.single;
    expect(copy.plainText, 'flutter run');
    expect(copy.origin, ChatCopyOrigin.codeTap);
    expect(copy.messageId, 42);
    expect(copy.codeLanguage, 'bash');
    expect(copy.content, isNull);
    expect(platformClipboard, isEmpty);
    await pumpEventQueue();
    expect(interactions.single, isA<ChatCopied>());
  });

  test('the live selection\'s structure is there for a host menu', () {
    expect(selection.textSelectionContent(), isNull);

    selection
      ..putBody(1, Markdown.fromString('Some text'))
      ..startSelection(1);
    selection.enterTextSelection(1);

    expect(
      selection.textSelectionContent()!.documents.single.blocks.single.text,
      'Some text',
    );
  });
}
