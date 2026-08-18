import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_controller.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_selection_controller.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_scroll_view.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_selectable_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../chat_message.dart';

IChatMessage _msg(int id, {String content = ''}) => UserChatMessage(
  id: id,
  sender: 'User',
  createdAt: DateTime(2026, 5, 29, 10, id),
  updatedAt: DateTime(2026, 5, 29, 10, id),
  content: content.isEmpty ? 'body-$id' : content,
);

class _LoadedSource extends ChatDataSource {
  _LoadedSource(Iterable<IChatMessage> messages) {
    upsertMessages(messages);
    if (messages.isEmpty) return;
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

/// Boundaries span ids 0–9; only id 5 is loaded — id 3 is dirty/unloaded.
class _SparseUnloadedSource extends ChatDataSource {
  _SparseUnloadedSource() {
    upsertMessage(_msg(5));
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: 9,
      reachedOldest: false,
      reachedNewest: false,
    );
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

class _InvokeTracker {
  final ids = <int>{};

  void reset() => ids.clear();

  ChatMessageBuilder get builder => (context, id, message, status, runLayout) {
    ids.add(id);
    if (message == null) {
      return SizedBox(height: 40, child: Text('shimmer-$id'));
    }
    return SizedBox(height: 40, child: Text('msg-$id'));
  };
}

Widget _harness({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  required ChatMessageBuilder messageBuilder,
  ChatSelectionController? selectionController,
  Widget Function(BuildContext)? emptyBuilder,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 400,
        height: 600,
        child: ChatScrollView(
          dataSource: dataSource,
          controller: controller,
          selectionController: selectionController,
          emptyBuilder: emptyBuilder,
          messageBuilder: messageBuilder,
        ),
      ),
    ),
  ),
);

Future<void> _pumpLoaded(
  WidgetTester tester,
  ChatDataSource ds,
  ChatScrollController controller,
  ChatMessageBuilder builder, {
  ChatSelectionController? selection,
  Widget Function(BuildContext)? emptyBuilder,
}) async {
  await tester.pumpWidget(
    _harness(
      dataSource: ds,
      controller: controller,
      messageBuilder: builder,
      selectionController: selection,
      emptyBuilder: emptyBuilder,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('absent slot build exclusion', () {
    testWidgets(
      'delete anchor of two leaves survivor without ghost builder call',
      (tester) async {
        final ds = _LoadedSource([_msg(1), _msg(2)]);
        final controller = ChatScrollController()..jumpTo(1);
        final tracker = _InvokeTracker();
        addTearDown(controller.dispose);
        addTearDown(ds.dispose);

        await _pumpLoaded(tester, ds, controller, tracker.builder);
        tracker.reset();

        ds.removeMessages([1]);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('msg-2'), findsOneWidget);
        expect(find.text('msg-1'), findsNothing);
        expect(find.text('shimmer-1'), findsNothing);
        expect(tracker.ids, isNot(contains(1)));
      },
    );

    testWidgets('selection mode delete anchor leaves no selectable ghost row', (
      tester,
    ) async {
      final ds = _LoadedSource([_msg(1), _msg(2)]);
      final controller = ChatScrollController()..jumpTo(1);
      final selection = ChatSelectionController()..startSelection(1);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      addTearDown(selection.dispose);

      await _pumpLoaded(
        tester,
        ds,
        controller,
        (context, id, message, status, runLayout) => SizedBox(
          height: 60,
          child: Text(message == null ? 'shimmer-$id' : 'msg-$id'),
        ),
        selection: selection,
      );

      expect(find.byType(SelectableMessage), findsNWidgets(2));

      ds.removeMessages([1]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('msg-1'), findsNothing);
      expect(find.byType(SelectableMessage), findsOneWidget);
    });

    testWidgets('delete non-anchor oldest skips builder for absent id', (
      tester,
    ) async {
      final ds = _LoadedSource([_msg(1), _msg(2), _msg(3)]);
      final controller = ChatScrollController()..jumpTo(3);
      final tracker = _InvokeTracker();
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await _pumpLoaded(tester, ds, controller, tracker.builder);
      tracker.reset();

      ds.removeMessages([1]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tracker.ids, isNot(contains(1)));
      expect(find.text('msg-2'), findsOneWidget);
      expect(find.text('msg-3'), findsOneWidget);
    });

    testWidgets('delete middle of three leaves no shimmer at absent id', (
      tester,
    ) async {
      final ds = _LoadedSource([_msg(1), _msg(2), _msg(3)]);
      final controller = ChatScrollController()..jumpTo(3);
      final tracker = _InvokeTracker();
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await _pumpLoaded(tester, ds, controller, tracker.builder);
      tracker.reset();

      ds.removeMessages([2]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tracker.ids, isNot(contains(2)));
      expect(find.text('shimmer-2'), findsNothing);
    });

    testWidgets('removed id is not built on subsequent layout passes', (
      tester,
    ) async {
      final ds = _LoadedSource([_msg(1), _msg(2)]);
      final controller = ChatScrollController()..jumpTo(2);
      final tracker = _InvokeTracker();
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await _pumpLoaded(tester, ds, controller, tracker.builder);
      ds.removeMessages([1]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      tracker.reset();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tracker.ids, isNot(contains(1)));
    });

    testWidgets('tail delete reassigns anchor to previous present', (
      tester,
    ) async {
      final ds = _LoadedSource([_msg(1), _msg(2), _msg(3)]);
      final controller = ChatScrollController()..jumpTo(3);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await _pumpLoaded(
        tester,
        ds,
        controller,
        (context, id, message, status, runLayout) =>
            SizedBox(height: 40, child: Text('msg-$id')),
      );

      ds.removeMessages([3]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(controller.anchorMessageId, 2);
      expect(find.text('msg-2'), findsOneWidget);
    });

    testWidgets('history delete reassigns anchor to next present', (
      tester,
    ) async {
      final ds = _LoadedSource([_msg(1), _msg(2)]);
      final controller = ChatScrollController()..jumpTo(1);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await _pumpLoaded(
        tester,
        ds,
        controller,
        (context, id, message, status, runLayout) =>
            SizedBox(height: 40, child: Text('msg-$id')),
      );

      ds.removeMessages([1]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(controller.anchorMessageId, 2);
    });

    testWidgets('delete sole message shows empty state without shimmer loop', (
      tester,
    ) async {
      final ds = _LoadedSource([_msg(1)]);
      final controller = ChatScrollController()..jumpTo(1);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await _pumpLoaded(
        tester,
        ds,
        controller,
        (context, id, message, status, runLayout) =>
            SizedBox(height: 40, child: Text('msg-$id')),
        emptyBuilder: (context) => const Text('empty-chat'),
      );

      ds.removeMessages([1]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(ds.isEmpty, isTrue);
      expect(find.text('msg-1'), findsNothing);
      expect(find.text('shimmer-1'), findsNothing);
      expect(find.text('empty-chat'), findsOneWidget);
    });

    testWidgets('unloaded dirty id still invokes builder for shimmer', (
      tester,
    ) async {
      final ds = _SparseUnloadedSource();
      final controller = ChatScrollController()..jumpTo(3);
      final tracker = _InvokeTracker();
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await _pumpLoaded(tester, ds, controller, tracker.builder);

      expect(tracker.ids, contains(3));
      expect(find.text('shimmer-3'), findsOneWidget);
    });

    testWidgets('demo bubble delete anchor shows sender on survivor', (
      tester,
    ) async {
      final ds = _LoadedSource([_msg(1, content: 'a'), _msg(2, content: 'b')]);
      final controller = ChatScrollController()..jumpTo(1);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);

      await tester.pumpWidget(
        _harness(
          dataSource: ds,
          controller: controller,
          messageBuilder: (context, id, message, status, runLayout) {
            if (message == null) {
              return const Text('shimmer', key: Key('shimmer'));
            }
            return Text(message.sender);
          },
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      ds.removeMessages([1]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('User'), findsOneWidget);
      expect(find.byKey(const Key('shimmer')), findsNothing);
    });
  });
}
