import 'package:chat_outbox/chat_outbox.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A row of the chat: outgoing while [clientMessageId] is set.
final class _Row implements IChatMessage {
  _Row(this.id, [this.clientMessageId]);

  @override
  final int id;

  final String? clientMessageId;

  String get label => clientMessageId ?? 'server-$id';

  @override
  String get sender => clientMessageId == null ? 'peer' : 'me';

  @override
  DateTime get createdAt => DateTime.utc(2026);

  @override
  DateTime get updatedAt => DateTime.utc(2026);
}

/// Confirmed history `0 … historyCount-1`, rows matched by client message id.
final class _Chat extends ChatDataSource {
  _Chat(int historyCount) {
    upsertMessages([for (var id = 0; id < historyCount; id++) _Row(id)]);
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: historyCount - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
    identityOf = (message) => switch (message) {
      _Row(:final clientMessageId?) => clientMessageId,
      _ => null,
    };
  }

  String? labelAt(int id) => switch (getMessage(id)) {
    _Row(:final label) => label,
    _ => null,
  };

  List<String?> labels(int from, int to) => [
    for (var id = from; id <= to; id++) labelAt(id),
  ];

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => [];
}

const double _rowHeight = 60;

Widget _view(ChatDataSource chat, ChatScrollController controller) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            height: 600,
            child: ChatScrollView(
              dataSource: chat,
              controller: controller,
              isSelfMessage: (message) => message.sender == 'me',
              messageBuilder: (context, id, message, status, runLayout) =>
                  SizedBox(
                    height: _rowHeight,
                    child: Text(switch (message) {
                      _Row(:final label) => label,
                      _ => 'shimmer',
                    }),
                  ),
            ),
          ),
        ),
      ),
    );

void main() {
  for (final (name, create) in <(String, OutgoingIdStrategy Function(_Chat))>[
    (
      'SequentialServerIds',
      (chat) =>
          SequentialServerIds(chatId: 'c1', tail: OutgoingTailTarget.of(chat)),
    ),
    (
      'LocalIds',
      (chat) => LocalIds(chatId: 'c1', tail: OutgoingTailTarget.of(chat)),
    ),
  ]) {
    group('$name over a ChatDataSource', () {
      late _Chat chat;
      late OutgoingIdStrategy strategy;

      setUp(() {
        chat = _Chat(20);
        strategy = create(chat);
      });

      tearDown(() => chat.dispose());

      void allocate(String id) => strategy.allocate(id, (p) => _Row(p, id));

      test('rows take tip+1 … tip+k and every move lands in the rows', () {
        allocate('a');
        allocate('b');
        allocate('c');
        expect(chat.labels(19, 22), ['server-19', 'a', 'b', 'c']);

        strategy.incoming([_Row(20)]);
        expect(chat.labels(20, 23), ['server-20', 'a', 'b', 'c']);
        expect(chat.newestKnownId, 23);

        strategy
          ..fail('a')
          ..publishStart('c');
        expect(chat.labels(21, 23), ['c', 'b', 'a']);
        for (final id in ['c', 'b', 'a']) {
          expect(chat.labelAt(strategy.positionOf(id)!), id);
        }

        final confirmed = strategy.confirm('c')!;
        chat.updateMessage(_Row(confirmed));
        expect(confirmed, 21);
        expect(strategy.tip, 21);

        strategy.remove('b');
        expect(chat.labels(21, 23), ['server-21', 'a', null]);
        expect(chat.newestKnownId, 22);
        expect(strategy.positionOf('a'), 22);
        allocate('d');
        expect(chat.labels(22, 24), ['d', 'a', null]);
      });

      test('one data notification per move', () {
        allocate('a');
        allocate('b');
        var notifications = 0;
        chat.addDataListener(() => notifications++);

        strategy.incoming([_Row(20)]);

        expect(notifications, 1);
      });

      test('the data source refuses nothing the strategy asks', () {
        final diagnostics = RecordingDiagnostics.install();
        allocate('a');
        allocate('b');
        strategy
          ..fail('a')
          ..incoming([_Row(20), _Row(21)])
          ..retry('a')
          ..publishStart('a')
          ..remove('b');
        allocate('c');
        strategy.confirm('a');

        expect(diagnostics.whereOp(ChatRebaseOp.orderRejected), isEmpty);
      });
    });
  }

  group('an incoming message during an upload', () {
    testWidgets('at the tail: the outgoing row keeps its place, the incoming '
        'row appears above it', (tester) async {
      final chat = _Chat(20);
      final strategy = SequentialServerIds(
        chatId: 'c1',
        tail: OutgoingTailTarget.of(chat),
      );
      final controller = ChatScrollController()..jumpTo(19);
      addTearDown(controller.dispose);
      addTearDown(chat.dispose);
      await tester.pumpWidget(_view(chat, controller));
      await tester.pump();
      strategy.allocate('out', (position) => _Row(position, 'out'));
      await tester.pumpAndSettle();
      expect(controller.isAtTail.value, isTrue);
      final outTop = tester.getTopLeft(find.text('out')).dy;

      expect(strategy.incoming([_Row(20)]), isTrue);
      await tester.pump();

      expect(tester.getTopLeft(find.text('out')).dy, outTop);
      expect(tester.getTopLeft(find.text('server-20')).dy, outTop - _rowHeight);
      expect(controller.isAtTail.value, isTrue);
      expect(strategy.positionOf('out'), 21);
    });

    testWidgets('scrolled up: the reader stays where they are', (tester) async {
      final chat = _Chat(60);
      final strategy = SequentialServerIds(
        chatId: 'c1',
        tail: OutgoingTailTarget.of(chat),
      );
      final controller = ChatScrollController()..jumpTo(59);
      addTearDown(controller.dispose);
      addTearDown(chat.dispose);
      await tester.pumpWidget(_view(chat, controller));
      await tester.pump();
      strategy.allocate('out', (position) => _Row(position, 'out'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ChatScrollView), const Offset(0, 900));
      await tester.pumpAndSettle();
      expect(controller.isAtTail.value, isFalse);
      final probe = find.textContaining('server-').first;
      final label = (tester.widget(probe) as Text).data!;
      final probeTop = tester.getTopLeft(find.text(label)).dy;

      strategy.incoming([_Row(60)]);
      for (var i = 0; i < 120; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(controller.isAnimating, isFalse);
      expect(controller.isAtTail.value, isFalse);
      expect(tester.getTopLeft(find.text(label)).dy, probeTop);
      expect(strategy.positionOf('out'), 61);
    });
  });
}
