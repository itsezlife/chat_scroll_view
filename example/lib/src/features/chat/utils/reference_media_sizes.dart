import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:chat_scroll_view/chat_scroll_view.dart'
    show ChatMediaItem, ChatMediaKind, ChatMediaSizePolicy;
import 'package:content_model/content_model.dart' show ContentSize;
import 'package:flutter/foundation.dart';

/// The example's media size policy: how large a sticker or GIF sent on its
/// own is drawn in the chat, as the reference client draws it, per platform
/// family.
///
/// - [$Mobile] (Android, iOS; `ChatMessageCell.java`, the sticker and GIF
///   branches of `setMessageContent`): a sticker fitted in a square of half
///   the shorter of the chat's width and the screen's height (206 dp on a
///   412 dp phone), 40 % of the tablet side on a tablet; a GIF as wide as the
///   chat less 64 dp when it is landscape, 70 % of it when portrait, by its
///   proportion high, held between 120 dp and the width plus 100 dp.
/// - [$Desktop] (macOS, Windows, Linux and the web; `history_view_sticker.cpp`,
///   `history_view_gif.cpp`): a sticker fitted in 224 px and a GIF in 320 px,
///   never enlarged, whatever the window.
///
/// Both decode at most 512 px on the longer side, the reference render cap
/// (`ImageLoader.java`).
///
/// It sizes a message of a private chat: the reference client takes 52 dp more
/// off a GIF for the sender's avatar in a group and 10 dp for the share button
/// of a channel post, which the demo chat has neither of.
@immutable
sealed class ReferenceMediaSizes implements ChatMediaSizePolicy {
  const ReferenceMediaSizes();

  /// The phone and tablet sizes.
  const factory ReferenceMediaSizes.mobile() = ReferenceMediaSizes$Mobile;

  /// The desktop and web sizes.
  const factory ReferenceMediaSizes.desktop() = ReferenceMediaSizes$Desktop;

  /// The family of the platform the app runs on; pass [platform] / [isWeb] to
  /// pin it in tests.
  factory ReferenceMediaSizes.forPlatform({
    TargetPlatform? platform,
    bool? isWeb,
  }) {
    if (isWeb ?? kIsWeb) return const ReferenceMediaSizes.desktop();
    return switch (platform ?? defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.fuchsia ||
      TargetPlatform.iOS => const ReferenceMediaSizes.mobile(),
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => const ReferenceMediaSizes.desktop(),
    };
  }

  /// A sticker's size when its source is not known.
  static const ContentSize unknownSticker = ContentSize(512, 512);

  /// The reference render cap.
  static const int renderCap = 512;

  @override
  int? get maxDecodeExtent => renderCap;
}

/// The phone and tablet family of [ReferenceMediaSizes].
final class ReferenceMediaSizes$Mobile extends ReferenceMediaSizes {
  /// Creates the policy.
  const ReferenceMediaSizes$Mobile();

  /// The shortest side from which a screen is a tablet (Android's
  /// `values-sw600dp`).
  static const double tabletSide = 600;

  /// The square a GIF of unknown size is.
  static const double unknownGif = 150;

  /// The least height of a GIF.
  static const double minGifHeight = 120;

  @override
  Size sizeFor(
    ChatMediaItem item, {
    required Size viewport,
    required double parentWidth,
  }) => switch (item.kind) {
    ChatMediaKind.sticker => _sticker(
      item.source ?? ReferenceMediaSizes.unknownSticker,
      viewport,
      parentWidth,
    ),
    ChatMediaKind.gif => switch (item.source) {
      final source? => _gif(source, viewport, parentWidth),
      null => const Size.square(unknownGif),
    },
  };

  // Fitted to the box's width, then to its height.
  static Size _sticker(ContentSize source, Size viewport, double parentWidth) {
    final box = _isTablet(viewport)
        ? _minTabletSide(viewport) * 0.4
        : math.min(parentWidth, viewport.height) * 0.5;
    final height = source.height * box / source.width;
    return height > box ? Size(box * box / height, box) : Size(box, height);
  }

  static Size _gif(ContentSize source, Size viewport, double parentWidth) {
    final maxWidth = _gifWidth(source, viewport, parentWidth);
    final maxHeight = maxWidth + 100;
    final height = source.height * maxWidth / source.width;
    if (height > maxHeight) {
      return Size(maxWidth * maxHeight / height, maxHeight);
    }
    if (height < minGifHeight) {
      final width = source.width * minGifHeight / source.height;
      return Size(math.min(width, maxWidth), minGifHeight);
    }
    return Size(maxWidth, height);
  }

  // A landscape GIF takes the row less 64 dp, a portrait one 70 % of it.
  static double _gifWidth(
    ContentSize source,
    Size viewport,
    double parentWidth,
  ) {
    if (_isTablet(viewport)) return _minTabletSide(viewport) * 0.7;
    final side = math.min(parentWidth, viewport.height);
    return source.width >= source.height ? side - 64 : side * 0.7;
  }

  static bool _isTablet(Size viewport) => viewport.shortestSide >= tabletSide;

  // The chat's side of a tablet, the list column taken off it
  // (`AndroidUtilities.getMinTabletSide`).
  static double _minTabletSide(Size viewport) {
    final small = viewport.shortestSide;
    final large = viewport.longestSide;
    if (small <= 690) {
      return math.min(small, large - math.max(large * 0.35, 320));
    }
    return small - math.max(small * 0.35, 320);
  }

  @override
  bool operator ==(Object other) => other is ReferenceMediaSizes$Mobile;

  @override
  int get hashCode => (ReferenceMediaSizes$Mobile).hashCode;
}

/// The desktop and web family of [ReferenceMediaSizes].
final class ReferenceMediaSizes$Desktop extends ReferenceMediaSizes {
  /// Creates the policy.
  const ReferenceMediaSizes$Desktop();

  /// The box a sticker fits in (`st::maxStickerSize`).
  static const double stickerBox = 224;

  /// The box a GIF fits in (`st::maxGifSize`).
  static const double gifBox = 320;

  /// The least width and height of a GIF (`st::minPhotoSize`).
  static const double minGifSide = 100;

  @override
  Size sizeFor(
    ChatMediaItem item, {
    required Size viewport,
    required double parentWidth,
  }) => switch (item.kind) {
    ChatMediaKind.sticker => _downscaled(
      item.source ?? ReferenceMediaSizes.unknownSticker,
      stickerBox,
    ),
    ChatMediaKind.gif => switch (item.source) {
      final source? => _gif(source),
      null => const Size.square(gifBox),
    },
  };

  static Size _gif(ContentSize source) {
    final fitted = _downscaled(source, gifBox);
    return Size(
      math.max(fitted.width, minGifSide),
      math.max(fitted.height, minGifSide),
    );
  }

  // `DownscaledSize`: fitted in a [box] square when larger, as it is else.
  static Size _downscaled(ContentSize source, double box) {
    final width = source.width.toDouble();
    final height = source.height.toDouble();
    if (width <= box && height <= box) return Size(width, height);
    final scale = math.min(box / width, box / height);
    return Size(width * scale, height * scale);
  }

  @override
  bool operator ==(Object other) => other is ReferenceMediaSizes$Desktop;

  @override
  int get hashCode => (ReferenceMediaSizes$Desktop).hashCode;
}
