/// The picker's attach limits derived from a chat's capabilities.
///
/// **Seam:** `deriveAttachLimits` over a `ChatCapabilities` value, and
/// `attachLimitsOf` over a capabilities listenable, observed through the
/// `AttachLimits` they hold, who is notified, and the diagnostics events.
library;

import 'package:attach_model/attach_model.dart';
import 'package:attach_sheet/attach_sheet.dart';
import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_capabilities/testing.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('deriveAttachLimits', () {
    test('the default capabilities give exactly the default limits', () {
      final derived = deriveAttachLimits(const ChatCapabilities());
      const today = AttachLimits();
      expect(derived, today);
      expect(derived.allowedKinds, today.allowedKinds);
      expect(derived.singleSelect, today.singleSelect);
      expect(derived.captionLength, today.captionLength);
      expect(derived.fileSizeLimit, today.fileSizeLimit);
      expect(derived.timerAllowed, today.timerAllowed);
      expect(derived.scheduleAllowed, today.scheduleAllowed);
      expect(derived.groupingAllowed, today.groupingAllowed);
      expect(derived.spoilerAllowed, today.spoilerAllowed);
      expect(derived.sendAsFileAllowed, today.sendAsFileAllowed);
      expect(derived.albumSize, today.albumSize);
      expect(derived.oneSend, today.oneSend);
    });

    const attachOf = {
      MediaKind.photo: AttachKind.photo,
      MediaKind.video: AttachKind.video,
      MediaKind.animation: AttachKind.animation,
      MediaKind.file: AttachKind.file,
      MediaKind.audio: AttachKind.audio,
    };

    for (final MapEntry(key: kind, value: attach) in attachOf.entries) {
      test('${kind.name} denied removes ${attach.name} and only it', () {
        final derived = deriveAttachLimits(
          ChatCapabilities(
            sending: SendingCapabilities(
              media: SendableMedia(
                allowed: MediaKindSet.all.without(MediaKindSet.of([kind])),
              ),
            ),
          ),
        );
        expect(derived.allowedKinds, {...attachOf.values}..remove(attach));
      });
    }

    test('voice and round video have no attach kind', () {
      expect(attachKindOf(MediaKind.voice), isNull);
      expect(attachKindOf(MediaKind.roundVideo), isNull);
      final derived = deriveAttachLimits(
        ChatCapabilities(
          sending: SendingCapabilities(
            media: SendableMedia(
              allowed: MediaKindSet.of([MediaKind.voice, MediaKind.roundVideo]),
            ),
          ),
        ),
      );
      expect(derived.allowedKinds, isEmpty);
    });

    test(
      'a slow mode gives the one-send-unit limits: an album is one unit',
      () {
        final derived = deriveAttachLimits(
          const ChatCapabilities(
            slowMode: SlowMode(interval: Duration(seconds: 30)),
          ),
        );
        expect(derived.groupingAllowed, isTrue);
        expect(derived.singleSelect, isFalse);
        expect(derived.oneSend, isTrue);
        expect(derived.albumSize, 10);
      },
    );

    test('caption, file size and album size flow through', () {
      final derived = deriveAttachLimits(
        const ChatCapabilities(
          limits: ChatLimits(captionLength: 200, fileSize: 2000, albumSize: 4),
        ),
      );
      expect(derived.captionLength, 200);
      expect(derived.fileSizeLimit, 2000);
      expect(derived.albumSize, 4);
    });
  });

  group('attachLimitsOf', () {
    late RecordingDiagnostics diagnostics;
    late FakeChatCapabilitiesSource source;
    late int notified;

    setUp(() {
      diagnostics = RecordingDiagnostics.install();
      source = FakeChatCapabilitiesSource();
      notified = 0;
    });

    test('reads the current limits and follows a change', () {
      final limits = attachLimitsOf(source, chatId: 'c1');
      expect(limits.value, const AttachLimits());
      limits.addListener(() => notified++);
      source.update(limits: const ChatLimits(albumSize: 4));
      expect(notified, 1);
      expect(limits.value.albumSize, 4);
    });

    test('a slow mode tick that changes only nextSendAt notifies nobody', () {
      source.update(slowMode: const SlowMode(interval: Duration(seconds: 30)));
      final limits = attachLimitsOf(source, chatId: 'c1');
      limits.addListener(() => notified++);
      source.update(
        slowMode: SlowMode(
          interval: const Duration(seconds: 30),
          nextSendAt: DateTime(2026),
          pending: true,
        ),
      );
      source.update(limits: const ChatLimits());
      expect(notified, 0);
    });

    test('holds no subscription without listeners', () {
      final limits = attachLimitsOf(source, chatId: 'c1');
      void listener() {}
      limits.addListener(listener);
      expect(source.isListenedTo, isTrue);
      limits.removeListener(listener);
      expect(source.isListenedTo, isFalse);
    });

    test('reports limitsDerived with no content, once per distinct value', () {
      final limits = attachLimitsOf(source, chatId: 'c1');
      limits.addListener(() {});
      source
        ..update(limits: const ChatLimits(albumSize: 4, fileSize: 99))
        ..update(slowMode: const SlowMode(interval: Duration(seconds: 5)));
      final events = diagnostics.whereOp(CapabilitiesOp.limitsDerived);
      expect(events, hasLength(3));
      expect(events.first.correlation.chatId, 'c1');
      expect(events.first.fields, {
        'kinds': 'animation,audio,file,photo,video',
        'grouping': true,
        'singleSelect': false,
        'captionLength': 1024,
        'fileSizeLimit': 'none',
        'albumSize': 10,
        'oneSend': false,
      });
      expect(events[1].fields['albumSize'], 4);
      expect(events[1].fields['fileSizeLimit'], 99);
      expect(events.last.fields['oneSend'], isTrue);
    });
  });
}
