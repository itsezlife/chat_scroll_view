import 'dart:math' as math;
import 'dart:ui';

import 'package:message_media/src/layout/media_layout.dart';
import 'package:message_media/src/layout/media_layout_input.dart';
import 'package:meta/meta.dart';

/// Where the message's time pill sits over its media, per platform.
///
/// The pill is the host's chrome (its fill, its text, its checks); message
/// media only reports its rect, in layout coordinates, as
/// `MediaLayout.timePill`. The time sits over media only when media is the
/// bubble's bottom element ([sitsOnMedia]); otherwise the host places the
/// time in the caption.
///
/// The pill is [horizontalPadding] wider than the time on each side (plus
/// [outgoingExtraWidth] for an outgoing message's checks), and its height is
/// the time text's height plus [verticalPadding] on each side, at least
/// [minHeight]. It is anchored at the media's bottom-right: [rightInset]
/// from the right, and either its top [topFromBottom] above the media's
/// bottom (the pill grows down with a larger text) or its bottom
/// [bottomInset] above it.
@immutable
final class MediaTimePillPlacement {
  /// A placement of the given metrics.
  const MediaTimePillPlacement({
    required this.rightInset,
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.defaultTextHeight,
    this.bottomInset = 0,
    this.topFromBottom,
    this.smallRadiusHorizontalPadding,
    this.smallRadiusBelow = 0,
    this.minHeight = 0,
    this.outgoingExtraWidth = 0,
  });

  /// Bottom-right, its top 23 above the media's bottom, 12 + 6 + 6 around a
  /// 12 text (4 a side under a bubble radius below 10), at least 17 high,
  /// 20 wider for an outgoing message's checks.
  const MediaTimePillPlacement.android()
    : this(
        rightInset: 6,
        topFromBottom: 23,
        horizontalPadding: 6,
        smallRadiusHorizontalPadding: 4,
        smallRadiusBelow: 10,
        verticalPadding: 2.5,
        defaultTextHeight: 12,
        minHeight: 17,
        outgoingExtraWidth: 20,
      );

  /// Bottom-right, inset (6, 6), padded (7, 2) around the time.
  const MediaTimePillPlacement.ios()
    : this(
        rightInset: 6,
        bottomInset: 6,
        horizontalPadding: 7,
        verticalPadding: 2,
        defaultTextHeight: 14,
      );

  /// Bottom-right, inset 4, padded (8, 2) around the time.
  const MediaTimePillPlacement.desktop()
    : this(
        rightInset: 4,
        bottomInset: 4,
        horizontalPadding: 8,
        verticalPadding: 2,
        defaultTextHeight: 17,
      );

  /// The gap between the pill's right edge and the media's.
  final double rightInset;

  /// The gap between the pill's bottom and the media's, when
  /// [topFromBottom] is null.
  final double bottomInset;

  /// How far above the media's bottom the pill's top sits; null anchors the
  /// pill's bottom instead ([bottomInset]).
  final double? topFromBottom;

  /// The space on each side of the time.
  final double horizontalPadding;

  /// [horizontalPadding] under a bubble radius below [smallRadiusBelow];
  /// null keeps [horizontalPadding].
  final double? smallRadiusHorizontalPadding;

  /// The bubble radius under which [smallRadiusHorizontalPadding] applies.
  final double smallRadiusBelow;

  /// The space above and below the time text.
  final double verticalPadding;

  /// The time text's height when the host did not measure it
  /// (`MediaLayoutChrome.timeHeight` 0).
  final double defaultTextHeight;

  /// The pill's least height.
  final double minHeight;

  /// The width an outgoing message's checks add; a host that measures its
  /// checks into the time's width leaves it 0.
  final double outgoingExtraWidth;

  /// Whether the time sits over the media of [layout] laid out from
  /// [input]: a time is shown, nothing follows the media in the bubble (no
  /// caption below, no reactions below, no link preview card:
  /// `MediaLayoutInput.mediaIsBottom`) and the last block is boxes.
  static bool sitsOnMedia(MediaLayout layout, MediaLayoutInput input) =>
      input.chrome.timeWidth > 0 &&
      input.mediaIsBottom &&
      switch (layout.blocks) {
        [..., MediaBlock$Mosaic()] => true,
        _ => false,
      };

  /// The pill's rect over [media] (the bottom block's bounds) for the
  /// measured [chrome].
  Rect rectOf(
    Rect media,
    MediaLayoutChrome chrome, {
    required bool isOutgoing,
  }) {
    final padding = switch (smallRadiusHorizontalPadding) {
      final small? when chrome.bubbleRadius < smallRadiusBelow => small,
      _ => horizontalPadding,
    };
    final textHeight = chrome.timeHeight > 0
        ? chrome.timeHeight
        : defaultTextHeight;
    final height = math.max(minHeight, textHeight + 2 * verticalPadding);
    final width =
        chrome.timeWidth + 2 * padding + (isOutgoing ? outgoingExtraWidth : 0);
    final right = media.right - rightInset;
    final top = switch (topFromBottom) {
      final fromBottom? => media.bottom - fromBottom,
      null => media.bottom - bottomInset - height,
    };
    return Rect.fromLTWH(right - width, top, width, height);
  }

  /// The pill's rect in [layout] laid out from [input], or null when the
  /// time does not sit on the media.
  Rect? of(MediaLayout layout, MediaLayoutInput input) {
    if (!sitsOnMedia(layout, input)) return null;
    return rectOf(
      layout.blocks.last.rect,
      input.chrome,
      isOutgoing: input.isOutgoing,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MediaTimePillPlacement &&
      other.rightInset == rightInset &&
      other.bottomInset == bottomInset &&
      other.topFromBottom == topFromBottom &&
      other.horizontalPadding == horizontalPadding &&
      other.smallRadiusHorizontalPadding == smallRadiusHorizontalPadding &&
      other.smallRadiusBelow == smallRadiusBelow &&
      other.verticalPadding == verticalPadding &&
      other.defaultTextHeight == defaultTextHeight &&
      other.minHeight == minHeight &&
      other.outgoingExtraWidth == outgoingExtraWidth;

  @override
  int get hashCode => Object.hash(
    rightInset,
    bottomInset,
    topFromBottom,
    horizontalPadding,
    smallRadiusHorizontalPadding,
    smallRadiusBelow,
    verticalPadding,
    defaultTextHeight,
    minHeight,
    outgoingExtraWidth,
  );
}
