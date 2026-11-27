import 'dart:math' as math;
import 'dart:ui';

import 'package:content_model/content_model.dart';
import 'package:message_media/src/layout/media_layout_input.dart';
import 'package:message_media/src/single_media_layout.dart';
import 'package:meta/meta.dart';

/// A size rule a box took instead of its picture's own proportions.
enum MediaLayoutFallbackRule {
  /// The picture gives no dimensions; the box is the policy's fallback size.
  noDimensions,

  /// A minimum width (chrome, a platform floor) widened the box.
  minWidth,

  /// The caption widened the box.
  captionWidening,
}

/// The box of one item, and the fallback rules that shaped it.
@immutable
final class MediaBoxResult {
  /// A box of [size] shaped by [fallbacks].
  MediaBoxResult(this.size, {Set<MediaLayoutFallbackRule> fallbacks = const {}})
    : fallbacks = Set.unmodifiable(fallbacks);

  /// The box.
  final Size size;

  /// The fallback rules taken, empty when the picture's proportions held.
  final Set<MediaLayoutFallbackRule> fallbacks;

  @override
  bool operator ==(Object other) =>
      other is MediaBoxResult &&
      other.size == size &&
      other.fallbacks.length == fallbacks.length &&
      other.fallbacks.containsAll(fallbacks);

  @override
  int get hashCode => Object.hash(size, Object.hashAllUnordered(fallbacks));

  @override
  String toString() => 'MediaBoxResult($size, $fallbacks)';
}

/// How a platform sizes media boxes: a single box from its picture, and the
/// width of a block that spans the media budget (an album, a file stack, a
/// link preview card).
///
/// The three defaults differ in shape, not only in values, so each is its
/// own class with its own fields; a host changes a value with that class's
/// `copyWith`, or extends this class for a sizing of its own.
@immutable
abstract base class MediaBoxSizing {
  /// Lets a host's sizing extend this one.
  const MediaBoxSizing();

  /// The Android family's sizing.
  const factory MediaBoxSizing.android() = MediaBoxSizing$Android;

  /// The iOS family's sizing.
  const factory MediaBoxSizing.ios() = MediaBoxSizing$IOS;

  /// The desktop family's sizing.
  const factory MediaBoxSizing.desktop() = MediaBoxSizing$Desktop;

  /// The box of [item], a photo, video or animation, laid out alone.
  MediaBoxResult single(MediaItem item, MediaLayoutInput input);

  /// The width of a block that spans the media budget: a mosaic of two or
  /// more boxes, a file stack and a link preview card.
  double blockWidth(MediaLayoutInput input);
}

// --- Android ---

/// The Android family's box sizing: an orientation-dependent max width, the
/// height clamp at `maxWidth + 100`, chrome minimum widths and the caption
/// widening.
///
/// | Field | Value | Role |
/// | --- | --- | --- |
/// | [landscapeInset] | 64 | Taken from `min(listWidth, screenHeight)` for a landscape or square picture |
/// | [landscapeSideButtonInset] | 10 | More taken with a side button (landscape) |
/// | [portraitFraction] | 0.7 | Of `min(listWidth, screenHeight)` for a portrait picture |
/// | [portraitSideButtonInset] | 20 | Taken with a side button (portrait) |
/// | [tabletFraction] | 0.7 | Of the tablet's short side |
/// | [avatarInset] | 52 | Taken beside an avatar (landscape) |
/// | [heightExtra] | 100 | Max height over the max width |
/// | [sizeCap] | 1280 | Soft cap on both sides (portrait and tablet) |
/// | [minHeight] | 120 | Height floor |
/// | [noDimensionsSide] | 150 | Square box without dimensions |
/// | [videoBadgePadding] | 40 | Video width ≥ badge width + this |
/// | [progressLabelPadding] | 100 | Video / animation width ≥ progress label + this |
/// | [timePadding] | 22 | Width ≥ time + this (bubble radius ≥ [smallRadius]) |
/// | [smallRadiusTimePadding] | 18 | The same under [smallRadius] |
/// | [smallRadius] | 10 | Bubble radius that picks the time padding |
/// | [checksPadding] | 20 | More for an outgoing message's checks |
/// | [captionPadding] | 10 | The caption widens the box to its width + this |
/// | [albumWidthFraction] | 0.8 | Of the list width for an album |
/// | [albumAvatarInset] | 48 | Taken from an album beside an avatar |
final class MediaBoxSizing$Android extends MediaBoxSizing {
  /// The Android defaults; any value can be replaced.
  const MediaBoxSizing$Android({
    this.landscapeInset = 64,
    this.landscapeSideButtonInset = 10,
    this.portraitFraction = 0.7,
    this.portraitSideButtonInset = 20,
    this.tabletFraction = 0.7,
    this.avatarInset = 52,
    this.heightExtra = 100,
    this.sizeCap = 1280,
    this.minHeight = 120,
    this.noDimensionsSide = 150,
    this.videoBadgePadding = 40,
    this.progressLabelPadding = 100,
    this.timePadding = 22,
    this.smallRadiusTimePadding = 18,
    this.smallRadius = 10,
    this.checksPadding = 20,
    this.captionPadding = 10,
    this.albumWidthFraction = 0.8,
    this.albumAvatarInset = 48,
  });

  /// See the class table.
  final double landscapeInset;

  /// See the class table.
  final double landscapeSideButtonInset;

  /// See the class table.
  final double portraitFraction;

  /// See the class table.
  final double portraitSideButtonInset;

  /// See the class table.
  final double tabletFraction;

  /// See the class table.
  final double avatarInset;

  /// See the class table.
  final double heightExtra;

  /// See the class table.
  final double sizeCap;

  /// See the class table.
  final double minHeight;

  /// See the class table.
  final double noDimensionsSide;

  /// See the class table.
  final double videoBadgePadding;

  /// See the class table.
  final double progressLabelPadding;

  /// See the class table.
  final double timePadding;

  /// See the class table.
  final double smallRadiusTimePadding;

  /// See the class table.
  final double smallRadius;

  /// See the class table.
  final double checksPadding;

  /// See the class table.
  final double captionPadding;

  /// See the class table.
  final double albumWidthFraction;

  /// See the class table.
  final double albumAvatarInset;

  /// The max box `(width, height)` for a picture of [dimensions].
  ///
  /// The height comes from the width before the side button and avatar
  /// deductions, and a landscape box's height is not soft-capped: it is
  /// already bounded by the screen.
  (double, double) maxBox(ContentSize? dimensions, MediaLayoutInput input) {
    final base = math.min(input.availableWidth, input.displayHeight);
    final landscape = switch (dimensions) {
      ContentSize(:final width, :final height) => width >= height,
      null => false,
    };
    if (input.tabletMinSide case final side?) {
      return _capped(side * tabletFraction, input);
    }
    if (!landscape) {
      return _capped(base * portraitFraction, input);
    }
    var width =
        base -
        landscapeInset -
        (input.hasSideButton ? landscapeSideButtonInset : 0);
    final height = width + heightExtra;
    if (input.showsAvatar) width -= avatarInset;
    return (width, height);
  }

  (double, double) _capped(double width, MediaLayoutInput input) {
    var w = width;
    final h = math.min(w + heightExtra, sizeCap);
    if (input.hasSideButton) w -= portraitSideButtonInset;
    return (math.min(w, sizeCap), h);
  }

  @override
  MediaBoxResult single(MediaItem item, MediaLayoutInput input) {
    final fallbacks = <MediaLayoutFallbackRule>{};
    final dimensions = item.descriptor.size;
    final (maxWidth, maxHeight) = maxBox(dimensions, input);
    var (width, height) = switch (dimensions) {
      ContentSize(:final width, :final height) => () {
        final box = computeSingleMediaSize(
          aspectRatio: width / height,
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          minHeight: minHeight,
          zeroSide: noDimensionsSide,
          kind: item.kind,
        );
        return (box.width, box.height);
      }(),
      null => (noDimensionsSide, noDimensionsSide),
    };
    if (dimensions == null) fallbacks.add(MediaLayoutFallbackRule.noDimensions);

    final chrome = input.chrome;
    final minWidths = [
      if (item.kind == MediaItemKind.video)
        chrome.infoBadgeWidth + videoBadgePadding,
      if (item.kind == MediaItemKind.video ||
          item.kind == MediaItemKind.animation)
        chrome.progressLabelWidth + progressLabelPadding,
      if (chrome.timeWidth > 0)
        chrome.timeWidth +
            (chrome.bubbleRadius >= smallRadius
                ? timePadding
                : smallRadiusTimePadding) +
            (input.isOutgoing ? checksPadding : 0),
    ];
    for (final min in minWidths) {
      if (width < min) {
        width = min;
        fallbacks.add(MediaLayoutFallbackRule.minWidth);
      }
    }
    if (input.captionWidth case final caption? when input.hasText) {
      if (width < caption + captionPadding) {
        width = caption + captionPadding;
        fallbacks.add(MediaLayoutFallbackRule.captionWidening);
      }
    }
    return MediaBoxResult(Size(width, height), fallbacks: fallbacks);
  }

  @override
  double blockWidth(MediaLayoutInput input) => math.max(
    0,
    input.availableWidth * albumWidthFraction -
        (input.showsAvatar ? albumAvatarInset : 0),
  );

  /// A copy with the given values replaced.
  MediaBoxSizing$Android copyWith({
    double? landscapeInset,
    double? landscapeSideButtonInset,
    double? portraitFraction,
    double? portraitSideButtonInset,
    double? tabletFraction,
    double? avatarInset,
    double? heightExtra,
    double? sizeCap,
    double? minHeight,
    double? noDimensionsSide,
    double? videoBadgePadding,
    double? progressLabelPadding,
    double? timePadding,
    double? smallRadiusTimePadding,
    double? smallRadius,
    double? checksPadding,
    double? captionPadding,
    double? albumWidthFraction,
    double? albumAvatarInset,
  }) => MediaBoxSizing$Android(
    landscapeInset: landscapeInset ?? this.landscapeInset,
    landscapeSideButtonInset:
        landscapeSideButtonInset ?? this.landscapeSideButtonInset,
    portraitFraction: portraitFraction ?? this.portraitFraction,
    portraitSideButtonInset:
        portraitSideButtonInset ?? this.portraitSideButtonInset,
    tabletFraction: tabletFraction ?? this.tabletFraction,
    avatarInset: avatarInset ?? this.avatarInset,
    heightExtra: heightExtra ?? this.heightExtra,
    sizeCap: sizeCap ?? this.sizeCap,
    minHeight: minHeight ?? this.minHeight,
    noDimensionsSide: noDimensionsSide ?? this.noDimensionsSide,
    videoBadgePadding: videoBadgePadding ?? this.videoBadgePadding,
    progressLabelPadding: progressLabelPadding ?? this.progressLabelPadding,
    timePadding: timePadding ?? this.timePadding,
    smallRadiusTimePadding:
        smallRadiusTimePadding ?? this.smallRadiusTimePadding,
    smallRadius: smallRadius ?? this.smallRadius,
    checksPadding: checksPadding ?? this.checksPadding,
    captionPadding: captionPadding ?? this.captionPadding,
    albumWidthFraction: albumWidthFraction ?? this.albumWidthFraction,
    albumAvatarInset: albumAvatarInset ?? this.albumAvatarInset,
  );
}

// --- iOS ---

/// The iOS family's box sizing: fit the picture's native size into a max
/// box by list width class, then hold the minimum box.
///
/// | Field | Value | Role |
/// | --- | --- | --- |
/// | [compactMaxSize] | 300 × 380 | Max box on a compact list |
/// | [regularMaxSize] | 440 × 440 | Max box on a regular list |
/// | [compactMaxListWidth] | 680 | Widest list that is compact |
/// | [videoMaxHeightLandscape] | 250 | Video max height, landscape |
/// | [videoMaxHeightPortrait] | 360 | Video max height, portrait |
/// | [minSize] | 170 × 74 | Box floor |
/// | [noDimensionsSide] | 54 | Native side without dimensions |
/// | [sizeSourceScale] | 0.5 | Native size = pixel size × this |
/// | [sizeSourceMinSide] | 10 | Native side floor |
/// | [animationFillSize] | 480 × 480 | An animation's native size fills this first |
///
/// The box is capped by the bubble's max content width as well. In a
/// mosaic, an item without dimensions is a square.
final class MediaBoxSizing$IOS extends MediaBoxSizing {
  /// The iOS defaults; any value can be replaced.
  const MediaBoxSizing$IOS({
    this.compactMaxSize = const Size(300, 380),
    this.regularMaxSize = const Size(440, 440),
    this.compactMaxListWidth = 680,
    this.videoMaxHeightLandscape = 250,
    this.videoMaxHeightPortrait = 360,
    this.minSize = const Size(170, 74),
    this.noDimensionsSide = 54,
    this.sizeSourceScale = 0.5,
    this.sizeSourceMinSide = 10,
    this.animationFillSize = const Size(480, 480),
  });

  /// See the class table.
  final Size compactMaxSize;

  /// See the class table.
  final Size regularMaxSize;

  /// See the class table.
  final double compactMaxListWidth;

  /// See the class table.
  final double videoMaxHeightLandscape;

  /// See the class table.
  final double videoMaxHeightPortrait;

  /// See the class table.
  final Size minSize;

  /// See the class table.
  final double noDimensionsSide;

  /// See the class table.
  final double sizeSourceScale;

  /// See the class table.
  final double sizeSourceMinSide;

  /// See the class table.
  final Size animationFillSize;

  /// The max box for a list [listWidth] wide.
  Size maxSizeFor(double listWidth) =>
      listWidth <= compactMaxListWidth ? compactMaxSize : regularMaxSize;

  /// The native size of [item]: its pixel size scaled by [sizeSourceScale],
  /// an animation filling [animationFillSize]; null without dimensions.
  Size? nativeSizeOf(MediaItem item) {
    final dimensions = item.descriptor.size;
    if (dimensions == null) return null;
    var native = Size(
      math.max(
        sizeSourceMinSide,
        (dimensions.width * sizeSourceScale).floorToDouble(),
      ),
      math.max(
        sizeSourceMinSide,
        (dimensions.height * sizeSourceScale).floorToDouble(),
      ),
    );
    if (item.kind == MediaItemKind.animation) {
      final scale = math.max(
        animationFillSize.width / native.width,
        animationFillSize.height / native.height,
      );
      native = native * scale;
    }
    return native;
  }

  @override
  MediaBoxResult single(MediaItem item, MediaLayoutInput input) {
    final fallbacks = <MediaLayoutFallbackRule>{};
    final native = switch (nativeSizeOf(item)) {
      final size? => size,
      null => () {
        fallbacks.add(MediaLayoutFallbackRule.noDimensions);
        return Size.square(noDimensionsSide);
      }(),
    };
    var maxSize = maxSizeFor(input.availableWidth);
    if (item.kind == MediaItemKind.video) {
      maxSize = Size(
        maxSize.width,
        native.width > native.height
            ? videoMaxHeightLandscape
            : videoMaxHeightPortrait,
      );
    }
    final fitScale = math.min(
      maxSize.width / native.width,
      maxSize.height / native.height,
    );
    var width = [
      native.width,
      native.width * fitScale,
      input.contentWidth,
      maxSize.width,
    ].reduce(math.min);
    if (width < minSize.width) {
      width = minSize.width;
      fallbacks.add(MediaLayoutFallbackRule.minWidth);
    }
    // The picture fills the box's width, then the height is cut at the max
    // box and raised to the floor.
    final height = math.max(
      minSize.height,
      math.min(width * native.height / native.width, maxSize.height),
    );
    return MediaBoxResult(Size(width, height), fallbacks: fallbacks);
  }

  @override
  double blockWidth(MediaLayoutInput input) =>
      math.min(maxSizeFor(input.availableWidth).width, input.contentWidth);

  /// A copy with the given values replaced.
  MediaBoxSizing$IOS copyWith({
    Size? compactMaxSize,
    Size? regularMaxSize,
    double? compactMaxListWidth,
    double? videoMaxHeightLandscape,
    double? videoMaxHeightPortrait,
    Size? minSize,
    double? noDimensionsSide,
    double? sizeSourceScale,
    double? sizeSourceMinSide,
    Size? animationFillSize,
  }) => MediaBoxSizing$IOS(
    compactMaxSize: compactMaxSize ?? this.compactMaxSize,
    regularMaxSize: regularMaxSize ?? this.regularMaxSize,
    compactMaxListWidth: compactMaxListWidth ?? this.compactMaxListWidth,
    videoMaxHeightLandscape:
        videoMaxHeightLandscape ?? this.videoMaxHeightLandscape,
    videoMaxHeightPortrait:
        videoMaxHeightPortrait ?? this.videoMaxHeightPortrait,
    minSize: minSize ?? this.minSize,
    noDimensionsSide: noDimensionsSide ?? this.noDimensionsSide,
    sizeSourceScale: sizeSourceScale ?? this.sizeSourceScale,
    sizeSourceMinSide: sizeSourceMinSide ?? this.sizeSourceMinSide,
    animationFillSize: animationFillSize ?? this.animationFillSize,
  );
}

// --- Desktop ---

/// The desktop family's box sizing: the picture scaled into a square max
/// box by kind, minimum widths, the caption widening and a taller box to
/// crop less.
///
/// | Field | Value | Role |
/// | --- | --- | --- |
/// | [photoMaxSize] | 430 | Max box side for a photo and a video |
/// | [animationMaxSize] | 320 | Max box side for an animation |
/// | [bubbleMinWidth] | 200 | Width floor in a bubble |
/// | [minWidthWithoutBubble] | 100 | Width floor without a bubble |
/// | [minHeight] | 100 | Height floor |
/// | [noDimensionsSide] | 200 | Interim square without dimensions |
/// | [lessCropGrowth] | 4/3 | A widened box grows its height up to this factor to crop less |
///
/// The box is never taller than the width it may take. A caption widens it
/// up to its max side.
final class MediaBoxSizing$Desktop extends MediaBoxSizing {
  /// The desktop defaults; any value can be replaced.
  const MediaBoxSizing$Desktop({
    this.photoMaxSize = 430,
    this.animationMaxSize = 320,
    this.bubbleMinWidth = 200,
    this.minWidthWithoutBubble = 100,
    this.minHeight = 100,
    this.noDimensionsSide = 200,
    this.lessCropGrowth = 4 / 3,
  });

  /// See the class table.
  final double photoMaxSize;

  /// See the class table.
  final double animationMaxSize;

  /// See the class table.
  final double bubbleMinWidth;

  /// See the class table.
  final double minWidthWithoutBubble;

  /// See the class table.
  final double minHeight;

  /// See the class table.
  final double noDimensionsSide;

  /// See the class table.
  final double lessCropGrowth;

  /// The max box side of [kind].
  double maxSideOf(MediaItemKind kind) =>
      kind == MediaItemKind.animation ? animationMaxSize : photoMaxSize;

  @override
  MediaBoxResult single(MediaItem item, MediaLayoutInput input) {
    final fallbacks = <MediaLayoutFallbackRule>{};
    final maxSide = maxSideOf(item.kind);
    final thumbMax = math.min(input.contentWidth, maxSide);
    final minWidth = math.min(
      thumbMax,
      input.inBubble ? bubbleMinWidth : minWidthWithoutBubble,
    );
    final dimensions = item.descriptor.size;
    if (dimensions == null) {
      fallbacks.add(MediaLayoutFallbackRule.noDimensions);
      final side = math.min(noDimensionsSide, thumbMax);
      return MediaBoxResult(Size.square(side), fallbacks: fallbacks);
    }
    final dw = dimensions.width.toDouble();
    final dh = dimensions.height.toDouble();
    // Scaled down (never up) into the square max box, then to the width it
    // may take, and never taller than that width.
    var scale = math.min(1, math.min(maxSide / dw, maxSide / dh)).toDouble();
    var mediaWidth = dw * scale;
    var mediaHeight = dh * scale;
    if (mediaWidth > thumbMax) {
      scale = thumbMax / mediaWidth;
      mediaWidth *= scale;
      mediaHeight *= scale;
    }
    if (mediaHeight > thumbMax) {
      scale = thumbMax / mediaHeight;
      mediaWidth *= scale;
      mediaHeight *= scale;
    }
    var width = mediaWidth;
    if (width < minWidth) {
      width = minWidth;
      fallbacks.add(MediaLayoutFallbackRule.minWidth);
    }
    var height = math.max(mediaHeight, minHeight);
    if (input.captionWidth case final caption?
        when input.hasText && input.inBubble) {
      final widened = math.min(math.max(width, caption), thumbMax);
      if (widened > width) {
        width = widened;
        fallbacks.add(MediaLayoutFallbackRule.captionWidening);
      }
    }
    if (width > mediaWidth) {
      height = math.max(
        height,
        math.min(width * dh / dw, mediaHeight * lessCropGrowth),
      );
    }
    return MediaBoxResult(Size(width, height), fallbacks: fallbacks);
  }

  @override
  double blockWidth(MediaLayoutInput input) =>
      math.min(photoMaxSize, input.contentWidth);

  /// A copy with the given values replaced.
  MediaBoxSizing$Desktop copyWith({
    double? photoMaxSize,
    double? animationMaxSize,
    double? bubbleMinWidth,
    double? minWidthWithoutBubble,
    double? minHeight,
    double? noDimensionsSide,
    double? lessCropGrowth,
  }) => MediaBoxSizing$Desktop(
    photoMaxSize: photoMaxSize ?? this.photoMaxSize,
    animationMaxSize: animationMaxSize ?? this.animationMaxSize,
    bubbleMinWidth: bubbleMinWidth ?? this.bubbleMinWidth,
    minWidthWithoutBubble: minWidthWithoutBubble ?? this.minWidthWithoutBubble,
    minHeight: minHeight ?? this.minHeight,
    noDimensionsSide: noDimensionsSide ?? this.noDimensionsSide,
    lessCropGrowth: lessCropGrowth ?? this.lessCropGrowth,
  );
}
