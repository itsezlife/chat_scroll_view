import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat_message.dart';

class _LoadedSource extends ChatDataSource {
  _LoadedSource() {
    upsertMessages([
      for (var id = 1; id <= 3; id++)
        UserChatMessage(
          id: id,
          sender: 'User',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          content: 'body $id',
        ),
    ]);
    seedBoundaries(
      oldestKnownId: 1,
      newestKnownId: 3,
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

void main() {
  late ChatSelectionController selection;

  Future<void> pump(WidgetTester tester, {Key? listKey}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatScrollView(
            key: listKey,
            dataSource: _LoadedSource(),
            controller: ChatScrollController(),
            selectionController: selection,
            messageBuilder: (context, id, message, status, run) =>
                ChatMarkdownBody(controller: selection, messageId: id),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Map<int, MarkdownThemeData> themes(WidgetTester tester) => {
    for (final element in find.byType(MarkdownWidget).evaluate())
      element.findAncestorWidgetOfExactType<ChatMarkdownBody>()!.messageId:
          (element.widget as MarkdownWidget).theme!,
  };

  setUp(() {
    selection = ChatSelectionController();
    for (var id = 1; id <= 3; id++) {
      selection.putBody(id, Markdown.fromString('body $id'));
    }
  });
  tearDown(() => selection.dispose());

  testWidgets('bodies with the same inputs share one theme', (tester) async {
    await pump(tester);
    final byId = themes(tester);
    expect(byId, hasLength(3));
    expect(byId[2], same(byId[1]));
    expect(byId[3], same(byId[1]));
  });

  testWidgets('a body that comes back gets the theme it had', (tester) async {
    await pump(tester, listKey: const Key('first'));
    final before = themes(tester)[1];
    // A new list: every body is mounted anew.
    await pump(tester, listKey: const Key('second'));
    expect(themes(tester)[1], same(before));
  });

  testWidgets('a selected body has a theme of its own', (tester) async {
    await pump(tester);
    selection.startSelection(2);
    await tester.pumpAndSettle();
    final byId = themes(tester);
    // Its tables stop panning; the other bodies keep theirs.
    expect(byId[2], isNot(same(byId[1])));
    expect(byId[3], same(byId[1]));
  });
}
