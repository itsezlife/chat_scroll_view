import 'package:chat_scroll_view_example/src/features/chat/utils/chat_viewport_insets.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/ios_keyboard_safe_peel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('iosKeyboardSafeBandPeel', () {
    test('returns full safe when keyboard is closed on iOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(
        iosKeyboardSafeBandPeel(
          safeBottom: 34,
          keyboard: 0,
          keyboardTarget: 340,
        ),
        34,
      );
    });

    test('returns zero safe peel at full keyboard occupancy on iOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(
        iosKeyboardSafeBandPeel(
          safeBottom: 34,
          keyboard: 340,
          keyboardTarget: 340,
        ),
        0,
      );
    });

    test('lerps safe band mid-open on iOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(
        iosKeyboardSafeBandPeel(
          safeBottom: 34,
          keyboard: 170,
          keyboardTarget: 340,
        ),
        17,
      );
    });
  });

  group('ChatViewportInsets iOS safe peel', () {
    test('bottomPadding drops composer safe term as keyboard opens', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final insets = ChatViewportInsets(composerHeight: 96);
      addTearDown(insets.dispose);

      insets
        ..setSafeBottom(34)
        ..setKeyboardTarget(340);

      expect(insets.bottomPadding.value, 96);

      insets.setKeyboard(340);
      expect(insets.bottomPadding.value, 402);

      insets.setKeyboard(170);
      expect(insets.bottomPadding.value, 249);
    });
  });
}
