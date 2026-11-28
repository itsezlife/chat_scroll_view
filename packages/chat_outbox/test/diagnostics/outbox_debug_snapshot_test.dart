import 'dart:convert';

import 'package:chat_capabilities/chat_capabilities.dart';
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

  const emptyCounters = {
    'accepted': 0,
    'rebases': <String, Object?>{},
    'conflicts': 0,
    'retries': 0,
    'cancels': 0,
    'restores': 0,
    'itemsDropped': 0,
    'cancelsTooLate': 0,
  };

  test('an empty outbox declares every section', () {
    expect(outbox.debugSnapshot(const ChatId('c1')).toMap(), {
      'chatId': 'c1',
      'strategy': null,
      'tip': null,
      'tail': <Object?>[],
      'publisherRegistered': false,
      'sendInFlight': false,
      'counters': emptyCounters,
    });
  });

  test('a one-row outbox describes the row and its items', () {
    projection.put(
      outgoingNote(
        const ClientMessageId('m1'),
        position: 101,
        text: 'abc',
        items: [outgoingItem(const ClientMessageId('m1'), 0)],
      ),
      fresh: true,
    );

    expect(outbox.debugSnapshot(const ChatId('c1')).toMap(), {
      'chatId': 'c1',
      'strategy': null,
      'tip': null,
      'tail': [
        {
          'position': 101,
          'clientMessageId': 'm1',
          'status': 'uploading',
          'failure': null,
          // {"text":"abc","silent":false}
          'payloadBytes': 29,
          'fresh': true,
          'jobId': null,
          'jobState': null,
          'stage': null,
          'attempts': null,
          'items': [
            {
              'mediaItemId': 'item:m1:0',
              'localKey': 'document:local-m1-0',
              'mediaKey': null,
              'transfer': null,
              'sendOriginHeld': false,
            },
          ],
        },
      ],
      'publisherRegistered': false,
      'sendInFlight': true,
      'counters': emptyCounters,
    });
  });

  test('rows are in tail order, a failed row with its reason form', () {
    projection
      ..put(
        outgoingNote(
          const ClientMessageId('late'),
          position: 103,
          status: const OutgoingStatus.failed(
            OutgoingFailure.denied(CapabilityAction.sendPhoto),
          ),
        ),
      )
      ..put(outgoingNote(const ClientMessageId('early'), position: 102))
      ..put(
        outgoingNote(
          const ClientMessageId('other chat'),
          chatId: const ChatId('c2'),
        ),
      );

    final tail = outbox.debugSnapshot(const ChatId('c1')).tail;

    expect(tail.map((row) => row.clientMessageId), ['early', 'late']);
    expect(tail.last.status, 'failed');
    expect(tail.last.failure, 'denied');
  });

  test('reading the snapshot leaves the fresh flag unread', () {
    projection.put(outgoingNote(const ClientMessageId('m1')), fresh: true);

    outbox
      ..debugSnapshot(const ChatId('c1'))
      ..debugSnapshot(const ChatId('c1'));

    expect(
      outbox.isFreshOutgoing(const ChatId('c1'), const ClientMessageId('m1')),
      isTrue,
    );
    expect(outbox.debugSnapshot(const ChatId('c1')).tail.single.fresh, isFalse);
  });

  test('an external local key is reported by its kind only', () {
    projection.put(
      outgoingNote(
        const ClientMessageId('m1'),
        items: [
          const OutgoingItem(
            id: MediaItemId('m1:0'),
            localKey: ContentKey.external('https://host/private/a.jpg'),
          ),
        ],
      ),
    );

    expect(
      outbox
          .debugSnapshot(const ChatId('c1'))
          .tail
          .single
          .items
          .single
          .localKey,
      'external',
    );
  });

  test('the snapshot is JSON-encodable', () {
    projection.put(
      outgoingNote(
        const ClientMessageId('m1'),
        items: [outgoingItem(const ClientMessageId('m1'), 0)],
      ),
    );

    expect(
      () => jsonEncode(outbox.debugSnapshot(const ChatId('c1')).toMap()),
      returnsNormally,
    );
  });

  test('no event and no snapshot carries the payload', () {
    final diagnostics = RecordingDiagnostics.install();
    const secret = 'meet me at the north gate';
    projection.put(
      outgoingNote(
        const ClientMessageId('m1'),
        text: secret,
        status: const OutgoingStatus.failed(OutgoingFailure.rejected('flood')),
        items: [outgoingItem(const ClientMessageId('m1'), 0)],
      ),
      fresh: true,
    );

    outbox
      ..byClientMessageId(const ChatId('c1'), const ClientMessageId('m1'))
      ..isFreshOutgoing(const ChatId('c1'), const ClientMessageId('m1'));
    final snapshot = jsonEncode(
      outbox.debugSnapshot(const ChatId('c1')).toMap(),
    );

    expect(diagnostics.events, isNotEmpty);
    for (final event in diagnostics.events) {
      expect('$event', isNot(contains('north gate')));
      expect('$event', isNot(contains('flood')));
    }
    expect(snapshot, isNot(contains('north gate')));
    expect(snapshot, isNot(contains('flood')));
    expect(
      '${outbox.byClientMessageId(const ChatId('c1'), const ClientMessageId('m1'))}',
      isNot(contains('north gate')),
    );
  });
}
