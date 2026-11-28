import 'package:attach_model/attach_model.dart';
import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_capabilities/testing.dart';
import 'package:chat_outbox/chat_outbox.dart';
import 'package:chat_outbox/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen/listen.dart';
import 'package:mpx_transfer/mpx_transfer.dart';

import '../support/note_payload_codec.dart';
import '../support/outgoing_messages.dart';
import '../support/sends.dart';

void main() {
  final now = DateTime.utc(2026, 11, 28, 12);
  late FakeOutboxTransfers transfers;
  late ValueNotifier<ChatCapabilities> capabilities;
  late RecordingCapabilityFeedback feedback;
  late ChatOutbox<Note> outbox;

  setUp(() {
    transfers = FakeOutboxTransfers();
    capabilities = ValueNotifier(const ChatCapabilities());
    feedback = RecordingCapabilityFeedback();
    outbox = ChatOutbox(
      transfers: transfers,
      codec: const NotePayloadCodec(),
      itemOf: sendItemOf,
      idStrategyOf: fakeIdStrategyOf,
      onSent: (_) {},
      rowOf: fakeRowOf,
      capabilitiesOf: (chatId) => chatId == 'c1' ? capabilities : null,
      feedback: feedback,
      clientMessageIds: clientMessageIdsFrom(),
      now: () => now,
    );
    addTearDown(outbox.dispose);
  });

  OutgoingMessage? sendText(
    String text, {
    ChatId chatId = const ChatId('c1'),
  }) =>
      outbox.sendText(chatId, RichText.plain(text), payload: Note(text: text));

  OutgoingMessage? sendAlbum(List<AttachItem> items) => outbox.send(
    const ChatId('c1'),
    PlannedSend.group(items, form: SendForm.media),
    payload: const Note(text: 'album'),
  );

  group('slow mode', () {
    test('during the countdown refuses sendNow with the wait, no job', () {
      capabilities.value = ChatCapabilities(
        slowMode: SlowMode.active(
          interval: const Duration(seconds: 30),
          nextSendAt: now.add(const Duration(seconds: 12)),
        ),
      );

      final message = sendAlbum([photo('a'), photo('b')]);

      expect(message, isNull);
      expect(transfers.requests, isEmpty);
      expect(feedback.denials, [
        (
          action: CapabilityAction.sendNow,
          reason: DenialReason.restricted(
            until: now.add(const Duration(seconds: 12)),
          ),
        ),
      ]);
      expect(
        outbox.byClientMessageId(
          const ChatId('c1'),
          const ClientMessageId('cm1'),
        ),
        isNull,
      );
    });

    group('a retry', () {
      const failed = PublishJobState.failed(
        stage: PublishStage.publish,
        reason: PublishFailureReason('network'),
        retryable: true,
      );

      Future<void> failFirst() async {
        sendText('one');
        await pumpEventQueue();
        transfers.setState(transfers.jobs.first.id, failed);
        await pumpEventQueue();
        expect(
          outbox
              .byClientMessageId(
                const ChatId('c1'),
                const ClientMessageId('cm1'),
              )
              ?.status,
          isA<OutgoingStatus$Failed>(),
        );
      }

      test('during the countdown is refused as a send is, nothing '
          'repeats', () async {
        await failFirst();
        capabilities.value = ChatCapabilities(
          slowMode: SlowMode.active(
            interval: const Duration(seconds: 30),
            nextSendAt: now.add(const Duration(seconds: 12)),
          ),
        );

        expect(
          outbox.retry(const ChatId('c1'), const ClientMessageId('cm1')),
          OutgoingRetryOutcome.refused,
        );
        expect(transfers.retried, isEmpty);
        expect(feedback.denials, [
          (
            action: CapabilityAction.sendNow,
            reason: DenialReason.restricted(
              until: now.add(const Duration(seconds: 12)),
            ),
          ),
        ]);
        expect(
          outbox
              .byClientMessageId(
                const ChatId('c1'),
                const ClientMessageId('cm1'),
              )
              ?.status,
          isA<OutgoingStatus$Failed>(),
        );
      });

      test('while another message is in flight is refused', () async {
        await failFirst();
        // Sent before slow mode came on: still publishing.
        sendText('two');
        capabilities.value = const ChatCapabilities(
          slowMode: SlowMode.active(interval: Duration(seconds: 30)),
        );

        expect(
          outbox.retry(const ChatId('c1'), const ClientMessageId('cm1')),
          OutgoingRetryOutcome.refused,
        );
        expect(
          feedback.denials.single.reason,
          const DenialReason.sendPending(),
        );
        expect(transfers.retried, isEmpty);
      });

      test('with slow mode off goes', () async {
        await failFirst();
        expect(
          outbox.retry(const ChatId('c1'), const ClientMessageId('cm1')),
          OutgoingRetryOutcome.retried,
        );
        expect(feedback.denials, isEmpty);
      });
    });

    test('while the host marks a send pending refuses sendNow', () {
      capabilities.value = const ChatCapabilities(
        slowMode: SlowMode.active(
          interval: Duration(seconds: 30),
          pending: true,
        ),
      );

      expect(sendText('hi'), isNull);
      expect(transfers.requests, isEmpty);
      expect(feedback.denials, [
        (
          action: CapabilityAction.sendNow,
          reason: const DenialReason.sendPending(),
        ),
      ]);
    });

    test('a second send while the first is in flight is refused, '
        'before the host folds pending in', () {
      capabilities.value = const ChatCapabilities(
        slowMode: SlowMode.active(interval: Duration(seconds: 30)),
      );

      expect(sendAlbum([photo('a'), photo('b')]), isNotNull);
      expect(sendAlbum([photo('c'), photo('d')]), isNull);

      expect(transfers.requests, hasLength(1));
      expect(feedback.denials, [
        (
          action: CapabilityAction.sendNow,
          reason: const DenialReason.sendPending(),
        ),
      ]);
    });

    test('once the send time came and nothing is in flight, sends', () {
      capabilities.value = ChatCapabilities(
        slowMode: SlowMode.active(
          interval: const Duration(seconds: 30),
          nextSendAt: now,
        ),
      );

      expect(sendText('hi'), isNotNull);
      expect(feedback.denials, isEmpty);
    });

    test('a chat without capabilities is unrestricted', () {
      expect(sendText('hi', chatId: const ChatId('c2')), isNotNull);
      expect(sendText('again', chatId: const ChatId('c2')), isNotNull);
    });
  });

  group('limits', () {
    test('a text over the message length is refused as sendText', () {
      capabilities.value = const ChatCapabilities(
        limits: ChatLimits(messageLength: 3),
      );

      // Three code points, five UTF-16 units: within the limit.
      expect(sendText('a😀😀'), isNotNull);
      expect(sendText('abcd'), isNull);

      expect(transfers.requests, hasLength(1));
      expect(feedback.denials, [
        (
          action: CapabilityAction.sendText,
          reason: const DenialReason.other('messageLength'),
        ),
      ]);
    });

    test('an album over the album size is refused, no job', () {
      capabilities.value = const ChatCapabilities(
        limits: ChatLimits(albumSize: 2),
      );

      expect(sendAlbum([video('a'), photo('b'), photo('c')]), isNull);

      expect(transfers.requests, isEmpty);
      expect(feedback.denials, [
        (
          action: CapabilityAction.sendVideo,
          reason: const DenialReason.other('albumSize'),
        ),
      ]);
    });

    test('a caption over the caption length is refused for its item', () {
      capabilities.value = const ChatCapabilities(
        limits: ChatLimits(captionLength: 2),
      );

      final message = outbox.send(
        const ChatId('c1'),
        PlannedSend.single(
          video('a'),
          form: SendForm.media,
          caption: const RichText.plain('abc'),
        ),
        payload: const Note(text: 'abc'),
      );

      expect(message, isNull);
      expect(feedback.denials, [
        (
          action: CapabilityAction.sendVideo,
          reason: const DenialReason.other('captionLength'),
        ),
      ]);
    });

    test('an item over the file size is refused as its send action', () {
      capabilities.value = const ChatCapabilities(
        limits: ChatLimits(fileSize: 100),
      );

      final message = outbox.send(
        const ChatId('c1'),
        PlannedSend.single(photo('a', byteSize: 101), form: SendForm.file),
        payload: const Note(text: 'file'),
      );

      expect(message, isNull);
      expect(transfers.requests, isEmpty);
      expect(feedback.denials, [
        (
          action: CapabilityAction.sendFile,
          reason: const DenialReason.other('fileSize'),
        ),
      ]);
    });
  });

  test('a refusal reports refusedBeforeJob and capabilities denied '
      'with consumer outbox, and no job events', () {
    final diagnostics = RecordingDiagnostics.install();
    capabilities.value = ChatCapabilities(
      slowMode: SlowMode.active(
        interval: const Duration(seconds: 30),
        nextSendAt: now.add(const Duration(seconds: 12)),
      ),
    );

    sendText('secret words');

    const correlation = ChatCorrelation(chatId: 'c1', clientMessageId: 'cm1');
    expect(diagnostics.whereOp(OutboxOp.refusedBeforeJob), [
      isChatEvent(
        level: ChatEventLevel.info,
        category: ChatEventCategory.outbox,
        correlation: correlation,
        fields: {'action': 'sendNow', 'reason': 'restrictedUntil'},
      ),
    ]);
    expect(diagnostics.whereOp(CapabilitiesOp.denied), [
      isChatEvent(
        level: ChatEventLevel.info,
        category: ChatEventCategory.capabilities,
        correlation: correlation,
        fields: {
          'action': CapabilityAction.sendNow,
          'reason': 'restrictedUntil',
          'consumer': CapabilityConsumer.outbox,
          'remainingMs': 12000,
        },
      ),
    ]);
    expect(diagnostics.whereOp(OutboxOp.accepted), isEmpty);
    expect(diagnostics.whereOp(OutboxOp.jobCreated), isEmpty);
  });

  group('send in flight', () {
    test('is on while a job runs and off once it settles', () async {
      final inFlight = outbox.sendInFlight(const ChatId('c1'));
      final seen = <bool>[];
      inFlight.addListener(() => seen.add(inFlight.value));
      expect(inFlight.value, isFalse);

      sendText('hi');
      expect(inFlight.value, isTrue);
      await pumpEventQueue();
      transfers.setState(
        transfers.jobs.single.id,
        const PublishJobState.completed(null),
      );
      await pumpEventQueue();

      expect(inFlight.value, isFalse);
      expect(seen, [true, false]);
    });

    test('a failed job is not in flight', () async {
      sendText('hi');
      await pumpEventQueue();
      transfers.setState(
        transfers.jobs.single.id,
        const PublishJobState.failed(
          stage: PublishStage.publish,
          reason: PublishFailureReason('network'),
          retryable: true,
        ),
      );
      await pumpEventQueue();

      expect(outbox.sendInFlight(const ChatId('c1')).value, isFalse);
    });

    test('is per chat and the same listenable on each call', () {
      sendText('hi', chatId: const ChatId('c2'));

      expect(outbox.sendInFlight(const ChatId('c1')).value, isFalse);
      expect(outbox.sendInFlight(const ChatId('c2')).value, isTrue);
      expect(
        identical(
          outbox.sendInFlight(const ChatId('c2')),
          outbox.sendInFlight(const ChatId('c2')),
        ),
        isTrue,
      );
    });

    test('reports sendInFlight on and off', () async {
      final diagnostics = RecordingDiagnostics.install();

      sendText('hi');
      await pumpEventQueue();
      transfers.setState(
        transfers.jobs.single.id,
        const PublishJobState.completed(null),
      );
      await pumpEventQueue();

      expect(diagnostics.whereOp(OutboxOp.sendInFlight), [
        isChatEvent(
          level: ChatEventLevel.debug,
          category: ChatEventCategory.outbox,
          correlation: const ChatCorrelation(chatId: 'c1'),
          fields: {'on': true},
        ),
        isChatEvent(
          correlation: const ChatCorrelation(chatId: 'c1'),
          fields: {'on': false},
        ),
      ]);
    });
  });
}
