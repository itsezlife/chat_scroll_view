import 'dart:ui';

import 'package:content_model/content_model.dart';
import 'package:message_media/src/layout/media_layout_text.dart';
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
    this.hasFooterInfo = false,
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

  /// Whether the message shows views, a signature or the edited mark, which
  /// some platforms put on an extra line under a file stack.
  final bool hasFooterInfo;

  @override
  bool operator ==(Object other) =>
      other is MediaLayoutChrome &&
      other.timeWidth == timeWidth &&
      other.timeHeight == timeHeight &&
      other.infoBadgeWidth == infoBadgeWidth &&
      other.progressLabelWidth == progressLabelWidth &&
      other.bubbleRadius == bubbleRadius &&
      other.hasFooterInfo == hasFooterInfo;

  @override
  int get hashCode => Object.hash(
    timeWidth,
    timeHeight,
    infoBadgeWidth,
    progressLabelWidth,
    bubbleRadius,
    hasFooterInfo,
  );
}

/// A link preview to lay out as a card block: the page, the message's
/// options for it, and what the card needs from the host.
@immutable
final class MediaLinkPreviewInput {
  /// The card of [page] with [options] in the message [messageId].
  const MediaLinkPreviewInput({
    required this.page,
    required this.messageId,
    this.options,
    this.buttonLabel,
    this.compact = false,
    this.textDirection = TextDirection.ltr,
  });

  /// The page.
  final LinkPreview page;

  /// The message's id, which the card's media item ids derive from
  /// (`MediaItemId.linkPreviewOf`).
  final String messageId;

  /// The message's preview options.
  final LinkPreviewOptions? options;

  /// The action button's label (for example an instant view); null draws
  /// no button. What the button does is the host's.
  final String? buttonLabel;

  /// Whether the host draws the chat in its compact layout (shorter
  /// descriptions; Android shows a photo small).
  final bool compact;

  /// The chat's direction: in a right-to-left chat the bar is on the right
  /// and, where the policy mirrors, the thumbnail on the left.
  final TextDirection textDirection;

  @override
  bool operator ==(Object other) =>
      other is MediaLinkPreviewInput &&
      other.page == page &&
      other.messageId == messageId &&
      other.options == options &&
      other.buttonLabel == buttonLabel &&
      other.compact == compact &&
      other.textDirection == textDirection;

  @override
  int get hashCode => Object.hash(
    page,
    messageId,
    options,
    buttonLabel,
    compact,
    textDirection,
  );
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
    required this.text,
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
    this.headerAbove = false,
    this.reactionsBelow = false,
    this.chrome = MediaLayoutChrome.none,
    this.correlation = ChatCorrelation.none,
    Map<MediaItemId, double> fileCaptionHeights = const {},
  }) : assert(availableWidth >= 0, 'availableWidth is not negative.'),
       items = List.unmodifiable(items),
       fileCaptionHeights = Map.unmodifiable(fileCaptionHeights);

  /// The media items, in order.
  final List<MediaItem> items;

  /// The width of the list the bubble lives in.
  final double availableWidth;

  /// What the layout measures text with: build it with
  /// `MediaLayoutText.of` where the media view is built.
  final MediaLayoutText text;

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

  /// The link preview drawn as a card block after the media, if any; none
  /// while its page is pending.
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

  /// Whether a header (the sender's name, a forward or reply header) sits
  /// above the media in the bubble: the first block's top touches text.
  final bool headerAbove;

  /// Whether reactions sit under the media in the bubble: the media is not
  /// the bubble's bottom element, so the time leaves it.
  final bool reactionsBelow;

  /// Measured chrome widths.
  final MediaLayoutChrome chrome;

  /// The chat and message the layout's diagnostics events name.
  final ChatCorrelation correlation;

  /// The measured height of each file's own caption, by item: a file in a
  /// stack keeps a caption of its own under its row. The caption body is
  /// the host's text; the file stack reports where each one goes.
  final Map<MediaItemId, double> fileCaptionHeights;

  /// Whether the message has text next to its media.
  bool get hasText => captionPosition != MediaCaptionPosition.none;

  /// The screen's height, or [availableWidth] when it is unknown.
  double get displayHeight => displaySize?.height ?? availableWidth;

  /// The bubble's max content width.
  double get contentWidth => maxContentWidth ?? availableWidth;

  /// Whether the media blocks end the bubble: no text and no reactions
  /// under them.
  bool get mediaIsBottom =>
      captionPosition != MediaCaptionPosition.below && !reactionsBelow;

  /// Whether the link preview card is the bubble's bottom element, which
  /// moves the time under the card (its own line, or the card's bottom
  /// inset, by platform).
  bool get cardIsLast => linkPreview != null && mediaIsBottom;

  /// A copy with the given fields replaced.
  MediaLayoutInput copyWith({
    List<MediaItem>? items,
    double? availableWidth,
    MediaLayoutText? text,
    MediaCaptionPosition? captionPosition,
    double? captionWidth,
    bool? isOutgoing,
    bool? joinedAbove,
    bool? joinedBelow,
    bool? headerAbove,
    bool? reactionsBelow,
    MediaLayoutChrome? chrome,
    Map<MediaItemId, double>? fileCaptionHeights,
  }) => MediaLayoutInput(
    items: items ?? this.items,
    availableWidth: availableWidth ?? this.availableWidth,
    text: text ?? this.text,
    displaySize: displaySize,
    tabletMinSide: tabletMinSide,
    maxContentWidth: maxContentWidth,
    captionPosition: captionPosition ?? this.captionPosition,
    captionWidth: captionWidth ?? this.captionWidth,
    linkPreview: linkPreview,
    isOutgoing: isOutgoing ?? this.isOutgoing,
    showsAvatar: showsAvatar,
    hasSideButton: hasSideButton,
    inBubble: inBubble,
    joinedAbove: joinedAbove ?? this.joinedAbove,
    joinedBelow: joinedBelow ?? this.joinedBelow,
    headerAbove: headerAbove ?? this.headerAbove,
    reactionsBelow: reactionsBelow ?? this.reactionsBelow,
    chrome: chrome ?? this.chrome,
    correlation: correlation,
    fileCaptionHeights: fileCaptionHeights ?? this.fileCaptionHeights,
  );

  @override
  bool operator ==(Object other) =>
      other is MediaLayoutInput &&
      _listEquals(other.items, items) &&
      other.availableWidth == availableWidth &&
      other.text == text &&
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
      other.headerAbove == headerAbove &&
      other.reactionsBelow == reactionsBelow &&
      other.chrome == chrome &&
      other.correlation == correlation &&
      _mapEquals(other.fileCaptionHeights, fileCaptionHeights);

  @override
  int get hashCode => Object.hash(
    Object.hashAll(items),
    availableWidth,
    text,
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
    headerAbove,
    reactionsBelow,
    chrome,
    correlation,
    Object.hashAllUnordered(
      fileCaptionHeights.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );

  static bool _mapEquals(
    Map<MediaItemId, double> a,
    Map<MediaItemId, double> b,
  ) {
    if (a.length != b.length) return false;
    for (final MapEntry(:key, :value) in a.entries) {
      if (b[key] != value) return false;
    }
    return true;
  }

  static bool _listEquals(List<MediaItem> a, List<MediaItem> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
