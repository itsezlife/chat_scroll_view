import 'package:chatscrollview/src/chat_message.dart';
import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chatscrollview/src/chat_widgets/chat_scroll_view.dart';
import 'package:chatscrollview/src/chat_widgets/demo/demo_last_read_store.dart';
import 'package:chatscrollview/src/chat_widgets/demo/new_messages_pill.dart';
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

IChatMessage _msg(int i) => UserChatMessage(
  id: i,
  sender: 'User',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: 'content $i',
);

class _PreloadedDataSource extends ChatDataSource {
  _PreloadedDataSource(this.count, {Set<int> omitIds = const {}}) {
    for (var i = 0; i < count; i++) {
      if (!omitIds.contains(i)) {
        upsertMessage(_msg(i));
      }
    }
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: count - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
  }

  final int count;

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

/// Metadata-only at connect — like [BackendChatDataSource.connect] before the
/// first [fetchRange]; exercises open-anchor resolution without cached bodies.
class _MetadataOnlyDataSource extends ChatDataSource {
  _MetadataOnlyDataSource(this.count) {
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: count - 1,
      reachedNewest: true,
    );
  }

  final int count;

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

const _viewportWidth = 400.0;
const _viewportHeight = 600.0;

Widget _harness({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  bool reverse = true,
  ValueListenable<double>? bottomPadding,
  ValueNotifier<int?>? lastSeenNewestId,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: _viewportWidth,
          height: _viewportHeight,
          child: Stack(
            children: <Widget>[
              ChatScrollView(
                reverse: reverse,
                dataSource: dataSource,
                controller: controller,
                bottomPadding: bottomPadding,
                messageBuilder: (context, id, message, status) => SizedBox(
                  height: 60,
                  child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
                ),
              ),
              NewMessagesPill(
                controller: controller,
                dataSource: dataSource,
                bottomInset: bottomPadding,
                lastSeenNewestId: lastSeenNewestId,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

String _pillText(WidgetTester tester) {
  final txt = tester.widget<Text>(
    find.descendant(
      of: find.byType(NewMessagesPill),
      matching: find.byType(Text),
    ),
  );
  return txt.data ?? '';
}

int _openAnchor({required ChatDataSource ds, int? storedLastRead}) {
  return resolveOpenAnchor(
    storedLastRead: storedLastRead,
    newestKnownId: ds.newestKnownId,
    oldestKnownId: ds.oldestKnownId,
    getMessage: ds.getMessage,
  );
}

void main() {
  group('open at last read', () {
    test(
      'stored last-read before any messages loaded resolves to stored id',
      () {
        const count = 10004;
        const lastRead = 9950;
        final ds = _MetadataOnlyDataSource(count);
        addTearDown(ds.dispose);

        final anchor = resolveOpenAnchor(
          storedLastRead: lastRead,
          newestKnownId: ds.newestKnownId,
          oldestKnownId: ds.oldestKnownId,
          getMessage: ds.getMessage,
        );
        expect(anchor, lastRead);
      },
    );

    testWidgets('open at stored last-read anchors off tail', (tester) async {
      const count = 100;
      const lastRead = 40;
      final newest = count - 1;
      final ds = _PreloadedDataSource(count);
      final anchor = _openAnchor(ds: ds, storedLastRead: lastRead);
      expect(anchor, lastRead);

      final controller = ChatScrollController()..jumpTo(anchor);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await tester.pump();

      expect(controller.anchorMessageId, lastRead);
      expect(controller.isAtTail.value, isFalse);
      expect(find.text('msg-$newest'), findsNothing);
      expect(find.text('msg-$lastRead'), findsOneWidget);
    });

    testWidgets('first visit with no stored last-read opens at newest', (
      tester,
    ) async {
      const count = 100;
      final newest = count - 1;
      final ds = _PreloadedDataSource(count);
      final anchor = _openAnchor(ds: ds);
      expect(anchor, newest);

      final controller = ChatScrollController()..jumpTo(anchor);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _harness(dataSource: ds, controller: controller, reverse: true),
      );
      await tester.pump();

      expect(controller.anchorMessageId, newest);
      expect(controller.isAtTail.value, isTrue);
    });

    testWidgets('pill shows unread count on last-read open', (tester) async {
      const count = 151;
      const lastRead = 50;
      final ds = _PreloadedDataSource(count);
      final anchor = _openAnchor(ds: ds, storedLastRead: lastRead);

      final controller = ChatScrollController()..jumpTo(anchor);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      final lastSeen = ValueNotifier<int?>(lastRead);
      addTearDown(lastSeen.dispose);

      await tester.pumpWidget(
        _harness(
          dataSource: ds,
          controller: controller,
          lastSeenNewestId: lastSeen,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(_pillText(tester), '100 new messages');
    });

    testWidgets('pill tap jumps to newest', (tester) async {
      const count = 100;
      const lastRead = 40;
      final newest = count - 1;
      final ds = _PreloadedDataSource(count);
      final anchor = _openAnchor(ds: ds, storedLastRead: lastRead);
      final inset = ValueNotifier<double>(96);
      final lastSeen = ValueNotifier<int?>(lastRead);

      final controller = ChatScrollController()..jumpTo(anchor);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      addTearDown(inset.dispose);
      addTearDown(lastSeen.dispose);

      await tester.pumpWidget(
        _harness(
          dataSource: ds,
          controller: controller,
          bottomPadding: inset,
          lastSeenNewestId: lastSeen,
        ),
      );
      await tester.pump();
      expect(controller.isAtTail.value, isFalse);

      await tester.tap(
        find.descendant(
          of: find.byType(NewMessagesPill),
          matching: find.byType(InkWell),
        ),
      );
      await tester.pump();
      expect(_pillText(tester), isNot('0 new messages'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(_pillText(tester), isNot('0 new messages'));
      }
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();

      expect(controller.isAtTail.value, isTrue);
      expect(controller.anchorMessageId, newest);
      expect(find.text('shimmer-$count'), findsNothing);
      expect(_pillText(tester), '0 new messages');
    });

    testWidgets('isAtTail persists newest to store', (tester) async {
      const count = 100;
      const lastRead = 40;
      final newest = count - 1;
      final ds = _PreloadedDataSource(count);
      final anchor = _openAnchor(ds: ds, storedLastRead: lastRead);

      final controller = ChatScrollController()..jumpTo(anchor);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      final lastSeen = ValueNotifier<int?>(lastRead);
      addTearDown(lastSeen.dispose);

      await tester.pumpWidget(
        _harness(
          dataSource: ds,
          controller: controller,
          lastSeenNewestId: lastSeen,
        ),
      );
      await tester.pump();

      controller.jumpTo(newest);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(lastSeen.value, newest);
    });

    testWidgets('reopen after caught up lands at newest', (tester) async {
      const count = 100;
      final newest = count - 1;
      final ds = _PreloadedDataSource(count);

      final anchor = _openAnchor(ds: ds, storedLastRead: newest);
      expect(anchor, newest);

      final controller = ChatScrollController()..jumpTo(anchor);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(controller.anchorMessageId, newest);
      expect(controller.isAtTail.value, isTrue);
      expect(_pillText(tester), '0 new messages');
    });

    testWidgets('new messages off-tail increase unread count', (tester) async {
      const count = 100;
      const lastRead = 40;
      final ds = _PreloadedDataSource(count);
      final anchor = _openAnchor(ds: ds, storedLastRead: lastRead);

      final controller = ChatScrollController()..jumpTo(anchor);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      final lastSeen = ValueNotifier<int?>(lastRead);
      addTearDown(lastSeen.dispose);

      await tester.pumpWidget(
        _harness(
          dataSource: ds,
          controller: controller,
          lastSeenNewestId: lastSeen,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(_pillText(tester), '59 new messages');

      ds.upsertMessage(_msg(100));
      ds.upsertMessage(_msg(101));
      ds.seedBoundaries(newestKnownId: 101);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(_pillText(tester), '61 new messages');
    });

    testWidgets('deleted last-read anchors at previous surviving message', (
      tester,
    ) async {
      const count = 100;
      const deletedId = 50;
      final ds = _PreloadedDataSource(count, omitIds: {deletedId});

      final anchor = resolveOpenAnchor(
        storedLastRead: deletedId,
        newestKnownId: ds.newestKnownId,
        oldestKnownId: ds.oldestKnownId,
        getMessage: ds.getMessage,
      );
      expect(anchor, deletedId - 1);

      final controller = ChatScrollController()..jumpTo(anchor);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await tester.pump();

      expect(controller.anchorMessageId, deletedId - 1);
    });

    testWidgets('stored past newest clamps to newest', (tester) async {
      const count = 100;
      final newest = count - 1;
      final ds = _PreloadedDataSource(count);

      final anchor = resolveOpenAnchor(
        storedLastRead: newest + 10,
        newestKnownId: ds.newestKnownId,
        oldestKnownId: ds.oldestKnownId,
        getMessage: ds.getMessage,
      );
      expect(anchor, newest);

      final controller = ChatScrollController()..jumpTo(anchor);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await tester.pump();

      expect(controller.anchorMessageId, newest);
      expect(controller.isAtTail.value, isTrue);
    });

    testWidgets('stored before oldest clamps to oldest', (tester) async {
      const count = 100;
      final ds = _PreloadedDataSource(count);

      final anchor = resolveOpenAnchor(
        storedLastRead: -5,
        newestKnownId: ds.newestKnownId,
        oldestKnownId: ds.oldestKnownId,
        getMessage: ds.getMessage,
      );
      expect(anchor, 0);

      final controller = ChatScrollController()..jumpTo(anchor);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(_harness(dataSource: ds, controller: controller));
      await tester.pump();

      expect(controller.anchorMessageId, 0);
    });
  });
}
