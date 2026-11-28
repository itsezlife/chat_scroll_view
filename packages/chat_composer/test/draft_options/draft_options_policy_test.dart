/// The draft options policy: one pure-Dart value per platform family, each
/// field pinned per platform.
///
/// **Seam:** `DraftOptionsPolicy` and its `forPlatform`.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('forPlatform', () {
    test('Android and Fuchsia take the Android policy', () {
      expect(
        DraftOptionsPolicy.forPlatform(TargetPlatform.android),
        isA<DraftOptionsPolicy$Android>(),
      );
      expect(
        DraftOptionsPolicy.forPlatform(TargetPlatform.fuchsia),
        isA<DraftOptionsPolicy$Android>(),
      );
    });

    test('iOS takes the iOS policy, the iPad one in a regular width', () {
      final phone = DraftOptionsPolicy.forPlatform(TargetPlatform.iOS);
      final pad = DraftOptionsPolicy.forPlatform(
        TargetPlatform.iOS,
        regularWidth: true,
      );

      expect(phone, isA<DraftOptionsPolicy$IOS>());
      expect(phone.presentation, DraftOptionsPresentation.ios);
      expect(pad.presentation, DraftOptionsPresentation.ipad);
    });

    test('macOS, Windows and Linux take the desktop policy', () {
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        expect(
          DraftOptionsPolicy.forPlatform(platform),
          isA<DraftOptionsPolicy$Desktop>(),
          reason: '$platform',
        );
      }
    });

    test('the web takes the menu on every platform, not the overlay', () {
      for (final platform in TargetPlatform.values) {
        final policy = DraftOptionsPolicy.forPlatform(platform, isWeb: true);
        expect(policy, isA<DraftOptionsPolicy$Web>(), reason: '$platform');
        expect(policy.usesOverlay, isFalse);
        expect(policy.scrim, isNull);
      }
    });
  });

  group('part order', () {
    test('Android: reply, forward, link', () {
      expect(const DraftOptionsPolicy$Android().partOrder, [
        DraftPart.reply,
        DraftPart.forward,
        DraftPart.link,
      ]);
    });

    test('desktop: link, reply, forward', () {
      expect(const DraftOptionsPolicy$Desktop().partOrder, [
        DraftPart.link,
        DraftPart.reply,
        DraftPart.forward,
      ]);
    });

    test('iOS and the web: link, reply, forward', () {
      const order = [DraftPart.link, DraftPart.reply, DraftPart.forward];
      expect(const DraftOptionsPolicy$IOS().partOrder, order);
      expect(const DraftOptionsPolicy$Web().partOrder, order);
    });

    test('a host may pass its own order', () {
      expect(
        const DraftOptionsPolicy$Android(partOrder: [DraftPart.link]).partOrder,
        [DraftPart.link],
      );
    });

    test('pages lists the parts present in the order', () {
      const policy = DraftOptionsPolicy$Android();
      expect(policy.pages({DraftPart.link, DraftPart.reply}), [
        DraftPart.reply,
        DraftPart.link,
      ]);
      expect(
        const DraftOptionsPolicy$Desktop().pages({
          DraftPart.reply,
          DraftPart.link,
        }),
        [DraftPart.link, DraftPart.reply],
      );
    });
  });

  group('apply mode', () {
    test('mobile applies live, desktop commits on save, the web live', () {
      expect(
        const DraftOptionsPolicy$Android().apply,
        DraftOptionsApply.liveApply,
      );
      expect(const DraftOptionsPolicy$IOS().apply, DraftOptionsApply.liveApply);
      expect(
        const DraftOptionsPolicy$Desktop().apply,
        DraftOptionsApply.commitOnSave,
      );
      expect(const DraftOptionsPolicy$Web().apply, DraftOptionsApply.liveApply);
    });

    test('a host may override it', () {
      expect(
        const DraftOptionsPolicy$Desktop(
          apply: DraftOptionsApply.liveApply,
        ).apply,
        DraftOptionsApply.liveApply,
      );
    });
  });

  group('opening', () {
    test('mobile opens on a pending page, desktop only on a loaded one', () {
      expect(const DraftOptionsPolicy$Android().opensOnPending, isTrue);
      expect(const DraftOptionsPolicy$IOS().opensOnPending, isTrue);
      expect(const DraftOptionsPolicy$Desktop().opensOnPending, isFalse);
    });

    test('the overlay is the mobile and desktop form', () {
      expect(const DraftOptionsPolicy$Android().usesOverlay, isTrue);
      expect(const DraftOptionsPolicy$IOS().usesOverlay, isTrue);
      expect(const DraftOptionsPolicy$Desktop().usesOverlay, isTrue);
    });
  });

  group('title', () {
    test('Android a title and subtitle, desktop a title, iOS none', () {
      expect(
        const DraftOptionsPolicy$Android().title,
        DraftOptionsTitle.titleAndSubtitle,
      );
      expect(
        const DraftOptionsPolicy$Desktop().title,
        DraftOptionsTitle.titleWithOnePart,
      );
      expect(const DraftOptionsPolicy$IOS().title, DraftOptionsTitle.none);
    });
  });

  group('scrim', () {
    test('each platform takes its preset', () {
      expect(
        const DraftOptionsPolicy$Android().scrim,
        ChromeScrimPreset.android,
      );
      expect(const DraftOptionsPolicy$IOS().scrim, ChromeScrimPreset.ios);
      expect(
        const DraftOptionsPolicy$IOS(iPad: true).scrim,
        ChromeScrimPreset.ipad,
      );
      expect(
        const DraftOptionsPolicy$Desktop().scrim,
        ChromeScrimPreset.desktop,
      );
    });

    test('a host may pass another preset', () {
      expect(
        const DraftOptionsPolicy$IOS(scrim: ChromeScrimPreset.desktop).scrim,
        ChromeScrimPreset.desktop,
      );
    });
  });

  test('the presentation names each family', () {
    expect(
      const DraftOptionsPolicy$Android().presentation,
      DraftOptionsPresentation.android,
    );
    expect(
      const DraftOptionsPolicy$Desktop().presentation,
      DraftOptionsPresentation.desktop,
    );
    expect(
      const DraftOptionsPolicy$Web().presentation,
      DraftOptionsPresentation.web,
    );
  });

  group('link page', () {
    const metrics = DraftLinkRowMetrics(
      height: 48,
      iconSize: 24,
      iconStart: 17,
      labelStart: 59,
      fontSize: 16,
      minWidthBeyondLabel: 77,
    );

    test('Android: size row always (inert at 50 %), 8 gap at 6 %, apply, '
        '"Do not preview" with a 12 % press, next link, ripple, 300 ms '
        'ease-out-quint label', () {
      final page = const DraftOptionsPolicy$Android().linkPage;

      expect(page.sizeRow, DraftLinkSizeRow.inertWithoutShrinkable);
      expect(page.inertOpacity, 0.5);
      expect(page.positionNeedsText, isFalse);
      expect(page.separator, DraftLinkSeparator.gap);
      expect(page.separatorExtent, 8);
      expect(page.separatorOpacity, 0.06);
      expect(page.applyRow, isTrue);
      expect(page.removeLabel, DraftLinkRemoveLabel.doNotPreview);
      expect(page.removePressOpacity, 0.12);
      expect(page.linkHint, isFalse);
      expect(page.removeFallsBackToNextLink, isTrue);
      expect(page.rowMetrics, metrics);
      expect(
        page.labelChange,
        const MotionSpec(Duration(milliseconds: 300), Curves.easeOutQuint),
      );
      expect(page.ink, ChromeInkKind.ripple);
      expect(page.rowGuard, const Duration(milliseconds: 400));
    });

    test('iOS: size row only when shrinkable, separator, apply, "Do not '
        'preview", highlight, the label at once', () {
      final page = const DraftOptionsPolicy$IOS().linkPage;

      expect(page.sizeRow, DraftLinkSizeRow.whenShrinkable);
      expect(page.positionNeedsText, isFalse);
      expect(page.separator, DraftLinkSeparator.gap);
      expect(page.applyRow, isTrue);
      expect(page.removeLabel, DraftLinkRemoveLabel.doNotPreview);
      expect(page.linkHint, isFalse);
      expect(page.removeFallsBackToNextLink, isFalse);
      expect(page.labelChange.duration, Duration.zero);
      expect(page.ink, ChromeInkKind.highlight);
      expect(const DraftOptionsPolicy$IOS(iPad: true).linkPage, page);
    });

    test('desktop: 4 skip above, position only with text, size only when '
        'shrinkable, no apply row, "Remove preview", the link hint, pointer, '
        'instant', () {
      final page = const DraftOptionsPolicy$Desktop().linkPage;

      expect(page.sizeRow, DraftLinkSizeRow.whenShrinkable);
      expect(page.positionNeedsText, isTrue);
      expect(page.separator, DraftLinkSeparator.skipAbove);
      expect(page.separatorExtent, 4);
      expect(page.applyRow, isFalse);
      expect(page.removeLabel, DraftLinkRemoveLabel.removePreview);
      expect(page.linkHint, isTrue);
      expect(page.removeFallsBackToNextLink, isFalse);
      expect(page.labelChange.duration, Duration.zero);
      expect(page.ink, ChromeInkKind.pointer);
    });

    test('web: the menu applies each choice, no apply row', () {
      final page = const DraftOptionsPolicy$Web().linkPage;

      expect(page.applyRow, isFalse);
      expect(page.sizeRow, DraftLinkSizeRow.whenShrinkable);
    });

    test('a host may override a field', () {
      final policy = DraftOptionsPolicy.android(
        linkPage: DraftLinkPagePolicy.android.copyWith(applyRow: false),
      );

      expect(policy.linkPage.applyRow, isFalse);
      expect(policy.linkPage.ink, ChromeInkKind.ripple);
    });
  });
}
