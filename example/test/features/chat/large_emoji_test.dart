/// The host's two facts for the emoji-only body besides the text: the
/// large-emoji setting the user keeps, and the chat's permission and the
/// message's media that gate it (research 05, section 2).
library;

import 'package:chat_scroll_view/chat_scroll_view.dart' show ChatEmojiPolicy;
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/large_emoji_setting.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/large_emoji_policy.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';

UserChatMessage _message(String content, {bool hasMedia = false}) =>
    UserChatMessage(
      id: 1,
      sender: 'alice',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      content: content,
      hasMedia: hasMedia,
    );

void main() {
  group('LargeEmojiSetting', () {
    late FakeKeyValueStore storage;

    setUp(() => storage = FakeKeyValueStore());

    test('is on until the user turns it off', () async {
      final setting = await LargeEmojiSetting.load(storage);
      addTearDown(setting.dispose);

      expect(setting.enabled.value, isTrue);
    });

    test('a choice is seen at once, notified once and kept', () async {
      final setting = await LargeEmojiSetting.load(storage);
      addTearDown(setting.dispose);
      var notified = 0;
      setting.enabled.addListener(() => notified++);

      final saved = setting.set(enabled: false);

      expect(setting.enabled.value, isFalse);
      expect(notified, 1);
      await saved;
      final reopened = await LargeEmojiSetting.load(storage);
      addTearDown(reopened.dispose);
      expect(reopened.enabled.value, isFalse);
    });

    test('choosing what is already chosen changes nothing', () async {
      final setting = await LargeEmojiSetting.load(storage);
      addTearDown(setting.dispose);
      var notified = 0;
      setting.enabled.addListener(() => notified++);

      await setting.set(enabled: true);

      expect(notified, 0);
      expect(storage.writeCount, 0);
    });

    test('unreadable storage leaves it on', () async {
      storage.failure = Exception('unreachable');

      final setting = await LargeEmojiSetting.load(storage);
      addTearDown(setting.dispose);

      expect(setting.enabled.value, isTrue);
    });

    test('a value of another version is ignored', () async {
      await storage.write(
        LargeEmojiSetting.namespace,
        LargeEmojiSetting.key,
        const StoredValue('off', version: 99),
      );

      final setting = await LargeEmojiSetting.load(storage);
      addTearDown(setting.dispose);

      expect(setting.enabled.value, isTrue);
    });
  });

  group('LargeEmojiSetting: the desktop cap', () {
    late FakeKeyValueStore storage;

    setUp(() => storage = FakeKeyValueStore());

    test('is the reference client\'s 3 until the user moves it', () async {
      final setting = await LargeEmojiSetting.load(storage);
      addTearDown(setting.dispose);

      expect(setting.desktopLimit.value, 3);
    });

    test('a choice is seen at once, notified once and kept', () async {
      final setting = await LargeEmojiSetting.load(storage);
      addTearDown(setting.dispose);
      var notified = 0;
      setting.desktopLimit.addListener(() => notified++);

      final saved = setting.setDesktopLimit(7);

      expect(setting.desktopLimit.value, 7);
      expect(notified, 1);
      await saved;
      final reopened = await LargeEmojiSetting.load(storage);
      addTearDown(reopened.dispose);
      expect(reopened.desktopLimit.value, 7);
    });

    test(
      'choosing what is already chosen changes and writes nothing',
      () async {
        final setting = await LargeEmojiSetting.load(storage);
        addTearDown(setting.dispose);

        await setting.setDesktopLimit(3);

        expect(storage.writeCount, 0);
      },
    );

    test(
      'is a record of its own: the on/off choice does not touch it',
      () async {
        final setting = await LargeEmojiSetting.load(storage);
        addTearDown(setting.dispose);
        await setting.setDesktopLimit(5);

        await setting.set(enabled: false);

        final reopened = await LargeEmojiSetting.load(storage);
        addTearDown(reopened.dispose);
        expect(reopened.desktopLimit.value, 5);
        expect(reopened.enabled.value, isFalse);
      },
    );

    test(
      'a value out of range, unreadable or of another version is 3',
      () async {
        for (final stored in [
          const StoredValue('0', version: LargeEmojiSetting.version),
          const StoredValue('1000', version: LargeEmojiSetting.version),
          const StoredValue('many', version: LargeEmojiSetting.version),
          const StoredValue('5', version: 99),
        ]) {
          final store = FakeKeyValueStore();
          await store.write(
            LargeEmojiSetting.namespace,
            LargeEmojiSetting.desktopLimitKey,
            stored,
          );

          final setting = await LargeEmojiSetting.load(store);
          addTearDown(setting.dispose);

          expect(setting.desktopLimit.value, 3, reason: stored.value);
        }
      },
    );

    test('a limit outside the choices is refused', () async {
      final setting = await LargeEmojiSetting.load(storage);
      addTearDown(setting.dispose);

      expect(() => setting.setDesktopLimit(0), throwsArgumentError);
      expect(
        () => setting.setDesktopLimit(LargeEmojiSetting.maxDesktopLimit + 1),
        throwsArgumentError,
      );
    });
  });

  group('LargeEmojiPolicy', () {
    final emoji = _message('\u{1F44D}\u{1F680}\u{1F525}');

    test('shows the emoji of an emoji-only message when everything allows', () {
      const policy = LargeEmojiPolicy(enabled: true);

      expect(policy.emojiOnlyOf(emoji)?.items, hasLength(3));
    });

    test('keeps the markdown body for a message that is not emoji-only', () {
      const policy = LargeEmojiPolicy(enabled: true);

      expect(policy.emojiOnlyOf(_message('hello \u{1F44D}')), isNull);
    });

    test('keeps the markdown body with the setting off', () {
      const policy = LargeEmojiPolicy(enabled: false);

      expect(policy.emojiOnlyOf(emoji), isNull);
    });

    test('keeps the markdown body for a message with media or a link '
        'preview', () {
      const policy = LargeEmojiPolicy(enabled: true);

      expect(policy.emojiOnlyOf(_message('\u{1F44D}', hasMedia: true)), isNull);
    });

    test('needs the chat to allow stickers, or the user to be an admin', () {
      const closed = LargeEmojiPolicy(enabled: true, stickersAllowed: false);
      const admin = LargeEmojiPolicy(
        enabled: true,
        stickersAllowed: false,
        isAdmin: true,
      );

      expect(closed.emojiOnlyOf(emoji), isNull);
      expect(admin.emojiOnlyOf(emoji), isNotNull);
    });

    group('by platform family (04 section 4, rows 1 and 2)', () {
      const closed = LargeEmojiPolicy(enabled: true, stickersAllowed: false);
      final four = _message('\u{1F44D}\u{1F680}\u{1F525}\u{1F600}');

      test('Android keeps the sticker permission as a gate', () {
        expect(
          closed.emojiOnlyOf(emoji, platform: const ChatEmojiPolicy.android()),
          isNull,
        );
      });

      test('iOS and desktop do not gate on it', () {
        expect(
          closed.emojiOnlyOf(emoji, platform: const ChatEmojiPolicy.ios()),
          isNotNull,
        );
        expect(
          closed.emojiOnlyOf(emoji, platform: const ChatEmojiPolicy.desktop()),
          isNotNull,
        );
      });

      test('desktop shows at most 3 regular emoji large; the others show '
          'any number', () {
        const policy = LargeEmojiPolicy(enabled: true);

        expect(
          policy.emojiOnlyOf(emoji, platform: const ChatEmojiPolicy.desktop()),
          isNotNull,
        );
        expect(
          policy.emojiOnlyOf(four, platform: const ChatEmojiPolicy.desktop()),
          isNull,
        );
        expect(
          policy.emojiOnlyOf(four, platform: const ChatEmojiPolicy.android()),
          isNotNull,
        );
        expect(
          policy.emojiOnlyOf(four, platform: const ChatEmojiPolicy.ios()),
          isNotNull,
        );
      });

      test('the setting and media still gate every platform', () {
        const off = LargeEmojiPolicy(enabled: false);

        expect(
          off.emojiOnlyOf(emoji, platform: const ChatEmojiPolicy.desktop()),
          isNull,
        );
      });
    });

    group('the desktop cap', () {
      final six = _message('\u{1F44D}' * 6);
      const macOS = TargetPlatform.macOS;

      test('moves the boundary of the desktop family', () {
        const policy = LargeEmojiPolicy(enabled: true, desktopRegularLimit: 6);

        expect(
          policy.emojiOnlyOf(six, platform: policy.family(platform: macOS)),
          isNotNull,
        );
        expect(
          policy.emojiOnlyOf(
            _message('\u{1F44D}' * 7),
            platform: policy.family(platform: macOS),
          ),
          isNull,
        );
      });

      test('is 3 unless said otherwise', () {
        const policy = LargeEmojiPolicy(enabled: true);

        expect(
          policy.emojiOnlyOf(six, platform: policy.family(platform: macOS)),
          isNull,
        );
        expect(
          policy.emojiOnlyOf(
            _message('\u{1F44D}' * 3),
            platform: policy.family(platform: macOS),
          ),
          isNotNull,
        );
      });

      test('is ignored by the families that have no cap', () {
        const policy = LargeEmojiPolicy(enabled: true, desktopRegularLimit: 1);

        for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
          expect(
            policy.emojiOnlyOf(
              six,
              platform: policy.family(platform: platform),
            ),
            isNotNull,
            reason: '$platform',
          );
        }
      });

      test('is part of the value', () {
        expect(
          const LargeEmojiPolicy(enabled: true, desktopRegularLimit: 5),
          isNot(const LargeEmojiPolicy(enabled: true)),
        );
      });
    });

    test('a different policy is a different value', () {
      expect(
        const LargeEmojiPolicy(enabled: true),
        const LargeEmojiPolicy(enabled: true),
      );
      expect(
        const LargeEmojiPolicy(enabled: true),
        isNot(const LargeEmojiPolicy(enabled: false)),
      );
    });
  });
}
