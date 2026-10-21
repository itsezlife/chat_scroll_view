/// The service colour behind the pill and the headers of an emoji-only
/// message: derived from the wallpaper per platform family, with a documented
/// default when the host has no wallpaper (04 section 1.4, 2.4, 3.3).
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/emoji_message/emoji_service_colors.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

Matcher _color(double r, double g, double b, double a) => isA<Color>()
    .having((c) => c.r, 'red', closeTo(r, 0.004))
    .having((c) => c.g, 'green', closeTo(g, 0.004))
    .having((c) => c.b, 'blue', closeTo(b, 0.004))
    .having((c) => c.a, 'alpha', closeTo(a, 0.004));

void main() {
  group('Android', () {
    const policy = ChatEmojiPolicy.android();

    test('a flat wallpaper is darkened in HSV: s + .05 + .1 (1 - s), v x .65, '
        'at 0x66 (AndroidUtilities.calcDrawableColor)', () {
      // #748391: h 209 deg, s .2, v .5686 -> s .33, v .3696.
      final colors = EmojiServiceColors.of(
        policy,
        wallpaper: const Color(0xFF748391),
      );

      expect(colors.panel, _color(0.2476, 0.3107, 0.3696, 0x66 / 255));
    });

    test('the time pill is 60 % of the panel\'s alpha (Cell:23776)', () {
      final colors = EmojiServiceColors.of(
        policy,
        wallpaper: const Color(0xFF748391),
      );

      expect(colors.pill.a, closeTo(0x66 / 255 * 0.6, 0.004));
      expect(colors.pill.r, colors.panel.r);
    });

    test(
      'no wallpaper: the default wallpaper colour gives the same result',
      () {
        expect(
          EmojiServiceColors.of(policy),
          EmojiServiceColors.of(
            policy,
            wallpaper: EmojiServiceColors.defaultWallpaper,
          ),
        );
      },
    );

    test('black stays black', () {
      final colors = EmojiServiceColors.of(
        policy,
        wallpaper: const Color(0xFF000000),
      );

      expect(colors.panel, _color(0, 0, 0, 0x66 / 255));
    });

    test('the text is white', () {
      expect(EmojiServiceColors.of(policy).text, const Color(0xFFFFFFFF));
    });
  });

  group('iOS', () {
    const policy = ChatEmojiPolicy.ios();

    test('no wallpaper: the built-in wallpaper\'s #748391 at 0.45', () {
      final colors = EmojiServiceColors.of(policy);

      expect(colors.pill, _color(0x74 / 255, 0x83 / 255, 0x91 / 255, 0.45));
      expect(colors.panel, colors.pill);
    });

    test('a wallpaper the host gives: black at 0.2', () {
      final colors = EmojiServiceColors.of(
        policy,
        wallpaper: const Color(0xFF334455),
      );

      expect(colors.pill, _color(0, 0, 0, 0.2));
      expect(colors.panel, colors.pill);
    });
  });

  group('Desktop', () {
    const policy = ChatEmojiPolicy.desktop();

    test('the wallpaper average, darkened as on Android, with no 60 % '
        'factor on the pill (unverified palette)', () {
      final colors = EmojiServiceColors.of(
        policy,
        wallpaper: const Color(0xFF748391),
      );

      expect(colors.panel, _color(0.2476, 0.3107, 0.3696, 0x66 / 255));
      expect(colors.pill, colors.panel);
    });
  });
}
