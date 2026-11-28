/// The link preview card's policy: every per-platform value, the `auto`
/// media size table and its overrides, and the card's layout (no card for
/// a removed or empty page, the width rules, the thumbnail, large media,
/// the button, the enlarge button, the time under a last card, RTL), with
/// its media as an ordinary cell keyed by `MediaItemId.linkPreviewOf`.
library;

import 'dart:math' as math;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';

import '../support/media_scopes.dart';

/// A measure of fixed metrics: 8 per character, 18 per line, wrapped at
/// the width within the limit.
final class _FixedMeasure implements MediaTextMeasure {
  const _FixedMeasure();

  static const char = 8.0;
  static const line = 18.0;

  @override
  MediaTextSize measure(
    InlineSpan text, {
    required TextScaler scaler,
    double maxWidth = double.infinity,
    int maxLines = 1,
    bool ellipsis = false,
  }) {
    final length = text.toPlainText().length * char;
    final lines = maxWidth.isFinite && maxWidth > 0
        ? math.max(1, (length / maxWidth).ceil()).clamp(1, maxLines)
        : 1;
    return MediaTextSize(
      width: maxWidth.isFinite ? math.min(length, maxWidth) : length,
      height: lines * line,
      lines: lines,
    );
  }
}

final _text = MediaScopes.text.copyWith(measure: const _FixedMeasure());

const _android = MessageMediaPolicy.android();
const _ios = MessageMediaPolicy.ios();
const _desktop = MessageMediaPolicy.desktop();

ContentDescriptor _photo({int width = 800, int height = 600}) =>
    ContentDescriptor(
      key: const ContentKey.document('photo'),
      size: ContentSize(width, height),
    );

ContentDescriptor _video() => const ContentDescriptor(
  key: ContentKey.document('video'),
  size: ContentSize(1280, 720),
  mediaForm: MediaForm.video,
);

LinkPreview _page({
  String? site = 'Site',
  String? title = 'A title',
  String description = 'Some description text',
  ContentDescriptor? photo,
  ContentDescriptor? media,
  String? type,
  bool? hasLargeMedia,
}) => LinkPreview(
  url: Uri.parse('https://example.org/private/page'),
  siteName: site,
  title: title,
  description: RichText.plain(description),
  photo: photo,
  media: media,
  type: type,
  hasLargeMedia: hasLargeMedia,
);

MediaLayoutInput _input(
  LinkPreview? page, {
  LinkPreviewOptions? options,
  String? button,
  bool outgoing = false,
  bool joinedBelow = true,
  MediaCaptionPosition caption = MediaCaptionPosition.above,
  bool reactionsBelow = false,
  TextDirection direction = TextDirection.ltr,
  double width = 400,
  double timeWidth = 0,
  List<MediaItem> items = const [],
}) => MediaLayoutInput(
  text: _text,
  items: items,
  availableWidth: width,
  displaySize: const Size(400, 900),
  captionPosition: caption,
  isOutgoing: outgoing,
  joinedBelow: joinedBelow,
  reactionsBelow: reactionsBelow,
  chrome: MediaLayoutChrome(timeWidth: timeWidth),
  correlation: const ChatCorrelation(chatId: 'chat', scrollId: 'm1'),
  linkPreview: switch (page) {
    final page? => MediaLinkPreviewInput(
      page: page,
      messageId: 'm1',
      options: options,
      buttonLabel: button,
      textDirection: direction,
    ),
    null => null,
  },
);

MediaBlock$LinkPreview? _card(MessageMediaPolicy policy, MediaLayoutInput i) {
  for (final block in policy.layout(i).blocks) {
    if (block case final MediaBlock$LinkPreview card) return card;
  }
  return null;
}

LinkPreviewOptions _options(LinkPreviewMedia media) =>
    LinkPreviewOptions(url: Uri.parse('https://example.org/'), media: media);

void main() {
  group('values per platform', () {
    test('block style: bar 3, fill 0.10 / 0.1 / 0.12, radius 5 / 4 / 5', () {
      expect(LinkPreviewBlockStyle.android.barWidth, 3);
      expect(LinkPreviewBlockStyle.android.fillOpacity, 0.10);
      expect(
        LinkPreviewBlockStyle.android.fillOpacityFor(
          outgoing: true,
          dark: true,
        ),
        0.12,
      );
      expect(
        LinkPreviewBlockStyle.android.fillOpacityFor(
          outgoing: false,
          dark: true,
        ),
        0.10,
      );
      expect(LinkPreviewBlockStyle.android.radius, 5);
      expect(LinkPreviewBlockStyle.ios.barWidth, 3);
      expect(LinkPreviewBlockStyle.ios.fillOpacity, 0.1);
      expect(LinkPreviewBlockStyle.ios.radius, 4);
      expect(LinkPreviewBlockStyle.desktop.barWidth, 3);
      expect(LinkPreviewBlockStyle.desktop.fillOpacity, 0.12);
      expect(LinkPreviewBlockStyle.desktop.radius, 5);
    });

    test('android metrics', () {
      const m = LinkPreviewCardMetrics.android;
      expect(m.outerLeft, 12 - 1.33);
      // From the bubble body's edge, the tail outside it: the card lines
      // up with the text in every bubble.
      expect(m.outerLeftIncomingText, 12 - 1.33);
      expect(m.outerRight, 10);
      expect(m.outerRightOutgoingText, 0);
      expect(m.textInset.left, 10);
      expect(m.largeMediaInset.horizontal, 17);
      expect(m.siteToTitle, 4);
      expect(m.titleToAuthor, 2);
      expect(m.toDescription, 2);
      expect(m.textToMedia, 2);
      expect(m.mediaToButton, 6);
      expect(m.bottomPadding, 6);
      expect(m.bottomExtraWithMediaAndText, 2.66);
      expect(m.thumbnailSize, 48);
      expect(m.thumbnailGap, 10);
      expect(m.thumbnailTrailingInset, 6);
      expect(m.descriptionNarrowExtra, 10);
      expect(m.minHeightWithThumbnail, 50);
      expect(m.largeMediaHeightShare, 1 / 3);
      expect(m.largeMediaHeightShareDocument, 1 / 2);
      expect(m.largeMediaMinHeight, 60);
      expect(m.largeMediaZeroSide, 150);
      expect(m.mediaRadius, 4);
      expect(m.buttonHeight, 42);
      expect(m.buttonDividerWidth, 0.66);
      expect(m.buttonDividerOpacity, 0.18);
    });

    test('ios metrics', () {
      const m = LinkPreviewCardMetrics.ios;
      expect(m.outerLeft, 11);
      expect(m.outerRight, 11);
      expect(m.outerTopFirst, 11);
      expect(m.textInset, const EdgeInsets.fromLTRB(20, 3, 17, 3));
      expect(m.textToMedia, 6);
      expect(m.largeMediaInset.top, 6);
      expect(m.largeMediaInset.bottom, 6);
      expect(m.mediaToButton, 7);
      expect(m.buttonGap, 7);
      expect(m.thumbnailSize, 54);
      expect(m.thumbnailTopInset, 6);
      expect(m.thumbnailTrailingInset, 6);
      expect(m.thumbnailRadius, 4);
      expect(m.thumbnailGap, 6);
      expect(m.minHeightWithThumbnail, 66);
      expect(m.mediaRadius, 4);
      expect(m.buttonHeight, 36);
      expect(m.largeMediaHeightShare, isNull);
    });

    test('desktop metrics', () {
      const m = LinkPreviewCardMetrics.desktop;
      expect(m.outerLeft, 11);
      expect(m.outerRight, 11);
      expect(m.outerTop, 0);
      expect(m.outerTopFirst, 11);
      expect(m.outerBottom, 8);
      expect(m.textInset.left, 10);
      expect(m.textInset.top, 5);
      expect(m.textInset.right, 7);
      expect(m.bottomPadding, 7);
      expect(m.textToMedia, 5);
      expect(m.thumbnailSize, isNull);
      expect(m.thumbnailGap, 8);
      expect(m.thumbnailRadius, 3);
      expect(m.mediaRadius, 3);
      expect(m.buttonHeight, 36);
      expect(m.buttonPadding, const EdgeInsets.fromLTRB(13, 8, 13, 8));
      expect(m.buttonDividerWidth, 1);
      expect(m.buttonDividerOpacity, 0.3);
      expect(m.maxWidth, 430);
    });

    test('text: sizes, weights and line limits', () {
      const a = LinkPreviewCardText.android;
      expect(a.size, 14);
      expect((a.siteLines, a.titleLines, a.descriptionLines), (1, 4, 6));
      expect(a.descriptionLinesCompact, 3);
      const i = LinkPreviewCardText.ios;
      expect(i.size, 14);
      expect(i.siteWeight, FontWeight.w600);
      expect((i.siteLines, i.titleLines, i.descriptionLines), (2, 5, 12));
      expect(i.buttonSize, 14);
      expect(i.buttonWeight, FontWeight.w600);
      const d = LinkPreviewCardText.desktop;
      expect(d.siteWeight, FontWeight.w600);
      expect(d.titleWeight, FontWeight.w600);
      expect((d.siteLines, d.titleLines), (1, 2));
      expect(d.lineBudget, 5);
    });

    test('width rule, appear, press, gestures, time and RTL', () {
      const a = LinkPreviewCardPolicy.android();
      const i = LinkPreviewCardPolicy.ios();
      const d = LinkPreviewCardPolicy.desktop();
      expect(
        [a.width, i.width, d.width],
        const [
          LinkPreviewCardWidth.fillBudget,
          LinkPreviewCardWidth.fitMedia,
          LinkPreviewCardWidth.fitContent,
        ],
      );
      expect(
        [a.appear, i.appear, d.appear],
        const [
          LinkPreviewAppearForm.jump,
          LinkPreviewAppearForm.fade,
          LinkPreviewAppearForm.relayout,
        ],
      );
      expect(i.appearDuration, const Duration(milliseconds: 250));

      expect(a.press.kind, ChromeInkKind.ripple);
      expect(a.press.rippleOpacity, 0.10);
      expect(
        a.press.rippleRadius,
        const BorderRadius.only(
          topLeft: Radius.circular(3),
          topRight: Radius.circular(6),
          bottomRight: Radius.circular(6),
          bottomLeft: Radius.circular(3),
        ),
      );
      expect(a.press.cardScale, ChromeInkBounce.card);
      expect(a.press.buttonScale, ChromeInkBounce.button);
      expect(i.press.cardScale, ChromeInkInset.card);
      expect(i.press.buttonScale, ChromeInkInset.button);
      expect(i.press.rippleOpacity, 0);
      expect(d.press.kind, ChromeInkKind.pointer);
      expect(d.press.cardScale, isNull);
      expect(d.press.rippleRadius, const BorderRadius.all(Radius.circular(5)));

      expect(
        [a.photoTapOpensPage, i.photoTapOpensPage, d.photoTapOpensPage],
        [false, true, true],
      );
      expect(a.enlarge, isNull);
      expect(i.enlarge, isNull);
      expect(d.enlarge, const LinkPreviewEnlargeButton());
      expect(
        (d.enlarge!.size, d.enlarge!.radius, d.enlarge!.inset),
        (36.0, 8.0, 4.0),
      );

      expect(a.time, LinkPreviewTimePlacement.ownLine);
      expect(a.timeLineHeight, 14);
      expect(i.time, LinkPreviewTimePlacement.insideCard);
      expect(i.timeSpacing, 9);
      expect(d.time, LinkPreviewTimePlacement.insideCard);

      expect(
        [a.mirrorsInRtl, i.mirrorsInRtl, d.mirrorsInRtl],
        [false, false, true],
      );
    });

    test('the family presets are the message policy\'s', () {
      expect(
        const MessageMediaPolicy.android().linkPreview,
        const LinkPreviewCardPolicy.android(),
      );
      expect(
        const MessageMediaPolicy.ios().linkPreview,
        const LinkPreviewCardPolicy.ios(),
      );
      expect(
        const MessageMediaPolicy.desktop().linkPreview,
        const LinkPreviewCardPolicy.desktop(),
      );
    });
  });

  group('small or large (the auto table)', () {
    const android = LinkPreviewMediaSizeRule(
      family: LinkPreviewRuleFamily.android,
    );
    const ios = LinkPreviewMediaSizeRule(family: LinkPreviewRuleFamily.ios);
    const desktop = LinkPreviewMediaSizeRule(
      family: LinkPreviewRuleFamily.desktop,
    );

    test('no media: no size', () {
      expect(android.resolve(_page()), isNull);
    });

    test('android: small for a small type without media; compact makes a '
        'photo small', () {
      expect(
        android.resolve(_page(photo: _photo(), type: 'article')),
        LinkPreviewMediaSize.small,
      );
      expect(
        android.resolve(_page(photo: _photo(), type: 'video')),
        LinkPreviewMediaSize.large,
      );
      expect(
        android.resolve(_page(photo: _photo()), compact: true),
        LinkPreviewMediaSize.small,
      );
      // hasLargeMedia is not read.
      expect(
        android.resolve(_page(photo: _photo(), hasLargeMedia: false)),
        LinkPreviewMediaSize.large,
      );
    });

    test('ios: large unless hasLargeMedia is false or the type is small', () {
      expect(ios.resolve(_page(photo: _photo())), LinkPreviewMediaSize.large);
      expect(
        ios.resolve(_page(photo: _photo(), hasLargeMedia: false)),
        LinkPreviewMediaSize.small,
      );
      expect(
        ios.resolve(_page(photo: _photo(), type: 'profile')),
        LinkPreviewMediaSize.small,
      );
    });

    test('desktop: small for a photo page with text of a non-media type; '
        'profile always', () {
      expect(
        desktop.resolve(_page(photo: _photo(), type: 'article')),
        LinkPreviewMediaSize.small,
      );
      for (final type in ['photo', 'document', 'story', 'video']) {
        expect(
          desktop.resolve(_page(photo: _photo(), type: type)),
          LinkPreviewMediaSize.large,
          reason: type,
        );
      }
      expect(
        desktop.resolve(_page(photo: _photo(), media: _video())),
        LinkPreviewMediaSize.large,
      );
    });

    test('the options win, but never small without a title or a '
        'description, nor for video on android', () {
      final small = _options(LinkPreviewMedia.small);
      final large = _options(LinkPreviewMedia.large);
      for (final rule in [android, ios, desktop]) {
        expect(
          rule.resolve(
            _page(photo: _photo(), type: 'profile'),
            options: large,
          ),
          LinkPreviewMediaSize.large,
        );
        expect(
          rule.resolve(_page(photo: _photo()), options: small),
          LinkPreviewMediaSize.small,
        );
        expect(
          rule.resolve(
            _page(photo: _photo(), title: null, description: ''),
            options: small,
          ),
          LinkPreviewMediaSize.large,
        );
      }
      expect(
        android.resolve(_page(media: _video()), options: small),
        LinkPreviewMediaSize.large,
      );
      expect(
        ios.resolve(_page(media: _video()), options: small),
        LinkPreviewMediaSize.small,
      );
    });

    test('the host\'s small types', () {
      final rule = android.copyWith(smallMediaTypes: {'recipe'});
      expect(
        rule.resolve(_page(photo: _photo(), type: 'recipe')),
        LinkPreviewMediaSize.small,
      );
      expect(
        rule.resolve(_page(photo: _photo(), type: 'article')),
        LinkPreviewMediaSize.large,
      );
    });

    test('the switch is offered only for media that can shrink', () {
      expect(android.offersSwitch(_page(photo: _photo())), isTrue);
      expect(android.offersSwitch(_page()), isFalse);
      expect(android.offersSwitch(_page(media: _video())), isFalse);
      expect(
        ios.offersSwitch(_page(media: _video(), hasLargeMedia: true)),
        isTrue,
      );
      expect(
        android.offersSwitch(
          _page(photo: _photo(), title: null, description: ''),
        ),
        isFalse,
      );
    });

    test('iOS and desktop offer the switch only for a page whose media is '
        'large by default', () {
      for (final rule in [ios, desktop]) {
        expect(
          rule.offersSwitch(_page(photo: _photo(), hasLargeMedia: true)),
          isTrue,
          reason: rule.family.name,
        );
        expect(
          rule.offersSwitch(_page(photo: _photo(), hasLargeMedia: false)),
          isFalse,
          reason: rule.family.name,
        );
        expect(
          rule.offersSwitch(_page(photo: _photo())),
          isFalse,
          reason: '${rule.family.name}: no flag is not large',
        );
      }
      expect(
        android.offersSwitch(_page(photo: _photo(), hasLargeMedia: false)),
        isTrue,
        reason: 'android offers it for any shrinkable photo',
      );
    });
  });

  group('the card\'s layout', () {
    test('no preview, a removed page and an empty page draw no card', () {
      expect(_card(_android, _input(null)), isNull);
      expect(
        _card(
          _android,
          _input(
            _page(),
            options: LinkPreviewOptions(
              url: Uri.parse('https://example.org/'),
              removed: true,
            ),
          ),
        ),
        isNull,
      );
      expect(
        _card(
          _android,
          _input(_page(site: null, title: null, description: '')),
        ),
        isNull,
      );
      expect(
        _android.layout(
          _input(_page(site: null, title: null, description: '')),
        ),
        MediaLayout.empty,
      );
    });

    test('the media is an ordinary cell keyed by linkPreviewOf', () {
      final block = _card(_android, _input(_page(photo: _photo())))!;
      const id = MediaItemId.linkPreviewOf(
        'm1',
        slot: LinkPreviewMediaSlot.photo,
      );
      expect(block.item?.id, id);
      expect(block.cells.single.itemId, id);
      expect(
        _android.layout(_input(_page(photo: _photo()))).cellOf(id),
        isNotNull,
      );
      final video = _card(_android, _input(_page(media: _video())))!;
      expect(
        video.item?.id,
        const MediaItemId.linkPreviewOf('m1', slot: LinkPreviewMediaSlot.media),
      );
      expect(video.item?.kind, MediaItemKind.video);
    });

    test('android: large media fills the budget, card − 17 wide, corners 4 '
        'kept by the corner policy', () {
      final block = _card(_android, _input(_page(photo: _photo())))!;
      final card = block.card!;
      expect(card.mediaSize, LinkPreviewMediaSize.large);
      // Not tailed: the card is the budget, 400 − 80.
      expect(card.rect.width, closeTo(320, 1e-9));
      expect(card.rect.left, closeTo(12 - 1.33, 1e-9));
      final media = block.media!;
      expect(media.rect.width, closeTo(320 - 17, 1e-9));
      expect(media.rect.left, closeTo(card.rect.left + 10, 1e-9));
      expect(media.rect.height, closeTo((320 - 17) * 600 / 800, 1e-9));
      expect(media.radii, const MediaCornerRadii.all(4));
    });

    test('android: an incoming tailed text bubble sets the card where its '
        'text starts (+ 12 − 1.33 from the body, the tail outside it) and '
        'rounds the media\'s bottom-left by the near radius', () {
      final block = _card(
        _android,
        _input(_page(photo: _photo()), joinedBelow: false),
      )!;
      expect(block.card!.rect.left, closeTo(12 - 1.33, 1e-9));
      expect(block.media!.radii.bottomLeft, 3);
      expect(block.media!.radii.topLeft, 4);
    });

    test('android: large media height is at most a third of the display, at '
        'least 60', () {
      final tall = _card(
        _android,
        _input(_page(photo: _photo(width: 300, height: 3000))),
      )!;
      expect(tall.media!.rect.height, closeTo(900 / 3, 1e-9));
      final flat = _card(
        _android,
        _input(_page(photo: _photo(width: 3000, height: 100))),
      )!;
      expect(flat.media!.rect.height, 60);
    });

    test('android: a card without large media is its widest line + the '
        'insets', () {
      final block = _card(
        _android,
        _input(_page(site: 'Site', title: 'Title', description: 'Short')),
      )!;
      // 'Short' and 'Title' are 5 chars, 'Site' 4: widest 40, + 17.
      expect(block.card!.rect.width, 40 + 17);
    });

    test('android: the small thumbnail is 48, 6 from the right, the first '
        'lines narrowed by 48 + 10, a 50 minimum', () {
      final block = _card(
        _android,
        _input(_page(photo: _photo(), type: 'article', description: 'x' * 100)),
      )!;
      final card = block.card!;
      final thumb = block.media!.rect;
      expect(card.mediaSize, LinkPreviewMediaSize.small);
      expect(thumb.size, const Size(48, 48));
      expect(thumb.right, closeTo(card.rect.right - 6, 1e-9));
      expect(thumb.top, card.rect.top + 6);
      final site = card.pieceOf(LinkPreviewCardPart.siteName)!;
      expect(site.rect.width, closeTo(card.rect.width - 17 - 48 - 10, 1e-9));
      expect(card.rect.height, greaterThanOrEqualTo(50));
      expect(block.media!.radii, const MediaCornerRadii.all(4));
    });

    test(
      'ios: the thumbnail is 54, inset 6 from the top and trailing edge',
      () {
        final block = _card(
          _ios,
          _input(_page(photo: _photo(), hasLargeMedia: false)),
        )!;
        final thumb = block.media!.rect;
        expect(thumb.size, const Size(54, 54));
        expect(thumb.top, block.card!.rect.top + 6);
        expect(thumb.right, block.card!.rect.right - 6);
        expect(block.card!.rect.height, greaterThanOrEqualTo(66));
      },
    );

    test('ios: the media\'s natural width caps the card', () {
      final block = _card(
        _ios,
        _input(_page(photo: _photo(width: 200, height: 200), description: 'x')),
      )!;
      final card = block.card!;
      // A 200 photo in a 400 list stays at its box width, plus the insets.
      final natural = const MediaBoxSizing.ios()
          .single(
            block.item!,
            _input(_page(photo: _photo(width: 200, height: 200))),
          )
          .size
          .width;
      expect(card.rect.width, closeTo(natural + 37, 1e-9));
      expect(block.media!.rect.width, closeTo(natural, 1e-9));
    });

    test('desktop: fit content, capped at 430 with the offsets', () {
      final block = _card(
        _desktop,
        _input(_page(description: 'x' * 200), width: 1000),
      )!;
      expect(block.card!.rect.width, 430 - 22);
      final short = _card(
        _desktop,
        _input(_page(site: null, title: 'Hi', description: ''), width: 1000),
      )!;
      expect(short.card!.rect.width, 16 + 17);
    });

    test('desktop: the line budget shares 5 lines', () {
      final block = _card(
        _desktop,
        _input(
          _page(site: 'S', title: 'T' * 300, description: 'd' * 3000),
          width: 1000,
        ),
      )!;
      final card = block.card!;
      final lines = [
        for (final piece in card.texts) piece.rect.height / _FixedMeasure.line,
      ];
      expect(lines.fold<double>(0, (a, b) => a + b), 5);
      expect(card.pieceOf(LinkPreviewCardPart.title)!.maxLines, 2);
    });

    test('desktop: the enlarge button is 36, 4 from the photo\'s top-right, '
        'only with text', () {
      final block = _card(
        _desktop,
        _input(_page(photo: _photo(), type: 'photo')),
      )!;
      final media = block.media!.rect;
      expect(
        block.card!.enlarge,
        Rect.fromLTWH(media.right - 4 - 36, media.top + 4, 36, 36),
      );
      expect(block.media!.radii, const MediaCornerRadii.all(3));
      final bare = _card(
        _desktop,
        _input(
          _page(
            photo: _photo(),
            type: 'photo',
            site: null,
            title: null,
            description: '',
          ),
        ),
      )!;
      expect(bare.card!.enlarge, isNull);
    });

    test('the button: android 42, ios 7 + 36, desktop 36', () {
      for (final (policy, height, gap) in [
        (_android, 42.0, 0.0),
        (_ios, 36.0, 7.0),
        (_desktop, 36.0, 0.0),
      ]) {
        final without = _card(
          policy,
          _input(_page(), reactionsBelow: true),
        )!.card!;
        final block = _card(
          policy,
          _input(_page(), button: 'OPEN', reactionsBelow: true),
        )!;
        final button = block.card!.button!;
        expect(button.rect.height, height);
        expect(button.label, 'OPEN');
        final textBottom = block.card!.texts.last.rect.bottom;
        expect(button.rect.top, closeTo(textBottom + gap, 1e-9));
        expect(block.card!.rect.bottom, button.rect.bottom);
        expect(without.button, isNull);
      }
    });

    test('the time under a last card: android its own line (+ 14), ios and '
        'desktop inside the card\'s bottom inset', () {
      final android = _card(_android, _input(_page(), timeWidth: 40))!;
      final slot = android.card!.timeSlot!;
      expect(slot.height, 14);
      expect(slot.top, android.card!.rect.bottom);
      expect(android.rect.bottom, slot.bottom);

      final iosWithout = _card(
        _ios,
        _input(_page(), caption: MediaCaptionPosition.below),
      )!;
      expect(iosWithout.card!.timeSlot, isNull);
      final ios = _card(_ios, _input(_page()))!;
      final inside = ios.card!.timeSlot!;
      expect(inside.bottom, ios.card!.rect.bottom);
      expect(inside.height, 14);
      expect(ios.card!.rect.height - iosWithout.card!.rect.height, 9 + 14);

      final desktop = _card(_desktop, _input(_page()))!;
      expect(desktop.card!.timeSlot!.height, 17);
      expect(desktop.card!.timeSlot!.bottom, desktop.card!.rect.bottom);

      final reactions = _card(_android, _input(_page(), reactionsBelow: true))!;
      expect(reactions.card!.timeSlot, isNull);
    });

    test('rtl: the thumbnail mirrors on desktop and stays right on mobile; '
        'the bar follows the direction', () {
      final page = _page(photo: _photo(), type: 'article');
      final desktop = _card(
        _desktop,
        _input(page, direction: TextDirection.rtl),
      )!;
      expect(desktop.card!.rtl, isTrue);
      expect(desktop.media!.rect.left, lessThan(desktop.card!.rect.center.dx));
      final site = desktop.card!.pieceOf(LinkPreviewCardPart.siteName)!;
      expect(site.rect.left, greaterThan(desktop.media!.rect.right));

      final android = _card(
        _android,
        _input(page, direction: TextDirection.rtl),
      )!;
      expect(android.card!.rtl, isTrue);
      expect(
        android.media!.rect.right,
        closeTo(android.card!.rect.right - 6, 1e-9),
      );
    });

    test('above the text the card is first: ios and desktop take 11 above', () {
      final first = _card(
        _ios,
        _input(_page(), caption: MediaCaptionPosition.below),
      )!;
      expect(first.card!.rect.top, 11);
      final under = _card(_ios, _input(_page()))!;
      expect(under.card!.rect.top, 0);
    });

    test('a layout is a value; no event carries the page', () {
      final recorder = RecordingDiagnostics.install();
      final a = _android.layout(_input(_page(photo: _photo())));
      final b = _android.layout(_input(_page(photo: _photo())));
      expect(a, b);
      for (final event in recorder.events) {
        expect('${event.fields}', isNot(contains('example.org')));
        expect('${event.fields}', isNot(contains('title')));
        expect('${event.fields}', isNot(contains('description')));
      }
    });
  });

  group('transitions', () {
    MediaLayout layoutOf(
      MessageMediaPolicy policy,
      LinkPreview? page, {
      LinkPreviewOptions? options,
    }) => policy.layout(_input(page, options: options));

    test('small ↔ large rides MediaLayout.lerp: the media cell moves', () {
      final page = _page(photo: _photo());
      final small = layoutOf(
        _android,
        page,
        options: _options(LinkPreviewMedia.small),
      );
      final large = layoutOf(
        _android,
        page,
        options: _options(LinkPreviewMedia.large),
      );
      const id = MediaItemId.linkPreviewOf(
        'm1',
        slot: LinkPreviewMediaSlot.photo,
      );
      final a = small.cellOf(id)!.rect;
      final b = large.cellOf(id)!.rect;
      final mid = MediaLayout.lerp(small, large, 0.5);
      expect(mid.cellOf(id)!.rect, Rect.lerp(a, b, 0.5));
      expect(mid.exiting, isEmpty);
      final card = mid.blocks.whereType<MediaBlock$LinkPreview>().single;
      expect(card.card!.mediaSize, LinkPreviewMediaSize.large);
      expect(
        card.card!.rect.height,
        closeTo(
          (small.blocks.last.rect.height + large.blocks.last.rect.height) / 2 -
              0,
          20,
        ),
      );
    });

    test(
      'appear: android jumps, ios fades in over 250 ms, desktop at once',
      () {
        final before = layoutOf(_android, null);
        for (final (policy, card) in [
          (_android, const LinkPreviewCardPolicy.android()),
          (_desktop, const LinkPreviewCardPolicy.desktop()),
        ]) {
          final leg = MediaLayoutTransition(
            from: MediaTransitionFrame.settled(before),
            to: layoutOf(policy, _page()),
            policy: policy.transition,
            cardAppear: card.appear,
            cardFade: card.appearDuration,
          );
          expect(leg.duration, Duration.zero);
        }
        const ios = LinkPreviewCardPolicy.ios();
        final leg = MediaLayoutTransition(
          from: MediaTransitionFrame.settled(layoutOf(_ios, null)),
          to: layoutOf(_ios, _page()),
          policy: _ios.transition,
          cardAppear: ios.appear,
          cardFade: ios.appearDuration,
        );
        expect(leg.cardIn, const Duration(milliseconds: 250));
        expect(leg.frameAt(Duration.zero).cardOpacity, 0);
        final mid = leg.frameAt(const Duration(milliseconds: 125)).cardOpacity;
        expect(mid, greaterThan(0));
        expect(mid, lessThan(1));
        expect(leg.frameAt(const Duration(milliseconds: 400)).cardOpacity, 1);
      },
    );

    test('a new page cross-fades; a removed card fades out', () {
      final old = layoutOf(_android, _page());
      final next = _android.layout(
        _input(
          LinkPreview(url: Uri.parse('https://other.example/'), title: 'Other'),
        ),
      );
      final leg = MediaLayoutTransition(
        from: MediaTransitionFrame.settled(old),
        to: next,
        policy: _android.transition,
      );
      final start = leg.frameAt(Duration.zero);
      expect(start.cardOpacity, 0);
      expect(
        start.leavingCard?.page.url,
        Uri.parse('https://example.org/private/page'),
      );
      expect(start.leavingCardOpacity, 1);
      final end = leg.frameAt(leg.duration);
      expect(end.leavingCard, isNull);
      expect(end.cardOpacity, 1);

      final removed = MediaLayoutTransition(
        from: MediaTransitionFrame.settled(old),
        to: MediaLayout.empty,
        policy: _ios.transition,
        cardFade: const Duration(milliseconds: 250),
      );
      expect(removed.cardOut, const Duration(milliseconds: 250));
      expect(removed.frameAt(Duration.zero).leavingCard, isNotNull);
    });
  });
}
