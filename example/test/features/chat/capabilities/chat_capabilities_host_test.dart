/// One chat's capabilities as the demo host resolves them: each demo chat's
/// rights, the one signal with its diagnostics, the denial feedback that
/// becomes a bulletin, slow mode's sends and the lift of an unlockable ban.
///
/// **Seams:** [DemoChatRights.resolve] and [ChatCapabilitiesHost] (its
/// `capabilities`, `feedback`, `send`, `accessAction`), with a
/// [BulletinController] standing for the screen's bulletin host.
library;

import 'package:bulletins/bulletins.dart';
import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_scroll_view_example/src/common/constant/demo_config.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_kind.dart';
import 'package:chat_scroll_view_example/src/features/chat/capabilities/chat_capabilities_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/capabilities/chat_denial_strings.dart';
import 'package:chat_scroll_view_example/src/features/chat/capabilities/demo_chat_rights.dart';
import 'package:chat_scroll_view_example/src/features/chat_list/view/chat_list_screen.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime(2026, 11, 27, 12);
const _strings = ChatDenialStrings.english;

void main() {
  group('each demo chat kind yields its capabilities', () {
    test('a channel is read only; a private chat and a group allow '
        'everything', () {
      expect(DemoChatRights.forKind(ChatKind.channel), DemoChatRights.readOnly);
      expect(
        DemoChatRights.forKind(ChatKind.privateChat),
        DemoChatRights.member,
      );
      expect(DemoChatRights.forKind(ChatKind.group), DemoChatRights.member);
    });

    test('a member may do everything within the backend limits', () {
      final value = DemoChatRights.member.resolve(_now);
      expect(
        value,
        const ChatCapabilities(
          limits: ChatLimits(
            messageLength: DemoConfig.messageLengthMax,
            fileSize: 2000 * 1024 * 1024,
          ),
        ),
      );
    });

    test('a read-only channel replaces the input row', () {
      final value = DemoChatRights.readOnly.resolve(_now);
      expect(value.writeAccess, const WriteAccess.readOnly());
      expect(value.sending, const SendingCapabilities());
    });

    test('a group with a ban denies kinds with their reasons, and stickers '
        'until a boost', () {
      final value = DemoChatRights.banned.resolve(_now);
      final media = value.sending.media;
      final tomorrow = _now.add(const Duration(days: 1));
      expect(value.writeAccess, const WriteAccess.canWrite());
      expect(value.sending.text, const Capability.allowed());
      expect(
        media.reasonFor(MediaKind.photo),
        DenialReason.restricted(until: tomorrow),
      );
      expect(
        media.reasonFor(MediaKind.video),
        DenialReason.restricted(until: tomorrow),
      );
      expect(media.reasonFor(MediaKind.file), const DenialReason.everyone());
      expect(
        media.reasonFor(MediaKind.animation),
        const DenialReason.everyone(),
      );
      expect(media.reasonFor(MediaKind.voice), const DenialReason.restricted());
      expect(media.reasonFor(MediaKind.audio), isNull);
      expect(media.reasonFor(MediaKind.roundVideo), isNull);
      expect(
        value.sending.stickers,
        const Capability.denied(DenialReason.unlockable('boost')),
      );
    });

    test('a slow-mode group sends once every 30 s, free to send now', () {
      final value = DemoChatRights.slowMode.resolve(_now);
      expect(value.slowMode, const SlowMode(interval: Duration(seconds: 30)));
      expect(value.slowMode.canSendAt(_now), isTrue);
    });

    test('every value keeps the rules of a chat capabilities value', () {
      for (final rights in DemoChatRights.values) {
        expect(rights.resolve(_now).brokenRules, isEmpty, reason: '$rights');
      }
    });

    test('the chat list opens a chat of every rights', () {
      expect({
        for (final entry in ChatListScreen.demoEntries) entry.rights,
      }, DemoChatRights.values.toSet());
      final ids = [for (final entry in ChatListScreen.demoEntries) entry.id];
      expect(ids.toSet(), hasLength(ids.length), reason: 'ids are unique');
    });
  });

  group('the host', () {
    late RecordingDiagnostics diagnostics;
    late BulletinController bulletins;
    late DateTime now;
    late List<Bulletin> shown;

    ChatCapabilitiesHost host(DemoChatRights rights, {bool hint = true}) {
      final made = ChatCapabilitiesHost.forRights(
        rights,
        chatId: 'chat-7',
        bulletins: bulletins,
        strings: _strings,
        hintBulletins: hint,
        now: () => now,
      );
      addTearDown(made.dispose);
      return made;
    }

    setUp(() {
      diagnostics = RecordingDiagnostics.install();
      now = _now;
      bulletins = BulletinController();
      addTearDown(bulletins.dispose);
      shown = [];
      bulletins.current.addListener(() {
        if (bulletins.current.value case final handle?) {
          shown.add(handle.bulletin);
        }
      });
    });

    test('reports each change of the value under the chat id, with no '
        'user content', () {
      final chat = host(DemoChatRights.member);
      void listener() {}
      chat.capabilities.addListener(listener);
      addTearDown(() => chat.capabilities.removeListener(listener));

      chat.update((c) => c.copyWith(writeAccess: const WriteAccess.readOnly()));

      expect(diagnostics.whereOp(CapabilitiesOp.valueChanged), [
        isChatEvent(
          level: ChatEventLevel.debug,
          category: ChatEventCategory.capabilities,
          correlation: const ChatCorrelation(chatId: 'chat-7'),
          fields: allOf(
            containsPair('groups', 'writeAccess'),
            containsPair('writeAccess', 'readOnly'),
          ),
        ),
      ]);
    });

    test('words a denial in place from its strings', () {
      final chat = host(DemoChatRights.readOnly);
      expect(
        chat.feedback.denialText(
          CapabilityAction.sendText,
          const DenialReason.other('readOnly'),
        ),
        _strings.readOnly,
      );
      expect(
        chat.feedback.denialText(
          CapabilityAction.sendPhoto,
          DenialReason.restricted(until: DateTime(2026, 11, 28, 9, 5)),
        ),
        'The admins of this chat have restricted you from sending photos '
        'until 28.11 09:05.',
      );
      expect(
        chat.feedback.denialText(
          CapabilityAction.sendNow,
          DenialReason.restricted(until: _now.add(const Duration(seconds: 75))),
        ),
        'Slow mode is on. You can send again in 1:15.',
      );
    });

    test('shows every attempt as a bulletin, one per attempt, and reports '
        'it', () {
      final chat = host(DemoChatRights.banned);
      for (var i = 0; i < 3; i++) {
        chat.feedback.onDenied(
          CapabilityAction.sendFile,
          const DenialReason.everyone(),
          consumer: CapabilityConsumer.picker,
          correlation: const ChatCorrelation(chatId: 'chat-7'),
        );
      }

      expect(shown, hasLength(3));
      expect(
        shown.first.message,
        'The admins of this chat have turned off sending files.',
      );
      expect(shown.first.action, isNull);
      expect(diagnostics.whereOp(CapabilitiesOp.denied), hasLength(3));
    });

    test('a hint on the touch families, a toast elsewhere', () {
      host(DemoChatRights.banned).feedback.onDenied(
        CapabilityAction.sendVoice,
        const DenialReason.restricted(),
        consumer: CapabilityConsumer.composer,
      );
      host(DemoChatRights.banned, hint: false).feedback.onDenied(
        CapabilityAction.sendVoice,
        const DenialReason.restricted(),
        consumer: CapabilityConsumer.composer,
      );

      expect(
        shown[0].duration,
        const BulletinDuration.exactly(ChromeHintTiming.controlHint),
      );
      expect(shown[1].duration, isNull);
    });

    test('an unlockable denial offers the lift, which lifts what that kind '
        'unlocks', () {
      final chat = host(DemoChatRights.banned);
      chat.feedback.onDenied(
        CapabilityAction.sendSticker,
        const DenialReason.unlockable('boost'),
        consumer: CapabilityConsumer.panel,
      );

      final action = shown.single.action;
      expect(action, isA<BulletinAction$Button>());
      (action! as BulletinAction$Button).onPressed();

      expect(chat.value.sending.stickers, const Capability.allowed());
      // A ban that is not the boost's stays.
      expect(
        chat.value.sending.media.reasonFor(MediaKind.file),
        const DenialReason.everyone(),
      );
    });

    test("the restriction bar's action lifts an unlockable ban; other bars "
        'have none', () {
      final chat = host(DemoChatRights.member);
      const banned = WriteAccess.restricted(DenialReason.unlockable('boost'));
      chat.update((c) => c.copyWith(writeAccess: banned));

      final action = chat.accessAction(banned);
      expect(action?.label, 'Boost to lift');
      action!.onTap();
      action.onTap();
      expect(chat.value.writeAccess, const WriteAccess.canWrite());

      expect(chat.accessAction(const WriteAccess.readOnly()), isNull);
      expect(
        chat.accessAction(
          const WriteAccess.restricted(DenialReason.restricted()),
        ),
        isNull,
      );
    });

    test('a send in slow mode is pending until it lands, and the next send '
        'waits an interval from it', () async {
      final chat = host(DemoChatRights.slowMode);
      SlowMode? during;
      await chat.send(() async => during = chat.value.slowMode);

      expect(
        during,
        SlowMode(
          interval: const Duration(seconds: 30),
          nextSendAt: _now.add(const Duration(seconds: 30)),
          pending: true,
        ),
      );
      expect(chat.value.slowMode.pending, isFalse);
      expect(chat.value.slowMode.canSendAt(_now), isFalse);
      expect(
        chat.value.slowMode.canSendAt(_now.add(const Duration(seconds: 30))),
        isTrue,
      );
    });

    test('a send outside slow mode leaves the value alone', () async {
      final chat = host(DemoChatRights.member);
      final before = chat.value;
      var sent = false;
      await chat.send(() async => sent = true);
      expect(sent, isTrue);
      expect(chat.value, same(before));
    });
  });
}
