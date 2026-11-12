import 'dart:ui' show Size;

import 'package:chat_scroll_view/chat_scroll_view.dart'
    show ChatMediaItem, ChatMediaKind;
import 'package:chat_scroll_view_example/src/features/chat/utils/reference_media_sizes.dart';
import 'package:content_model/content_model.dart' show ContentSize;
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';

/// **Seam:** [ReferenceMediaSizes], the example's media size policy. The
/// expectations are worked from the formulas by hand, not
/// from the code.
void main() {
  ChatMediaItem sticker([ContentSize? source]) =>
      ChatMediaItem(kind: ChatMediaKind.sticker, source: source);
  ChatMediaItem gif([ContentSize? source]) =>
      ChatMediaItem(kind: ChatMediaKind.gif, source: source);

  void near(Size actual, Size expected) {
    expect(actual.width, moreOrLessEquals(expected.width, epsilon: 0.05));
    expect(actual.height, moreOrLessEquals(expected.height, epsilon: 0.05));
  }

  group('mobile', () {
    const policy = ReferenceMediaSizes.mobile();
    const phone = Size(412, 915);

    Size of(ChatMediaItem item, {Size viewport = phone, double? parent}) =>
        policy.sizeFor(
          item,
          viewport: viewport,
          parentWidth: parent ?? viewport.width,
        );

    test('a sticker fills half the short side: 206 dp on a 412 dp phone', () {
      expect(of(sticker(const ContentSize(512, 512))), const Size.square(206));
    });

    test('a sticker of unknown size is taken as 512 px square', () {
      expect(of(sticker()), const Size.square(206));
    });

    test('a sticker that is not square keeps its proportion in the box', () {
      // 512 x 256 fitted to 206 wide: 103 high.
      near(of(sticker(const ContentSize(512, 256))), const Size(206, 103));
      // 256 x 512: 206 wide would be 412 high, so 206 high and 103 wide.
      near(of(sticker(const ContentSize(256, 512))), const Size(103, 206));
    });

    test('a small sticker is enlarged to the box', () {
      expect(of(sticker(const ContentSize(128, 128))), const Size.square(206));
    });

    test('landscape takes half the height', () {
      expect(
        of(sticker(), viewport: const Size(915, 412)),
        const Size.square(206),
      );
    });

    test('a tablet takes 40 % of its side less the list column', () {
      // 800 x 1280, a large tablet (short side over 690): the short side
      // less max(35 % of it, 320) = 800 - 320 = 480; 40 % of it is 192.
      expect(
        of(sticker(), viewport: const Size(800, 1280)),
        const Size.square(192),
      );
      // 600 x 960, a small tablet: min(short side, long side less
      // max(35 % of it, 320)) = min(600, 960 - 336) = 600; 40 % is 240.
      expect(
        of(sticker(), viewport: const Size(600, 960)),
        const Size.square(240),
      );
    });

    test('a landscape GIF is the width less 64 dp wide, by its proportion '
        'high', () {
      // 412 - 64 = 348; 270 x 348 / 480 = 195.75.
      near(of(gif(const ContentSize(480, 270))), const Size(348, 195.75));
      expect(of(gif(const ContentSize(100, 100))), const Size.square(348));
    });

    test('a portrait GIF is 70 % of the width wide, held to that plus 100 dp '
        'high', () {
      // 0.7 x 412 = 288.4; 240 x 480 at that width is 576.8 high, over
      // 388.4: scaled to 388.4 high, 194.2 wide.
      near(of(gif(const ContentSize(240, 480))), const Size(194.2, 388.4));
      // 300 x 400 at 288.4 wide is 384.5 high, under the cap.
      near(of(gif(const ContentSize(300, 400))), const Size(288.4, 384.53));
    });

    test('a flat GIF is at least 120 dp high', () {
      // 348 wide is 87 high: raised to 120; 400 x 120 / 100 = 480 is wider
      // than 348, so the width stays.
      near(of(gif(const ContentSize(400, 100))), const Size(348, 120));
    });

    test('a GIF of unknown size is a 150 dp square', () {
      expect(of(gif()), const Size.square(150));
    });

    test('a GIF is a share of the chat column, not of the window', () {
      near(
        of(gif(const ContentSize(100, 100)), parent: 300),
        const Size.square(236),
      );
    });

    test('a tablet GIF is 70 % of its side less the list column', () {
      // 800 x 1280: 480 (see the sticker above); 0.7 x 480 = 336.
      near(
        of(gif(const ContentSize(480, 270)), viewport: const Size(800, 1280)),
        const Size(336, 189),
      );
    });

    test('decodes at most 512 px', () {
      expect(policy.maxDecodeExtent, 512);
    });
  });

  group('desktop', () {
    const policy = ReferenceMediaSizes.desktop();

    Size of(ChatMediaItem item, {Size viewport = const Size(1440, 900)}) =>
        policy.sizeFor(item, viewport: viewport, parentWidth: viewport.width);

    test('a sticker fits in 224 px, whatever the window', () {
      expect(of(sticker(const ContentSize(512, 512))), const Size.square(224));
      expect(
        of(
          sticker(const ContentSize(512, 512)),
          viewport: const Size(800, 600),
        ),
        const Size.square(224),
      );
      expect(of(sticker()), const Size.square(224));
      near(of(sticker(const ContentSize(512, 256))), const Size(224, 112));
    });

    test('a sticker smaller than the box keeps its own size', () {
      expect(of(sticker(const ContentSize(128, 128))), const Size.square(128));
    });

    test('a GIF fits in 320 px and is at least 100 px each way', () {
      expect(of(gif(const ContentSize(480, 270))), const Size(320, 180));
      expect(of(gif(const ContentSize(180, 240))), const Size(180, 240));
      expect(of(gif(const ContentSize(64, 64))), const Size(100, 100));
      expect(of(gif(const ContentSize(640, 100))), const Size(320, 100));
    });

    test('a GIF of unknown size is a 320 px square', () {
      expect(of(gif()), const Size.square(320));
    });
  });

  group('for platform', () {
    test('a phone is mobile, a desktop or the web is desktop', () {
      expect(
        ReferenceMediaSizes.forPlatform(
          platform: TargetPlatform.android,
          isWeb: false,
        ),
        const ReferenceMediaSizes.mobile(),
      );
      expect(
        ReferenceMediaSizes.forPlatform(
          platform: TargetPlatform.iOS,
          isWeb: false,
        ),
        const ReferenceMediaSizes.mobile(),
      );
      expect(
        ReferenceMediaSizes.forPlatform(
          platform: TargetPlatform.macOS,
          isWeb: false,
        ),
        const ReferenceMediaSizes.desktop(),
      );
      expect(
        ReferenceMediaSizes.forPlatform(
          platform: TargetPlatform.android,
          isWeb: true,
        ),
        const ReferenceMediaSizes.desktop(),
      );
    });
  });
}
