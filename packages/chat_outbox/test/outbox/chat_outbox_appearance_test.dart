/// The outbox's answer to "how does this fresh row appear": once per
/// message, from its appearance policy, knowing itself whether the message
/// has media and a send origin, and the `rowAppeared` event.
///
/// **Seam:** `ChatOutbox.appearanceOf` over the fake transfers and the
/// fake id strategy, observed through its answers and
/// `RecordingDiagnostics`.
library;

import 'dart:ui' show Rect;

import 'package:attach_model/attach_model.dart';
import 'package:chat_outbox/chat_outbox.dart';
import 'package:chat_outbox/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/note_payload_codec.dart';
import '../support/outgoing_messages.dart';
import '../support/sends.dart';

void main() {
  const origin = Rect.fromLTWH(10, 400, 90, 90);

  late FakeOutboxTransfers transfers;

  ChatOutbox<Note> outboxOf(OutgoingAppearancePolicy appearance) {
    final outbox = ChatOutbox<Note>(
      transfers: transfers,
      codec: const NotePayloadCodec(),
      itemOf: sendItemOf,
      idStrategyOf: fakeIdStrategyOf,
      onSent: (_) {},
      rowOf: fakeRowOf,
      clientMessageIds: clientMessageIdsFrom(),
      appearance: appearance,
    );
    addTearDown(outbox.dispose);
    return outbox;
  }

  setUp(() => transfers = FakeOutboxTransfers());

  OutgoingMessage sendPhoto(ChatOutbox<Note> outbox, {Rect? from}) =>
      outbox.send(
        'c1',
        PlannedSend.single(photo('a'), form: SendForm.media),
        payload: const Note(text: 'one'),
        origins: [from],
      )!;

  test('defaults to the running platform preset', () {
    final outbox = ChatOutbox<Note>(
      transfers: transfers,
      codec: const NotePayloadCodec(),
      itemOf: sendItemOf,
      idStrategyOf: fakeIdStrategyOf,
      onSent: (_) {},
      rowOf: fakeRowOf,
    );
    addTearDown(outbox.dispose);

    expect(outbox.appearance, OutgoingAppearancePolicy.platform());
  });

  test('answers once per fresh message, null after and for others', () {
    final outbox = outboxOf(const OutgoingAppearancePolicy.android());
    final message = sendPhoto(outbox);

    expect(
      outbox.appearanceOf(
        'c1',
        message.clientMessageId,
        atBottom: true,
        reduceMotion: false,
      ),
      isA<OutgoingAppearance$SlideUp>(),
    );
    expect(
      outbox.appearanceOf(
        'c1',
        message.clientMessageId,
        atBottom: true,
        reduceMotion: false,
      ),
      isNull,
    );
    // Asking shares isFreshOutgoing's one-shot.
    expect(outbox.isFreshOutgoing('c1', message.clientMessageId), isFalse);
    expect(
      outbox.appearanceOf('c1', 'never', atBottom: true, reduceMotion: false),
      isNull,
    );
  });

  test('the host may answer with the policy of the moment (the web picks '
      'it by the live window and input)', () {
    final outbox = outboxOf(OutgoingAppearancePolicy.web(compactTouch: false));
    final wide = sendPhoto(outbox);
    final narrowed = sendPhoto(outbox);

    expect(
      outbox.appearanceOf(
        'c1',
        wide.clientMessageId,
        atBottom: true,
        reduceMotion: false,
      ),
      isA<OutgoingAppearance$None>(),
    );
    expect(
      outbox.appearanceOf(
        'c1',
        narrowed.clientMessageId,
        atBottom: true,
        reduceMotion: false,
        policy: OutgoingAppearancePolicy.web(compactTouch: true),
      ),
      isA<OutgoingAppearance$SlideUp>(),
    );
  });

  test('on iOS a held send origin gives the flight, without one a slide', () {
    final outbox = outboxOf(const OutgoingAppearancePolicy.ios());
    final flown = sendPhoto(outbox, from: origin);
    final plain = sendPhoto(outbox);

    expect(
      outbox.appearanceOf(
        'c1',
        flown.clientMessageId,
        atBottom: true,
        reduceMotion: false,
      ),
      isA<OutgoingAppearance$Flight>(),
    );
    expect(
      outbox.appearanceOf(
        'c1',
        plain.clientMessageId,
        atBottom: false,
        reduceMotion: false,
      ),
      isA<OutgoingAppearance$FadeScale>(),
    );
  });

  test('asking leaves the origin for the cell to take', () {
    final outbox = outboxOf(const OutgoingAppearancePolicy.ios());
    final message = sendPhoto(outbox, from: origin);

    outbox.appearanceOf(
      'c1',
      message.clientMessageId,
      atBottom: true,
      reduceMotion: false,
    );

    expect(outbox.takeSendOrigin(message.items.single.id), origin);
  });

  test('an origin the cell already took is no flight', () {
    final outbox = outboxOf(const OutgoingAppearancePolicy.ios());
    final message = sendPhoto(outbox, from: origin);
    outbox.takeSendOrigin(message.items.single.id);

    expect(
      outbox.appearanceOf(
        'c1',
        message.clientMessageId,
        atBottom: true,
        reduceMotion: false,
      ),
      isA<OutgoingAppearance$SlideUp>(),
    );
  });

  test('a text message appears as media does, with no flight', () {
    final outbox = outboxOf(const OutgoingAppearancePolicy.ios());
    final message = outbox.sendText(
      'c1',
      const RichText.plain('hi'),
      payload: const Note(text: 'hi'),
    )!;

    expect(
      outbox.appearanceOf(
        'c1',
        message.clientMessageId,
        atBottom: true,
        reduceMotion: false,
      ),
      isA<OutgoingAppearance$SlideUp>(),
    );
  });

  test('reduce motion answers none, and still takes the fresh flag', () {
    final outbox = outboxOf(const OutgoingAppearancePolicy.android());
    final message = sendPhoto(outbox);

    expect(
      outbox.appearanceOf(
        'c1',
        message.clientMessageId,
        atBottom: true,
        reduceMotion: true,
      ),
      isA<OutgoingAppearance$None>(),
    );
    expect(outbox.isFreshOutgoing('c1', message.clientMessageId), isFalse);
  });

  test('reports rowAppeared with the form, at bottom and reduce motion', () {
    final outbox = outboxOf(const OutgoingAppearancePolicy.ios());
    final flown = sendPhoto(outbox, from: origin);
    final faded = sendPhoto(outbox);
    final reduced = sendPhoto(outbox);
    final diagnostics = RecordingDiagnostics.install();

    outbox
      ..appearanceOf(
        'c1',
        flown.clientMessageId,
        atBottom: true,
        reduceMotion: false,
      )
      ..appearanceOf(
        'c1',
        faded.clientMessageId,
        atBottom: false,
        reduceMotion: false,
      )
      ..appearanceOf(
        'c1',
        reduced.clientMessageId,
        atBottom: true,
        reduceMotion: true,
      )
      // Not fresh any more: no row appears, no event.
      ..appearanceOf(
        'c1',
        flown.clientMessageId,
        atBottom: true,
        reduceMotion: false,
      );

    expect(diagnostics.whereOp(OutboxOp.rowAppeared), [
      isChatEvent(
        level: ChatEventLevel.debug,
        category: ChatEventCategory.outbox,
        correlation: ChatCorrelation(
          chatId: 'c1',
          clientMessageId: flown.clientMessageId,
          scrollId: '${flown.position}',
        ),
        fields: {'form': 'flight', 'atBottom': true, 'reduceMotion': false},
      ),
      isChatEvent(
        correlation: ChatCorrelation(
          chatId: 'c1',
          clientMessageId: faded.clientMessageId,
          scrollId: '${faded.position}',
        ),
        fields: {'form': 'fadeScale', 'atBottom': false, 'reduceMotion': false},
      ),
      isChatEvent(
        fields: {'form': 'none', 'atBottom': true, 'reduceMotion': true},
      ),
    ]);
  });
}
