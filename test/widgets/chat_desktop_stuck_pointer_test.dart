import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, kSecondaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

/// Global point over glyph ink of [messageId] at the offsets
/// `[from, to)` of its first block.
Offset _glyphPoint(
  ChatSelectionController selection,
  int messageId, {
  int from = 0,
  int to = 1,
}) {
  final surface = selection.surfaceFor(messageId)!;
  final boxes = surface.localBoxesForRange(0, from, to);
  return (surface as RenderBox).localToGlobal(boxes.first.center);
}

MouseCursor? _cursorUnderMouse() =>
    RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);

/// A pumped desktop chat of three markdown messages, plus the glyph points
/// (read while every body is idle, before any interaction) the probes use.
class _Chat {
  _Chat._(this.selection, this.links, this.menus, this.points);

  final ChatSelectionController selection;
  final List<int> links;
  final List<int> menus;
  final ({Offset text1, Offset linkOn2, Offset text3, Offset text3End}) points;

  static Future<_Chat> pump(WidgetTester tester) async {
    final dataSource = _LoadedSource([_msg(1), _msg(2), _msg(3)]);
    final controller = ChatScrollController();
    final links = <int>[];
    final menus = <int>[];
    final selection = ChatSelectionController(
      policy: const ChatSelectionPolicy.desktop(),
      onInteraction: (i) {
        if (i case ChatLinkActivated(
          :final messageId,
          gesture: ChatInlineGesture.tap,
        )) {
          links.add(messageId);
        }
      },
    );
    addTearDown(controller.dispose);
    addTearDown(selection.dispose);
    addTearDown(dataSource.dispose);

    selection
      ..putBody(1, Markdown.fromString('Alpha message one'))
      ..putBody(2, Markdown.fromString('Beta [link](https://b.example)'))
      ..putBody(3, Markdown.fromString('Gamma message three'));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.macOS),
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: ChatScrollView(
              dataSource: dataSource,
              controller: controller,
              selectionController: selection,
              onSecondaryMessageTap: (request) => menus.add(request.messageId),
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
    return _Chat._(selection, links, menus, (
      text1: _glyphPoint(selection, 1, from: 1, to: 2),
      linkOn2: _glyphPoint(selection, 2, from: 6, to: 7),
      text3: _glyphPoint(selection, 3, from: 1, to: 2),
      text3End: _glyphPoint(selection, 3, from: 8, to: 9),
    ));
  }
}

/// ADR 012 (desktop): a press on another message's text takes the text
/// selection subject over, and hover / inline activation / the secondary
/// menu on other messages stay live no matter what interaction happened
/// before. No click elsewhere or Esc may be needed to "unstick" them.
///
/// Every probe runs on a fresh chat after exactly one interaction, because a
/// probe that clicks (link, drag) is itself a reset and would hide the next
/// probe's failure.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('desktop: an interaction in one message leaves the others live', () {
    // The interactions that arm / drive the per-body desktop scope of one
    // message (the origin), each ending with the pointer released.
    final interactions =
        <String, Future<void> Function(WidgetTester tester, Offset at)>{
          'click': (tester, at) async {
            final mouse = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
              pointer: 1,
            );
            await mouse.addPointer(location: at);
            await mouse.down(at);
            await mouse.up();
            await tester.pump();
            await mouse.removePointer();
          },
          'double click': (tester, at) async {
            final mouse = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
              pointer: 1,
            );
            await mouse.addPointer(location: at);
            await mouse.down(at);
            await mouse.up();
            await tester.pump(const Duration(milliseconds: 50));
            await mouse.down(at);
            await mouse.up();
            await tester.pump();
            await mouse.removePointer();
          },
          'long press': (tester, at) async {
            final mouse = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
              pointer: 1,
            );
            await mouse.addPointer(location: at);
            await mouse.down(at);
            await tester.pump(const Duration(milliseconds: 800));
            await mouse.up();
            await tester.pump();
            await mouse.removePointer();
          },
          'press hold drop': (tester, at) async {
            final mouse = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
              pointer: 1,
            );
            await mouse.addPointer(location: at);
            await mouse.down(at);
            await tester.pump(const Duration(milliseconds: 800));
            await mouse.moveBy(const Offset(40, 0));
            await tester.pump();
            await mouse.up();
            await tester.pump();
            await mouse.removePointer();
          },
          'secondary click': (tester, at) async {
            final mouse = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
              pointer: 1,
              buttons: kSecondaryMouseButton,
            );
            await mouse.addPointer(location: at);
            await mouse.down(at);
            await mouse.up();
            await tester.pump();
            await mouse.removePointer();
          },
        };

    interactions['nothing (control)'] = (tester, at) async {};

    final probes =
        <String, Future<void> Function(WidgetTester tester, _Chat chat)>{
          'hover text of message 3 shows the I-beam': (tester, chat) async {
            final hover = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
              pointer: 1,
            );
            await hover.addPointer(location: chat.points.text1);
            await hover.moveTo(chat.points.text3);
            await tester.pump();
            expect(_cursorUnderMouse(), SystemMouseCursors.text);
            await hover.removePointer();
          },
          'hover link of message 2 shows the click cursor':
              (tester, chat) async {
                final hover = await tester.createGesture(
                  kind: PointerDeviceKind.mouse,
                  pointer: 1,
                );
                await hover.addPointer(location: chat.points.text1);
                await hover.moveTo(chat.points.linkOn2);
                await tester.pump();
                expect(_cursorUnderMouse(), SystemMouseCursors.click);
                await hover.removePointer();
              },
          'click on the link of message 2 activates it': (tester, chat) async {
            final mouse = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
              pointer: 1,
            );
            await mouse.addPointer(location: chat.points.linkOn2);
            await mouse.down(chat.points.linkOn2);
            await mouse.up();
            await tester.pump();
            expect(chat.links, <int>[2]);
            await mouse.removePointer();
          },
          'secondary click on message 3 reaches its menu':
              (tester, chat) async {
                final mouse = await tester.createGesture(
                  kind: PointerDeviceKind.mouse,
                  pointer: 1,
                  buttons: kSecondaryMouseButton,
                );
                await mouse.addPointer(location: chat.points.text3);
                await mouse.down(chat.points.text3);
                await mouse.up();
                await tester.pump();
                expect(chat.menus, <int>[3]);
                await mouse.removePointer();
              },
          'press-drag on message 3 selects its text': (tester, chat) async {
            final mouse = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
              pointer: 1,
            );
            await mouse.addPointer(location: chat.points.text3);
            await mouse.down(chat.points.text3);
            await mouse.moveTo(chat.points.text3End);
            await mouse.up();
            await tester.pump();
            expect(chat.selection.textSelectionSubject, 3);
            expect(chat.selection.textSelection?.isCollapsed, isFalse);
            await mouse.removePointer();
          },
        };

    for (final MapEntry(key: name, value: interact) in interactions.entries) {
      for (final MapEntry(key: probeName, value: probe) in probes.entries) {
        testWidgets('after $name on message 1: $probeName', (tester) async {
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          try {
            final chat = await _Chat.pump(tester);
            await interact(tester, chat.points.text1);
            // No reset: neither a click elsewhere nor Esc.
            chat.links.clear();
            chat.menus.clear();
            await probe(tester, chat);
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        });
      }
    }
  });

  testWidgets('a drag from message 1 over message 3 stays inside message 1', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final chat = await _Chat.pump(tester);
      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        pointer: 1,
      );
      await mouse.addPointer(location: chat.points.text1);
      await mouse.down(chat.points.text1);
      await mouse.moveTo(chat.points.text1 + const Offset(30, 0));
      await mouse.moveTo(chat.points.text3End);
      await mouse.up();
      await tester.pump();

      final range = chat.selection.textSelection;
      expect(chat.selection.textSelectionSubject, 1);
      expect(range, isNotNull);
      expect(range!.base.documentId, 1);
      expect(range.extent.documentId, 1);
      expect(range.isCollapsed, isFalse);
      await mouse.removePointer();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
