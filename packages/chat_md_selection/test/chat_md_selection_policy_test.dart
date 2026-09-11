import 'package:chat_md_selection/chat_md_selection.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatMdSelectionPolicy.forPlatform', () {
    test('iOS and Android map to mobile', () {
      expect(
        ChatMdSelectionPolicy.forPlatform(platform: TargetPlatform.iOS, isWeb: false),
        isA<ChatMdSelectionPolicy$Mobile>(),
      );
      expect(
        ChatMdSelectionPolicy.forPlatform(
          platform: TargetPlatform.android,
          isWeb: false,
        ),
        isA<ChatMdSelectionPolicy$Mobile>(),
      );
    });

    test('desktop OSes map to desktop', () {
      for (final platform in <TargetPlatform>[
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        expect(
          ChatMdSelectionPolicy.forPlatform(platform: platform, isWeb: false),
          isA<ChatMdSelectionPolicy$Desktop>(),
          reason: '$platform → desktop',
        );
      }
    });

    test('web maps to desktop regardless of TargetPlatform', () {
      expect(
        ChatMdSelectionPolicy.forPlatform(
          platform: TargetPlatform.android,
          isWeb: true,
        ),
        isA<ChatMdSelectionPolicy$Desktop>(),
      );
    });
  });

  group(r'ChatMdSelectionPolicy$Mobile membership + Copy flags', () {
    test('collapses enter membership and clears on Copy', () {
      const policy = ChatMdSelectionPolicy.mobile();
      final messages = ChatSelectionController()
        ..startSelection(1)
        ..toggle(2);

      policy.applyEnterMembership(messages, 2);
      expect(messages.selectedIds, <int>{2});
      expect(policy.allowsTextEntryWithoutMessageSelection, isFalse);
      expect(policy.claimsSpanYieldForTextEntry, isTrue);
      expect(policy.nestsTextSubjectInMessageSelection, isTrue);

      var clearedText = false;
      var clearedMessages = false;
      policy.applyCopySuccess(
        clearTextSelection: () => clearedText = true,
        clearMessageSelection: () => clearedMessages = true,
      );
      expect(clearedText, isTrue);
      expect(clearedMessages, isTrue);
    });
  });

  group(r'ChatMdSelectionPolicy$Desktop membership + Copy flags', () {
    test('clears enter membership and keeps range on Copy', () {
      const policy = ChatMdSelectionPolicy.desktop();
      final messages = ChatSelectionController()
        ..startSelection(1)
        ..toggle(2);

      policy.applyEnterMembership(messages, 2);
      expect(messages.selectedIds, isEmpty);
      expect(policy.allowsTextEntryWithoutMessageSelection, isTrue);
      expect(policy.claimsSpanYieldForTextEntry, isFalse);
      expect(policy.nestsTextSubjectInMessageSelection, isFalse);

      var clearedText = false;
      var clearedMessages = false;
      policy.applyCopySuccess(
        clearTextSelection: () => clearedText = true,
        clearMessageSelection: () => clearedMessages = true,
      );
      expect(clearedText, isFalse);
      expect(clearedMessages, isFalse);
    });
  });
}
