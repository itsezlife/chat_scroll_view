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
  };

  test('an empty outbox declares every section', () {
    expect(outbox.debugSnapshot('c1').toMap(), {
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
        'm1',
        position: 101,
        text: 'abc',
        items: [outgoingItem('m1', 0)],
      ),
      fresh: true,
    );

    expect(outbox.debugSnapshot('c1').toMap(), {
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
          'late',
          position: 103,
          status: const OutgoingStatus.failed(
            OutgoingFailure.denied(CapabilityAction.sendPhoto),
          ),
        ),
      )
      ..put(outgoingNote('early', position: 102))
      ..put(outgoingNote('other chat', chatId: 'c2'));

    final tail = outbox.debugSnapshot('c1').tail;

    expect(tail.map((row) => row.clientMessageId), ['early', 'late']);
    expect(tail.last.status, 'failed');
    expect(tail.last.failure, 'denied');
  });

  test('reading the snapshot leaves the fresh flag unread', () {
    projection.put(outgoingNote('m1'), fresh: true);

    outbox
      ..debugSnapshot('c1')
      ..debugSnapshot('c1');

    expect(outbox.isFreshOutgoing('c1', 'm1'), isTrue);
    expect(outbox.debugSnapshot('c1').tail.single.fresh, isFalse);
  });

  test('an external local key is reported by its kind only', () {
    projection.put(
      outgoingNote(
        'm1',
        items: [
          const OutgoingItem(
            id: MediaItemId('m1:0'),
            localKey: ContentKey.external('https://host/private/a.jpg'),
          ),
        ],
      ),
    );

    expect(
      outbox.debugSnapshot('c1').tail.single.items.single.localKey,
      'external',
    );
  });

  test('the snapshot is JSON-encodable', () {
    projection.put(outgoingNote('m1', items: [outgoingItem('m1', 0)]));

    expect(
      () => jsonEncode(outbox.debugSnapshot('c1').toMap()),
      returnsNormally,
    );
  });

  test('no event and no snapshot carries the payload', () {
    final diagnostics = RecordingDiagnostics.install();
    const secret = 'meet me at the north gate';
    projection.put(
      outgoingNote(
        'm1',
        text: secret,
        status: const OutgoingStatus.failed(OutgoingFailure.rejected('flood')),
        items: [outgoingItem('m1', 0)],
      ),
      fresh: true,
    );

    outbox
      ..byClientMessageId('c1', 'm1')
      ..isFreshOutgoing('c1', 'm1');
    final snapshot = jsonEncode(outbox.debugSnapshot('c1').toMap());

    expect(diagnostics.events, isNotEmpty);
    for (final event in diagnostics.events) {
      expect('$event', isNot(contains('north gate')));
      expect('$event', isNot(contains('flood')));
    }
    expect(snapshot, isNot(contains('north gate')));
    expect(snapshot, isNot(contains('flood')));
    expect(
      '${outbox.byClientMessageId('c1', 'm1')}',
      isNot(contains('north gate')),
    );
  });
}
