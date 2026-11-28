import 'dart:typed_data';

import 'package:chat_outbox/chat_outbox.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/outgoing_messages.dart';

void main() {
  test('equal by value, the payload compared byte by byte', () {
    expect(
      outgoingNote('m1', items: [outgoingItem('m1', 0)]),
      outgoingNote('m1', items: [outgoingItem('m1', 0)]),
    );
    expect(outgoingNote('m1').hashCode, outgoingNote('m1').hashCode);
  });

  test('differs by each part', () {
    final base = outgoingNote('m1');

    expect(outgoingNote('m1', chatId: 'c2'), isNot(base));
    expect(outgoingNote('m2'), isNot(base));
    expect(outgoingNote('m1', position: 102), isNot(base));
    expect(
      outgoingNote('m1', status: const OutgoingStatus.sent()),
      isNot(base),
    );
    expect(outgoingNote('m1', text: 'other'), isNot(base));
    expect(outgoingNote('m1', items: [outgoingItem('m1', 0)]), isNot(base));
  });

  test('keeps its own copy of the payload and items', () {
    final payload = Uint8List.fromList([1, 2, 3]);
    final items = [outgoingItem('m1', 0)];
    final message = OutgoingMessage(
      chatId: 'c1',
      clientMessageId: 'm1',
      position: 101,
      status: const OutgoingStatus.preparing(),
      payload: payload,
      items: items,
    );

    payload[0] = 9;
    items.add(outgoingItem('m1', 1));

    expect(message.payload, [1, 2, 3]);
    expect(message.items, hasLength(1));
    expect(() => message.payload[0] = 9, throwsUnsupportedError);
    expect(message.items.clear, throwsUnsupportedError);
  });

  test('toString leaves the payload out', () {
    expect(
      '${outgoingNote('m1', text: 'private words')}',
      isNot(contains('private words')),
    );
  });
}
