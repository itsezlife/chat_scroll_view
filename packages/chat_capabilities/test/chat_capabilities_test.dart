// Values are built at run time on purpose: equality must hold without
// const canonicalisation.
// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables

import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:test/test.dart';

void main() {
  const denied = Capability.denied(DenialReason.everyone());

  group('the no-signal value', () {
    test('const ChatCapabilities() equals one built from every default', () {
      final built = ChatCapabilities(
        sending: SendingCapabilities(),
        writeAccess: WriteAccess$CanWrite(),
        slowMode: SlowMode$None(),
        protection: ChatProtection(),
        limits: ChatLimits(),
        custom: <String, Capability>{},
      );
      expect(built, const ChatCapabilities());
      expect(built.hashCode, const ChatCapabilities().hashCode);
    });

    test('allows every sending capability', () {
      const sending = SendingCapabilities();
      for (final capability in [
        sending.text,
        sending.stickers,
        sending.linkPreviews,
        sending.polls,
        sending.inline,
      ]) {
        expect(capability.isAllowed, isTrue);
      }
    });

    test('lets the user write, with no slow mode', () {
      const value = ChatCapabilities();
      expect(value.writeAccess.canWrite, isTrue);
      expect(value.slowMode, SlowMode.none);
      expect(value.slowMode.isActive, isFalse);
    });

    test('protects nothing', () {
      const protection = ChatProtection();
      expect(protection.copy, isTrue);
      expect(protection.forward, isTrue);
      expect(protection.save, isTrue);
      expect(protection.captureBlocked, isFalse);
    });

    test('pins the default limits', () {
      const limits = ChatLimits();
      expect(limits.messageLength, 4096);
      expect(limits.captionLength, 1024);
      expect(limits.fileSize, isNull);
      expect(limits.albumSize, 10);
    });

    test('holds no custom capability', () {
      expect(const ChatCapabilities().custom, isEmpty);
    });
  });

  group('value equality', () {
    test('each group differs from its default when a field does', () {
      expect(
        const SendingCapabilities(polls: denied),
        isNot(const SendingCapabilities()),
      );
      expect(
        const SendingCapabilities(polls: denied),
        const SendingCapabilities(polls: denied),
      );
      expect(
        const SlowMode.active(interval: Duration(seconds: 30)),
        isNot(SlowMode.none),
      );
      expect(
        const ChatProtection(forward: false),
        isNot(const ChatProtection()),
      );
      expect(const ChatLimits(fileSize: 1), isNot(const ChatLimits()));
      expect(const ChatLimits(fileSize: 1), const ChatLimits(fileSize: 1));
    });

    test('custom maps compare by entries, not identity or order', () {
      final a = ChatCapabilities(
        custom: {'x': const Capability.allowed(), 'y': denied},
      );
      final b = ChatCapabilities(
        custom: {'y': denied, 'x': const Capability.allowed()},
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(ChatCapabilities(custom: {'x': denied, 'y': denied})));
    });

    test('custom cannot be changed through the value', () {
      final value = ChatCapabilities(custom: {'x': denied});
      expect(
        () => value.custom['y'] = denied,
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  group('copyWith', () {
    test('replaces one group and keeps the others', () {
      const value = ChatCapabilities(protection: ChatProtection(copy: false));
      final next = value.copyWith(limits: const ChatLimits(albumSize: 5));
      expect(next.limits.albumSize, 5);
      expect(next.protection, value.protection);
      expect(next.sending, value.sending);
      expect(value.copyWith(), value);
    });

    test('replaces a custom map with an unmodifiable copy', () {
      final source = {'x': denied};
      final next = const ChatCapabilities().copyWith(custom: source);
      source['y'] = denied;
      expect(next.custom.keys, ['x']);
    });

    test('per group', () {
      expect(const SendingCapabilities().copyWith(text: denied).text, denied);
      final at = DateTime.utc(2026, 11, 27);
      final slow = const SlowMode$Active(
        interval: Duration(minutes: 1),
      ).copyWith(nextSendAt: at, pending: true);
      expect(slow.nextSendAt, at);
      expect(slow.pending, isTrue);
      expect(slow.interval, const Duration(minutes: 1));
      expect(slow.copyWith(clearNextSendAt: true).nextSendAt, isNull);
      expect(
        const ChatProtection().copyWith(captureBlocked: true),
        const ChatProtection(captureBlocked: true),
      );
      final limits = const ChatLimits().copyWith(fileSize: 100);
      expect(limits.fileSize, 100);
      expect(limits.copyWith(clearFileSize: true).fileSize, isNull);
    });
  });

  group('brokenRules', () {
    test('a valid value breaks none', () {
      expect(const ChatCapabilities().brokenRules, isEmpty);
    });

    test('names every rule a value breaks', () {
      final value = ChatCapabilities(
        sending: SendingCapabilities(
          media: SendableMedia(
            allowed: MediaKindSet.of([MediaKind.photo]),
            denials: {
              MediaKind.photo: const DenialReason.everyone(),
              MediaKind.video: const DenialReason.everyone(),
            },
          ),
        ),
        slowMode: const SlowMode.active(interval: Duration.zero),
        limits: const ChatLimits(
          messageLength: 0,
          captionLength: -1,
          fileSize: 0,
          albumSize: 0,
        ),
        custom: {'': denied},
      );
      expect(value.brokenRules, [
        CapabilitiesRule.mediaDenialForAllowedKind,
        CapabilitiesRule.slowModeIntervalNotPositive,
        CapabilitiesRule.messageLengthBelowOne,
        CapabilitiesRule.captionLengthNegative,
        CapabilitiesRule.fileSizeBelowOne,
        CapabilitiesRule.albumSizeBelowOne,
        CapabilitiesRule.customKeyEmpty,
      ]);
      expect(
        const ChatCapabilities(
          slowMode: SlowMode.active(interval: Duration(seconds: -1)),
        ).brokenRules,
        [CapabilitiesRule.slowModeIntervalNotPositive],
      );
    });

    test('a denial for a denied kind is valid', () {
      expect(
        const ChatCapabilities(
          sending: SendingCapabilities(
            media: SendableMedia(
              allowed: MediaKindSet.none,
              denials: {MediaKind.photo: DenialReason.everyone()},
            ),
          ),
        ).brokenRules,
        isEmpty,
      );
    });

    test('a zero caption length is a valid value (captions off)', () {
      expect(
        const ChatCapabilities(
          limits: ChatLimits(captionLength: 0),
        ).brokenRules,
        isEmpty,
      );
    });
  });

  group('debugDescribe', () {
    test('describes every group of the default value', () {
      expect(const ChatCapabilities().debugDescribe(), {
        'sending': {
          'text': 'allowed',
          'media': {
            'allowed': [
              'photo',
              'video',
              'animation',
              'file',
              'audio',
              'voice',
              'roundVideo',
            ],
            'bits': 127,
            'denials': <String, Object>{},
          },
          'stickers': 'allowed',
          'linkPreviews': 'allowed',
          'polls': 'allowed',
          'inline': 'allowed',
        },
        'writeAccess': 'canWrite',
        'slowMode': 'none',
        'protection': {
          'copy': true,
          'forward': true,
          'save': true,
          'captureBlocked': false,
          'bits': 0,
        },
        'limits': {
          'messageLength': 4096,
          'captionLength': 1024,
          'fileSize': 'unlimited',
          'albumSize': 10,
        },
        'custom': <String, Object>{},
      });
    });

    test('names denials by reason form and host tags only', () {
      final value = ChatCapabilities(
        sending: SendingCapabilities(
          text: const Capability.denied(DenialReason.restricted()),
          media: const SendableMedia(
            allowed: MediaKindSet.none,
            denials: {MediaKind.voice: DenialReason.unlockable('premium')},
          ),
          stickers: Capability.denied(
            DenialReason.restricted(until: DateTime.utc(2026, 12, 1)),
          ),
          linkPreviews: const Capability.denied(
            DenialReason.unlockable('boost'),
          ),
          polls: const Capability.denied(DenialReason.other('ruleTag')),
          inline: denied,
        ),
        writeAccess: const WriteAccess.restricted(
          DenialReason.unlockable('boost'),
        ),
        slowMode: SlowMode.active(
          interval: const Duration(seconds: 30),
          nextSendAt: DateTime.utc(2026, 11, 27, 12),
          pending: true,
        ),
        protection: const ChatProtection(copy: false, captureBlocked: true),
        limits: const ChatLimits(fileSize: 2048),
        custom: const {'hostRule': Capability.allowed()},
      );
      expect(value.debugDescribe(), {
        'sending': {
          'text': 'denied(restricted)',
          'media': {
            'allowed': <String>[],
            'bits': 0,
            'denials': {'voice': 'unlockable(premium)'},
          },
          'stickers': 'denied(restricted(until: 2026-12-01T00:00:00.000Z))',
          'linkPreviews': 'denied(unlockable(boost))',
          'polls': 'denied(other(ruleTag))',
          'inline': 'denied(everyone)',
        },
        'writeAccess': 'restricted(unlockable(boost))',
        'slowMode': {
          'intervalMs': 30000,
          'nextSendAt': '2026-11-27T12:00:00.000Z',
          'pending': true,
        },
        'protection': {
          'copy': false,
          'forward': true,
          'save': true,
          'captureBlocked': true,
          'bits': 9,
        },
        'limits': {
          'messageLength': 4096,
          'captionLength': 1024,
          'fileSize': 2048,
          'albumSize': 10,
        },
        'custom': {'hostRule': 'allowed'},
      });
    });
  });

  group('SendingCapabilities.map', () {
    test('changes every plain right and keeps the media kinds', () {
      const media = SendableMedia(
        allowed: MediaKindSet.none,
        denials: {MediaKind.photo: DenialReason.everyone()},
      );
      final lifted = const SendingCapabilities(
        text: denied,
        stickers: denied,
        polls: denied,
        media: media,
      ).map((_) => const Capability.allowed());
      expect(lifted, const SendingCapabilities(media: media));
    });
  });

  group('ChatProtection', () {
    test('its flags and its fields are one value', () {
      final protection = ChatProtection.of(
        ProtectionFlags.copy | ProtectionFlags.captureBlocked,
      );
      expect(
        protection,
        const ChatProtection(copy: false, captureBlocked: true),
      );
      expect(protection.copy, isFalse);
      expect(protection.forward, isTrue);
      expect(protection.save, isTrue);
      expect(protection.captureBlocked, isTrue);
      expect(const ChatProtection(save: false).flags, ProtectionFlags.save);
    });
  });

  group('reasons by action', () {
    test('sending reads each action from its right', () {
      const sticker = DenialReason.unlockable('boost');
      final sending = SendingCapabilities(
        text: denied,
        stickers: const Capability.denied(sticker),
        media: SendableMedia(
          allowed: MediaKindSet.all.without(MediaKindSet.of({MediaKind.voice})),
          denials: const {MediaKind.voice: DenialReason.everyone()},
        ),
      );
      expect(sending.reasonFor(CapabilityAction.sendText), isNotNull);
      expect(sending.reasonFor(CapabilityAction.sendSticker), sticker);
      expect(
        sending.reasonFor(CapabilityAction.sendVoice),
        const DenialReason.everyone(),
      );
      expect(sending.reasonFor(CapabilityAction.sendPhoto), isNull);
      for (final action in [
        CapabilityAction.sendNow,
        CapabilityAction.copy,
        CapabilityAction.forward,
        CapabilityAction.save,
      ]) {
        expect(sending.reasonFor(action), isNull, reason: action.name);
      }
    });

    test('a write access gives the reason of its panel', () {
      expect(const WriteAccess.canWrite().denialReason, isNull);
      expect(
        const WriteAccess.restricted(DenialReason.everyone()).denialReason,
        const DenialReason.everyone(),
      );
      expect(
        const WriteAccess.join().denialReason,
        const DenialReason.noWriteAccess(WriteAccess.join()),
      );
      expect(
        const WriteAccess.custom('topic').denialReason,
        const DenialReason.noWriteAccess(WriteAccess.custom('topic')),
      );
    });
  });
}
