/// The chrome slots' pure rules: the time pill's rect per platform, the
/// options affordance's placement, hit area and hiding, and the spoiler
/// reveal's timing.
///
/// **Seam:** `MediaTimePillPlacement`, `MediaOptionsPlacement`,
/// `MediaSpoilerReveal` and `MessageMediaPolicy.layout`.
library;

import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';

MediaItem _item(
  String id, {
  MediaItemKind kind = MediaItemKind.photo,
  ContentSize? size = const ContentSize(4, 3),
}) => MediaItem(
  id: MediaItemId(id),
  kind: kind,
  descriptor: ContentDescriptor(
    key: ContentKey.document('doc-$id'),
    size: size,
  ),
);

MediaCell _cell(String id, MediaItemKind kind, Rect rect) => MediaCell(
  itemId: MediaItemId(id),
  kind: kind,
  rect: rect,
  neighbours: MediaNeighbours.bubble,
);

void main() {
  group('time pill rect', () {
    const media = Rect.fromLTWH(0, 0, 300, 200);
    const chrome = MediaLayoutChrome(timeWidth: 30);

    test('Android: bottom-right, top 23 above the bottom, 6 a side, at least '
        '17 high, 20 wider outgoing', () {
      const pill = MediaTimePillPlacement.android();
      expect(
        pill.rectOf(media, chrome, isOutgoing: false),
        const Rect.fromLTWH(252, 177, 42, 17),
      );
      expect(
        pill.rectOf(media, chrome, isOutgoing: true),
        const Rect.fromLTWH(232, 177, 62, 17),
      );
      // Under a bubble radius below 10 the padding is 4 a side.
      expect(
        pill.rectOf(
          media,
          const MediaLayoutChrome(timeWidth: 30, bubbleRadius: 8),
          isOutgoing: false,
        ),
        const Rect.fromLTWH(256, 177, 38, 17),
      );
      // A larger text grows the pill down from the same top.
      expect(
        pill.rectOf(
          media,
          const MediaLayoutChrome(timeWidth: 30, timeHeight: 16),
          isOutgoing: false,
        ),
        const Rect.fromLTWH(252, 177, 42, 21),
      );
    });

    test('iOS: bottom-right inset (6, 6), padded (7, 2)', () {
      expect(
        const MediaTimePillPlacement.ios().rectOf(
          media,
          chrome,
          isOutgoing: true,
        ),
        const Rect.fromLTWH(250, 176, 44, 18),
      );
    });

    test('desktop: bottom-right inset 4, padded (8, 2)', () {
      expect(
        const MediaTimePillPlacement.desktop().rectOf(
          media,
          chrome,
          isOutgoing: false,
        ),
        const Rect.fromLTWH(250, 175, 46, 21),
      );
    });

    group('through the policy', () {
      MediaLayout layoutOf(
        MessageMediaPolicy policy,
        List<MediaItem> items, {
        MediaCaptionPosition caption = MediaCaptionPosition.none,
        double timeWidth = 30,
        MediaLinkPreviewInput? linkPreview,
      }) => policy.layout(
        MediaLayoutInput(
          items: items,
          availableWidth: 375,
          displaySize: const Size(375, 640),
          captionPosition: caption,
          linkPreview: linkPreview,
          chrome: MediaLayoutChrome(timeWidth: timeWidth),
        ),
      );

      for (final policy in const [
        MessageMediaPolicy.android(),
        MessageMediaPolicy.ios(),
        MessageMediaPolicy.desktop(),
      ]) {
        test('${policy.family.name}: the pill sits over the bottom block', () {
          final layout = layoutOf(policy, [_item('a'), _item('b')]);
          expect(
            layout.timePill,
            policy.chrome.timePill.rectOf(
              layout.blocks.last.rect,
              const MediaLayoutChrome(timeWidth: 30),
              isOutgoing: false,
            ),
          );
        });
      }

      test('the pill is on media with no text or the caption above', () {
        const policy = MessageMediaPolicy.android();
        expect(layoutOf(policy, [_item('a')]).timePill, isNotNull);
        expect(
          layoutOf(policy, [
            _item('a'),
          ], caption: MediaCaptionPosition.above).timePill,
          isNotNull,
        );
      });

      test('no pill under a caption below, a card, a file stack or no '
          'time', () {
        const policy = MessageMediaPolicy.android();
        expect(
          layoutOf(policy, [
            _item('a'),
          ], caption: MediaCaptionPosition.below).timePill,
          isNull,
        );
        expect(
          layoutOf(
            policy,
            [_item('a')],
            linkPreview: MediaLinkPreviewInput(
              messageId: 'm1',
              page: LinkPreview(
                url: Uri.parse('https://example.com/'),
                title: 'Example',
              ),
            ),
          ).timePill,
          isNull,
        );
        expect(
          layoutOf(policy, [
            _item('f', kind: MediaItemKind.file, size: null),
          ]).timePill,
          isNull,
        );
        expect(layoutOf(policy, [_item('a')], timeWidth: 0).timePill, isNull);
      });
    });
  });

  group('options affordance', () {
    const android = MediaOptionsPlacement.android();
    const box = Rect.fromLTWH(10, 20, 300, 200);
    final video = _cell('v', MediaItemKind.video, box);
    final mosaic = MediaBlock.mosaic(rect: box, cells: [video]);

    test('on a video or animation box: dots 6 × 18 at (right − 14, top + '
        '8.1), hit x ± 20 and y −4 to +30 around them', () {
      const expected = MediaOptionsAffordance(
        iconRect: Rect.fromLTWH(296, 28.1, 6, 18),
        hitRect: Rect.fromLTRB(276, 24.1, 316, 58.1),
      );
      expect(android.affordanceOf(video, mosaic), expected);
      final gif = _cell('g', MediaItemKind.animation, box);
      expect(
        android.affordanceOf(gif, MediaBlock.mosaic(rect: box, cells: [gif])),
        expected,
      );
    });

    test('none on a photo, nor on iOS or desktop', () {
      final photo = _cell('p', MediaItemKind.photo, box);
      expect(
        android.affordanceOf(
          photo,
          MediaBlock.mosaic(rect: box, cells: [photo]),
        ),
        isNull,
      );
      expect(
        const MediaChromeSlots.ios().options.affordanceOf(video, mosaic),
        isNull,
      );
      expect(
        const MediaChromeSlots.desktop().options.affordanceOf(video, mosaic),
        isNull,
      );
      expect(MediaOptionsPlacement.none.isNone, isTrue);
    });

    test('on a file stack\'s first row only, at its top-right', () {
      final first = _cell(
        'f1',
        MediaItemKind.file,
        const Rect.fromLTWH(0, 0, 280, 56),
      );
      final second = _cell(
        'f2',
        MediaItemKind.file,
        const Rect.fromLTWH(0, 56, 280, 56),
      );
      final stack = MediaBlock.fileStack(
        rect: const Rect.fromLTWH(0, 0, 280, 112),
        cells: [first, second],
      );
      expect(
        android.affordanceOf(first, stack),
        const MediaOptionsAffordance(
          iconRect: Rect.fromLTWH(253, 4, 24, 24),
          hitRect: Rect.fromLTRB(233, 0, 273, 34),
        ),
      );
      expect(android.affordanceOf(second, stack), isNull);
    });

    test('hidden in compact mode, on a preview, under a hidden spoiler and '
        'on a small image', () {
      expect(
        android.affordanceOf(
          video,
          mosaic,
          context: const MediaChromeContext(compact: true),
        ),
        isNull,
      );
      expect(
        android.affordanceOf(
          video,
          mosaic,
          context: const MediaChromeContext(preview: true),
        ),
        isNull,
      );
      expect(android.affordanceOf(video, mosaic, spoilerHidden: true), isNull);
      expect(android.affordanceOf(video, mosaic, smallImage: true), isNull);
    });
  });

  group('spoiler rect', () {
    test('the cell\'s rect while a box\'s spoiler is hidden', () {
      const rect = Rect.fromLTWH(0, 0, 100, 80);
      final cell = _cell('a', MediaItemKind.photo, rect);
      final hidden = MediaItem(
        id: const MediaItemId('a'),
        kind: MediaItemKind.photo,
        spoiler: true,
        descriptor: const ContentDescriptor(key: ContentKey.document('doc-a')),
      );
      expect(
        MediaChromeSlots.spoilerRectOf(cell, hidden, revealed: false),
        rect,
      );
      expect(
        MediaChromeSlots.spoilerRectOf(cell, hidden, revealed: true),
        isNull,
      );
      expect(
        MediaChromeSlots.spoilerRectOf(cell, _item('a'), revealed: false),
        isNull,
      );
    });
  });

  group('reveal origin', () {
    test('the state hands the touch point out once, and only with the '
        'first reveal', () {
      final state = MessageMediaState();
      addTearDown(state.dispose);
      const id = MediaItemId('a');
      state.revealSpoiler(id, at: const Offset(4, 5));
      state.revealSpoiler(id, at: const Offset(9, 9));
      expect(state.takeRevealOrigin(id), const Offset(4, 5));
      expect(state.takeRevealOrigin(id), isNull);
      expect(state.isSpoilerRevealed(id), isTrue);
    });
  });

  group('reveal timing', () {
    test('circle: clamp(r · 0.3, 250, 550) ms, r in physical pixels', () {
      const circle = MediaSpoilerReveal$Circle();
      expect(circle.durationFor(100), const Duration(milliseconds: 250));
      expect(circle.durationFor(1000), const Duration(milliseconds: 300));
      expect(circle.durationFor(1500), const Duration(milliseconds: 450));
      expect(circle.durationFor(4000), const Duration(milliseconds: 550));
      // r is the cell's diagonal (300 × 400 → 500) at the device's ratio,
      // wherever the touch.
      expect(
        circle.durationOf(
          const Size(300, 400),
          Offset.zero,
          devicePixelRatio: 2,
        ),
        const Duration(milliseconds: 300),
      );
      expect(circle.delay, Duration.zero);
      expect(circle.curve, Curves.easeInOut);
      expect(circle.holeRadiusOf(const Size(300, 400), Offset.zero, 0.5), 250);
    });

    test('spot: after 100 ms, 450 ms from the centre, 250 ms from an '
        'edge', () {
      const spot = MediaSpoilerReveal$Spot();
      const size = Size(300, 400);
      expect(spot.delay, const Duration(milliseconds: 100));
      expect(
        spot.durationOf(size, const Offset(150, 200)),
        const Duration(milliseconds: 450),
      );
      expect(
        spot.durationOf(size, const Offset(0, 200)),
        const Duration(milliseconds: 250),
      );
      expect(
        spot.totalOf(size, const Offset(75, 200)),
        const Duration(milliseconds: 450),
      );
      expect(spot.holeRadiusOf(size, Offset.zero, 1), 500);
    });

    test('cross-fade: 200 ms, linear, the cover fading out', () {
      const fade = MediaSpoilerReveal$CrossFade();
      expect(
        fade.durationOf(const Size(10, 10), Offset.zero),
        const Duration(milliseconds: 200),
      );
      expect(fade.curve, Curves.linear);
      expect(fade.coverOpacityOf(0.25), 0.75);
      expect(fade.holeRadiusOf(const Size(10, 10), Offset.zero, 0.5), isNull);
    });

    test('each family\'s form', () {
      expect(
        const MessageMediaPolicy.android().chrome.reveal,
        isA<MediaSpoilerReveal$Circle>(),
      );
      expect(
        const MessageMediaPolicy.ios().chrome.reveal,
        isA<MediaSpoilerReveal$Spot>(),
      );
      expect(const MessageMediaPolicy.ios().chrome.spoilerBlocksPinch, isTrue);
      expect(
        const MessageMediaPolicy.desktop().chrome.reveal,
        isA<MediaSpoilerReveal$CrossFade>(),
      );
    });
  });
}
