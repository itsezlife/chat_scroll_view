/// The platform family the demo host arranges its own chrome for, and what
/// each family chooses.
///
/// **Seam:** [AppPlatformPolicy] directly; pure.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/app/app_platform_policy.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_shell/panel_shell.dart';

void main() {
  group('the family', () {
    test('is mobile on Android and iOS, a desktop on every other system', () {
      expect(
        AppPlatformPolicy.forPlatform(TargetPlatform.android, isWeb: false),
        const AppPlatformPolicy.android(),
      );
      expect(
        AppPlatformPolicy.forPlatform(TargetPlatform.iOS, isWeb: false),
        const AppPlatformPolicy.iOS(),
      );
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        expect(
          AppPlatformPolicy.forPlatform(platform, isWeb: false),
          const AppPlatformPolicy.desktop(),
          reason: '$platform',
        );
      }
    });

    test('is the web in a browser, whatever the system', () {
      for (final platform in TargetPlatform.values) {
        expect(
          AppPlatformPolicy.forPlatform(platform, isWeb: true),
          const AppPlatformPolicy.web(),
          reason: '$platform',
        );
      }
    });

    test('of the running app follows a platform override', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(
        AppPlatformPolicy.current(),
        kIsWeb
            ? const AppPlatformPolicy.web()
            : const AppPlatformPolicy.desktop(),
      );
    });
  });

  test('a phone: a bottom sheet, every edit said, removals behind Undo', () {
    for (final policy in const [
      AppPlatformPolicy.android(),
      AppPlatformPolicy.iOS(),
    ]) {
      expect(policy.bulletinTokens, isNull);
      expect(policy.packSheetArrangement, PanelArrangement.touch);
      expect(policy.asksInBoxes, isFalse);
      expect(policy.confirmsPackRemovals, isFalse);
      expect(policy.saysLibraryEdits, isTrue);
      expect(policy.saysListReplacements, isTrue);
    }
    expect(const AppPlatformPolicy.android().inkKind, ChromeInkKind.ripple);
    expect(const AppPlatformPolicy.iOS().inkKind, ChromeInkKind.highlight);
  });

  test('a desktop app: a box that asks before a removal, no edit said', () {
    const policy = AppPlatformPolicy.desktop();
    expect(policy.bulletinTokens, BulletinTokens.desktop);
    expect(policy.packSheetArrangement, PanelArrangement.pointer);
    expect(policy.asksInBoxes, isTrue);
    expect(policy.confirmsPackRemovals, isTrue);
    expect(policy.saysLibraryEdits, isFalse);
    expect(policy.saysListReplacements, isFalse);
    expect(policy.inkKind, ChromeInkKind.pointer);
  });

  test('a browser: a box that removes at once, a full list said', () {
    const policy = AppPlatformPolicy.web();
    expect(policy.bulletinTokens, BulletinTokens.desktop);
    expect(policy.packSheetArrangement, PanelArrangement.pointer);
    expect(policy.asksInBoxes, isTrue);
    expect(policy.confirmsPackRemovals, isFalse);
    expect(policy.saysLibraryEdits, isFalse);
    expect(policy.saysListReplacements, isTrue);
    expect(policy.inkKind, ChromeInkKind.pointer);
  });

  group('the message menu', () {
    const touch = ChatSelectionPolicy.mobile();
    const mouse = ChatSelectionPolicy.desktop();

    test('follows the selection policy in an app', () {
      for (final policy in const [
        AppPlatformPolicy.android(),
        AppPlatformPolicy.iOS(),
        AppPlatformPolicy.desktop(),
      ]) {
        expect(
          policy.messageMenuPresentationFor(touch),
          ChatMessageMenuPresentation.sheet,
          reason: '$policy',
        );
        expect(
          policy.messageMenuPresentationFor(mouse),
          ChatMessageMenuPresentation.popup,
          reason: '$policy',
        );
      }
    });

    test('is a popup at the press in a browser, touched or not', () {
      const policy = AppPlatformPolicy.web();
      expect(
        policy.messageMenuPresentationFor(touch),
        ChatMessageMenuPresentation.popup,
      );
      expect(
        policy.messageMenuPresentationFor(mouse),
        ChatMessageMenuPresentation.popup,
      );
    });
  });
}
