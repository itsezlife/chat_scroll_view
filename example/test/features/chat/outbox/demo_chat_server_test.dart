import 'dart:async';

import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_chat_server.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const chat = 'c1';

  DemoServerSend sendOf(
    String clientMessageId, {
    int? proposedId,
    List<String> itemIds = const [],
    String body = 'hi',
  }) => DemoServerSend(
    chatId: chat,
    clientMessageId: clientMessageId,
    proposedId: proposedId,
    sender: 'me',
    body: body,
    itemIds: itemIds,
  );

  group('accept-if-next', () {
    test('a send proposing the next id is stored there and echoed', () {
      fakeAsync((async) {
        final server = DemoChatServer()..open(chat, nextId: 10);
        final delivered = <DemoServerMessage>[];
        server.deliveries(chat).listen(delivered.add);

        DemoServerAnswer? answer;
        server.send(sendOf('m1', proposedId: 10)).then((a) => answer = a);
        async.flushMicrotasks();

        expect(
          answer,
          isA<DemoServerAccepted>()
              .having((a) => a.message.id, 'id', 10)
              .having((a) => a.missing, 'missing', isEmpty),
        );
        expect(server.nextIdOf(chat), 11);
        async.elapse(Duration.zero);
        expect(delivered.single.clientMessageId, 'm1');
      });
    });

    test('a send proposing a taken id is a conflict naming the next id and '
        'the messages the client lacks', () async {
      final server = DemoChatServer()..open(chat, nextId: 10);
      final peer = server.postPeer(chat);

      final answer = await server.send(sendOf('m1', proposedId: 10));

      expect(
        answer,
        isA<DemoServerConflict>().having((a) => a.nextId, 'nextId', 11).having(
          (a) => a.missing,
          'missing',
          [peer],
        ),
      );
      expect(server.nextIdOf(chat), 11);
    });

    test('a send with no proposal takes the next id', () async {
      final server = DemoChatServer()..open(chat, nextId: 3);

      final answer = await server.send(sendOf('m1'));

      expect(
        answer,
        isA<DemoServerAccepted>().having((a) => a.message.id, 'id', 3),
      );
    });

    test('the same client message id sent again answers the stored message '
        '(an idempotent replay)', () async {
      final server = DemoChatServer()..open(chat, nextId: 10);
      await server.send(sendOf('m1', proposedId: 10));

      final again = await server.send(sendOf('m1', proposedId: 11));

      expect(
        again,
        isA<DemoServerAccepted>().having((a) => a.message.id, 'id', 10),
      );
      expect(server.nextIdOf(chat), 11);
    });
  });

  group('scripts', () {
    test('reject, deny and reupload answer the next send once', () async {
      final server = DemoChatServer()..open(chat, nextId: 0);

      server.script(chat, DemoServerScript.reject);
      expect(
        await server.send(sendOf('a', proposedId: 0)),
        isA<DemoServerRejected>(),
      );
      server.script(chat, DemoServerScript.deny);
      expect(
        await server.send(sendOf('b', proposedId: 0)),
        isA<DemoServerDenied>(),
      );
      server.script(chat, DemoServerScript.reupload);
      expect(
        await server.send(sendOf('c', proposedId: 0, itemIds: ['c:0'])),
        isA<DemoServerReupload>().having((a) => a.itemIds, 'ids', {'c:0'}),
      );
      expect(
        await server.send(sendOf('c', proposedId: 0, itemIds: ['c:0'])),
        isA<DemoServerAccepted>().having((a) => a.message.id, 'id', 0),
      );
    });

    test('conflict puts a peer message first, unseen until after the '
        'answer', () {
      fakeAsync((async) {
        final server = DemoChatServer()..open(chat, nextId: 5);
        final delivered = <DemoServerMessage>[];
        server.deliveries(chat).listen(delivered.add);
        server.script(chat, DemoServerScript.conflict);

        DemoServerAnswer? answer;
        server.send(sendOf('m', proposedId: 5)).then((a) => answer = a);
        async.flushMicrotasks();

        expect(
          answer,
          isA<DemoServerConflict>().having((a) => a.nextId, 'nextId', 6).having(
            (a) => [for (final m in a.missing) m.id],
            'missing',
            [5],
          ),
        );
        async.elapse(Duration.zero);
        expect([for (final m in delivered) m.id], [5]);
      });
    });

    test(
      'replay stores the message past a peer and answers it at that id',
      () async {
        final server = DemoChatServer()..open(chat, nextId: 5);
        server.script(chat, DemoServerScript.replay);

        final answer = await server.send(sendOf('m', proposedId: 5));

        expect(
          answer,
          isA<DemoServerAccepted>().having((a) => a.message.id, 'id', 6).having(
            (a) => [for (final m in a.missing) m.id],
            'missing',
            [5],
          ),
        );
      },
    );

    test('peer, armed, posts a peer message once the next send starts '
        'uploading', () {
      fakeAsync((async) {
        final server = DemoChatServer(peerDelay: const Duration(seconds: 1))
          ..open(chat, nextId: 5);
        final delivered = <DemoServerMessage>[];
        server.deliveries(chat).listen(delivered.add);
        server.script(chat, DemoServerScript.peer);

        server.sendStarted(chat, 'm');
        async.elapse(const Duration(milliseconds: 900));
        expect(delivered, isEmpty);
        async.elapse(const Duration(milliseconds: 200));

        expect(delivered.single.id, 5);
        expect(delivered.single.clientMessageId, isNull);
        server.sendStarted(chat, 'n');
        async.elapse(const Duration(seconds: 2));
        expect(delivered, hasLength(1));
      });
    });

    test('every scripted event is reported as fakeServer, with the chat and '
        'the message it acted on', () async {
      final diagnostics = RecordingDiagnostics.install();
      final server = DemoChatServer()..open(chat, nextId: 0);

      for (final script in [
        DemoServerScript.reject,
        DemoServerScript.deny,
        DemoServerScript.conflict,
      ]) {
        server.script(chat, script);
        await server.send(sendOf(script.name, proposedId: 0));
      }

      final events = diagnostics.events
          .where((e) => e.op == DemoServerOp.fakeServer)
          .toList();
      expect(
        [for (final e in events) e.fields['event']],
        ['reject', 'deny', 'conflict'],
      );
      expect(
        events.every((e) => e.category == ChatEventCategory.outbox),
        isTrue,
      );
      expect(events.first.correlation.chatId, chat);
      expect(events.first.correlation.clientMessageId, 'reject');
      expect(
        events.every((e) => !'${e.fields}'.contains('hi')),
        isTrue,
        reason: 'no message text in an event',
      );
    });
  });

  test('a peer reads what the user sent after the read delay: the second '
      'check', () {
    fakeAsync((async) {
      final server = DemoChatServer(readDelay: const Duration(seconds: 2))
        ..open(chat, nextId: 0);
      unawaited(server.send(sendOf('m', proposedId: 0)));
      async.flushMicrotasks();
      expect(server.readUpTo(chat).value, isNull);

      async.elapse(const Duration(seconds: 2));

      expect(server.readUpTo(chat).value, 0);
    });
  });

  group('stored form', () {
    const codec = DemoServerMessageCodec();

    test('a message round-trips through its stored row', () {
      final message = DemoServerMessage(
        id: 4,
        sender: 'me',
        body: 'hi',
        extras: const {'invertMedia': true},
        clientMessageId: 'm',
        sentAt: DateTime.utc(2026, 11, 28, 10),
      );

      expect(codec.decode(codec.encode(message)), message);
    });

    test('a row missing a field throws a FormatException naming it', () {
      expect(
        () => codec.decode({'id': 1, 'sender': 'a', 'body': 'b'}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('sentAt'),
          ),
        ),
      );
    });
  });
}
