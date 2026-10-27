import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart'
    show MD$Paragraph, MD$Style, MarkdownSpoilerController;
import 'package:flutter_test/flutter_test.dart';

import '../chat_message.dart';

IChatMessage _msg(int id) => UserChatMessage(
  id: id,
  sender: 'User',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: 'content $id',
);

class _LoadedSource extends ChatDataSource {
  _LoadedSource(List<IChatMessage> messages) {
    upsertMessages(messages);
    final ids = messages.map((m) => m.id).toList()..sort();
    seedBoundaries(
      oldestKnownId: ids.first,
      newestKnownId: ids.last,
      reachedOldest: true,
      reachedNewest: true,
    );
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

/// A text selection over a hidden spoiler does not reveal it, as on Android
/// and Desktop (ADR 037): the selection is made with the spoiler still
/// hidden, a tap still reveals, and the spoiler travels with the copy.
///
/// Through the real host path: [ChatMarkdownBody] in a [ChatScrollView], with
/// real pointer events (a mouse on the desktop policy, a finger on mobile).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Rendered text: `a ` is 0..2, the spoiler `secret` 2..8, ` b` 8..10.
  const body = 'a ||secret|| b';

  late ChatScrollController controller;
  late ChatSelectionController selection;

  setUp(() => controller = ChatScrollController());
  tearDown(() => controller.dispose());

  void spoilerTest(
    String name,
    Future<void> Function(WidgetTester tester) test, {
    required TargetPlatform platform,
    required ChatSelectionPolicy policy,
  }) => testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      selection = ChatSelectionController(policy: policy);
      addTearDown(selection.dispose);
      final dataSource = _LoadedSource([_msg(1), _msg(2)]);
      addTearDown(dataSource.dispose);
      selection
        ..putBody(1, Markdown.fromString(body))
        ..putBody(2, Markdown.fromString('plain second'));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 600,
              child: ChatScrollView(
                dataSource: dataSource,
                controller: controller,
                selectionController: selection,
                messageBuilder: (context, id, message, status, runLayout) =>
                    Container(
                      padding: const EdgeInsets.all(12),
                      color: Colors.white,
                      child: ChatMarkdownBody(
                        key: ValueKey('md-$id'),
                        controller: selection,
                        messageId: id,
                      ),
                    ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await test(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  Offset pointOn(int from, int to) {
    final surface = selection.surfaceFor(1)!;
    final boxes = surface.localBoxesForRange(0, from, to);
    return (surface as RenderBox).localToGlobal(boxes.first.center);
  }

  Future<void> mouseDrag(WidgetTester tester, Offset from, Offset to) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: from);
    await tester.pump();
    await mouse.down(from);
    await mouse.moveTo(to);
    await tester.pump();
    await mouse.up();
    await tester.pumpAndSettle();
  }

  group(r'$Desktop', () {
    void desktopTest(
      String name,
      Future<void> Function(WidgetTester tester) test,
    ) => spoilerTest(
      name,
      test,
      platform: TargetPlatform.macOS,
      policy: const ChatSelectionPolicy.desktop(),
    );

    desktopTest(
      'a mouse drag over the spoiler selects it and leaves it hidden',
      (tester) async {
        await mouseDrag(tester, pointOn(0, 1), pointOn(9, 10));

        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.textSelection!.isCollapsed, isFalse);
        expect(selection.spoilers.isRevealed(1), isFalse);
      },
    );

    desktopTest('a drag that starts on the hidden spoiler selects, no reveal', (
      tester,
    ) async {
      await mouseDrag(tester, pointOn(2, 3), pointOn(9, 10));

      expect(selection.isTextSelectionActive, isTrue);
      expect(selection.textSelection!.isCollapsed, isFalse);
      expect(selection.spoilers.isRevealed(1), isFalse);
    });

    desktopTest('select all leaves the spoiler hidden', (tester) async {
      expect(selection.enterTextSelection(1), isTrue);
      await tester.pumpAndSettle();

      expect(selection.spoilers.isRevealed(1), isFalse);
    });

    desktopTest('the plain text of the selection is the text under it', (
      tester,
    ) async {
      expect(selection.enterTextSelection(1), isTrue);
      await tester.pumpAndSettle();

      // Android puts the characters under a spoiler on the clipboard as they
      // are; the spoiler travels as a style (the structured content below).
      expect(selection.textSelectionPlainText(), 'a secret b');
    });

    desktopTest('the structured copy carries the spoiler of a hidden one', (
      tester,
    ) async {
      await mouseDrag(tester, pointOn(0, 1), pointOn(9, 10));

      final content = selection.textSelectionContent();

      expect(content, isNotNull);
      final block = content!.documents.single.blocks.single.block;
      expect(
        (block as MD$Paragraph).spans
            .where((span) => span.style.contains(MD$Style.spoiler))
            .map((span) => span.text),
        ['secret'],
      );
      expect(selection.spoilers.isRevealed(1), isFalse);
    });

    desktopTest('a click reveals after a selection has ended', (tester) async {
      await mouseDrag(tester, pointOn(0, 1), pointOn(9, 10));
      selection.clearTextSelection();
      await tester.pumpAndSettle();

      await tester.tapAt(pointOn(2, 8), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      expect(selection.spoilers.isRevealed(1), isTrue);
    });

    desktopTest('a click on the hidden spoiler still reveals', (tester) async {
      await tester.tapAt(pointOn(2, 8), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      expect(selection.spoilers.isRevealed(1), isTrue);
    });
  });

  group(r'$Mobile', () {
    void mobileTest(
      String name,
      Future<void> Function(WidgetTester tester) test,
    ) => spoilerTest(
      name,
      test,
      platform: TargetPlatform.android,
      policy: const ChatSelectionPolicy.mobile(),
    );

    mobileTest('select all on a selected message leaves the spoiler hidden', (
      tester,
    ) async {
      selection.startSelection(1);
      await tester.pumpAndSettle();

      expect(selection.enterTextSelection(1), isTrue);
      await tester.pumpAndSettle();

      expect(selection.isTextSelectionActive, isTrue);
      expect(selection.spoilers.isRevealed(1), isFalse);
    });

    mobileTest('a word under the spoiler is selected and stays hidden', (
      tester,
    ) async {
      selection.startSelection(1);
      await tester.pumpAndSettle();

      expect(
        selection.enterTextSelection(1, globalOffset: pointOn(2, 8)),
        isTrue,
      );
      await tester.pumpAndSettle();

      expect(selection.textSelection, isNotNull);
      expect(selection.textSelection!.isCollapsed, isFalse);
      expect(selection.spoilers.isRevealed(1), isFalse);
    });

    mobileTest('a long press on a word, dragged over the spoiler, selects it '
        'hidden', (tester) async {
      selection.startSelection(1);
      await tester.pumpAndSettle();

      final finger = await tester.startGesture(pointOn(0, 1));
      await tester.pump(const Duration(milliseconds: 700));
      await finger.moveTo(pointOn(9, 10));
      await tester.pump();
      await finger.up();
      await tester.pumpAndSettle();

      expect(selection.isTextSelectionActive, isTrue);
      expect(selection.textSelection!.isCollapsed, isFalse);
      expect(
        selection.textSelection!.extent.offset,
        greaterThan(selection.textSelection!.base.offset),
      );
      expect(selection.spoilers.isRevealed(1), isFalse);
    });

    mobileTest('a tap on a hidden spoiler still reveals', (tester) async {
      await tester.tapAt(pointOn(2, 8));
      await tester.pumpAndSettle();

      expect(selection.spoilers.isRevealed(1), isTrue);
    });
  });

  test('a spoiler controller handed in is the facade\'s and survives it', () {
    final mine = MarkdownSpoilerController(animate: false);
    addTearDown(mine.dispose);
    final other = ChatSelectionController(spoilers: mine);

    expect(other.spoilers, same(mine));
    other.dispose();

    // Disposed twice would assert; a live one still answers.
    expect(mine.isRevealed(1), isFalse);
  });
}
