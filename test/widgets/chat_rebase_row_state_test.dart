import 'dart:async';

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_chunk_fetch_scheduler.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_chunk.dart';
import 'package:chat_scroll_view/src/chat_widgets/render_chat_scroll_view.dart';
import 'package:content_model/content_model.dart'
    show ChatEventCategory, ChatEventLevel;
import 'package:content_model/testing.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
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
  _Outgoing(this.id, this.clientId, {this.text = ''});

  @override
  final int id;

  final String clientId;

  /// Body text, changed by an edit.
  final String text;

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
  _TailDataSource(
    int historyCount, {
    List<String> outgoing = const [],
    this.chunkBudget = 16,
  }) {
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

  final int chunkBudget;

  @override
  int get maxChunks => chunkBudget;

  /// What the server returns for a range.
  final Map<int, IChatMessage> server = {};

  final mutations = <ChatMutation>[];

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

/// A host row with widget state of its own: it records the label of the
/// message it was first built for, so a test sees whose state a slot holds.
class _Row extends StatefulWidget {
  const _Row({required this.label});

  final String label;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  late final String bornFor = widget.label;

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: 60, child: Text(widget.label));
}

_RowState _rowState(WidgetTester tester, String label) => tester.state(
  find.ancestor(of: find.text(label), matching: find.byType(_Row)),
);

Widget _scaffold({
  required ChatDataSource dataSource,
  required ChatScrollController controller,
  ChatMessageBuilder? messageBuilder,
  ChatSelectionController? selection,
  ValueListenable<int?>? unreadBoundary,
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
          selectionController: selection,
          unreadBoundary: unreadBoundary,
          unreadSeparatorBuilder: unreadBoundary == null
              ? null
              : (context) => const SizedBox(height: 20, child: Text('unread')),
          messageBuilder:
              messageBuilder ??
              (context, id, message, status, runLayout) =>
                  _Row(label: _label(message)),
        ),
      ),
    ),
  ),
);

void main() {
  group('row widget state', () {
    testWidgets('follows the moved message; the incoming row starts fresh', (
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
      final stateA = _rowState(tester, 'out-A');
      final stateB = _rowState(tester, 'out-B');

      ds.rebaseTail(order: ['out-A', 'out-B'], insert: [_server(20)]);
      await tester.pump();

      expect(ds.labelAt(21), 'out-A');
      expect(_rowState(tester, 'out-A'), same(stateA));
      expect(_rowState(tester, 'out-B'), same(stateB));
      expect(_rowState(tester, 'server-20').bornFor, 'server-20');
    });

    testWidgets('a reorder carries each row; a removed row passes on none', (
      tester,
    ) async {
      final ds = _TailDataSource(20, outgoing: ['out-A', 'out-B', 'out-C']);
      final controller = ChatScrollController()..jumpTo(22);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller),
      );
      await tester.pump();
      final stateA = _rowState(tester, 'out-A');
      final stateC = _rowState(tester, 'out-C');

      // out-B leaves, out-C goes first, an incoming row takes tip+1.
      ds.rebaseTail(order: ['out-C', 'out-A'], insert: [_server(20)]);
      await tester.pump();

      expect(
        [ds.labelAt(20), ds.labelAt(21), ds.labelAt(22)],
        ['server-20', 'out-C', 'out-A'],
      );
      expect(_rowState(tester, 'out-A'), same(stateA));
      expect(_rowState(tester, 'out-C'), same(stateC));
      expect(_rowState(tester, 'server-20').bornFor, 'server-20');
      expect(find.text('out-B'), findsNothing);
    });

    testWidgets('a running change transition follows its message', (
      tester,
    ) async {
      final ds = _TailDataSource(20, outgoing: ['out-A']);
      final controller = ChatScrollController()..jumpTo(20);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          messageBuilder: (context, id, message, status, runLayout) =>
              ChatMessageChangeTransition(
                contentIdentity: switch (message) {
                  _Outgoing(:final text) => text,
                  _ => _label(message),
                },
                content: Text(_label(message)),
                metaBuilder: (context, editedOpacity) =>
                    const SizedBox(width: 20, height: 12),
                color: const Color(0xFF2196F3),
                borderRadius: BorderRadius.zero,
                outgoing: _isSelf(message ?? _server(0)),
              ),
        ),
      );
      await tester.pump();
      // The host edits the outgoing row in place: the edit morph starts.
      ds.updateMessage(_Outgoing(20, 'out-A', text: 'edited'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      State transitionOf(String label) => tester.state(
        find.ancestor(
          of: find.text(label).first,
          matching: find.byType(ChatMessageChangeTransition),
        ),
      );
      final running = transitionOf('out-A');
      expect(tester.hasRunningAnimations, isTrue);

      ds.rebaseTail(order: ['out-A'], insert: [_server(20)]);
      await tester.pump();

      expect(transitionOf('out-A'), same(running));
      expect(tester.hasRunningAnimations, isTrue);
      expect(transitionOf('server-20'), isNot(same(running)));
      await tester.pumpAndSettle();
    });
  });

  group('message selection', () {
    testWidgets('membership follows the moved message', (tester) async {
      final ds = _TailDataSource(20, outgoing: ['out-A', 'out-B', 'out-C']);
      final controller = ChatScrollController()..jumpTo(22);
      final selection = ChatSelectionController()
        ..startSelection(18)
        ..toggle(20)
        ..toggle(21);
      addTearDown(selection.dispose);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller, selection: selection),
      );
      await tester.pump();

      // out-B (21) leaves, the incoming row takes 20: out-A goes to 21.
      ds.rebaseTail(order: ['out-A', 'out-C'], insert: [_server(20)]);
      await tester.pump();

      expect(ds.labelAt(21), 'out-A');
      expect(selection.selectedIds, {18, 21});
      expect(selection.isSelected(20), isFalse);
    });
  });

  group('message highlight', () {
    testWidgets('follows the moved message', (tester) async {
      final ds = _TailDataSource(20, outgoing: ['out-A', 'out-B']);
      final controller = ChatScrollController()..jumpTo(21);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller),
      );
      await tester.pump();
      RenderChatScrollView render() =>
          tester.renderObject(find.byType(ChatScrollView));
      controller.highlight(21);
      await tester.pump();
      expect(render().debugSnapshot.highlightTargetId, 21);

      ds.rebaseTail(order: ['out-A', 'out-B'], insert: [_server(20)]);
      await tester.pump();

      expect(ds.labelAt(22), 'out-B');
      expect(render().debugSnapshot.highlightTargetId, 22);
      await tester.pumpAndSettle();
    });
  });

  group('open message menu', () {
    testWidgets('on a moved row closes; on a row that stays, stays open', (
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
      final context = tester.element(find.byType(ChatScrollView));

      Future<ChatMessageMenuResult?> open(int id) {
        // The host's usual presence watch, through the row it opened on.
        final row = ds.rowPresence(id);
        return ChatMessageMenu.show(
          context: context,
          messageRect: const Rect.fromLTWH(40, 120, 200, 48),
          items: const [
            ChatMessageMenuItem(id: 'copy', label: 'Copy', icon: Icons.copy),
          ],
          presence: row,
          isPresent: () => row.isPresent,
        );
      }

      ChatMessageMenuResult? moved;
      var movedDone = false;
      unawaited(
        open(21).then((result) {
          moved = result;
          movedDone = true;
        }),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Copy'), findsOneWidget);

      ds.rebaseTail(order: ['out-A', 'out-B'], insert: [_server(20)]);
      await tester.pump();
      expect(movedDone, isTrue);
      expect(moved, isNull);
      await tester.pumpAndSettle();
      expect(find.text('Copy'), findsNothing);

      var stayedDone = false;
      unawaited(open(19).then((_) => stayedDone = true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      ds.rebaseTail(order: ['out-B', 'out-A']);
      await tester.pump();
      expect(stayedDone, isFalse);
      expect(find.text('Copy'), findsOneWidget);
    });
  });

  group('text selection', () {
    Future<ChatSelectionController> mount(
      WidgetTester tester,
      _TailDataSource ds,
    ) async {
      final controller = ChatScrollController()..jumpTo(21);
      final selection = ChatSelectionController(
        policy: const ChatSelectionPolicy.mobile(),
      );
      addTearDown(selection.dispose);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller, selection: selection),
      );
      await tester.pump();
      return selection;
    }

    testWidgets('on a moved row is cleared', (tester) async {
      final ds = _TailDataSource(20, outgoing: ['out-A', 'out-B']);
      addTearDown(ds.dispose);
      final selection = await mount(tester, ds);
      selection
        ..putBody(21, Markdown.fromString('outgoing body text'))
        ..startSelection(21);
      expect(selection.enterTextSelection(21), isTrue);
      expect(selection.selectAllText(), isTrue);

      ds.rebaseTail(order: ['out-A', 'out-B'], insert: [_server(20)]);
      await tester.pump();

      expect(selection.isTextSelectionActive, isFalse);
      expect(selection.textSelectionSubject, isNull);
      // Message selection still carries over.
      expect(selection.selectedIds, {22});
    });

    testWidgets('on a row the move leaves in place is kept', (tester) async {
      final ds = _TailDataSource(20, outgoing: ['out-A', 'out-B']);
      addTearDown(ds.dispose);
      final selection = await mount(tester, ds);
      selection
        ..putBody(19, Markdown.fromString('server body text'))
        ..startSelection(19);
      expect(selection.enterTextSelection(19), isTrue);
      expect(selection.selectAllText(), isTrue);

      ds.rebaseTail(order: ['out-B', 'out-A']);
      await tester.pump();

      expect(selection.isTextSelectionActive, isTrue);
      expect(selection.textSelectionSubject, 19);
    });
  });

  group('diagnostics', () {
    testWidgets('rowStateCarried counts what followed, no user content', (
      tester,
    ) async {
      final diagnostics = RecordingDiagnostics.install();
      final ds = _TailDataSource(20, outgoing: ['out-A', 'out-B']);
      final controller = ChatScrollController()..jumpTo(21);
      final selection = ChatSelectionController(
        policy: const ChatSelectionPolicy.mobile(),
      )..startSelection(21);
      addTearDown(selection.dispose);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller, selection: selection),
      );
      await tester.pump();
      controller.highlight(20);
      await tester.pump();
      final row = ds.rowPresence(20);
      void onRow() {}
      row.addListener(onRow);
      addTearDown(() => row.removeListener(onRow));

      ds.rebaseTail(order: ['out-A', 'out-B'], insert: [_server(20)]);
      await tester.pump();

      final event = diagnostics.whereOp(ChatRebaseOp.rowStateCarried).single;
      expect(event.level, ChatEventLevel.debug);
      expect(event.category, ChatEventCategory.rebase);
      expect(event.correlation.scrollId, '20');
      expect(event.fields, {
        'toScrollId': '21',
        'selectionCarried': 1,
        'highlightCarried': true,
        'transitionsCarried': 2,
        'textSelectionsCleared': 0,
        'menusClosed': 1,
      });
      await tester.pumpAndSettle();
    });
  });

  group('range fetch inside the tail', () {
    Future<_TailDataSource> refetch(
      _TailDataSource ds,
      List<int> serverIds,
    ) async {
      for (final id in serverIds) {
        ds.server[id] = _server(id);
      }
      ds
        ..addMutationListener(ds.mutations.add)
        ..invalidate()
        ..requestChunks(0, 0);
      await pumpEventQueue();
      return ds;
    }

    test('server rows at provisional positions go before the tail', () async {
      final diagnostics = RecordingDiagnostics.install();
      final ds = _TailDataSource(20, outgoing: ['out-A', 'out-B']);
      addTearDown(ds.dispose);

      await refetch(ds, [20, 21]);

      expect(
        [for (var id = 19; id <= 23; id++) ds.labelAt(id)],
        ['server-19', 'server-20', 'server-21', 'out-A', 'out-B'],
      );
      expect(ds.newestKnownId, 23);
      final rebase = ds.mutations.whereType<RebaseTailMutation>().single;
      expect(rebase.insertedIds, [20, 21]);
      expect(rebase.moved, {20: 22, 21: 23});
      final event = diagnostics.whereOp(ChatRebaseOp.fetchInsideTail).single;
      expect(event.level, ChatEventLevel.info);
      expect(event.category, ChatEventCategory.rebase);
      expect(event.correlation.scrollId, '20');
      expect(event.fields, {'rows': 2});
    });

    test('a server row past the tail shifts it past that row too', () async {
      final ds = _TailDataSource(20, outgoing: ['out-A', 'out-B']);
      addTearDown(ds.dispose);

      await refetch(ds, [20, 21, 22]);

      expect(
        [for (var id = 20; id <= 24; id++) ds.labelAt(id)],
        ['server-20', 'server-21', 'server-22', 'out-A', 'out-B'],
      );
    });

    testWidgets('carries the shifted rows like any move', (tester) async {
      final ds = _TailDataSource(20, outgoing: ['out-A', 'out-B']);
      final controller = ChatScrollController()..jumpTo(21);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      await tester.pumpWidget(
        _scaffold(dataSource: ds, controller: controller),
      );
      await tester.pump();
      final stateA = _rowState(tester, 'out-A');

      await tester.runAsync(() => refetch(ds, [20]));
      await tester.pump();

      expect(ds.labelAt(21), 'out-A');
      expect(_rowState(tester, 'out-A'), same(stateA));
      expect(_rowState(tester, 'server-20').bornFor, 'server-20');
    });

    test('a fetch with nothing inside the tail does not move it', () async {
      final diagnostics = RecordingDiagnostics.install();
      final ds = _TailDataSource(20, outgoing: ['out-A', 'out-B']);
      addTearDown(ds.dispose);

      await refetch(ds, const []);

      expect(ds.labelAt(20), 'out-A');
      expect(ds.labelAt(21), 'out-B');
      expect(ds.mutations.whereType<RebaseTailMutation>(), isEmpty);
      expect(diagnostics.whereOp(ChatRebaseOp.fetchInsideTail), isEmpty);
    });
  });

  group('unread boundary', () {
    testWidgets('stays on its server row across a move', (tester) async {
      final ds = _TailDataSource(20, outgoing: ['out-A', 'out-B']);
      final controller = ChatScrollController()..jumpTo(21);
      final boundary = ValueNotifier<int?>(19);
      addTearDown(boundary.dispose);
      addTearDown(controller.dispose);
      addTearDown(ds.dispose);
      await tester.pumpWidget(
        _scaffold(
          dataSource: ds,
          controller: controller,
          unreadBoundary: boundary,
        ),
      );
      await tester.pump();
      double gap() =>
          tester.getTopLeft(find.text('server-19')).dy -
          tester.getTopLeft(find.text('unread')).dy;
      expect(gap(), 20);

      ds.rebaseTail(order: ['out-B', 'out-A'], insert: [_server(20)]);
      await tester.pump();

      expect(boundary.value, 19);
      expect(find.text('unread'), findsOneWidget);
      expect(gap(), 20);
    });
  });

  group('chunk eviction', () {
    test('never drops a chunk that holds provisional rows', () {
      // History fills chunks 0-3; the tail sits at the end of chunk 3.
      final ds = _TailDataSource(
        200,
        outgoing: ['out-A', 'out-B'],
        chunkBudget: 1,
      );
      addTearDown(ds.dispose);
      final scheduler = ChatChunkFetchScheduler(
        dataSource: ds,
        requestRange: (_, _, {allowWiden = true}) {},
        anchorChunkIndex: () => 0,
      );
      addTearDown(scheduler.dispose);

      // The reader is at the top of history: every other chunk may go.
      scheduler.onLayoutComplete(0, 0);

      expect(ds.chunkAt(ChatScrollChunk.chunkOf(200)), isNotNull);
      expect(ds.chunkAt(1), isNull);
      expect(ds.chunkAt(2), isNull);
      ds.rebaseTail(order: ['out-B', 'out-A']);
      expect(ds.labelAt(200), 'out-B');
      expect(ds.labelAt(201), 'out-A');
    });
  });
}
