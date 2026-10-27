import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind, kLongPressTimeout, kPressTimeout, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_md/flutter_md.dart';
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
    seedBoundaries(oldestKnownId: ids.first, newestKnownId: ids.last, reachedOldest: true, reachedNewest: true);
  }

  @override
  Future<List<IChatMessage>> fetchRange({required int fromId, required int toId}) async => const <IChatMessage>[];
}

const _thumb = '\u{1F44D}';
const _heart = '\u{2764}\u{FE0F}';
const _party = '\u{1F389}';
const _fire = '\u{1F525}';
const _grin = '\u{1F600}';
const _pack = ContentKey.document('thumb-sticker');
const _custom = ContentKey.document('5368');

/// Characters: 👍 [0,2) ❤️ [2,4) 🎉 [4,6), a break, 🔥 [7,9) 😀 [9,11). Three
/// items on the first line and two on the second.
final _text = EmojiOnly(const [
  EmojiOnlyItem(ContentKey.unicode(_thumb)),
  EmojiOnlyItem(ContentKey.unicode(_heart)),
  EmojiOnlyItem(ContentKey.unicode(_party)),
  EmojiOnlyItem(ContentKey.unicode(_fire), lineBreaksBefore: 1),
  EmojiOnlyItem(ContentKey.unicode(_grin)),
]);

/// A custom emoji between two unicode ones.
final _mixed = EmojiOnly(const [
  EmojiOnlyItem(ContentKey.unicode(_thumb)),
  EmojiOnlyItem(_custom, alt: _party),
  EmojiOnlyItem(ContentKey.unicode(_grin)),
]);

final _single = EmojiOnly(const [EmojiOnlyItem(ContentKey.unicode(_thumb))]);

/// The text selection of the emoji-only body (ticket 03 of chat-polish-3),
/// through the real host path: [ChatEmojiBody] in a [ChatScrollView], the
/// viewport's selection pointer, the per-body markdown scope and the facade.
///
/// **Seams:** the facade (`textSelection`, `copyTextSelection`,
/// `ChatTextCopy`, `surfaceFor`), the real pointer events, the widget tree.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ChatScrollController controller;
  late List<ChatTextCopy> copies;
  late List<ChatSelectionInteraction> interactions;
  late List<int> idleTaps;
  late List<int> menus;

  setUp(() {
    controller = ChatScrollController();
    copies = [];
    interactions = [];
    idleTaps = [];
    menus = [];
  });
  tearDown(() => controller.dispose());

  ChatSelectionController newSelection(ChatSelectionPolicy policy, {bool handlesEmbedHits = false}) {
    final selection = ChatSelectionController(
      policy: policy,
      handlesEmbedHits: handlesEmbedHits,
      onInteraction: interactions.add,
      copyWriter: (copy) async => copies.add(copy),
    );
    addTearDown(selection.dispose);
    return selection;
  }

  /// The chat of three messages: 1 is [first], 2 a markdown body, 3 the
  /// sticker layout of one emoji.
  Future<void> pump(WidgetTester tester, ChatSelectionController selection, {EmojiOnly? first}) async {
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    selection.putBody(2, Markdown.fromString('Plain markdown message'));
    final dataSource = _LoadedSource([_msg(1), _msg(2), _msg(3)]);
    addTearDown(dataSource.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: debugDefaultTargetPlatformOverride),
        home: Scaffold(
          body: ChatScrollView(
            dataSource: dataSource,
            controller: controller,
            selectionController: selection,
            onIdleMessageTap: (request) => idleTaps.add(request.messageId),
            onSecondaryMessageTap: (request) => menus.add(request.messageId),
            messageBuilder: (context, id, message, status, runLayout) => switch (id) {
              1 => Align(
                alignment: Alignment.centerLeft,
                child: ChatEmojiBody(
                  key: const ValueKey('emoji-1'),
                  controller: selection,
                  messageId: 1,
                  emojiOnly: first ?? _text,
                  embedFactory: (_, _) => null,
                ),
              ),
              2 => Container(
                padding: const EdgeInsets.all(12),
                child: ChatMarkdownBody(key: const ValueKey('md-2'), controller: selection, messageId: 2),
              ),
              _ => Align(
                alignment: Alignment.centerLeft,
                child: ChatEmojiBody(
                  key: const ValueKey('emoji-3'),
                  controller: selection,
                  messageId: 3,
                  emojiOnly: _single,
                  sticker: _pack,
                  embedFactory: (_, _) => null,
                ),
              ),
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Global rect of the item holding characters `[from, to)` of message 1.
  Rect itemRect(ChatSelectionController selection, int from, int to, {int messageId = 1}) {
    final surface = selection.surfaceFor(messageId)!;
    final boxes = surface.localBoxesForRange(0, from, to);
    final first = boxes.first;
    final last = boxes.last;
    return (surface as RenderBox).localToGlobal(first.topLeft) & Size(last.right - first.left, first.height);
  }

  Offset leading(Rect rect) => rect.centerLeft + const Offset(3, 0);
  Offset trailing(Rect rect) => rect.centerRight - const Offset(3, 0);

  String? selectedText(ChatSelectionController selection) =>
      selection.isTextSelectionActive ? selection.markdownSelection.getText() : null;

  Future<TestGesture> mouse(WidgetTester tester, Offset at) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse, pointer: 1);
    await gesture.addPointer(location: at);
    addTearDown(gesture.removePointer);
    return gesture;
  }

  void desktopTest(String name, Future<void> Function(WidgetTester, ChatSelectionController) body) =>
      testWidgets('desktop: $name', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          await body(tester, newSelection(const ChatSelectionPolicy.desktop()));
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

  void mobileTest(String name, Future<void> Function(WidgetTester, ChatSelectionController) body) =>
      testWidgets('mobile: $name', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        try {
          await body(tester, newSelection(const ChatSelectionPolicy.mobile()));
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

  group('the text layout is a text body of the facade', () {
    desktopTest('it registers a model the facade can copy from', (tester, selection) async {
      await pump(tester, selection);

      expect(selection.hasBody(1), isTrue);
      expect(selection.surfaceFor(1), isNotNull);
      expect(selection.surfaceFor(1)!.documentId, 1);
    });

    desktopTest('the sticker layout registers no text', (tester, selection) async {
      await pump(tester, selection);

      expect(selection.hasBody(3), isFalse);
      expect(selection.surfaceFor(3), isNull);
    });
  });

  group('desktop selection', () {
    desktopTest('a drag across several emoji selects them', (tester, selection) async {
      await pump(tester, selection);
      final start = leading(itemRect(selection, 0, 2));
      final end = trailing(itemRect(selection, 4, 6));
      final pointer = await mouse(tester, start);

      await pointer.down(start);
      await pointer.moveTo(start + const Offset(30, 0));
      await pointer.moveTo(end);
      await pointer.up();
      await tester.pump();

      expect(selection.textSelectionSubject, 1);
      expect(selectedText(selection), '$_thumb$_heart$_party');
    });

    desktopTest('a partial range starts and ends on item edges', (tester, selection) async {
      await pump(tester, selection);
      final start = trailing(itemRect(selection, 0, 2));
      final end = trailing(itemRect(selection, 2, 4));
      final pointer = await mouse(tester, start);

      await pointer.down(start);
      await pointer.moveTo(start + const Offset(10, 0));
      await pointer.moveTo(end);
      await pointer.up();
      await tester.pump();

      // The press was on the trailing half of the first item: it is not in.
      expect(selectedText(selection), _heart);
      final range = selection.textSelection!;
      expect(range.base.offset, 2);
      expect(range.extent.offset, 4);
    });

    desktopTest('a drag across lines selects the break between them', (tester, selection) async {
      await pump(tester, selection);
      final start = leading(itemRect(selection, 4, 6));
      final end = trailing(itemRect(selection, 7, 9));
      final pointer = await mouse(tester, start);

      await pointer.down(start);
      await pointer.moveTo(start + const Offset(0, 10));
      await pointer.moveTo(end);
      await pointer.up();
      await tester.pump();

      expect(selectedText(selection), '$_party\n$_fire');
    });

    desktopTest('a double click selects one emoji, not the run', (tester, selection) async {
      await pump(tester, selection);
      final at = itemRect(selection, 2, 4).center;
      final pointer = await mouse(tester, at);

      await pointer.down(at);
      await pointer.up();
      await tester.pump(const Duration(milliseconds: 50));
      await pointer.down(at);
      await pointer.up();
      await tester.pump();

      expect(selectedText(selection), _heart);
    });

    desktopTest('select all takes every item and the break', (tester, selection) async {
      await pump(tester, selection);
      final at = itemRect(selection, 0, 2).center;
      final pointer = await mouse(tester, at);
      await pointer.down(at);
      await pointer.up();
      await tester.pump();

      expect(selection.selectAllText(), isTrue);

      expect(selectedText(selection), '$_thumb$_heart$_party\n$_fire$_grin');
    });

    desktopTest('a selection is one message: a drag onto another stays', (tester, selection) async {
      await pump(tester, selection);
      final start = leading(itemRect(selection, 0, 2));
      final pointer = await mouse(tester, start);
      final other = tester.getCenter(find.byType(MarkdownWidget));

      await pointer.down(start);
      await pointer.moveTo(start + const Offset(20, 0));
      await pointer.moveTo(other);
      await pointer.up();
      await tester.pump();

      expect(selection.textSelectionSubject, 1);
      expect(selection.textSelection!.extent.documentId, 1);
    });

    desktopTest('copy writes the emoji, plain and structured', (tester, selection) async {
      await pump(tester, selection, first: _mixed);
      final start = leading(itemRect(selection, 0, 2));
      final end = trailing(itemRect(selection, 4, 6));
      final pointer = await mouse(tester, start);
      await pointer.down(start);
      await pointer.moveTo(start + const Offset(30, 0));
      await pointer.moveTo(end);
      await pointer.up();
      await tester.pump();

      expect(await selection.copyTextSelection(), isTrue);

      final copy = copies.single;
      expect(copy.plainText, '$_thumb$_party$_grin');
      expect(copy.messageId, 1);
      final paragraph = copy.content!.documents.single.blocks.single.block as MD$Paragraph;
      final image = paragraph.spans.singleWhere((span) => span.style.contains(MD$Style.image));
      expect(image.extra?['src'], _custom.encoded);
      expect(image.text, _party);
    });

    desktopTest('the sticker layout cannot start a text selection', (tester, selection) async {
      await pump(tester, selection);
      final rect = selection.stickerRectOf(3)!;
      final start = rect.center - const Offset(20, 0);
      final pointer = await mouse(tester, start);

      await pointer.down(start);
      await pointer.moveTo(start + const Offset(10, 0));
      await pointer.moveTo(start + const Offset(40, 0));
      await pointer.up();
      await tester.pump();

      expect(selection.isTextSelectionActive, isFalse);
      expect(selection.textSelection, isNull);
    });

    desktopTest('the hover cursor over an emoji is the I-beam', (tester, selection) async {
      await pump(tester, selection);
      final on = itemRect(selection, 2, 4).center;
      final pointer = await mouse(tester, const Offset(300, 300));

      await pointer.moveTo(on);
      await tester.pump();

      expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.text);
    });

    desktopTest('a click on a custom emoji the host handles is its tap', (tester, selection) async {
      final handling = newSelection(const ChatSelectionPolicy.desktop(), handlesEmbedHits: true);
      await pump(tester, handling, first: _mixed);
      final at = itemRect(handling, 2, 4).center;
      final pointer = await mouse(tester, at);

      await pointer.down(at);
      await pointer.up();
      await tester.pump();

      expect(interactions.whereType<ChatEmbedActivated>(), hasLength(1));
      expect(handling.hasTextSelectionOnMessage(1), isFalse);
    });

    desktopTest('a drag that starts on a custom emoji nobody handles still '
        'selects', (tester, selection) async {
      await pump(tester, selection, first: _mixed);
      final start = leading(itemRect(selection, 2, 4));
      final end = trailing(itemRect(selection, 4, 6));
      final pointer = await mouse(tester, start);

      await pointer.down(start);
      await pointer.moveTo(start + const Offset(10, 0));
      await pointer.moveTo(end);
      await pointer.up();
      await tester.pump();

      expect(selectedText(selection), '$_party$_grin');
    });

    desktopTest('a press on another message takes the subject over', (tester, selection) async {
      await pump(tester, selection);
      final on = itemRect(selection, 0, 2).center;
      final pointer = await mouse(tester, on);
      await pointer.down(on);
      await pointer.up();
      await tester.pump();
      final md = tester.getCenter(find.byType(MarkdownWidget));

      await pointer.moveTo(md);
      await pointer.down(md);
      await pointer.moveTo(md + const Offset(30, 0));
      await pointer.up();
      await tester.pump();

      expect(selection.textSelectionSubject, 2);
    });

    desktopTest('after a drag in the emoji row the other rows stay live '
        '(the stuck-pointer rule of ADR 012)', (tester, selection) async {
      await pump(tester, selection);
      final start = leading(itemRect(selection, 0, 2));
      final end = trailing(itemRect(selection, 4, 6));
      final md = tester.getCenter(find.byType(MarkdownWidget));
      final pointer = await mouse(tester, start);
      await pointer.down(start);
      await pointer.moveTo(start + const Offset(30, 0));
      await pointer.moveTo(end);
      await pointer.up();
      await tester.pump();

      // The I-beam over the markdown text, with no click elsewhere or Esc.
      await pointer.moveTo(md);
      await tester.pump();
      expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.text);
    });

    desktopTest('a secondary click on an emoji reaches the menu with no '
        'selection started', (tester, selection) async {
      await pump(tester, selection);
      final at = itemRect(selection, 2, 4).center;
      final secondary = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await secondary.addPointer(location: at);
      addTearDown(secondary.removePointer);

      await secondary.down(at);
      await secondary.up();
      await tester.pump();

      expect(menus, [1]);
      expect(selection.hasTextSelectionOnMessage(1), isFalse);
    });
  });

  group('mobile selection', () {
    mobileTest('a long press on a message selected before selects one emoji, '
        'with handles and the toolbar', (tester, selection) async {
      await pump(tester, selection);
      selection.startSelection(1);
      await tester.pumpAndSettle();

      final at = itemRect(selection, 2, 4).center;
      final gesture = await tester.startGesture(at);
      await tester.pump(kLongPressTimeout + kPressTimeout);
      await tester.pump();
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(selection.textSelectionSubject, 1);
      expect(selectedText(selection), _heart);
      expect(find.byType(CompositedTransformFollower), findsNWidgets(2));
      expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
    });

    mobileTest('the first long press is message selection, never text', (tester, selection) async {
      await pump(tester, selection);

      await tester.longPressAt(itemRect(selection, 0, 2).center);
      await tester.pumpAndSettle();

      expect(selection.isSelected(1), isTrue);
      expect(selection.isTextSelectionActive, isFalse);
    });

    mobileTest('moving the end edge extends the range by items', (tester, selection) async {
      await pump(tester, selection);
      selection.startSelection(1);
      await tester.pumpAndSettle();
      final at = itemRect(selection, 0, 2).center;
      final press = await tester.startGesture(at);
      await tester.pump(kLongPressTimeout + kPressTimeout);
      await tester.pump();
      await tester.pump();
      await press.up();
      await tester.pumpAndSettle();
      expect(selectedText(selection), _thumb);

      // What a handle drag does: move one edge to the global point.
      selection.markdownSelection.moveSelectionEdgeToGlobal(trailing(itemRect(selection, 4, 6)), isStart: false);
      await tester.pumpAndSettle();

      expect(selectedText(selection), '$_thumb$_heart$_party');
    });

    mobileTest('dragging the start handle onto the end of the last emoji '
        'keeps both handles on item edges', (tester, selection) async {
      // Ticket 49: the edge landed on the fixed end, the controller stepped
      // it back one code unit, into the surrogate pair of the last emoji, and
      // placing the handle there threw a RangeError.
      await pump(
        tester,
        selection,
        first: EmojiOnly(const [EmojiOnlyItem(ContentKey.unicode(_thumb)), EmojiOnlyItem(ContentKey.unicode(_grin))]),
      );
      selection.startSelection(1);
      await tester.pumpAndSettle();
      final at = itemRect(selection, 2, 4).center;
      final press = await tester.startGesture(at);
      await tester.pump(kLongPressTimeout + kPressTimeout);
      await tester.pump();
      await tester.pump();
      await press.up();
      await tester.pumpAndSettle();
      expect(selectedText(selection), _grin);

      selection.markdownSelection.moveSelectionEdgeToGlobal(trailing(itemRect(selection, 2, 4)), isStart: true);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Each handle sits on an edge of the emoji, wherever the controller
      // left the moved edge.
      final handles = selection.markdownSelection.selectionHandleEndpoints()!;
      final grin = itemRect(selection, 2, 4);
      final edges = [grin.left, grin.right];
      expect(edges, contains(moreOrLessEquals(handles.startGlobal.left)));
      expect(edges, contains(moreOrLessEquals(handles.endGlobal.left)));
    });

    mobileTest('copy writes the emoji', (tester, selection) async {
      await pump(tester, selection);
      selection.startSelection(1);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(itemRect(selection, 4, 6).center);
      await tester.pump(kLongPressTimeout + kPressTimeout);
      await tester.pump();
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(await selection.copyTextSelection(), isTrue);

      expect(copies.single.plainText, _party);
    });

    mobileTest('the sticker layout never enters text selection', (tester, selection) async {
      await pump(tester, selection);
      selection.startSelection(3);
      await tester.pumpAndSettle();
      final rect = selection.stickerRectOf(3)!;

      final gesture = await tester.startGesture(rect.center);
      await tester.pump(kLongPressTimeout + kPressTimeout);
      await tester.pump();
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(selection.isTextSelectionActive, isFalse);
      expect(selection.textSelection, isNull);
    });
  });

  group('the host can keep the reference clients\' rule', () {
    desktopTest('selectableText: false is a non-text body', (tester, selection) async {
      tester.view
        ..physicalSize = const Size(400, 800)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final dataSource = _LoadedSource([_msg(1)]);
      addTearDown(dataSource.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          home: Scaffold(
            body: ChatScrollView(
              dataSource: dataSource,
              controller: controller,
              selectionController: selection,
              messageBuilder: (context, id, message, status, runLayout) => Align(
                alignment: Alignment.centerLeft,
                child: ChatEmojiBody(
                  controller: selection,
                  messageId: id,
                  emojiOnly: _text,
                  selectableText: false,
                  embedFactory: (_, _) => null,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(selection.hasBody(1), isFalse);
    });
  });
}
