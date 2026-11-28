import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_chunk.dart';
import 'package:chat_scroll_view/src/chat_widgets/chat_data_source_ext.dart';
import 'package:chat_scroll_view/src/chat_widgets/render_chat_scroll_view.dart';
import 'package:content_model/content_model.dart'
    show ChatEventCategory, ChatEventLevel;
import 'package:content_model/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat_message.dart';

IChatMessage _server(int id) => UserChatMessage(
  id: id,
  sender: 'Peer',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  content: 'server-$id',
);

/// An outgoing row the server has not confirmed: its identity is [clientId],
/// its [id] only the position it was inserted at.
final class _Outgoing implements IChatMessage {
  _Outgoing(this.id, this.clientId);

  @override
  final int id;

  final String clientId;

  @override
  String get sender => 'Me';

  @override
  DateTime get createdAt => DateTime(2026);

  @override
  DateTime get updatedAt => DateTime(2026);
}

Object? _identityOf(IChatMessage message) => switch (message) {
  _Outgoing(:final clientId) => clientId,
  _ => null,
};

bool _isSelf(IChatMessage message) => message is _Outgoing;

String _label(IChatMessage? message) => switch (message) {
  _Outgoing(:final clientId) => clientId,
  UserChatMessage(:final content) => content,
  _ => 'shimmer',
};

/// Server history `0 … historyCount-1`, then the outgoing rows of
/// [outgoing] at the positions after it.
class _TailDataSource extends ChatDataSource {
  _TailDataSource(int historyCount, {List<String> outgoing = const []}) {
    for (var i = 0; i < historyCount; i++) {
      server[i] = _server(i);
      upsertMessage(server[i]!);
    }
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: historyCount - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
    identityOf = _identityOf;
    insertMessages([
      for (var i = 0; i < outgoing.length; i++)
        _Outgoing(historyCount + i, outgoing[i]),
    ]);
  }

  /// What the server returns for a range.
  final Map<int, IChatMessage> server = {};

  int notifications = 0;
  final mutations = <ChatMutation>[];

  void startCounting() {
    addDataListener(() => notifications++);
    addMutationListener(mutations.add);
  }

  String? labelAt(int id) => switch (getMessage(id)) {
    final message? => _label(message),
    null => null,
  };

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => [for (var id = fromId; id <= toId; id++) ?server[id]];
}

const double _rowHeight = 60;

Widget _scaffold({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  double Function(IChatMessage? message)? heightOf,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 400,
        height: 600,
        child: ChatScrollView(
          dataSource: dataSource,
          controller: controller,
          isSelfMessage: _isSelf,
          messageBuilder: (context, id, message, status, runLayout) => SizedBox(
            height: heightOf?.call(message) ?? _rowHeight,
            child: Text(_label(message)),
          ),
        ),
      ),
    ),
  ),
);

RenderChatScrollView _render(WidgetTester tester) =>
    tester.renderObject<RenderChatScrollView>(find.byType(ChatScrollView));

double _top(WidgetTester tester, String label) =>
    tester.getTopLeft(find.text(label)).dy;

void main() {
  group('data source', () {
    test('an incoming row takes tip+1 and the tail shifts in one write', () {
      final ds = _TailDataSource(20, outgoing: ['out-A', 'out-B'])
        ..startCounting();
      addTearDown(ds.dispose);

      ds.rebaseTail(order: ['out-A', 'out-B'], insert: [_server(20)]);

      expect(ds.labelAt(20), 'server-20');
      expect(ds.labelAt(21), 'out-A');
      expect(ds.labelAt(22), 'out-B');
      expect(ds.newestKnownId, 22);
      expect(ds.reachedNewest, isTrue);
      expect(ds.notifications, 1);
      expect(ds.mutations, hasLength(1));
      final mutation = ds.mutations.single as RebaseTailMutation;
      expect(mutation.insertedIds, [20]);
      expect(mutation.moved, {20: 21, 21: 22});
      expect(mutation.removedIds, isEmpty);
    });

    test('a reorder with no insertion moves rows in one write', () {
      final ds = _TailDataSource(20, outgoing: ['out-A', 'out-B', 'out-C'])
        ..startCounting();
      addTearDown(ds.dispose);

      // out-C starts publishing: it goes first, the others keep their order.
      ds.rebaseTail(order: ['out-C', 'out-A', 'out-B']);

      expect(
        [ds.labelAt(20), ds.labelAt(21), ds.labelAt(22)],
        ['out-C', 'out-A', 'out-B'],
      );
      expect(ds.newestKnownId, 22);
      expect(ds.notifications, 1);
      final mutation = ds.mutations.single as RebaseTailMutation;
      expect(mutation.insertedIds, isEmpty);
      expect(mutation.moved, {22: 20, 20: 21, 21: 22});
    });

    test('the same order and no insertion changes nothing', () {
      final ds = _TailDataSource(20, outgoing: ['out-A'])..startCounting();
      addTearDown(ds.dispose);

      ds.rebaseTail(order: ['out-A']);

      expect(ds.notifications, 0);
      expect(ds.mutations, isEmpty);
    });

    test('an identity left out of the order leaves the tail atomically', () {
      final ds = _TailDataSource(20, outgoing: ['out-A', 'out-B', 'out-C'])
        ..startCounting();
      addTearDown(ds.dispose);

      ds.rebaseTail(order: ['out-A', 'out-C']);

      expect(ds.labelAt(20), 'out-A');
      expect(ds.labelAt(21), 'out-C');
      expect(ds.labelAt(22), isNull);
      expect(ds.statusOf(22).isAbsent, isTrue);
      expect(ds.newestKnownId, 21);
      expect(ds.notifications, 1);
      final mutation = ds.mutations.single as RebaseTailMutation;
      expect(mutation.removedIds, [21]);
      expect(mutation.moved, {22: 21});

      // The freed position is the next one a message may take.
      ds.insertMessage(_server(22));
      expect(ds.labelAt(22), 'server-22');
    });

    test(
      'removing every provisional row retracts to the newest server row',
      () {
        final ds = _TailDataSource(20, outgoing: ['out-A', 'out-B']);
        addTearDown(ds.dispose);

        ds.rebaseTail(order: const []);

        expect(ds.newestKnownId, 19);
        expect(ds.statusOf(20).isAbsent, isTrue);
        expect(ds.statusOf(21).isAbsent, isTrue);
      },
    );

    test('no staged position is left: an insert at a freed id does not '
        'assert', () {
      final ds = _TailDataSource(20, outgoing: ['out-A', 'out-B']);
      addTearDown(ds.dispose);
      // A host that removed a provisional row through the ordinary call
      // leaves its position staged.
      ds.removeMessages([21]);
      expect(ds.pendingRemovalIds, {21});

      ds.rebaseTail(order: ['out-A'], insert: [_server(20)]);

      expect(ds.pendingRemovalIds, isEmpty);
      expect(ds.labelAt(21), 'out-A');
      expect(ds.nextInsertId, 22);
      ds.insertMessage(_server(22));
      expect(ds.labelAt(22), 'server-22');
    });

    test('the unconfirmed tail covers the shifted range', () async {
      final ds = _TailDataSource(20, outgoing: ['out-A', 'out-B']);
      addTearDown(ds.dispose);
      ds
        ..rebaseTail(order: ['out-A', 'out-B'], insert: [_server(20)])
        ..server[20] = _server(20);

      // The tail chunk is dropped and refetched; the server knows nothing
      // past 20, so 21 and 22 come back empty.
      ds
        ..evictChunk(ChatScrollChunk.chunkOf(22))
        ..requestChunks(0, 0);
      await pumpEventQueue();

      expect(ds.labelAt(20), 'server-20');
      expect(ds.statusOf(21).isAbsent, isFalse);
      expect(ds.statusOf(22).isAbsent, isFalse);
    });

    test('an insert lands before the tail, gaps stay unloaded', () {
      final ds = _TailDataSource(20, outgoing: ['out-A']);
      addTearDown(ds.dispose);

      ds.rebaseTail(order: ['out-A'], insert: [_server(22)]);

      expect(ds.labelAt(20), isNull);
      expect(ds.statusOf(20).isAbsent, isFalse);
      expect(ds.labelAt(22), 'server-22');
      expect(ds.labelAt(23), 'out-A');
      expect(ds.newestKnownId, 23);
    });

    group('refused input', () {
      late RecordingDiagnostics diagnostics;
      setUp(() => diagnostics = RecordingDiagnostics.install());

      void expectRefused(
        _TailDataSource ds,
        void Function() call,
        ChatRebaseRejection rule,
      ) {
        ds.startCounting();
        final before = [for (var id = 18; id <= 23; id++) ds.labelAt(id)];
        expect(call, throwsAssertionError);
        expect([for (var id = 18; id <= 23; id++) ds.labelAt(id)], before);
        expect(ds.notifications, 0);
        expect(ds.mutations, isEmpty);
        final event = diagnostics.whereOp(ChatRebaseOp.orderRejected).single;
        expect(event.level, ChatEventLevel.error);
        expect(event.category, ChatEventCategory.rebase);
        expect(event.fields['rule'], rule);
      }

      test('an identity that is not provisional', () {
        final ds = _TailDataSource(20, outgoing: ['out-A']);
        addTearDown(ds.dispose);
        expectRefused(
          ds,
          () => ds.rebaseTail(order: ['out-A', 'out-Z']),
          ChatRebaseRejection.notProvisional,
        );
      });

      test('a duplicate identity', () {
        final ds = _TailDataSource(20, outgoing: ['out-A', 'out-B']);
        addTearDown(ds.dispose);
        expectRefused(
          ds,
          () => ds.rebaseTail(order: ['out-A', 'out-A']),
          ChatRebaseRejection.duplicateIdentity,
        );
      });

      test('no identityOf', () {
        final ds = _TailDataSource(20, outgoing: ['out-A'])..identityOf = null;
        addTearDown(ds.dispose);
        expectRefused(
          ds,
          () => ds.rebaseTail(order: ['out-A']),
          ChatRebaseRejection.identityOfNull,
        );
      });

      test('an insert that is provisional itself', () {
        final ds = _TailDataSource(20, outgoing: ['out-A']);
        addTearDown(ds.dispose);
        expectRefused(
          ds,
          () =>
              ds.rebaseTail(order: ['out-A'], insert: [_Outgoing(20, 'out-B')]),
          ChatRebaseRejection.insertInsideTail,
        );
      });

      test('an insert below the tail', () {
        final ds = _TailDataSource(20, outgoing: ['out-A']);
        addTearDown(ds.dispose);
        expectRefused(
          ds,
          () => ds.rebaseTail(order: ['out-A'], insert: [_server(19)]),
          ChatRebaseRejection.insertBelowTail,
        );
      });
    });

    test('emits rebaseTail and stagingFinalised with counts only', () {
      final diagnostics = RecordingDiagnostics.install();
      final ds = _TailDataSource(20, outgoing: ['out-A', 'out-B']);
      addTearDown(ds.dispose);
      ds
        ..removeMessages([21])
        ..rebaseTail(order: ['out-A'], insert: [_server(20)]);

      final staging = diagnostics.whereOp(ChatRebaseOp.stagingFinalised).single;
      expect(staging.level, ChatEventLevel.trace);
      expect(staging.fields, {'freed': 0, 'reused': 1});

      final event = diagnostics.whereOp(ChatRebaseOp.rebaseTail).single;
      expect(event.level, ChatEventLevel.debug);
      expect(event.category, ChatEventCategory.rebase);
      expect(event.correlation.scrollId, '21');
      expect(event.fields['provisionalBefore'], 1);
      expect(event.fields['provisionalAfter'], 1);
      expect(event.fields['inserted'], 1);
      expect(event.fields['moved'], 1);
      expect(event.fields['reorderOnly'], isFalse);
      expect(event.fields['removed'], 0);
      expect(event.fields['durationUs'], isA<int>());
    });
  });

  group('viewport', () {
    testWidgets('at the tail the outgoing rows keep their place, one layout', (
      tester,
    ) async {
      final ds = _TailDataSource(20, outgoing: ['out-A', 'out-B']);
      final controller = ChatScrollController()..jumpTo(21);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller),
      );
      await tester.pump();
      expect(controller.isAtTail.value, isTrue);
      final aBefore = _top(tester, 'out-A');
      final bBefore = _top(tester, 'out-B');
      ds.startCounting();
      final layoutsBefore = _render(tester).debugLayoutFrameId;

      ds.rebaseTail(order: ['out-A', 'out-B'], insert: [_server(20)]);
      await tester.pump();

      expect(ds.notifications, 1);
      expect(_render(tester).debugLayoutFrameId - layoutsBefore, 1);
      expect(_top(tester, 'out-A'), aBefore);
      expect(_top(tester, 'out-B'), bBefore);
      expect(_top(tester, 'server-20'), aBefore - _rowHeight);
      expect(controller.isAnimating, isFalse);
      expect(controller.isAtTail.value, isTrue);
    });

    testWidgets('a reorder at the tail keeps the bottom', (tester) async {
      final ds = _TailDataSource(20, outgoing: ['out-A', 'out-B']);
      final controller = ChatScrollController()..jumpTo(21);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          heightOf: (message) => switch (message) {
            _Outgoing(clientId: 'out-A') => 140,
            _ => _rowHeight,
          },
        ),
      );
      await tester.pump();
      final bottom = tester.getBottomLeft(find.text('out-B')).dy;

      ds.rebaseTail(order: ['out-B', 'out-A']);
      await tester.pump();

      expect(tester.getBottomLeft(find.text('out-A')).dy, bottom);
      expect(tester.getBottomLeft(find.text('out-B')).dy, bottom - 140);
      expect(controller.isAtTail.value, isTrue);
    });

    testWidgets('a reorder of a tail taller than the band keeps the bottom', (
      tester,
    ) async {
      final outgoing = [for (var i = 0; i < 12; i++) 'out-$i'];
      final ds = _TailDataSource(5, outgoing: outgoing);
      final controller = ChatScrollController()..jumpTo(16);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          heightOf: (message) => switch (message) {
            _Outgoing(clientId: 'out-8') => 200,
            _ => _rowHeight,
          },
        ),
      );
      await tester.pump();
      final bottom = tester.getBottomLeft(find.text('out-11')).dy;

      // The tall row sinks to the end: every row above the bottom changes.
      ds.rebaseTail(
        order: [
          for (final id in outgoing)
            if (id != 'out-8') id,
          'out-8',
        ],
      );
      await tester.pump();

      expect(tester.getBottomLeft(find.text('out-8')).dy, bottom);
      expect(controller.isAtTail.value, isTrue);
    });

    testWidgets('scrolled up, the reader stays put (no self-insert follow)', (
      tester,
    ) async {
      final diagnostics = RecordingDiagnostics.install();
      final ds = _TailDataSource(60, outgoing: ['out-A', 'out-B']);
      final controller = ChatScrollController()..jumpTo(61);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller),
      );
      await tester.pump();
      await tester.drag(find.byType(ChatScrollView), const Offset(0, 900));
      await tester.pump(const Duration(seconds: 1));
      expect(controller.isAtTail.value, isFalse);
      final probe = find.textContaining('server-').first;
      final label = (tester.widget(probe) as Text).data!;
      final probeBefore = _top(tester, label);

      ds.rebaseTail(order: ['out-A', 'out-B'], insert: [_server(60)]);
      await tester.pump();
      expect(controller.isAnimating, isFalse);
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(controller.isAnimating, isFalse);
      expect(controller.isAtTail.value, isFalse);
      expect(_top(tester, label), probeBefore);
      expect(diagnostics.whereOp(ChatRebaseOp.followSuppressed), hasLength(1));
    });

    testWidgets('a pinned animateTo survives the move', (tester) async {
      final diagnostics = RecordingDiagnostics.install();
      final ds = _TailDataSource(254, outgoing: ['out-A', 'out-B']);
      final controller = ChatScrollController()..jumpTo(20);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller),
      );
      await tester.pump();

      final future = controller.animateTo(
        255,
        duration: const Duration(milliseconds: 800),
        highlight: false,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(controller.isAnimating, isTrue);

      ds.rebaseTail(order: ['out-A', 'out-B'], insert: [_server(254)]);
      await tester.pump();

      expect(controller.isAnimating, isTrue);
      final kept = diagnostics.whereOp(ChatRebaseOp.animationKept).single;
      expect(kept.fields['target'], 'tail');
      expect(kept.fields['pinned'], isTrue);
      await tester.pump(const Duration(seconds: 2));
      await future;
      expect(controller.isAnimating, isFalse);
    });
  });
}
