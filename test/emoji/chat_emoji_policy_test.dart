import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

// Every expectation is a literal from the platform's own source, written out
// so it does not come from the code under test. Android: `MessageObject.java`
// font steps and `ChatMessageCell.java` sticker rule; iOS:
// `ChatMessageAnimatedStickerItemNode.swift` font table and sticker size;
// Desktop: `history_view_large_emoji.cpp`, `history_view_custom_emoji.cpp`,
// `history_view_sticker.cpp`.

const _glyph = ContentKey.unicode('\u{1F44D}');

/// [count] items on one line; all custom, or the first a unicode glyph.
EmojiOnly _line(int count, {required bool allCustom}) => EmojiOnly([
  for (var i = 0; i < count; i++)
    EmojiOnlyItem(!allCustom && i == 0 ? _glyph : ContentKey.document('d$i')),
]);

/// One item per line, [lines] lines.
EmojiOnly _column(int lines) => EmojiOnly([
  for (var i = 0; i < lines; i++)
    EmojiOnlyItem(ContentKey.document('d$i'), lineBreaksBefore: i == 0 ? 0 : 1),
]);

void main() {
  group('forPlatform', () {
    test('android and fuchsia are the Android family, iOS is iOS', () {
      expect(
        ChatEmojiPolicy.forPlatform(
          platform: TargetPlatform.android,
          isWeb: false,
        ),
        isA<ChatEmojiPolicy$Android>(),
      );
      expect(
        ChatEmojiPolicy.forPlatform(
          platform: TargetPlatform.fuchsia,
          isWeb: false,
        ),
        isA<ChatEmojiPolicy$Android>(),
      );
      expect(
        ChatEmojiPolicy.forPlatform(platform: TargetPlatform.iOS, isWeb: false),
        isA<ChatEmojiPolicy$Ios>(),
      );
    });

    test('macOS, Windows, Linux and the web are the desktop family', () {
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        expect(
          ChatEmojiPolicy.forPlatform(platform: platform, isWeb: false),
          isA<ChatEmojiPolicy$Desktop>(),
        );
      }
      expect(
        ChatEmojiPolicy.forPlatform(
          platform: TargetPlatform.android,
          isWeb: true,
        ),
        isA<ChatEmojiPolicy$Desktop>(),
        reason: 'web follows desktop',
      );
    });
  });

  group('Android', () {
    const policy = ChatEmojiPolicy.android();

    test('font steps are Android\'s by count and custom-ness', () {
      expect(policy.fontSizeFor(_line(1, allCustom: true)), 81.6);
      expect(policy.fontSizeFor(_line(1, allCustom: false)), 40.8);
      expect(policy.fontSizeFor(_line(3, allCustom: false)), 33.6);
      expect(policy.fontSizeFor(_line(10, allCustom: false)), 22.8);
    });

    test('an item box is the font plus 4 dp', () {
      expect(
        policy.itemBoxFor(_line(3, allCustom: false)),
        closeTo(37.6, 1e-9),
      );
    });

    test('the sticker is 0.5 x 0.625 of the short side, with no inset', () {
      expect(policy.stickerExtentFor(const Size(360, 640)), 112.5);
      expect(policy.stickerInset, 0);
    });

    test('no count cap, and the sticker permission is a gate', () {
      expect(policy.admits(_line(200, allCustom: false)), isTrue);
      expect(policy.gatesOnStickerPermission, isTrue);
    });

    test('under a header the text wraps at 65 % of the parent width', () {
      final limit = policy.wrapLimitUnderHeader(400);
      expect(limit.of(1000), closeTo(260, 1e-9));
      expect(limit.of(200), 200, reason: 'never wider than the row');
    });

    test('the header is above the text and beside the sticker', () {
      expect(
        policy.headerPlacementFor(ChatEmojiLayoutKind.text),
        ChatEmojiHeaderPlacement.above,
      );
      expect(
        policy.headerPlacementFor(ChatEmojiLayoutKind.sticker),
        ChatEmojiHeaderPlacement.beside,
      );
    });

    test('nothing mirrors in a right-to-left chat', () {
      expect(policy.mirrorsInRtl, isFalse);
      expect(policy.textDirectionFor(TextDirection.rtl), TextDirection.ltr);
    });

    test('a host overrides the tables and the wrap share', () {
      const custom = ChatEmojiPolicy.android(
        sizes: ChatEmojiSizes(stickerZoom: 0.5),
        headerWrapFraction: 0.5,
      );

      expect(custom.stickerExtentFor(const Size(360, 640)), 90);
      expect(custom.wrapLimitUnderHeader(400).of(1000), closeTo(200, 1e-9));
    });
  });

  group('iOS', () {
    const policy = ChatEmojiPolicy.ios();

    test(
      'font is 94 pt scaled and floored by the longest line or line count',
      () {
        const expected = <int, double>{
          1: 94,
          2: 78,
          3: 64,
          4: 49,
          5: 43,
          6: 35,
          7: 30,
          8: 25,
          9: 22,
          10: 19,
          30: 19,
        };
        for (final MapEntry(key: count, value: font) in expected.entries) {
          expect(
            policy.fontSizeFor(_line(count, allCustom: false)),
            font,
            reason: '$count in a line',
          );
        }
      },
    );

    test('custom emoji take the same table as glyphs', () {
      expect(policy.fontSizeFor(_line(3, allCustom: true)), 64);
    });

    test('the longer of the longest line and the line count decides', () {
      expect(policy.fontSizeFor(_column(5)), 43);
      final wide = EmojiOnly([
        for (var i = 0; i < 2; i++)
          EmojiOnlyItem(_glyph, lineBreaksBefore: i == 0 ? 0 : 1),
        const EmojiOnlyItem(_glyph),
        const EmojiOnlyItem(_glyph),
      ]);
      // Two lines, the second three long.
      expect(policy.fontSizeFor(wide), 64);
    });

    test('the sticker is 112 pt whatever the screen, in a 10 pt inset', () {
      expect(policy.stickerExtentFor(const Size(360, 640)), 112);
      expect(policy.stickerExtentFor(const Size(1024, 1366)), 112);
      expect(policy.stickerInset, 10);
    });

    test('no count cap and the sticker permission is not a gate', () {
      expect(policy.admits(_line(200, allCustom: false)), isTrue);
      expect(policy.gatesOnStickerPermission, isFalse);
    });

    test('a header takes 45 pt off the wrap width', () {
      expect(policy.wrapLimitUnderHeader(400).of(300), 255);
    });

    test('the header is beside both layouts, and nothing mirrors', () {
      expect(
        policy.headerPlacementFor(ChatEmojiLayoutKind.text),
        ChatEmojiHeaderPlacement.beside,
      );
      expect(
        policy.headerPlacementFor(ChatEmojiLayoutKind.sticker),
        ChatEmojiHeaderPlacement.beside,
      );
      expect(policy.mirrorsInRtl, isFalse);
    });
  });

  group('Desktop', () {
    const policy = ChatEmojiPolicy.desktop();

    test(
      'a unicode or mixed message of up to 3 is 38 px images, 2 px apart',
      () {
        for (var count = 1; count <= 3; count++) {
          final emoji = _line(count, allCustom: false);
          expect(policy.itemBoxFor(emoji), closeTo(38, 1e-9), reason: '$count');
          expect(policy.itemSkipFor(emoji), 2);
        }
      },
    );

    test('more than 3 regular emoji are not emoji-only', () {
      expect(policy.admits(_line(3, allCustom: false)), isTrue);
      expect(policy.admits(_line(4, allCustom: false)), isFalse);
      expect(
        policy.admits(_column(4)),
        isTrue,
        reason: 'custom emoji lines are not capped',
      );
    });

    test('custom emoji lines scale 112, 78, 58 by their larger dimension', () {
      expect(policy.itemBoxFor(_line(1, allCustom: true)), closeTo(112, 1e-9));
      expect(policy.itemBoxFor(_line(2, allCustom: true)), closeTo(78, 1e-9));
      expect(policy.itemBoxFor(_line(3, allCustom: true)), closeTo(58, 1e-9));
      // The dimension is max(lines, longest line): two lines of one.
      expect(policy.itemBoxFor(_column(2)), closeTo(78, 1e-9));
      expect(policy.itemBoxFor(_line(4, allCustom: true)), closeTo(38, 1e-9));
      expect(policy.itemBoxFor(_line(5, allCustom: true)), closeTo(38, 1e-9));
      expect(policy.itemSkipFor(_line(2, allCustom: true)), 0);
    });

    test('the sticker is 112 px with no inset, and no permission gate', () {
      expect(policy.stickerExtentFor(const Size(1440, 900)), 112);
      expect(policy.stickerInset, 0);
      expect(policy.gatesOnStickerPermission, isFalse);
    });

    test('a header does not narrow the text, and sits beside when it fits', () {
      expect(policy.wrapLimitUnderHeader(900).of(500), 500);
      expect(
        policy.headerPlacementFor(ChatEmojiLayoutKind.text),
        ChatEmojiHeaderPlacement.besideWhenFits,
      );
      expect(
        policy.headerPlacementFor(ChatEmojiLayoutKind.sticker),
        ChatEmojiHeaderPlacement.besideWhenFits,
      );
    });

    test('everything mirrors in a right-to-left chat', () {
      expect(policy.mirrorsInRtl, isTrue);
      expect(policy.textDirectionFor(TextDirection.rtl), TextDirection.rtl);
      expect(policy.textDirectionFor(TextDirection.ltr), TextDirection.ltr);
    });
  });

  group('the unverified Desktop sizes', () {
    // Named constants, each recorded in ADR 036's divergence table.
    test('6 and 7 custom emoji and 8 and more take their named values', () {
      const policy = ChatEmojiPolicy.desktop();

      expect(
        policy.itemBoxFor(_line(6, allCustom: true)),
        ChatEmojiPolicy$Desktop.unverifiedLargeCustomBox,
      );
      expect(
        policy.itemBoxFor(_line(8, allCustom: true)),
        ChatEmojiPolicy$Desktop.unverifiedNormalCustomBox,
      );
    });
  });

  group('the wrap limit', () {
    test(
      'an infinite row stays infinite, so intrinsic widths are the items',
      () {
        expect(
          const ChatEmojiWrapLimit(cap: 100, reduction: 10).of(double.infinity),
          double.infinity,
        );
      },
    );

    test('the cap and the reduction both apply', () {
      const limit = ChatEmojiWrapLimit(cap: 100, reduction: 10);

      expect(limit.of(500), 100);
      expect(limit.of(105), 95);
      expect(ChatEmojiWrapLimit.none.of(500), 500);
    });
  });
}
