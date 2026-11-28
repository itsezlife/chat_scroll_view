import 'package:chat_outbox/chat_outbox.dart';
import 'package:chat_outbox/src/outbox/outbox_projection.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/note_payload_codec.dart';
import '../support/outgoing_messages.dart';

void main() {
  late OutboxProjection projection;
  late ChatOutbox<Note> outbox;

  setUp(() {
    projection = OutboxProjection();
    outbox = outboxOver(projection);
  });

  group('byClientMessageId', () {
    test('finds the outgoing message by its id in its chat', () {
      final message = outgoingNote(const ClientMessageId('m1'), position: 103);
      projection
        ..put(outgoingNote(const ClientMessageId('m0'), position: 102))
        ..put(message);

      expect(
        outbox.byClientMessageId(
          const ChatId('c1'),
          const ClientMessageId('m1'),
        ),
        message,
      );
    });

    test('answers null for an id never sent, or sent to another chat', () {
      projection.put(outgoingNote(const ClientMessageId('m1')));

      expect(
        outbox.byClientMessageId(
          const ChatId('c1'),
          const ClientMessageId('m2'),
        ),
        isNull,
      );
      expect(
        outbox.byClientMessageId(
          const ChatId('c2'),
          const ClientMessageId('m1'),
        ),
        isNull,
      );
    });

    test('answers null after the message is Absent', () {
      projection.put(outgoingNote(const ClientMessageId('m1')));

      projection.remove(const ChatId('c1'), const ClientMessageId('m1'));

      expect(
        outbox.byClientMessageId(
          const ChatId('c1'),
          const ClientMessageId('m1'),
        ),
        isNull,
      );
    });

    test('finds the message by id whatever its position', () {
      projection
        ..put(outgoingNote(const ClientMessageId('m1'), position: 101))
        ..put(outgoingNote(const ClientMessageId('m1'), position: 102));

      expect(
        outbox
            .byClientMessageId(const ChatId('c1'), const ClientMessageId('m1'))
            ?.position,
        102,
      );
    });

    test('reports echoMatched with the match and its status', () {
      final diagnostics = RecordingDiagnostics.install();
      projection.put(
        outgoingNote(
          const ClientMessageId('m1'),
          position: 104,
          status: const OutgoingStatus.publishing(),
        ),
      );

      outbox
        ..byClientMessageId(const ChatId('c1'), const ClientMessageId('m1'))
        ..byClientMessageId(const ChatId('c1'), const ClientMessageId('m9'));

      expect(diagnostics.whereOp(OutboxOp.echoMatched), [
        isChatEvent(
          level: ChatEventLevel.debug,
          category: ChatEventCategory.outbox,
          correlation: const ChatCorrelation(
            chatId: 'c1',
            clientMessageId: 'm1',
            scrollId: '104',
          ),
          fields: {'matched': true, 'status': 'publishing'},
        ),
        isChatEvent(
          level: ChatEventLevel.debug,
          correlation: const ChatCorrelation(
            chatId: 'c1',
            clientMessageId: 'm9',
          ),
          fields: {'matched': false},
        ),
      ]);
    });
  });

  group('isFreshOutgoing', () {
    test('answers true once for a fresh message, then false', () {
      projection.put(outgoingNote(const ClientMessageId('m1')), fresh: true);

      expect(
        outbox.isFreshOutgoing(const ChatId('c1'), const ClientMessageId('m1')),
        isTrue,
      );
      expect(
        outbox.isFreshOutgoing(const ChatId('c1'), const ClientMessageId('m1')),
        isFalse,
      );
      expect(
        outbox.isFreshOutgoing(const ChatId('c1'), const ClientMessageId('m1')),
        isFalse,
      );
    });

    test('a status change before the host asks keeps the message fresh', () {
      projection
        ..put(outgoingNote(const ClientMessageId('m1')), fresh: true)
        ..put(
          outgoingNote(
            const ClientMessageId('m1'),
            status: const OutgoingStatus.publishing(),
          ),
        );

      expect(
        outbox.isFreshOutgoing(const ChatId('c1'), const ClientMessageId('m1')),
        isTrue,
      );
    });

    test('answers false for a message not fresh, unknown or Absent', () {
      projection
        ..put(outgoingNote(const ClientMessageId('restored')))
        ..put(outgoingNote(const ClientMessageId('gone')), fresh: true)
        ..remove(const ChatId('c1'), const ClientMessageId('gone'));

      expect(
        outbox.isFreshOutgoing(
          const ChatId('c1'),
          const ClientMessageId('restored'),
        ),
        isFalse,
      );
      expect(
        outbox.isFreshOutgoing(
          const ChatId('c1'),
          const ClientMessageId('never'),
        ),
        isFalse,
      );
      expect(
        outbox.isFreshOutgoing(
          const ChatId('c1'),
          const ClientMessageId('gone'),
        ),
        isFalse,
      );
    });

    test('is per chat', () {
      projection.put(
        outgoingNote(const ClientMessageId('m1'), chatId: const ChatId('c2')),
        fresh: true,
      );

      expect(
        outbox.isFreshOutgoing(const ChatId('c1'), const ClientMessageId('m1')),
        isFalse,
      );
      expect(
        outbox.isFreshOutgoing(const ChatId('c2'), const ClientMessageId('m1')),
        isTrue,
      );
    });

    test('reports freshOutgoingTaken with each answer', () {
      final diagnostics = RecordingDiagnostics.install();
      projection.put(outgoingNote(const ClientMessageId('m1')), fresh: true);

      outbox
        ..isFreshOutgoing(const ChatId('c1'), const ClientMessageId('m1'))
        ..isFreshOutgoing(const ChatId('c1'), const ClientMessageId('m1'));

      expect(diagnostics.whereOp(OutboxOp.freshOutgoingTaken), [
        isChatEvent(
          level: ChatEventLevel.trace,
          category: ChatEventCategory.outbox,
          correlation: const ChatCorrelation(
            chatId: 'c1',
            clientMessageId: 'm1',
          ),
          fields: {'answered': true},
        ),
        isChatEvent(fields: {'answered': false}),
      ]);
    });
  });
}
