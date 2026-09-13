import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat_message.dart';

/// Red loop for ADR 015 regression: with [ChatMarkdownBody] (scope-armed
/// selected rows), tap must still dismiss text and toggle message membership.
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

Widget _harness({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  required ChatSelectionController selection,
}) => MaterialApp(
  theme: ThemeData(platform: TargetPlatform.iOS),
  home: Scaffold(
    body: SizedBox(
      width: 400,
      height: 600,
      child: ChatScrollView(
        dataSource: dataSource,
        controller: controller,
        selectionController: selection,
        messageBuilder: (context, id, message, status, runLayout) => Container(
          key: ValueKey('row-$id'),
          height: 80,
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
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'tap on selected body dismisses text selection and keeps membership',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final dataSource = _LoadedSource([_msg(1)]);
        final controller = ChatScrollController();
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        selection.putBody(1, Markdown.fromString('Hello selectable world'));

        await tester.pumpWidget(
          _harness(
            dataSource: dataSource,
            controller: controller,
            selection: selection,
          ),
        );
        await tester.pumpAndSettle();

        selection.startSelection(1);
        await tester.pumpAndSettle();
        final global =
            tester.getTopLeft(find.byType(MarkdownWidget)) +
            const Offset(24, 16);
        expect(selection.enterTextSelection(1, globalOffset: global), isTrue);
        await tester.pump();
        await tester.pumpAndSettle();
        expect(selection.isTextSelectionActive, isTrue);
        expect(selection.selectedIds, <int>{1});

        await tester.tapAt(global);
        await tester.pumpAndSettle();

        expect(
          selection.isTextSelectionActive,
          isFalse,
          reason: 'tap must dismiss text selection (viewport idle-tap path)',
        );
        expect(selection.selectedIds, <int>{1});
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'tap on selected body toggles message off when text is inactive',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final dataSource = _LoadedSource([_msg(1)]);
        final controller = ChatScrollController();
        final selection = ChatSelectionController(
          policy: const ChatSelectionPolicy.mobile(),
        );
        addTearDown(controller.dispose);
        addTearDown(selection.dispose);
        addTearDown(dataSource.dispose);

        selection.putBody(1, Markdown.fromString('Hello selectable world'));

        await tester.pumpWidget(
          _harness(
            dataSource: dataSource,
            controller: controller,
            selection: selection,
          ),
        );
        await tester.pumpAndSettle();

        selection.startSelection(1);
        await tester.pumpAndSettle();
        expect(selection.isSelected(1), isTrue);
        expect(selection.isTextSelectionActive, isFalse);

        final global =
            tester.getTopLeft(find.byType(MarkdownWidget)) +
            const Offset(24, 16);

        await tester.tapAt(global);
        await tester.pumpAndSettle();

        expect(
          selection.isSelected(1),
          isFalse,
          reason:
              'tap on selected body must toggle membership off when text '
              'is inactive',
        );
        expect(selection.isSelectionMode, isFalse);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );
}
