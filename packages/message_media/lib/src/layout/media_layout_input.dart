import 'dart:ui';

import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// Where a message's text sits against its media blocks.
///
/// For a caption, above is the message's `invertMedia`; for a link preview
/// message, the body sits above the card unless `invertMedia` puts the card
/// first.
enum MediaCaptionPosition {
  /// Text over the first block.
  above,

  /// Text under the last block.
  below,

  /// No text: the media fills the bubble.
  none,
}

/// The measured widths of chrome that sets a box's minimum width.
///
/// The host measures them with its own text styles; the policy adds its
/// paddings. Zero is "not shown".
@immutable
final class MediaLayoutChrome {
  /// Chrome widths; each defaults to not shown.
  const MediaLayoutChrome({
    this.timeWidth = 0,
    this.timeHeight = 0,
    this.infoBadgeWidth = 0,
    this.progressLabelWidth = 0,
    this.bubbleRadius = 17,
  }) : assert(
         timeWidth >= 0 &&
             timeHeight >= 0 &&
             infoBadgeWidth >= 0 &&
             progressLabelWidth >= 0,
         'Chrome widths are not negative.',
       );

  /// No chrome measured, the default bubble radius.
  static const none = MediaLayoutChrome();

  /// The time text's width (the time pill's content).
  final double timeWidth;

  /// The time text's height, which sets the time pill's; 0 is the
  /// platform's default (`MediaTimePillPlacement.defaultTextHeight`).
  final double timeHeight;

  /// The video's duration / size badge text width.
  final double infoBadgeWidth;

  /// The width of the widest progress label a loading video or animation
  /// shows ("100%").
  final double progressLabelWidth;

  /// The bubble's corner radius, which picks the time pill's padding.
  final double bubbleRadius;

  @override
  bool operator ==(Object other) =>
      other is MediaLayoutChrome &&
      other.timeWidth == timeWidth &&
      other.timeHeight == timeHeight &&
      other.infoBadgeWidth == infoBadgeWidth &&
      other.progressLabelWidth == progressLabelWidth &&
      other.bubbleRadius == bubbleRadius;

  @override
  int get hashCode => Object.hash(
    timeWidth,
    timeHeight,
    infoBadgeWidth,
    progressLabelWidth,
    bubbleRadius,
  );
}

/// A link preview to lay out as a card block: the page and the message's
/// options for it.
@immutable
final class MediaLinkPreviewInput {
  /// The card of [page] with [options].
  const MediaLinkPreviewInput({required this.page, this.options});

  /// The page.
  final LinkPreview page;

  /// The message's preview options.
  final LinkPreviewOptions? options;

  @override
  bool operator ==(Object other) =>
      other is MediaLinkPreviewInput &&
      other.page == page &&
      other.options == options;

  @override
  int get hashCode => Object.hash(page, options);
}

/// Everything the layout step reads: the items and the bubble they sit in.
///
/// Never a message: the items may come from one message or, later, from a
/// group of them.
@immutable
final class MediaLayoutInput {
  /// The input for [items] in a list [availableWidth] wide.
  MediaLayoutInput({
    required List<MediaItem> items,
    required this.availableWidth,
    this.displaySize,
    this.tabletMinSide,
    this.maxContentWidth,
    this.captionPosition = MediaCaptionPosition.none,
    this.captionWidth,
    this.linkPreview,
    this.isOutgoing = false,
    this.showsAvatar = false,
    this.hasSideButton = false,
    this.inBubble = true,
    this.joinedAbove = false,
    this.joinedBelow = false,
    this.chrome = MediaLayoutChrome.none,
    this.correlation = ChatCorrelation.none,
  }) : assert(availableWidth >= 0, 'availableWidth is not negative.'),
       items = List.unmodifiable(items);

  /// The media items, in order.
  final List<MediaItem> items;

  /// The width of the list the bubble lives in.
  final double availableWidth;

  /// The screen's size; null reads as a square of [availableWidth].
  final Size? displaySize;

  /// The shorter side of a tablet's screen; null on a phone or a desktop.
  final double? tabletMinSide;

  /// The bubble's max content width; null is [availableWidth].
  final double? maxContentWidth;

  /// Where the message's text sits against the media.
  final MediaCaptionPosition captionPosition;

  /// The caption's laid-out text width, when the host measured it; a
  /// policy that widens media for its caption reads it.
  final double? captionWidth;

  /// The link preview drawn as a card block after the media, if any.
  final MediaLinkPreviewInput? linkPreview;

  /// Whether the message is outgoing (its time carries status checks).
  final bool isOutgoing;

  /// Whether an avatar sits beside the bubble.
  final bool showsAvatar;

  /// Whether a side button (share, go to) sits beside the bubble.
  final bool hasSideButton;

  /// Whether the media is drawn in a bubble.
  final bool inBubble;

  /// Whether the bubble is joined to the bubble above it.
  final bool joinedAbove;

  /// Whether the bubble is joined to the bubble below it.
  final bool joinedBelow;

  /// Measured chrome widths.
  final MediaLayoutChrome chrome;

  /// The chat and message the layout's diagnostics events name.
  final ChatCorrelation correlation;

  /// Whether the message has text next to its media.
  bool get hasText => captionPosition != MediaCaptionPosition.none;

  /// The screen's height, or [availableWidth] when it is unknown.
  double get displayHeight => displaySize?.height ?? availableWidth;

  /// The bubble's max content width.
  double get contentWidth => maxContentWidth ?? availableWidth;

  @override
  bool operator ==(Object other) =>
      other is MediaLayoutInput &&
      _listEquals(other.items, items) &&
      other.availableWidth == availableWidth &&
      other.displaySize == displaySize &&
      other.tabletMinSide == tabletMinSide &&
      other.maxContentWidth == maxContentWidth &&
      other.captionPosition == captionPosition &&
      other.captionWidth == captionWidth &&
      other.linkPreview == linkPreview &&
      other.isOutgoing == isOutgoing &&
      other.showsAvatar == showsAvatar &&
      other.hasSideButton == hasSideButton &&
      other.inBubble == inBubble &&
      other.joinedAbove == joinedAbove &&
      other.joinedBelow == joinedBelow &&
      other.chrome == chrome &&
      other.correlation == correlation;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(items),
    availableWidth,
    displaySize,
    tabletMinSide,
    maxContentWidth,
    captionPosition,
    captionWidth,
    linkPreview,
    isOutgoing,
    showsAvatar,
    hasSideButton,
    inBubble,
    joinedAbove,
    joinedBelow,
    chrome,
    correlation,
  );

  static bool _listEquals(List<MediaItem> a, List<MediaItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
