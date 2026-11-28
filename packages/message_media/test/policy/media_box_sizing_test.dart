/// Each platform's single box sizing: the values it is built from, pinned
/// field by field, and the boxes they give.
library;

import 'dart:ui';

import 'package:chrome_foundation/chrome_foundation.dart' show ChromeWidthClass;
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';

import '../support/media_scopes.dart';

MediaItem _item(
  MediaItemKind kind, {
  int? width,
  int? height,
  String id = 'a',
}) => MediaItem(
  id: MediaItemId(id),
  kind: kind,
  descriptor: ContentDescriptor(
    key: ContentKey.document(id),
    size: switch ((width, height)) {
      (final w?, final h?) => ContentSize(w, h),
      _ => null,
    },
  ),
);

MediaLayoutInput _input({
  double availableWidth = 364,
  Size? displaySize = const Size(364, 800),
  double? tabletMinSide,
  double? maxContentWidth,
  MediaCaptionPosition captionPosition = MediaCaptionPosition.none,
  double? captionWidth,
  bool isOutgoing = false,
  bool showsAvatar = false,
  bool hasSideButton = false,
  bool inBubble = true,
  MediaLayoutChrome chrome = MediaLayoutChrome.none,
  ChromeWidthClass? widthClass,
}) => MediaLayoutInput(
  text: MediaScopes.text,
  items: const [],
  availableWidth: availableWidth,
  displaySize: displaySize,
  tabletMinSide: tabletMinSide,
  maxContentWidth: maxContentWidth,
  captionPosition: captionPosition,
  captionWidth: captionWidth,
  isOutgoing: isOutgoing,
  showsAvatar: showsAvatar,
  hasSideButton: hasSideButton,
  inBubble: inBubble,
  chrome: chrome,
  widthClass: widthClass,
);

void main() {
  group('Android', () {
    const sizing = MediaBoxSizing$Android();

    test('pins every value', () {
      expect(sizing.landscapeInset, 64);
      expect(sizing.landscapeSideButtonInset, 10);
      expect(sizing.portraitFraction, 0.7);
      expect(sizing.portraitSideButtonInset, 20);
      expect(sizing.tabletFraction, 0.7);
      expect(sizing.avatarInset, 52);
      expect(sizing.heightExtra, 100);
      expect(sizing.sizeCap, 1280);
      expect(sizing.minHeight, 120);
      expect(sizing.noDimensionsSide, 150);
      expect(sizing.videoBadgePadding, 40);
      expect(sizing.progressLabelPadding, 100);
      expect(sizing.timePadding, 22);
      expect(sizing.smallRadiusTimePadding, 18);
      expect(sizing.smallRadius, 10);
      expect(sizing.checksPadding, 20);
      expect(sizing.captionPadding, 10);
      expect(sizing.albumWidthFraction, 0.8);
      expect(sizing.albumAvatarInset, 48);
      expect(const MediaBoxSizing.android(), isA<MediaBoxSizing$Android>());
    });

    test('a landscape picture takes the list width less 64', () {
      final box = sizing.single(
        _item(MediaItemKind.photo, width: 1600, height: 900),
        _input(),
      );
      expect(box.size, const Size(300, 168));
      expect(box.fallbacks, isEmpty);
    });

    test('a landscape picture beside an avatar loses 52 of width, not of '
        'max height', () {
      final (width, height) = sizing.maxBox(
        const ContentSize(1600, 900),
        _input(showsAvatar: true),
      );
      expect(width, 248);
      expect(height, 400);
    });

    test('a landscape side button takes 10 more', () {
      final (width, _) = sizing.maxBox(
        const ContentSize(1600, 900),
        _input(hasSideButton: true),
      );
      expect(width, 290);
    });

    test('a portrait picture takes 0.7 of the list, less 20 with a side '
        'button', () {
      final (width, height) = sizing.maxBox(
        const ContentSize(900, 1600),
        _input(),
      );
      expect(width, closeTo(254.8, 1e-9));
      expect(height, closeTo(354.8, 1e-9));
      final (withButton, _) = sizing.maxBox(
        const ContentSize(900, 1600),
        _input(hasSideButton: true),
      );
      expect(withButton, closeTo(234.8, 1e-9));
    });

    test('the screen height bounds the width in landscape', () {
      final (width, _) = sizing.maxBox(
        const ContentSize(1600, 900),
        _input(availableWidth: 900, displaySize: const Size(900, 400)),
      );
      expect(width, 336);
    });

    test('a tablet takes 0.7 of its short side, capped at 1280', () {
      final (width, height) = sizing.maxBox(
        const ContentSize(1600, 900),
        _input(availableWidth: 1000, tabletMinSide: 800),
      );
      expect(width, 560);
      expect(height, 660);
      final (big, bigHeight) = sizing.maxBox(
        const ContentSize(1600, 900),
        _input(availableWidth: 3000, tabletMinSide: 2000),
      );
      expect(big, 1280);
      expect(bigHeight, 1280);
    });

    test('no dimensions give a 150 square', () {
      final box = sizing.single(_item(MediaItemKind.photo), _input());
      expect(box.size, const Size(150, 150));
      expect(box.fallbacks, {MediaLayoutFallbackRule.noDimensions});
    });

    test('a video is at least its badge + 40 and its progress label + 100 '
        'wide', () {
      final narrow = _item(MediaItemKind.video, width: 100, height: 1000);
      final photo = sizing.single(
        _item(MediaItemKind.photo, width: 100, height: 1000),
        _input(),
      );
      expect(photo.size.width, 35);
      final badge = sizing.single(
        narrow,
        _input(chrome: const MediaLayoutChrome(infoBadgeWidth: 120)),
      );
      expect(badge.size.width, 160);
      expect(badge.fallbacks, {MediaLayoutFallbackRule.minWidth});
      final progress = sizing.single(
        narrow,
        _input(chrome: const MediaLayoutChrome(progressLabelWidth: 30)),
      );
      expect(progress.size.width, 130);
    });

    test('an animation is at least its progress label + 100 wide', () {
      final box = sizing.single(
        _item(MediaItemKind.animation, width: 100, height: 1000),
        _input(chrome: const MediaLayoutChrome(progressLabelWidth: 30)),
      );
      expect(box.size.width, 130);
    });

    test('any box fits the time pill: time + 22, + 18 under radius 10, + 20 '
        'with checks', () {
      final narrow = _item(MediaItemKind.photo, width: 100, height: 1000);
      Size box(MediaLayoutChrome chrome, {bool outgoing = false}) => sizing
          .single(narrow, _input(chrome: chrome, isOutgoing: outgoing))
          .size;
      expect(box(const MediaLayoutChrome(timeWidth: 40)).width, 62);
      expect(
        box(const MediaLayoutChrome(timeWidth: 40, bubbleRadius: 8)).width,
        58,
      );
      expect(
        box(const MediaLayoutChrome(timeWidth: 40), outgoing: true).width,
        82,
      );
    });

    test('a caption widens the box to its width + 10', () {
      final photo = _item(MediaItemKind.photo, width: 1600, height: 900);
      final widened = sizing.single(
        photo,
        _input(captionPosition: MediaCaptionPosition.below, captionWidth: 320),
      );
      expect(widened.size, const Size(330, 168));
      expect(widened.fallbacks, {MediaLayoutFallbackRule.captionWidening});
      final noText = sizing.single(photo, _input(captionWidth: 320));
      expect(noText.size, const Size(300, 168));
    });

    test('an album is 0.8 of the list, less 48 beside an avatar', () {
      expect(sizing.blockWidth(_input(availableWidth: 400)), 320);
      expect(
        sizing.blockWidth(_input(availableWidth: 400, showsAvatar: true)),
        272,
      );
    });

    test('copyWith replaces one value', () {
      final changed = sizing.copyWith(noDimensionsSide: 120);
      expect(changed.noDimensionsSide, 120);
      expect(changed.minHeight, 120);
      expect(
        changed.single(_item(MediaItemKind.photo), _input()).size,
        const Size(120, 120),
      );
    });
  });

  group('iOS', () {
    const sizing = MediaBoxSizing$IOS();

    test('pins every value', () {
      expect(sizing.compactMaxSize, const Size(300, 380));
      expect(sizing.regularMaxSize, const Size(440, 440));
      expect(sizing.compactMaxListWidth, 680);
      expect(sizing.videoMaxHeightLandscape, 250);
      expect(sizing.videoMaxHeightPortrait, 360);
      expect(sizing.minSize, const Size(170, 74));
      expect(sizing.noDimensionsSide, 54);
      expect(sizing.sizeSourceScale, 0.5);
      expect(sizing.sizeSourceMinSide, 10);
      expect(sizing.animationFillSize, const Size(480, 480));
      expect(const MediaBoxSizing.ios(), isA<MediaBoxSizing$IOS>());
    });

    test('a compact list fits into 300 × 380, a regular one into 440', () {
      final photo = _item(MediaItemKind.photo, width: 4000, height: 3000);
      expect(
        sizing.single(photo, _input(availableWidth: 390)).size,
        const Size(300, 225),
      );
      expect(
        sizing.single(photo, _input(availableWidth: 680)).size,
        const Size(300, 225),
      );
      expect(
        sizing.single(photo, _input(availableWidth: 800)).size,
        const Size(440, 330),
      );
    });

    test('a photo is cut at the max box height', () {
      final tall = _item(MediaItemKind.photo, width: 1000, height: 4000);
      expect(
        sizing.single(tall, _input(availableWidth: 390)).size,
        const Size(170, 380),
      );
    });

    test('a video is at most 250 high in landscape, 360 in portrait', () {
      final landscape = _item(MediaItemKind.video, width: 1920, height: 1080);
      expect(
        sizing.single(landscape, _input(availableWidth: 390)).size,
        const Size(300, 168.75),
      );
      final portrait = _item(MediaItemKind.video, width: 1080, height: 1920);
      expect(
        sizing.single(portrait, _input(availableWidth: 390)).size,
        const Size(202.5, 360),
      );
    });

    test('the box is at least 170 × 74', () {
      final small = sizing.single(
        _item(MediaItemKind.photo, width: 100, height: 40),
        _input(availableWidth: 390),
      );
      expect(small.size, const Size(170, 74));
      expect(small.fallbacks, {MediaLayoutFallbackRule.minWidth});
    });

    test('the native size is half the pixels, at least 10 a side', () {
      expect(
        sizing.nativeSizeOf(_item(MediaItemKind.photo, width: 801, height: 7)),
        const Size(400, 10),
      );
    });

    test('an animation fills 480 × 480 first, so a small one scales up', () {
      expect(
        sizing.nativeSizeOf(
          _item(MediaItemKind.animation, width: 200, height: 100),
        ),
        const Size(960, 480),
      );
      expect(
        sizing
            .single(
              _item(MediaItemKind.animation, width: 200, height: 100),
              _input(availableWidth: 390),
            )
            .size,
        const Size(300, 150),
      );
    });

    test('no dimensions give a 54 native square, raised to the minimum', () {
      final box = sizing.single(
        _item(MediaItemKind.photo),
        _input(availableWidth: 390),
      );
      expect(box.size, const Size(170, 170));
      expect(box.fallbacks, {
        MediaLayoutFallbackRule.noDimensions,
        MediaLayoutFallbackRule.minWidth,
      });
    });

    test("the bubble's max content width caps the box", () {
      final photo = _item(MediaItemKind.photo, width: 4000, height: 3000);
      expect(
        sizing
            .single(photo, _input(availableWidth: 390, maxContentWidth: 250))
            .size,
        const Size(250, 187.5),
      );
      expect(
        sizing.blockWidth(_input(availableWidth: 390, maxContentWidth: 250)),
        250,
      );
      expect(sizing.blockWidth(_input(availableWidth: 800)), 440);
    });
  });

  group('desktop', () {
    const sizing = MediaBoxSizing$Desktop();

    test('pins every value', () {
      expect(sizing.photoMaxSize, 430);
      expect(sizing.animationMaxSize, 320);
      expect(sizing.bubbleMinWidth, 200);
      expect(sizing.minWidthWithoutBubble, 100);
      expect(sizing.minHeight, 100);
      expect(sizing.lessCropGrowth, 4 / 3);
      expect(const MediaBoxSizing.desktop(), isA<MediaBoxSizing$Desktop>());
    });

    test('a photo or a video scales into 430, an animation into 320', () {
      final input = _input(availableWidth: 800);
      expect(
        sizing
            .single(_item(MediaItemKind.photo, width: 1000, height: 500), input)
            .size,
        const Size(430, 215),
      );
      expect(
        sizing
            .single(_item(MediaItemKind.video, width: 1000, height: 500), input)
            .size,
        const Size(430, 215),
      );
      expect(
        sizing
            .single(
              _item(MediaItemKind.animation, width: 1000, height: 500),
              input,
            )
            .size,
        const Size(320, 160),
      );
    });

    test('a small picture is never scaled up; the box is at least 200 wide in '
        'a bubble, 100 without, and 100 high', () {
      final small = _item(MediaItemKind.photo, width: 100, height: 60);
      final inBubble = sizing.single(small, _input(availableWidth: 800));
      expect(inBubble.size.width, 200);
      expect(inBubble.fallbacks, {MediaLayoutFallbackRule.minWidth});
      expect(inBubble.size.height, 100);
      final bare = sizing.single(
        small,
        _input(availableWidth: 800, inBubble: false),
      );
      expect(bare.size, const Size(100, 100));
    });

    test('the box is never taller than the width it may take', () {
      final tall = _item(MediaItemKind.photo, width: 500, height: 2000);
      final box = sizing.single(
        tall,
        _input(availableWidth: 800, inBubble: false),
      );
      expect(box.size, const Size(107.5, 430));
    });

    test('a widened box grows up to 4/3 of its height to crop less', () {
      final wide = _item(MediaItemKind.photo, width: 300, height: 100);
      final box = sizing.single(
        wide,
        _input(
          availableWidth: 800,
          captionPosition: MediaCaptionPosition.below,
          captionWidth: 400,
        ),
      );
      expect(box.size.width, 400);
      expect(box.size.height, closeTo(100 * 4 / 3, 1e-9));
    });

    test('a caption widens the photo up to 430', () {
      final square = _item(MediaItemKind.photo, width: 300, height: 300);
      final widened = sizing.single(
        square,
        _input(
          availableWidth: 800,
          captionPosition: MediaCaptionPosition.below,
          captionWidth: 380,
        ),
      );
      expect(widened.size, const Size(380, 380));
      expect(widened.fallbacks, {MediaLayoutFallbackRule.captionWidening});
      final capped = sizing.single(
        square,
        _input(
          availableWidth: 800,
          captionPosition: MediaCaptionPosition.below,
          captionWidth: 600,
        ),
      );
      expect(capped.size.width, 430);
    });

    group('no dimensions', () {
      const kinds = [
        MediaItemKind.photo,
        MediaItemKind.video,
        MediaItemKind.animation,
      ];

      test('every kind is the bubble width floor by the height floor', () {
        for (final kind in kinds) {
          final box = sizing.single(_item(kind), _input(availableWidth: 800));
          expect(box.size, const Size(200, 100), reason: '$kind');
          expect(box.fallbacks, {MediaLayoutFallbackRule.noDimensions});
        }
      });

      test('without a bubble the width floor is 100', () {
        for (final kind in kinds) {
          final box = sizing.single(
            _item(kind),
            _input(availableWidth: 800, inBubble: false),
          );
          expect(box.size, const Size(100, 100), reason: '$kind');
        }
      });

      test('the width floor never passes the width it may take', () {
        final box = sizing.single(
          _item(MediaItemKind.photo),
          _input(availableWidth: 150),
        );
        expect(box.size, const Size(150, 100));
      });

      test(
        'a caption widens the box; only video and animation grow taller',
        () {
          final input = _input(
            availableWidth: 800,
            captionPosition: MediaCaptionPosition.below,
            captionWidth: 300,
          );
          final photo = sizing.single(_item(MediaItemKind.photo), input);
          expect(photo.size, const Size(300, 100));
          for (final kind in [MediaItemKind.video, MediaItemKind.animation]) {
            final box = sizing.single(_item(kind), input);
            expect(box.size.width, 300, reason: '$kind');
            expect(
              box.size.height,
              closeTo(100 * 4 / 3, 1e-9),
              reason: '$kind',
            );
          }
        },
      );
    });

    test('a block spans up to 430', () {
      expect(sizing.blockWidth(_input(availableWidth: 800)), 430);
      expect(sizing.blockWidth(_input(availableWidth: 300)), 300);
    });
  });

  group('web', () {
    const sizing = MediaBoxSizing$Web();
    // A window of [width], the class the input names left to the size.
    MediaLayoutInput window(
      double width, {
      MediaCaptionPosition captionPosition = MediaCaptionPosition.none,
      double? captionWidth,
      double? maxContentWidth,
      ChromeWidthClass? widthClass,
    }) => _input(
      availableWidth: width,
      displaySize: Size(width, 800),
      maxContentWidth: maxContentWidth,
      captionPosition: captionPosition,
      captionWidth: captionWidth,
      widthClass: widthClass,
    );

    test('pins every value', () {
      expect(sizing.compactBox, const Size(340, 340));
      expect(sizing.regularBox, const Size(420, 400));
      expect(sizing.compactLinkPreviewBox, const Size(340, 200));
      expect(sizing.regularLinkPreviewBox, const Size(420, 380));
      expect(sizing.compactAlbumWidth, 340);
      expect(sizing.regularAlbumWidth, 420);
      expect(sizing.minSide, 200);
      expect(sizing.minWidth, 120);
      expect(sizing.textMinWidth, 320);
      expect(sizing.noDimensionsSide, 100);
      expect(sizing.noDimensionsPlayingSide, 512);
    });

    test('a compact window fits the picture into 340 x 340', () {
      final landscape = _item(MediaItemKind.photo, width: 1280, height: 720);
      final portrait = _item(MediaItemKind.video, width: 720, height: 1280);
      expect(
        sizing.single(landscape, window(400)),
        MediaBoxResult(const Size(340, 191)),
      );
      expect(
        sizing.single(portrait, window(400)),
        MediaBoxResult(const Size(191, 340)),
      );
    });

    test('a medium or expanded window fits it into 420 x 400', () {
      final landscape = _item(MediaItemKind.photo, width: 1280, height: 720);
      final portrait = _item(MediaItemKind.photo, width: 720, height: 1280);
      expect(
        sizing.single(landscape, window(800)),
        MediaBoxResult(const Size(420, 236)),
      );
      expect(
        sizing.single(portrait, window(1400)),
        MediaBoxResult(const Size(225, 400)),
      );
    });

    test('the class flips across 600', () {
      final photo = _item(MediaItemKind.photo, width: 1280, height: 720);
      expect(sizing.single(photo, window(600)).size, const Size(340, 191));
      expect(sizing.single(photo, window(601)).size, const Size(420, 236));
    });

    test('the class the host read wins over the window size', () {
      final photo = _item(MediaItemKind.photo, width: 1280, height: 720);
      expect(
        sizing
            .single(photo, window(800, widthClass: ChromeWidthClass.compact))
            .size,
        const Size(340, 191),
      );
    });

    test('a small picture is never zoomed, but grows to the 200 side', () {
      final small = _item(MediaItemKind.photo, width: 300, height: 250);
      final tiny = _item(MediaItemKind.photo, width: 150, height: 100);
      expect(sizing.single(small, window(400)).size, const Size(300, 250));
      expect(
        sizing.single(tiny, window(400)),
        MediaBoxResult(
          const Size(200, 133),
          fallbacks: const {MediaLayoutFallbackRule.minWidth},
        ),
      );
    });

    test('a narrow picture is widened to 120', () {
      final narrow = _item(MediaItemKind.photo, width: 100, height: 1000);
      expect(
        sizing.single(narrow, window(400)),
        MediaBoxResult(
          const Size(120, 340),
          fallbacks: const {MediaLayoutFallbackRule.minWidth},
        ),
      );
    });

    test('a caption widens the box to 320', () {
      final portrait = _item(MediaItemKind.photo, width: 720, height: 1280);
      expect(
        sizing.single(
          portrait,
          window(
            400,
            captionPosition: MediaCaptionPosition.below,
            captionWidth: 40,
          ),
        ),
        MediaBoxResult(
          const Size(320, 340),
          fallbacks: const {MediaLayoutFallbackRule.captionWidening},
        ),
      );
    });

    test('without dimensions: a photo 100 grown to 200, a video 512', () {
      expect(
        sizing.single(_item(MediaItemKind.photo), window(400)),
        MediaBoxResult(
          const Size(200, 200),
          fallbacks: const {
            MediaLayoutFallbackRule.noDimensions,
            MediaLayoutFallbackRule.minWidth,
          },
        ),
      );
      expect(
        sizing.single(_item(MediaItemKind.video), window(400)),
        MediaBoxResult(
          const Size(340, 340),
          fallbacks: const {MediaLayoutFallbackRule.noDimensions},
        ),
      );
    });

    test('the box is capped by the bubble content width', () {
      final photo = _item(MediaItemKind.photo, width: 1280, height: 720);
      expect(
        sizing.single(photo, window(1400, maxContentWidth: 300)).size,
        const Size(300, 168),
      );
    });

    test('an album is 340 wide compact and 420 otherwise', () {
      expect(sizing.blockWidth(window(400)), 340);
      expect(sizing.blockWidth(window(800)), 420);
      expect(sizing.blockWidth(window(1400, maxContentWidth: 300)), 300);
    });

    test('link preview media fits 340 x 200 compact, 420 x 380 otherwise', () {
      final photo = _item(MediaItemKind.photo, width: 1280, height: 720);
      final portrait = _item(MediaItemKind.photo, width: 720, height: 1280);
      expect(
        sizing.linkPreviewMedia(photo, window(400)).size,
        const Size(340, 191),
      );
      expect(
        sizing.linkPreviewMedia(portrait, window(400)).size,
        const Size(112, 200),
      );
      expect(
        sizing.linkPreviewMedia(photo, window(800)).size,
        const Size(420, 236),
      );
    });

    test('the other families size link preview media as a single box', () {
      const desktop = MediaBoxSizing$Desktop();
      final photo = _item(MediaItemKind.photo, width: 1280, height: 720);
      expect(
        desktop.linkPreviewMedia(photo, window(800)),
        desktop.single(photo, window(800)),
      );
    });
  });
}
