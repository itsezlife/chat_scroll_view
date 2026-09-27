// ignore_for_file: implementation_imports
import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_events.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_sender_run_layout.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/controller/unread_boundary_controller.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_data_source_extension.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/unread_boundary_sender_run_layout.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/scroll_to_bottom_button.dart';
import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

const _selfSender = 'Me';

IChatMessage _msg(int i, {bool self = false}) => UserChatMessage(
  id: i,
  sender: self ? _selfSender : 'User',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: 'content $i',
);

bool _isSelf(IChatMessage message) => message.sender == _selfSender;

/// Stands in for the backend's "read on another client" signal.
class _FakeReadElsewhere extends ChangeNotifier {
  void fire() => notifyListeners();
}

class _PreloadedDataSource extends ChatDataSource {
  _PreloadedDataSource(
    this.count, {
    Set<int> omitIds = const {},
    Set<int> selfIds = const {},
  }) {
    for (var i = 0; i < count; i++) {
      if (!omitIds.contains(i)) {
        upsertMessage(_msg(i, self: selfIds.contains(i)));
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
  _MetadataOnlyDataSource(
    this.count, {
    this.selfIds = const {},
    this.failFetch = false,
  }) {
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: count - 1,
      reachedNewest: true,
    );
  }

  final int count;

  /// Ids the fetch returns as self messages.
  final Set<int> selfIds;

  /// Whether every fetch throws.
  final bool failFetch;

  /// Every `(fromId, toId)` range requested so far.
  final List<(int, int)> fetches = <(int, int)>[];

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async {
    fetches.add((fromId, toId));
    if (failFetch) throw StateError('fetch failed');
    return <IChatMessage>[
      for (var i = fromId; i <= toId && i < count; i++)
        _msg(i, self: selfIds.contains(i)),
    ];
  }
}

const _viewportWidth = 400.0;
const _viewportHeight = 600.0;

Widget _harness({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  bool reverse = true,
  ValueListenable<double>? bottomPadding,
  ValueNotifier<int?>? lastSeenNewestId,
  ValueListenable<int?>? unreadBoundary,
  ChatSenderRunLayout senderRunLayout = DefaultChatSenderRunLayout.instance,
  void Function(int id, MessageRunLayout runLayout)? onBuildMessage,
  bool Function()? interceptPageDown,
}) => MaterialApp(
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
              senderRunLayout: senderRunLayout,
              messageBuilder: (context, id, message, status, runLayout) {
                onBuildMessage?.call(id, runLayout);
                return SizedBox(
                  height: 60,
                  child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
                );
              },
              unreadBoundary: unreadBoundary,
              unreadSeparatorBuilder: (context) =>
                  const SizedBox(height: 32, child: Text('unread')),
            ),
            ChatScrollToBottomButton(
              controller: controller,
              dataSource: dataSource,
              bottomInset: bottomPadding,
              lastSeenNewestId: lastSeenNewestId,
              interceptTap: interceptPageDown,
            ),
          ],
        ),
      ),
    ),
  ),
);

String _pillText(WidgetTester tester) {
  final badge = find.byKey(const ValueKey<String>('scroll_to_bottom_badge'));
  if (badge.evaluate().isEmpty) {
    return '0 new messages';
  }
  final raw = tester.widget<Text>(badge).data ?? '0';
  final count = int.tryParse(raw) ?? 0;
  if (count <= 0) return '0 new messages';
  return count == 1 ? '1 new message' : '$count new messages';
}

String _expectedPillLabel(int count) =>
    count == 1 ? '1 new message' : '$count new messages';

/// Flush layout + post-frame initial viewport read sync (pill defers until
/// [ChatVisibleRange] stabilizes).
Future<void> _pumpOpenSettled(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(const Duration(milliseconds: 16));
}

int _openAnchor({required ChatDataSource ds, int? storedLastRead}) =>
    ds.resolveOpenAnchor(
      storedLastRead: storedLastRead,
      newestKnownId: ds.newestKnownId,
      oldestKnownId: ds.oldestKnownId,
    );

/// The open position of [ds] without a saved Center Band — always an open
/// at a message.
Future<MessageOpenPosition> _openAtMessage(
  ChatDataSource ds, {
  required int? storedLastRead,
}) async =>
    switch (await ds.resolveOpenPosition(
      storedLastRead: storedLastRead,
      isSelfMessage: _isSelf,
    )) {
      final MessageOpenPosition position => position,
      CenterBandOpenPosition() => throw StateError('opened at a Center Band'),
    };

void main() {
  group('open at last read', () {
    test(
      'stored last-read before any messages loaded resolves to stored id',
      () {
        const count = 10004;
        const lastRead = 9951;
        final ds = _MetadataOnlyDataSource(count);
        addTearDown(ds.dispose);

        final anchor = ds.resolveOpenAnchor(
          storedLastRead: lastRead,
          newestKnownId: ds.newestKnownId,
          oldestKnownId: ds.oldestKnownId,
        );
        expect(anchor, lastRead);
      },
    );

    testWidgets('open at stored last-read anchors off tail', (tester) async {
      const count = 100;
      const lastRead = 40;
      const newest = count - 1;
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
      const newest = count - 1;
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
      await _pumpOpenSettled(tester);

      // Large off-screen backlog (ratio ≥ 0.75) — open sync defers prefix
      // read-marking; baseline stays at stored last-read.
      expect(lastSeen.value, lastRead);
      expect(
        _pillText(tester),
        _expectedPillLabel(ds.newestKnownId! - lastRead),
      );
    });

    testWidgets('pill tap jumps to newest', (tester) async {
      const count = 100;
      const lastRead = 40;
      const newest = count - 1;
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
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 300));
      expect(controller.isAtTail.value, isFalse);

      await tester.tap(find.byKey(const ValueKey<String>('scroll_to_bottom')));
      await tester.pump();
      // Badge stays frozen while the FAB fades out on tap.
      expect(_pillText(tester), isNot('0 new messages'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(_pillText(tester), isNot('0 new messages'));
      }
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(controller.isAtTail.value, isTrue);
      expect(controller.anchorMessageId, newest);
      expect(find.text('shimmer-$count'), findsNothing);
      expect(_pillText(tester), '0 new messages');
    });

    testWidgets('isAtTail persists newest to store', (tester) async {
      const count = 100;
      const lastRead = 40;
      const newest = count - 1;
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
      const newest = count - 1;
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
      await _pumpOpenSettled(tester);
      final baselineAfterOpen = lastSeen.value!;
      expect(baselineAfterOpen, lastRead);
      expect(
        _pillText(tester),
        _expectedPillLabel(ds.newestKnownId! - baselineAfterOpen),
      );

      ds
        ..upsertMessage(_msg(100))
        ..upsertMessage(_msg(101))
        ..seedBoundaries(newestKnownId: 101);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(_pillText(tester), _expectedPillLabel(101 - baselineAfterOpen));
    });

    testWidgets('deleted last-read anchors at previous surviving message', (
      tester,
    ) async {
      const count = 100;
      const deletedId = 50;
      final ds = _PreloadedDataSource(count, omitIds: {deletedId});

      final anchor = ds.resolveOpenAnchor(
        storedLastRead: deletedId,
        newestKnownId: ds.newestKnownId,
        oldestKnownId: ds.oldestKnownId,
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
      const newest = count - 1;
      final ds = _PreloadedDataSource(count);

      final anchor = ds.resolveOpenAnchor(
        storedLastRead: newest + 10,
        newestKnownId: ds.newestKnownId,
        oldestKnownId: ds.oldestKnownId,
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

      final anchor = ds.resolveOpenAnchor(
        storedLastRead: -5,
        newestKnownId: ds.newestKnownId,
        oldestKnownId: ds.oldestKnownId,
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

  group('unread boundary', () {
    Future<int?> boundary(ChatDataSource ds, int? storedLastRead) =>
        ds.resolveUnreadBoundary(
          storedLastRead: storedLastRead,
          isSelfMessage: _isSelf,
        );

    test('is the first incoming message after last-read, skipping own '
        'messages', () async {
      final ds = _PreloadedDataSource(100, selfIds: {41, 42});
      addTearDown(ds.dispose);

      expect(await boundary(ds, 40), 43);
    });

    test('is none when caught up', () async {
      final ds = _PreloadedDataSource(100);
      addTearDown(ds.dispose);

      expect(await boundary(ds, 99), isNull);
      expect(await boundary(ds, 150), isNull);
    });

    test('is none without a stored last-read', () async {
      final ds = _PreloadedDataSource(100);
      addTearDown(ds.dispose);

      expect(await boundary(ds, null), isNull);
    });

    test('is none when every unread message is own', () async {
      final ds = _PreloadedDataSource(100, selfIds: {96, 97, 98, 99});
      addTearDown(ds.dispose);

      expect(await boundary(ds, 95), isNull);
    });

    test('a loaded window resolves without fetching', () async {
      final ds = _MetadataOnlyDataSource(100)..upsertMessage(_msg(41));
      addTearDown(ds.dispose);

      expect(await boundary(ds, 40), 41);
      expect(ds.fetches, isEmpty);
    });

    test('an unloaded id fetches its whole chunk once', () async {
      final ds = _MetadataOnlyDataSource(10004, selfIds: {9952, 9953});
      addTearDown(ds.dispose);

      expect(await boundary(ds, 9951), 9954);
      expect(ds.fetches, <(int, int)>[(9920, 9983)]);
    });

    test('an open makes at most one fetch', () async {
      final ds = _MetadataOnlyDataSource(
        10004,
        selfIds: {for (var i = 9952; i <= 9983; i++) i},
      );
      addTearDown(ds.dispose);

      expect(await boundary(ds, 9951), isNull);
      expect(ds.fetches, hasLength(1));
    });

    test('a failed fetch opens at last-read without a boundary', () async {
      final ds = _MetadataOnlyDataSource(100, failFetch: true);
      addTearDown(ds.dispose);

      final position = await _openAtMessage(ds, storedLastRead: 40);
      expect(ds.fetches, hasLength(1));
      expect(position.unreadBoundary, isNull);
      expect(position.anchor, 40);
      expect(position.alignment, 0.8);
    });

    test('with a boundary the open position is the boundary at alignment 0; '
        'without one it is the last-read open', () async {
      final ds = _PreloadedDataSource(100, selfIds: {41});
      addTearDown(ds.dispose);

      final withBoundary = await _openAtMessage(ds, storedLastRead: 40);
      expect(withBoundary.unreadBoundary, 42);
      expect(withBoundary.anchor, 42);
      expect(withBoundary.alignment, 0.0);
      expect(withBoundary.tailFitFraction, 0.5);

      final firstVisit = await _openAtMessage(ds, storedLastRead: null);
      expect(firstVisit.unreadBoundary, isNull);
      expect(firstVisit.anchor, 99);
      expect(firstVisit.alignment, 0.0);
      expect(firstVisit.tailFitFraction, isNull);

      final ownTail = _PreloadedDataSource(100, selfIds: {97, 98, 99});
      addTearDown(ownTail.dispose);
      final onlyOwnUnread = await _openAtMessage(ownTail, storedLastRead: 96);
      expect(onlyOwnUnread.unreadBoundary, isNull);
      expect(onlyOwnUnread.anchor, 96);
      expect(onlyOwnUnread.alignment, 0.8);
      expect(onlyOwnUnread.tailFitFraction, isNull);
    });

    group('tail or target', () {
      const count = 151;
      const newest = count - 1;

      /// Opens at [storedLastRead] the way the demo screen does: the
      /// boundary controller exists before the tail-or-target jump, and the
      /// sender run policy listens to the same boundary.
      Future<UnreadBoundaryController> open(
        WidgetTester tester, {
        required int storedLastRead,
      }) async {
        final ds = _PreloadedDataSource(count);
        final position = await _openAtMessage(
          ds,
          storedLastRead: storedLastRead,
        );
        final controller = ChatScrollController();
        final boundary = UnreadBoundaryController(
          dataSource: ds,
          controller: controller,
          isSelfMessage: _isSelf,
          boundary: position.unreadBoundary,
        );
        controller.jumpTo(
          position.anchor,
          alignment: position.alignment,
          tailFitFraction: position.tailFitFraction,
        );
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);
        addTearDown(boundary.dispose);

        await tester.pumpWidget(
          _harness(
            dataSource: ds,
            controller: controller,
            unreadBoundary: boundary,
            senderRunLayout: UnreadBoundarySenderRunLayout(boundary: boundary),
          ),
        );
        return boundary;
      }

      double bandTop(WidgetTester tester) =>
          tester.getTopLeft(find.byType(ChatScrollView)).dy;

      double bandBottom(WidgetTester tester) =>
          tester.getBottomLeft(find.byType(ChatScrollView)).dy;

      testWidgets('unread content within half the viewport opens at the '
          'tail with the boundary cleared', (tester) async {
        const lastRead = newest - 3;
        final boundary = await open(tester, storedLastRead: lastRead);

        expect(boundary.value, isNull);
        expect(find.text('unread'), findsNothing);
        await _pumpOpenSettled(tester);
        expect(find.text('unread'), findsNothing);
        expect(
          tester.getBottomLeft(find.text('msg-$newest')).dy,
          bandBottom(tester),
        );
        expect(
          tester.getTopLeft(find.text('msg-${lastRead + 1}')).dy,
          tester.getBottomLeft(find.text('msg-$lastRead')).dy,
          reason: 'no separator between the read and the unread messages',
        );
      });

      testWidgets('unread content of exactly half the viewport opens at the '
          'tail', (tester) async {
        final boundary = await open(tester, storedLastRead: newest - 5);
        await _pumpOpenSettled(tester);

        expect(boundary.value, isNull);
        expect(find.text('unread'), findsNothing);
        expect(
          tester.getBottomLeft(find.text('msg-$newest')).dy,
          bandBottom(tester),
        );
      });

      testWidgets('unread content past half the viewport keeps the boundary '
          'and opens as a plain open at it', (tester) async {
        const lastRead = newest - 6;
        final boundary = await open(tester, storedLastRead: lastRead);
        await _pumpOpenSettled(tester);

        expect(boundary.value, lastRead + 1);
        expect(
          tester.getBottomLeft(find.text('msg-$newest')).dy,
          bandBottom(tester),
          reason: 'too little content below the separator to fill the band',
        );
        expect(
          tester.getTopLeft(find.text('unread')).dy,
          bandBottom(tester) - 6 * 60 - 32,
        );
        expect(
          tester.getTopLeft(find.text('msg-${lastRead + 1}')).dy,
          tester.getBottomLeft(find.text('unread')).dy,
        );
      });

      testWidgets('a long unread backlog opens at the separator at the band '
          'top', (tester) async {
        const lastRead = newest - 40;
        final boundary = await open(tester, storedLastRead: lastRead);
        await _pumpOpenSettled(tester);

        expect(boundary.value, lastRead + 1);
        expect(tester.getTopLeft(find.text('unread')).dy, bandTop(tester));
        expect(
          tester.getTopLeft(find.text('msg-${lastRead + 1}')).dy,
          bandTop(tester) + 32,
        );
      });
    });

    testWidgets('open puts the boundary row at the band top under the '
        'separator; pill count unchanged', (tester) async {
      const count = 151;
      const lastRead = 50;
      final ds = _PreloadedDataSource(count);
      final position = await _openAtMessage(ds, storedLastRead: lastRead);
      expect(position.unreadBoundary, lastRead + 1);

      final controller = ChatScrollController()
        ..jumpTo(
          position.anchor,
          alignment: position.alignment,
          tailFitFraction: position.tailFitFraction,
        );
      final boundaryId = ValueNotifier<int?>(position.unreadBoundary);
      final lastSeen = ValueNotifier<int?>(lastRead);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      addTearDown(boundaryId.dispose);
      addTearDown(lastSeen.dispose);

      await tester.pumpWidget(
        _harness(
          dataSource: ds,
          controller: controller,
          lastSeenNewestId: lastSeen,
          unreadBoundary: boundaryId,
        ),
      );
      await _pumpOpenSettled(tester);

      final bandTop = tester.getTopLeft(find.byType(ChatScrollView)).dy;
      final separatorTop = tester.getTopLeft(find.text('unread')).dy;
      expect(separatorTop, bandTop);
      expect(
        tester.getTopLeft(find.text('msg-${lastRead + 1}')).dy,
        separatorTop + 32,
      );
      expect(
        tester.getBottomLeft(find.text('msg-$lastRead')).dy,
        lessThanOrEqualTo(bandTop),
        reason: 'the last read message sits above the band',
      );
      expect(lastSeen.value, lastRead);
      expect(_pillText(tester), _expectedPillLabel(count - 1 - lastRead));
    });

    group('live', () {
      const count = 151;
      const lastRead = 50;
      const boundaryId = lastRead + 1;
      late _FakeReadElsewhere readElsewhere;

      Future<
        ({
          _PreloadedDataSource ds,
          ChatScrollController controller,
          UnreadBoundaryController boundary,
          ValueNotifier<int?> lastSeen,
        })
      >
      open(WidgetTester tester) async {
        final ds = _PreloadedDataSource(count);
        final position = await _openAtMessage(ds, storedLastRead: lastRead);
        final controller = ChatScrollController()
          ..jumpTo(
            position.anchor,
            alignment: position.alignment,
            tailFitFraction: position.tailFitFraction,
          );
        readElsewhere = _FakeReadElsewhere();
        final boundary = UnreadBoundaryController(
          dataSource: ds,
          controller: controller,
          isSelfMessage: _isSelf,
          boundary: position.unreadBoundary,
          readElsewhere: readElsewhere,
        );
        final lastSeen = ValueNotifier<int?>(lastRead);
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);
        addTearDown(boundary.dispose);
        addTearDown(lastSeen.dispose);
        addTearDown(readElsewhere.dispose);

        await tester.pumpWidget(
          _harness(
            dataSource: ds,
            controller: controller,
            lastSeenNewestId: lastSeen,
            unreadBoundary: boundary,
          ),
        );
        await _pumpOpenSettled(tester);
        expect(boundary.value, boundaryId);
        expect(find.text('unread'), findsOneWidget);
        return (
          ds: ds,
          controller: controller,
          boundary: boundary,
          lastSeen: lastSeen,
        );
      }

      testWidgets('scroll-reading advances the read baseline, not the '
          'boundary', (tester) async {
        final (:ds, :controller, :boundary, :lastSeen) = await open(tester);

        for (var step = 0; step < 8; step++) {
          await tester.drag(find.byType(ChatScrollView), const Offset(0, -180));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
        }

        expect(lastSeen.value, greaterThan(lastRead));
        expect(boundary.value, boundaryId);
      });

      testWidgets('an own message that arrives loaded clears the boundary', (
        tester,
      ) async {
        final (:ds, :controller, :boundary, :lastSeen) = await open(tester);
        expect(controller.isAtTail.value, isFalse);

        ds.insertMessage(_msg(count, self: true));
        await tester.pump();

        expect(boundary.value, isNull);
        expect(find.text('unread'), findsNothing);
      });

      testWidgets('an arrival that is not loaded keeps the boundary', (
        tester,
      ) async {
        final (:ds, :controller, :boundary, :lastSeen) = await open(tester);

        ds.seedBoundaries(newestKnownId: count);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));

        expect(boundary.value, boundaryId);
        expect(find.text('unread'), findsOneWidget);
      });

      testWidgets('an incoming message at the tail keeps the boundary while '
          'the list follows the tail', (tester) async {
        final (:ds, :controller, :boundary, :lastSeen) = await open(tester);
        controller.jumpTo(count - 1);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(controller.isAtTail.value, isTrue);

        ds.insertMessage(_msg(count));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));

        expect(boundary.value, boundaryId);
        expect(controller.isAtTail.value, isTrue);
        final viewportBottom = tester
            .getBottomLeft(find.byType(ChatScrollView))
            .dy;
        expect(
          tester.getBottomLeft(find.text('msg-$count')).dy,
          viewportBottom,
          reason: 'follow tail pins the newest row to the bottom edge',
        );

        controller.jumpTo(boundaryId, alignment: 0);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(find.text('unread'), findsOneWidget);
      });

      testWidgets('an incoming message off the tail keeps the boundary', (
        tester,
      ) async {
        final (:ds, :controller, :boundary, :lastSeen) = await open(tester);
        final rowTop = tester.getTopLeft(find.text('msg-$boundaryId')).dy;

        ds.insertMessage(_msg(count));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));

        expect(controller.isAtTail.value, isFalse);
        expect(boundary.value, boundaryId);
        expect(find.text('unread'), findsOneWidget);
        expect(tester.getTopLeft(find.text('msg-$boundaryId')).dy, rowTop);
      });

      testWidgets('deleting a message clears the boundary', (tester) async {
        final (:ds, :controller, :boundary, :lastSeen) = await open(tester);

        ds.removeMessages([boundaryId + 2]);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));

        expect(boundary.value, isNull);
        expect(find.text('unread'), findsNothing);
        expect(find.text('msg-$boundaryId'), findsOneWidget);
      });

      testWidgets('editing a message keeps the boundary', (tester) async {
        final (:ds, :controller, :boundary, :lastSeen) = await open(tester);

        ds.updateMessage(_msg(boundaryId));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));

        expect(boundary.value, boundaryId);
        expect(find.text('unread'), findsOneWidget);
      });

      testWidgets('a read on another client clears the boundary', (
        tester,
      ) async {
        final (:ds, :controller, :boundary, :lastSeen) = await open(tester);

        readElsewhere.fire();
        await tester.pump();

        expect(boundary.value, isNull);
        expect(find.text('unread'), findsNothing);
      });

      testWidgets('the separator counts as seen once its row is on screen; '
          'a moved boundary starts unseen', (tester) async {
        final (:ds, :controller, :boundary, :lastSeen) = await open(tester);
        expect(boundary.separatorSeen, isTrue);

        const movedId = boundaryId + 40;
        boundary.setBoundary(movedId);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(find.text('unread'), findsNothing);
        expect(boundary.separatorSeen, isFalse);

        controller.jumpTo(movedId, alignment: 0);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(find.text('unread'), findsOneWidget);
        expect(boundary.separatorSeen, isTrue);
      });

      testWidgets('the host can set the boundary again after a clear', (
        tester,
      ) async {
        final (:ds, :controller, :boundary, :lastSeen) = await open(tester);
        final separatorTop = tester.getTopLeft(find.text('unread')).dy;

        boundary.clear();
        await tester.pump();
        expect(find.text('unread'), findsNothing);

        boundary.setBoundary(boundaryId);
        await tester.pump();
        expect(boundary.value, boundaryId);
        expect(find.text('unread'), findsOneWidget);
        expect(
          tester.getTopLeft(find.text('msg-$boundaryId')).dy,
          tester.getBottomLeft(find.text('unread')).dy,
        );
        expect(tester.getTopLeft(find.text('unread')).dy, separatorTop);
      });

      /// Taps page-down; the returned list collects the path each
      /// [ChatAnimateEnd] reports.
      Future<List<AnimateToPath>> tapPageDown(
        WidgetTester tester,
        ChatScrollController controller,
      ) async {
        final paths = <AnimateToPath>[];
        void onEvent(ChatScrollEvent event) {
          if (event case ChatAnimateEnd(:final path)) paths.add(path);
        }

        controller.addScrollListener(onEvent);
        addTearDown(() => controller.removeScrollListener(onEvent));
        // Let the button finish sliding in so the tap lands on it.
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(
          find.byKey(const ValueKey<String>('scroll_to_bottom')),
        );
        await tester.pump();
        return paths;
      }

      /// Pumps until page-down's flight has ended; returns its path.
      Future<AnimateToPath> land(
        WidgetTester tester,
        List<AnimateToPath> paths,
      ) async {
        for (var i = 0; i < 200 && paths.isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pump();
        return paths.single;
      }

      testWidgets('a page-down that stitches to the tail clears the boundary '
          'once it lands', (tester) async {
        final (:ds, :controller, :boundary, :lastSeen) = await open(tester);

        final paths = await tapPageDown(tester, controller);
        await tester.pump(const Duration(milliseconds: 16));
        expect(controller.isAnimating, isTrue);
        expect(boundary.value, boundaryId, reason: 'still in flight');

        expect(await land(tester, paths), AnimateToPath.stitch);
        expect(controller.isAtTail.value, isTrue);
        expect(boundary.value, isNull);
        expect(find.text('unread'), findsNothing);
      });

      testWidgets('a page-down that scrolls through built rows keeps the '
          'boundary', (tester) async {
        final (:ds, :controller, :boundary, :lastSeen) = await open(tester);
        controller.jumpTo(count - 11);
        await _pumpOpenSettled(tester);
        expect(controller.isAtTail.value, isFalse);

        final paths = await tapPageDown(tester, controller);
        expect(await land(tester, paths), AnimateToPath.close);
        expect(controller.isAtTail.value, isTrue);
        expect(boundary.value, boundaryId);

        controller.jumpTo(boundaryId);
        await tester.pump();
        expect(find.text('unread'), findsOneWidget);
      });
    });

    group('host writes', () {
      const count = 151;
      const boundaryId = 51;

      late _FakeReadElsewhere readElsewhere;

      ({
        _PreloadedDataSource ds,
        UnreadBoundaryController boundary,
        List<int?> heard,
      })
      holder({
        int? initial = boundaryId,
        Set<int> omitIds = const {},
        Set<int> selfIds = const {},
      }) {
        final ds = _PreloadedDataSource(
          count,
          omitIds: omitIds,
          selfIds: selfIds,
        );
        final controller = ChatScrollController();
        readElsewhere = _FakeReadElsewhere();
        final boundary = UnreadBoundaryController(
          dataSource: ds,
          controller: controller,
          isSelfMessage: _isSelf,
          boundary: initial,
          readElsewhere: readElsewhere,
        );
        final heard = <int?>[];
        boundary.addListener(() => heard.add(boundary.value));
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);
        addTearDown(boundary.dispose);
        addTearDown(readElsewhere.dispose);
        return (ds: ds, boundary: boundary, heard: heard);
      }

      test('set, move, and clear each notify once, and a cleared boundary '
          'can be set again', () {
        final (:ds, :boundary, :heard) = holder();

        boundary
          ..clear()
          ..setBoundary(boundaryId)
          ..setBoundary(boundaryId + 5)
          ..clear();

        expect(heard, <int?>[null, boundaryId, boundaryId + 5, null]);
        expect(boundary.value, isNull);
      });

      test('same-value writes are silent', () {
        final (:ds, :boundary, :heard) = holder();

        boundary
          ..setBoundary(boundaryId)
          ..clear()
          ..clear();

        expect(heard, <int?>[null]);
      });

      test('writes after dispose are silent and the value freezes', () {
        final (:ds, :boundary, :heard) = holder();
        boundary.dispose();

        boundary
          ..setBoundary(80)
          ..setPendingBoundary(90)
          ..clear();
        ds
          ..insertMessage(_msg(count, self: true))
          ..removeMessages([boundaryId]);
        readElsewhere.fire();

        expect(heard, isEmpty);
        expect(boundary.value, boundaryId);
      });

      test('a remove batch clears the boundary, even for an id that was '
          'never loaded', () {
        final (:ds, :boundary, :heard) = holder(omitIds: {120});

        ds.removeMessages([120]);

        expect(heard, <int?>[null]);
        expect(boundary.value, isNull);
      });

      test('a remove batch drops a pending boundary', () {
        final (:ds, :boundary, :heard) = holder(
          initial: null,
          omitIds: {70},
        );

        boundary.setPendingBoundary(70);
        ds
          ..removeMessages([100])
          ..upsertMessage(_msg(70));

        expect(boundary.value, isNull);
        expect(heard, isEmpty);
      });

      test('an edit keeps the boundary', () {
        final (:ds, :boundary, :heard) = holder();

        ds
          ..updateMessage(_msg(boundaryId))
          ..updateMessages([_msg(60), _msg(61)]);

        expect(heard, isEmpty);
        expect(boundary.value, boundaryId);
      });

      test('a read elsewhere clears the boundary, pending or not', () {
        final (:ds, :boundary, :heard) = holder(omitIds: {70});

        readElsewhere.fire();
        expect(heard, <int?>[null]);

        boundary.setPendingBoundary(70);
        readElsewhere.fire();
        ds.upsertMessage(_msg(70));
        expect(boundary.value, isNull);
        expect(heard, <int?>[null]);
      });

      test('an incoming arrival never clears the boundary', () {
        final (:ds, :boundary, :heard) = holder();

        ds.insertMessage(_msg(count));

        expect(heard, isEmpty);
        expect(boundary.value, boundaryId);
      });

      test('a pending boundary resolves to the first loaded incoming message '
          'at or after its id', () {
        final (:ds, :boundary, :heard) = holder(
          initial: null,
          selfIds: {60, 61},
        );

        boundary.setPendingBoundary(60);

        expect(heard, <int?>[62]);
        expect(boundary.value, 62);
      });

      test('a pending boundary replaces the current one and waits for its '
          'row to load', () {
        final (:ds, :boundary, :heard) = holder(omitIds: {70});

        boundary
          ..setPendingBoundary(70)
          ..setPendingBoundary(70);
        expect(heard, <int?>[null]);

        ds.upsertMessage(_msg(70));
        expect(heard, <int?>[null, 70]);
        expect(boundary.value, 70);
      });

      test('a pending boundary with no incoming message up to the reached '
          'newest lapses; a later arrival does not resolve it', () {
        final (:ds, :boundary, :heard) = holder(
          initial: null,
          selfIds: {count - 2, count - 1},
        );

        boundary.setPendingBoundary(count - 2);
        expect(boundary.value, isNull);
        boundary.setPendingBoundary(count + 5);
        expect(boundary.value, isNull);

        ds.insertMessage(_msg(count));
        expect(boundary.value, isNull);
        expect(heard, isEmpty);
      });

      test('a pending boundary whose rows load as own messages lapses', () {
        final (:ds, :boundary, :heard) = holder(
          initial: null,
          omitIds: {count - 1},
        );

        boundary.setPendingBoundary(count - 1);
        ds
          ..upsertMessage(_msg(count - 1, self: true))
          ..insertMessage(_msg(count));
        expect(boundary.value, isNull);
        expect(heard, isEmpty);
      });

      test('an own arrival, a set, or a clear drops a pending boundary', () {
        final (:ds, :boundary, :heard) = holder(
          initial: null,
          omitIds: {70, 80, 90},
        );

        boundary.setPendingBoundary(70);
        ds
          ..insertMessage(_msg(count, self: true))
          ..upsertMessage(_msg(70));
        expect(boundary.value, isNull);

        boundary
          ..setPendingBoundary(80)
          ..setBoundary(boundaryId);
        ds.upsertMessage(_msg(80));
        expect(boundary.value, boundaryId);

        boundary
          ..setPendingBoundary(90)
          ..clear();
        ds.upsertMessage(_msg(90));
        expect(boundary.value, isNull);
        expect(heard, <int?>[boundaryId, null]);
      });

      test('unseenFromId is the pending search start, then the placed row, '
          'and null without a boundary', () {
        final (:ds, :boundary, :heard) = holder(
          initial: null,
          omitIds: {70},
          selfIds: {70},
        );
        expect(boundary.unseenFromId, isNull);

        boundary.setPendingBoundary(70);
        expect(boundary.value, isNull);
        expect(boundary.unseenFromId, 70);

        ds.upsertMessage(_msg(70, self: true));
        expect(boundary.value, 71);
        expect(boundary.unseenFromId, 71);

        boundary.clear();
        expect(boundary.unseenFromId, isNull);
      });
    });

    group('sender run', () {
      const count = 151;
      const lastRead = 50;
      const boundaryId = lastRead + 1;

      /// Opens at the boundary with every message in one sender run. The
      /// returned map holds the run layout of each message build, keyed by
      /// id; clearing it makes its keys the ids built afterwards.
      Future<Map<int, MessageRunLayout>> open(
        WidgetTester tester, {
        required ChatDataSource ds,
        required ValueListenable<int?> boundary,
        ChatScrollController? controller,
      }) async {
        final runs = <int, MessageRunLayout>{};
        controller ??= ChatScrollController();
        addTearDown(controller.dispose);
        controller.jumpTo(boundaryId, alignment: 0);

        await tester.pumpWidget(
          _harness(
            dataSource: ds,
            controller: controller,
            unreadBoundary: boundary,
            senderRunLayout: UnreadBoundarySenderRunLayout(boundary: boundary),
            onBuildMessage: (id, runLayout) => runs[id] = runLayout,
          ),
        );
        await _pumpOpenSettled(tester);
        return runs;
      }

      testWidgets('the boundary row starts a run and its predecessor ends '
          'one', (tester) async {
        final ds = _PreloadedDataSource(count);
        final boundary = ValueNotifier<int?>(boundaryId);
        addTearDown(ds.dispose);
        addTearDown(boundary.dispose);

        final runs = await open(tester, ds: ds, boundary: boundary);

        expect(runs[boundaryId - 1]?.isFirstInSenderRun, isFalse);
        expect(runs[boundaryId - 1]?.isLastInSenderRun, isTrue);
        expect(runs[boundaryId]?.isFirstInSenderRun, isTrue);
        expect(runs[boundaryId]?.isLastInSenderRun, isFalse);
        expect(runs[boundaryId + 1]?.isFirstInSenderRun, isFalse);
      });

      testWidgets('clearing the boundary rejoins the run, rebuilding only '
          'the boundary row and its predecessor', (tester) async {
        final ds = _PreloadedDataSource(count);
        final controller = ChatScrollController();
        final boundary = UnreadBoundaryController(
          dataSource: ds,
          controller: controller,
          isSelfMessage: _isSelf,
          boundary: boundaryId,
        );
        addTearDown(ds.dispose);
        addTearDown(boundary.dispose);

        final runs = await open(
          tester,
          ds: ds,
          boundary: boundary,
          controller: controller,
        );
        final built = runs.keys.toSet();
        runs.clear();

        ds.insertMessage(_msg(count, self: true));
        await tester.pump();

        expect(boundary.value, isNull);
        expect(
          runs.keys.where(built.contains),
          unorderedEquals(<int>[boundaryId - 1, boundaryId]),
          reason:
              'the separator leaving exposes new rows; of the rows '
              'already built, only the two whose flags flip rebuild',
        );
        expect(runs[boundaryId - 1]?.isLastInSenderRun, isFalse);
        expect(runs[boundaryId]?.isFirstInSenderRun, isFalse);
      });

      testWidgets('moving the boundary moves the run break', (tester) async {
        const movedId = boundaryId + 2;
        final ds = _PreloadedDataSource(count);
        final boundary = ValueNotifier<int?>(boundaryId);
        addTearDown(ds.dispose);
        addTearDown(boundary.dispose);

        final runs = await open(tester, ds: ds, boundary: boundary);
        final built = runs.keys.toSet();
        runs.clear();

        boundary.value = movedId;
        await tester.pump();

        expect(
          runs.keys.where(built.contains),
          unorderedEquals(<int>[
            boundaryId - 1,
            boundaryId,
            movedId - 1,
            movedId,
          ]),
        );
        expect(runs[boundaryId - 1]?.isLastInSenderRun, isFalse);
        expect(runs[boundaryId]?.isFirstInSenderRun, isFalse);
        expect(runs[movedId - 1]?.isLastInSenderRun, isTrue);
        expect(runs[movedId]?.isFirstInSenderRun, isTrue);
      });

      testWidgets('the run break follows a host clear, set, and move', (
        tester,
      ) async {
        final ds = _PreloadedDataSource(count);
        final controller = ChatScrollController();
        final boundary = UnreadBoundaryController(
          dataSource: ds,
          controller: controller,
          isSelfMessage: _isSelf,
          boundary: boundaryId,
        );
        addTearDown(ds.dispose);
        addTearDown(boundary.dispose);

        final runs = await open(
          tester,
          ds: ds,
          boundary: boundary,
          controller: controller,
        );

        runs.clear();
        boundary.clear();
        await tester.pump();
        expect(runs[boundaryId - 1]?.isLastInSenderRun, isFalse);
        expect(runs[boundaryId]?.isFirstInSenderRun, isFalse);

        const setId = boundaryId + 2;
        runs.clear();
        boundary.setBoundary(setId);
        await tester.pump();
        expect(runs[setId - 1]?.isLastInSenderRun, isTrue);
        expect(runs[setId]?.isFirstInSenderRun, isTrue);

        const movedId = setId + 2;
        runs.clear();
        boundary.setBoundary(movedId);
        await tester.pump();
        expect(runs[setId - 1]?.isLastInSenderRun, isFalse);
        expect(runs[setId]?.isFirstInSenderRun, isFalse);
        expect(runs[movedId - 1]?.isLastInSenderRun, isTrue);
        expect(runs[movedId]?.isFirstInSenderRun, isTrue);
      });

      test('the predecessor is the nearest present message; an absent '
          'boundary breaks nothing', () {
        final ds = _PreloadedDataSource(count)
          ..removeMessages([boundaryId - 1]);
        addTearDown(ds.dispose);
        final boundary = ValueNotifier<int?>(boundaryId);
        addTearDown(boundary.dispose);
        final policy = UnreadBoundarySenderRunLayout(boundary: boundary);
        MessageRunLayout run(int id) =>
            policy.resolve(dataSource: ds, messageId: id);

        expect(run(boundaryId - 2).isLastInSenderRun, isTrue);
        expect(run(boundaryId).isFirstInSenderRun, isTrue);
        expect(run(boundaryId + 1).isFirstInSenderRun, isFalse);

        ds.removeMessages([boundaryId]);
        expect(run(boundaryId - 2).isLastInSenderRun, isFalse);
        expect(run(boundaryId + 1).isFirstInSenderRun, isFalse);
      });

      test('policies over the same boundary and delegate are equal', () {
        final boundary = ValueNotifier<int?>(boundaryId);
        final other = ValueNotifier<int?>(boundaryId);
        addTearDown(boundary.dispose);
        addTearDown(other.dispose);

        expect(
          UnreadBoundarySenderRunLayout(boundary: boundary),
          UnreadBoundarySenderRunLayout(boundary: boundary),
        );
        expect(
          UnreadBoundarySenderRunLayout(boundary: boundary),
          isNot(UnreadBoundarySenderRunLayout(boundary: other)),
        );
        expect(
          UnreadBoundarySenderRunLayout(boundary: boundary),
          isNot(
            UnreadBoundarySenderRunLayout(
              boundary: boundary,
              delegate: const DefaultChatSenderRunLayout(maxClusterGap: null),
            ),
          ),
        );
      });
    });

    group('saved reading position', () {
      const count = 300;
      const newest = count - 1;
      const lastRead = 250;
      const firstUnread = lastRead + 1;
      const saved = ChatCenterBand(messageId: 100, offsetFromMessageTop: 10);

      ChatCenterBand? leave(
        ChatDataSource ds, {
        required int newestVisibleId,
        required int? readMark,
        bool isAtTail = false,
      }) => ds.resolveLeavePosition(
        centerBand: saved,
        isAtTail: isAtTail,
        newestVisibleId: newestVisibleId,
        readMark: readMark,
        isSelfMessage: _isSelf,
      );

      /// Reopens [ds] at [saved] the way the demo screen does, with
      /// page-down going to the boundary until its separator is seen.
      Future<
        ({ChatScrollController controller, UnreadBoundaryController boundary})
      >
      reopen(WidgetTester tester, ChatDataSource ds) async {
        final position = await ds.resolveOpenPosition(
          storedLastRead: lastRead,
          isSelfMessage: _isSelf,
          savedCenterBand: saved,
        );
        final CenterBandOpenPosition(:centerBand, :pendingBoundaryFrom) =
            switch (position) {
              final CenterBandOpenPosition restore => restore,
              MessageOpenPosition() => throw StateError('opened at a message'),
            };
        final controller = ChatScrollController()
          ..jumpToCenterBand(
            centerBand.messageId,
            centerBand.offsetFromMessageTop,
          );
        final boundary = UnreadBoundaryController(
          dataSource: ds,
          controller: controller,
          isSelfMessage: _isSelf,
        );
        if (pendingBoundaryFrom case final fromId?) {
          boundary.setPendingBoundary(fromId);
        }
        final lastSeen = ValueNotifier<int?>(lastRead);
        final inset = ValueNotifier<double>(96);
        addTearDown(controller.dispose);
        addTearDown(boundary.dispose);
        addTearDown(lastSeen.dispose);
        addTearDown(inset.dispose);

        await tester.pumpWidget(
          _harness(
            dataSource: ds,
            controller: controller,
            bottomPadding: inset,
            lastSeenNewestId: lastSeen,
            unreadBoundary: boundary,
            interceptPageDown: () {
              final fromId = boundary.unseenFromId;
              if (fromId == null) return false;
              controller.animateTo(
                fromId,
                alignment: ChatDataSourceX.unreadBoundaryAlignment,
                highlight: false,
              );
              return true;
            },
          ),
        );
        await _pumpOpenSettled(tester);
        return (controller: controller, boundary: boundary);
      }

      Future<void> pumpNavigation(WidgetTester tester) async {
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      }

      testWidgets('leaving off the tail keeps the Center Band; leaving at '
          'the tail drops it', (tester) async {
        final ds = _PreloadedDataSource(count);
        final controller = ChatScrollController()..jumpTo(100, alignment: 0.5);
        addTearDown(ds.dispose);
        addTearDown(controller.dispose);
        await tester.pumpWidget(
          _harness(dataSource: ds, controller: controller),
        );
        await _pumpOpenSettled(tester);

        ChatCenterBand? leaveNow() => ds.resolveLeavePosition(
          centerBand: controller.centerBand.value,
          isAtTail: controller.isAtTail.value,
          newestVisibleId: controller.visibleRange.value!.lastId,
          readMark: newest,
          isSelfMessage: _isSelf,
        );

        expect(controller.centerBand.value?.messageId, 100);
        expect(leaveNow(), controller.centerBand.value);

        controller.jumpTo(newest);
        await _pumpOpenSettled(tester);
        expect(controller.isAtTail.value, isTrue);
        expect(leaveNow(), isNull);
      });

      test('no save when the newest visible message is unread incoming and '
          'an incoming message follows within four loaded messages', () {
        final ds = _PreloadedDataSource(
          count,
          omitIds: {130},
          selfIds: {111, 121, 122, 123, 124, 140},
        );
        addTearDown(ds.dispose);

        expect(leave(ds, newestVisibleId: 110, readMark: 109), isNull);
        expect(
          leave(ds, newestVisibleId: 110, readMark: 110),
          saved,
          reason: 'the newest visible message is read',
        );
        expect(
          leave(ds, newestVisibleId: 110, readMark: null),
          saved,
          reason: 'without a read mark nothing is unread',
        );
        expect(
          leave(ds, newestVisibleId: 140, readMark: 100),
          saved,
          reason: 'an own message is never unread',
        );
        expect(
          leave(ds, newestVisibleId: 120, readMark: 100),
          saved,
          reason: 'the next four messages are own; the fifth is not looked at',
        );
        expect(
          leave(ds, newestVisibleId: 129, readMark: 100),
          saved,
          reason: 'the look-ahead stops at a message that is not loaded',
        );
        expect(
          leave(ds, newestVisibleId: 110, readMark: 109, isAtTail: true),
          isNull,
        );
      });

      test('an absent message is skipped by the look-ahead', () {
        final ds = _PreloadedDataSource(count)..removeMessages([111, 112]);
        addTearDown(ds.dispose);

        expect(leave(ds, newestVisibleId: 110, readMark: 100), isNull);
      });

      test('a saved Center Band opens there with the boundary pending right '
          'after last-read, without fetching', () async {
        final ds = _MetadataOnlyDataSource(count);
        addTearDown(ds.dispose);

        final restore = await ds.resolveOpenPosition(
          storedLastRead: lastRead,
          isSelfMessage: _isSelf,
          savedCenterBand: saved,
        );
        expect(
          restore,
          isA<CenterBandOpenPosition>()
              .having((p) => p.centerBand, 'centerBand', saved)
              .having(
                (p) => p.pendingBoundaryFrom,
                'pendingBoundaryFrom',
                firstUnread,
              ),
        );
        expect(ds.fetches, isEmpty);

        final caughtUp = await ds.resolveOpenPosition(
          storedLastRead: newest,
          isSelfMessage: _isSelf,
          savedCenterBand: saved,
        );
        expect(
          caughtUp,
          isA<CenterBandOpenPosition>().having(
            (p) => p.pendingBoundaryFrom,
            'pendingBoundaryFrom',
            isNull,
          ),
        );

        final fresh = await _openAtMessage(ds, storedLastRead: lastRead);
        expect(fresh.unreadBoundary, firstUnread);
        expect(fresh.anchor, firstUnread);
        expect(fresh.alignment, ChatDataSourceX.unreadBoundaryAlignment);
      });

      testWidgets('reopening restores the Center Band; the separator paints '
          'when the reader reaches the boundary row', (tester) async {
        final ds = _MetadataOnlyDataSource(count);
        addTearDown(ds.dispose);
        final (:controller, :boundary) = await reopen(tester, ds);
        await pumpNavigation(tester);

        expect(controller.centerBand.value?.messageId, saved.messageId);
        expect(
          controller.centerBand.value?.offsetFromMessageTop,
          closeTo(saved.offsetFromMessageTop, 0.5),
        );
        expect(find.text('unread'), findsNothing);
        expect(boundary.unseenFromId, firstUnread);
        expect(boundary.separatorSeen, isFalse);

        for (var step = 0; step < 80 && !boundary.separatorSeen; step++) {
          await tester.drag(find.byType(ChatScrollView), const Offset(0, -180));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 16));
        }

        expect(boundary.separatorSeen, isTrue);
        expect(boundary.value, firstUnread);
        expect(boundary.unseenFromId, isNull);
        final viewport = tester.getRect(find.byType(ChatScrollView));
        final separatorTop = tester.getTopLeft(find.text('unread')).dy;
        expect(separatorTop, inInclusiveRange(viewport.top, viewport.bottom));
        expect(
          tester.getTopLeft(find.text('msg-$firstUnread')).dy,
          tester.getBottomLeft(find.text('unread')).dy,
        );
      });

      testWidgets('page-down goes to the boundary until its separator is '
          'seen, then to the newest message', (tester) async {
        final ds = _PreloadedDataSource(count);
        addTearDown(ds.dispose);
        final (:controller, :boundary) = await reopen(tester, ds);
        await pumpNavigation(tester);
        expect(controller.isAtTail.value, isFalse);
        expect(boundary.separatorSeen, isFalse);
        final pageDown = find.byKey(const ValueKey<String>('scroll_to_bottom'));

        await tester.tap(pageDown);
        await pumpNavigation(tester);

        final bandTop = tester.getTopLeft(find.byType(ChatScrollView)).dy;
        expect(tester.getTopLeft(find.text('unread')).dy, bandTop);
        expect(
          tester.getTopLeft(find.text('msg-$firstUnread')).dy,
          bandTop + 32,
        );
        expect(boundary.separatorSeen, isTrue);
        expect(controller.isAtTail.value, isFalse);

        await tester.tap(pageDown);
        await pumpNavigation(tester);

        expect(controller.isAtTail.value, isTrue);
        expect(find.text('msg-$newest'), findsOneWidget);
      });

      testWidgets('page-down while the boundary is pending goes to where '
          'unread starts; the separator lands at the band top once its row '
          'loads', (tester) async {
        final ds = _MetadataOnlyDataSource(count);
        addTearDown(ds.dispose);
        final (:controller, :boundary) = await reopen(tester, ds);
        await pumpNavigation(tester);
        expect(boundary.value, isNull, reason: 'the boundary row is unloaded');
        expect(boundary.unseenFromId, firstUnread);

        await tester.tap(
          find.byKey(const ValueKey<String>('scroll_to_bottom')),
        );
        await pumpNavigation(tester);

        final bandTop = tester.getTopLeft(find.byType(ChatScrollView)).dy;
        expect(boundary.value, firstUnread);
        expect(tester.getTopLeft(find.text('unread')).dy, bandTop);
        expect(boundary.separatorSeen, isTrue);
        expect(controller.isAtTail.value, isFalse);
      });
    });
  });
}
