import 'package:chat_composer/chat_composer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ComposerMenuPolicy.forPlatform', () {
    test('touch platforms keep the floating toolbar', () {
      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.fuchsia,
      ]) {
        final policy = ComposerMenuPolicy.forPlatform(platform);
        expect(policy, isA<ComposerMenuPolicy$Mobile>(), reason: '$platform');
        expect(policy.usesPointerMenu, isFalse);
      }
    });

    test('desktop platforms get the pointer menu', () {
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        final policy = ComposerMenuPolicy.forPlatform(platform);
        expect(policy, isA<ComposerMenuPolicy$Desktop>(), reason: '$platform');
        expect(policy.usesPointerMenu, isTrue);
      }
    });

    test('the web counts as desktop', () {
      expect(
        ComposerMenuPolicy.forPlatform(TargetPlatform.android, isWeb: true),
        isA<ComposerMenuPolicy$Desktop>(),
      );
    });
  });

  group('the click edge that opens the menu', () {
    test('is the press on macOS and Linux, the release on Windows', () {
      expect(
        const ComposerMenuPolicy$Desktop(
          platform: TargetPlatform.macOS,
        ).opensOn,
        ComposerMenuOpensOn.press,
      );
      expect(
        const ComposerMenuPolicy$Desktop(
          platform: TargetPlatform.linux,
        ).opensOn,
        ComposerMenuOpensOn.press,
      );
      expect(
        const ComposerMenuPolicy$Desktop(
          platform: TargetPlatform.windows,
        ).opensOn,
        ComposerMenuOpensOn.release,
      );
    });

    test('is one named set of platforms', () {
      expect(ComposerMenuPolicy$Desktop.platformsOpeningOnPress, {
        TargetPlatform.macOS,
        TargetPlatform.linux,
      });
    });
  });
}
