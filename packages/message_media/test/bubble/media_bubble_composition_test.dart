/// The bubble composition: the caption's side by `invertMedia` for media
/// and for a link preview card, the sides it tells the layout (corners
/// through the policy), the bubble's shape and tail, where the time goes,
/// and the caption width metrics per platform.
///
/// **Seam:** `MediaBubbleComposition` and `MessageMediaPolicy.layout`, pure.
library;

import 'package:content_model/content_model.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';

MediaItem _photo(String id, {ContentSize size = const ContentSize(800, 600)}) =>
    MediaItem(
      id: MediaItemId(id),
      kind: MediaItemKind.photo,
      descriptor: ContentDescriptor(key: ContentKey.document(id), size: size),
    );

MediaItem _file(String id) => MediaItem(
  id: MediaItemId(id),
  kind: MediaItemKind.file,
  descriptor: ContentDescriptor(
    key: ContentKey.document(id),
    fileName: 'a.pdf',
    byteSize: 2048,
  ),
);

final _page = LinkPreview(url: Uri.parse('https://example.org/a'));

MediaLayoutInput _base(
  List<MediaItem> items, {
  bool card = false,
  bool isOutgoing = false,
  double width = 360,
  double? captionWidth,
  double? maxContentWidth,
  MediaLayoutChrome chrome = const MediaLayoutChrome(timeWidth: 30),
}) => MediaLayoutInput(
  items: items,
  availableWidth: width,
  displaySize: Size(width, 640),
  maxContentWidth: maxContentWidth,
  captionWidth: captionWidth,
  isOutgoing: isOutgoing,
  linkPreview: card
      ? MediaLinkPreviewInput(messageId: 'm1', page: _page)
      : null,
  chrome: chrome,
);

void main() {
  group('caption position', () {
    test('media: the caption below, above under invertMedia', () {
      final base = _base([_photo('a')]);
      expect(
        const MediaBubbleComposition(hasCaption: true).captionPositionFor(base),
        MediaCaptionPosition.below,
      );
      expect(
        const MediaBubbleComposition(
          hasCaption: true,
          invertMedia: true,
        ).captionPositionFor(base),
        MediaCaptionPosition.above,
      );
      expect(
        const MediaBubbleComposition(
          invertMedia: true,
        ).captionPositionFor(base),
        MediaCaptionPosition.none,
      );
    });

    test('a link preview card: the text above, the card above under '
        'invertMedia', () {
      final base = _base(const [], card: true);
      expect(
        const MediaBubbleComposition(hasCaption: true).captionPositionFor(base),
        MediaCaptionPosition.above,
      );
      expect(
        const MediaBubbleComposition(
          hasCaption: true,
          invertMedia: true,
        ).captionPositionFor(base),
        MediaCaptionPosition.below,
      );
    });

    test('inputFor sets the position, the header and the reactions only', () {
      final base = _base([_photo('a')], captionWidth: 120);
      final input = const MediaBubbleComposition(
        hasCaption: true,
        invertMedia: true,
        hasHeader: true,
        reactionsBelow: true,
      ).inputFor(base);
      expect(input.captionPosition, MediaCaptionPosition.above);
      expect(input.headerAbove, isTrue);
      expect(input.reactionsBelow, isTrue);
      expect(input.captionWidth, 120);
      expect(input.items, base.items);
      expect(input.chrome, base.chrome);
    });
  });

  group('corners by invertMedia (Android: edge 15, text 4, joined 3)', () {
    const policy = MessageMediaPolicy.android();
    MediaCornerRadii radiiOf(MediaBubbleComposition c, {bool out = false}) =>
        policy
            .layout(c.inputFor(_base([_photo('a')], isOutgoing: out)))
            .cells
            .single
            .radii;

    test('caption below: top on the edge, bottom on the text, the incoming '
        'tail corner joined', () {
      expect(
        radiiOf(const MediaBubbleComposition(hasCaption: true)),
        const MediaCornerRadii(
          topLeft: 15,
          topRight: 15,
          bottomLeft: 3,
          bottomRight: 4,
        ),
      );
      expect(
        radiiOf(const MediaBubbleComposition(hasCaption: true), out: true),
        const MediaCornerRadii(
          topLeft: 15,
          topRight: 15,
          bottomLeft: 4,
          bottomRight: 4,
        ),
      );
    });

    test('caption above: top on the text, bottom on the edge, no tail', () {
      expect(
        radiiOf(
          const MediaBubbleComposition(hasCaption: true, invertMedia: true),
        ),
        const MediaCornerRadii(
          topLeft: 4,
          topRight: 4,
          bottomLeft: 15,
          bottomRight: 15,
        ),
      );
    });

    test('a header above takes the top corners to the text radius', () {
      expect(
        radiiOf(const MediaBubbleComposition(hasHeader: true)),
        const MediaCornerRadii(
          topLeft: 4,
          topRight: 4,
          bottomLeft: 15,
          bottomRight: 15,
        ),
      );
    });

    test('iOS compact: the text side squares', () {
      const ios = MessageMediaPolicy.ios();
      final radii = ios
          .layout(
            const MediaBubbleComposition(
              hasCaption: true,
              invertMedia: true,
            ).inputFor(_base([_photo('a')])),
          )
          .cells
          .single
          .radii;
      expect(radii.topLeft, 0);
      expect(radii.topRight, 0);
      expect(radii.bottomLeft, 16);
    });
  });

  group('shape', () {
    MediaBubbleShape shapeOf(MediaBubbleComposition c, MediaLayoutInput base) =>
        MediaBubbleShape.of(c.inputFor(base));

    test('media without a caption below is a media bubble without a tail', () {
      final base = _base([_photo('a')]);
      expect(
        shapeOf(const MediaBubbleComposition(), base),
        MediaBubbleShape.media,
      );
      expect(
        shapeOf(
          const MediaBubbleComposition(hasCaption: true, invertMedia: true),
          base,
        ),
        MediaBubbleShape.media,
      );
      expect(MediaBubbleShape.media.hasTail, isFalse);
    });

    test('a caption below makes a tailed text bubble; so does a card', () {
      expect(
        shapeOf(
          const MediaBubbleComposition(hasCaption: true),
          _base([_photo('a')]),
        ),
        MediaBubbleShape.text,
      );
      expect(
        shapeOf(
          const MediaBubbleComposition(hasCaption: true),
          _base(const [], card: true),
        ),
        MediaBubbleShape.text,
      );
      expect(MediaBubbleShape.text.hasTail, isTrue);
    });
  });

  group('time', () {
    const policy = MessageMediaPolicy.android();
    (MediaBubbleTime, Rect?) timeOf(
      MediaBubbleComposition c,
      MediaLayoutInput base,
    ) {
      final input = c.inputFor(base);
      final layout = policy.layout(input);
      return (MediaBubbleTime.of(layout, input), layout.timePill);
    }

    test('over the media when it ends the bubble (no caption, caption '
        'above)', () {
      final base = _base([_photo('a')]);
      for (final c in const [
        MediaBubbleComposition(),
        MediaBubbleComposition(hasCaption: true, invertMedia: true),
        MediaBubbleComposition(hasHeader: true),
      ]) {
        final (time, pill) = timeOf(c, base);
        expect(time, MediaBubbleTime.overMedia, reason: '$c');
        expect(pill, isNotNull, reason: '$c');
      }
    });

    test('in the text with a caption below or reactions below', () {
      final base = _base([_photo('a')]);
      for (final c in const [
        MediaBubbleComposition(hasCaption: true),
        MediaBubbleComposition(reactionsBelow: true),
        MediaBubbleComposition(
          hasCaption: true,
          invertMedia: true,
          reactionsBelow: true,
        ),
      ]) {
        final (time, pill) = timeOf(c, base);
        expect(time, MediaBubbleTime.inText, reason: '$c');
        expect(pill, isNull, reason: '$c');
      }
    });

    test('on the last file of a stack that ends the bubble', () {
      final (time, pill) = timeOf(
        const MediaBubbleComposition(),
        _base([_file('a'), _file('b')]),
      );
      expect(time, MediaBubbleTime.inLastFileRow);
      expect(pill, isNull);
    });

    test('under the card when it is last; in the text when the text is', () {
      final base = _base(const [], card: true);
      final last = const MediaBubbleComposition(
        hasCaption: true,
      ).inputFor(base);
      expect(last.cardIsLast, isTrue);
      expect(
        timeOf(const MediaBubbleComposition(hasCaption: true), base).$1,
        MediaBubbleTime.underCard,
      );
      final first = const MediaBubbleComposition(
        hasCaption: true,
        invertMedia: true,
      ).inputFor(base);
      expect(first.cardIsLast, isFalse);
      expect(
        timeOf(
          const MediaBubbleComposition(hasCaption: true, invertMedia: true),
          base,
        ).$1,
        MediaBubbleTime.inText,
      );
    });
  });

  group('caption width metrics', () {
    MediaWidthMetrics? metricsOf(
      MessageMediaPolicy policy,
      MediaLayoutInput base, {
      bool caption = true,
    }) => policy
        .layout(MediaBubbleComposition(hasCaption: caption).inputFor(base))
        .widthMetrics;

    test('none without a caption, or without items', () {
      expect(
        metricsOf(
          const MessageMediaPolicy.android(),
          _base([_photo('a')]),
          caption: false,
        ),
        isNull,
      );
      expect(
        metricsOf(
          const MessageMediaPolicy.android(),
          _base(const [], card: true),
        ),
        isNull,
      );
    });

    test('Android widenMedia: the caption wraps at the max content width', () {
      final metrics = metricsOf(
        const MessageMediaPolicy.android(),
        _base([
          _photo('a', size: const ContentSize(300, 900)),
        ], maxContentWidth: 320),
      );
      expect(metrics?.rule, MediaCaptionWidthRule.widenMedia);
      expect(metrics?.captionMaxWidth, 320);
    });

    test('iOS wrapAtMedia: the caption wraps at the media max width (300 '
        'compact, 440 regular)', () {
      final compact = metricsOf(
        const MessageMediaPolicy.ios(),
        _base([_photo('a', size: const ContentSize(200, 600))]),
      );
      expect(compact?.rule, MediaCaptionWidthRule.wrapAtMedia);
      expect(compact?.captionMaxWidth, 300);
      final regular = metricsOf(
        const MessageMediaPolicy.ios(),
        _base([_photo('a', size: const ContentSize(200, 600))], width: 900),
      );
      expect(regular?.captionMaxWidth, 440);
    });

    test('desktop widenMedia: up to 430', () {
      final metrics = metricsOf(
        const MessageMediaPolicy.desktop(),
        _base([_photo('a', size: const ContentSize(200, 600))], width: 900),
      );
      expect(metrics?.rule, MediaCaptionWidthRule.widenMedia);
      expect(metrics?.captionMaxWidth, 430);
    });

    test('never narrower than the media', () {
      final layout = const MessageMediaPolicy.android().layout(
        const MediaBubbleComposition(
          hasCaption: true,
        ).inputFor(_base([_photo('a')], maxContentWidth: 100)),
      );
      expect(layout.widthMetrics?.captionMaxWidth, layout.size.width);
    });

    test('a measured caption wider than the media widens it, up to the '
        'policy limit', () {
      final narrow = _photo('a', size: const ContentSize(200, 600));
      for (final (policy, limit) in const [
        (MessageMediaPolicy.android(), 360.0),
        (MessageMediaPolicy.ios(), 300.0),
        (MessageMediaPolicy.desktop(), 430.0),
      ]) {
        final plain = policy.layout(
          const MediaBubbleComposition(
            hasCaption: true,
          ).inputFor(_base([narrow], width: 900, maxContentWidth: 360)),
        );
        final widened = policy.layout(
          const MediaBubbleComposition(hasCaption: true).inputFor(
            _base(
              [narrow],
              width: 900,
              maxContentWidth: 360,
              captionWidth: 280,
            ),
          ),
        );
        expect(
          widened.size.width,
          greaterThan(plain.size.width),
          reason: policy.family.name,
        );
        expect(
          widened.size.width,
          lessThanOrEqualTo(limit + 10),
          reason: policy.family.name,
        );
      }
    });

    test('iOS widening keeps the box height', () {
      const policy = MessageMediaPolicy.ios();
      final narrow = _photo('a', size: const ContentSize(400, 1200));
      final plain = policy.layout(
        const MediaBubbleComposition(
          hasCaption: true,
        ).inputFor(_base([narrow])),
      );
      final widened = policy.layout(
        const MediaBubbleComposition(
          hasCaption: true,
        ).inputFor(_base([narrow], captionWidth: 280)),
      );
      expect(widened.size.width, 280);
      expect(widened.size.height, plain.size.height);
    });
  });
}
