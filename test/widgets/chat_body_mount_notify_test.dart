import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/material.dart';
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
  _LoadedSource(int count) {
    upsertMessages([for (var i = 0; i < count; i++) _msg(i)]);
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: count - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
    for (final chunk in loadedChunks) {
      chunk.status = ChatMessageStatus.valid;
    }
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

/// A markdown body that mounts or unmounts changes nothing the selection
/// facade exposes while no text is selected, so it must not notify: every
/// listener is the chrome of a mounted row, and one notification per row a
/// scroll brings in rebuilt all of them on the next frame (finding 03).
void main() {
  const count = 200;

  Future<ChatSelectionController> pump(
    WidgetTester tester,
    ChatSelectionPolicy policy,
  ) async {
    final dataSource = _LoadedSource(count);
    final controller = ChatScrollController()..jumpTo(count ~/ 2);
    final selection = ChatSelectionController(policy: policy);
    addTearDown(controller.dispose);
    addTearDown(selection.dispose);
    addTearDown(dataSource.dispose);
    for (var i = 0; i < count; i++) {
      selection.putBody(i, Markdown.fromString('Hello selectable world $i'));
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: SizedBox(
            width: 400,
            height: 600,
            child: ChatScrollView(
              dataSource: dataSource,
              controller: controller,
              selectionController: selection,
              messageBuilder: (context, id, message, status, runLayout) =>
                  Container(
                    height: 80,
                    padding: const EdgeInsets.all(12),
                    color: Colors.white,
                    child: ChatMarkdownBody(
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
    return selection;
  }

  /// Notifications of [selection] while a fling mounts and unmounts bodies,
  /// and how many bodies it mounted.
  Future<({int notifications, int mounted})> fling(
    WidgetTester tester,
    ChatSelectionController selection,
  ) async {
    final before = {
      for (var i = 0; i < count; i++)
        if (selection.surfaceFor(i) != null) i,
    };
    var notifications = 0;
    void onNotify() => notifications++;
    selection.addListener(onNotify);
    addTearDown(() => selection.removeListener(onNotify));
    await tester.fling(find.byType(ChatScrollView), const Offset(0, 600), 3000);
    await tester.pumpAndSettle();
    final after = {
      for (var i = 0; i < count; i++)
        if (selection.surfaceFor(i) != null) i,
    };
    return (
      notifications: notifications,
      mounted: after.difference(before).length,
    );
  }

  // Desktop direct entry arms the pressed body on pointer down, so a fling
  // there is a text gesture of its own; the idle case is the touch policies'.
  for (final policy in const [
    ChatSelectionPolicy.mobile(),
    ChatSelectionPolicy.textOnly(),
  ]) {
    testWidgets('bodies mounting in a fling do not notify '
        '(${policy.runtimeType})', (tester) async {
      final selection = await pump(tester, policy);
      final result = await fling(tester, selection);
      expect(result.mounted, greaterThan(0), reason: 'the fling mounts rows');
      expect(result.notifications, 0);
    });
  }

  testWidgets('a live text selection still hears bodies mounting', (
    tester,
  ) async {
    final selection = await pump(tester, const ChatSelectionPolicy.desktop());
    final subject = [
      for (var i = 0; i < count; i++)
        if (selection.surfaceFor(i) != null) i,
    ].first;
    expect(selection.enterTextSelection(subject), isTrue);
    await tester.pump();
    final result = await fling(tester, selection);
    expect(result.mounted, greaterThan(0));
    expect(result.notifications, greaterThan(0));
  });
}
