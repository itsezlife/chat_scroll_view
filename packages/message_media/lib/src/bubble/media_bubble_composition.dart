import 'package:message_media/src/layout/media_layout.dart';
import 'package:message_media/src/layout/media_layout_input.dart';
import 'package:meta/meta.dart';

/// What a media bubble holds besides its media, as the bubble composes it:
/// the message's `invertMedia`, a caption, a header and reactions.
///
/// The composition tells the layout which sides of the media touch text
/// ([inputFor]), so the corners follow it, and it decides the bubble's
/// [MediaBubbleShape] and where the time goes ([MediaBubbleTime]). It is
/// pure and known before anything is measured, so the host picks its bubble
/// shape and builds its time chrome from it.
///
/// ## Order
///
/// - Media items: the caption sits under the media, above it under
///   [invertMedia]. An album has one caption (top or bottom); each file of
///   a stack keeps its own caption under its row (the file stack's caption
///   slots, from `MediaLayoutInput.fileCaptionHeights`).
/// - A link preview card (no items): the text sits above the card, under
///   it under [invertMedia].
/// - A header (name, forward, reply) is always first.
@immutable
final class MediaBubbleComposition {
  /// A bubble of these parts.
  const MediaBubbleComposition({
    this.invertMedia = false,
    this.hasCaption = false,
    this.hasHeader = false,
    this.reactionsBelow = false,
  });

  /// The message's `invertMedia`: the caption above media, the card above
  /// the text.
  final bool invertMedia;

  /// Whether the message has text: a caption, or a link preview message's
  /// body.
  final bool hasCaption;

  /// Whether a header (name, forward, reply) sits at the bubble's top.
  final bool hasHeader;

  /// Whether reactions sit under everything else in the bubble.
  final bool reactionsBelow;

  /// Where the text sits against the media of [base].
  MediaCaptionPosition captionPositionFor(MediaLayoutInput base) {
    if (!hasCaption) return MediaCaptionPosition.none;
    return textFirst(hasItems: base.items.isNotEmpty)
        ? MediaCaptionPosition.above
        : MediaCaptionPosition.below;
  }

  /// Whether the text comes before the media: text sits after media items
  /// and before a link preview card ([hasItems] false), and [invertMedia]
  /// flips both.
  bool textFirst({required bool hasItems}) =>
      hasItems ? invertMedia : !invertMedia;

  /// [base] with the sides this composition sets: the caption position, the
  /// header above and the reactions below.
  MediaLayoutInput inputFor(MediaLayoutInput base) => base.copyWith(
    captionPosition: captionPositionFor(base),
    headerAbove: hasHeader,
    reactionsBelow: reactionsBelow,
  );

  /// A copy with the given parts replaced.
  MediaBubbleComposition copyWith({
    bool? invertMedia,
    bool? hasCaption,
    bool? hasHeader,
    bool? reactionsBelow,
  }) => MediaBubbleComposition(
    invertMedia: invertMedia ?? this.invertMedia,
    hasCaption: hasCaption ?? this.hasCaption,
    hasHeader: hasHeader ?? this.hasHeader,
    reactionsBelow: reactionsBelow ?? this.reactionsBelow,
  );

  @override
  bool operator ==(Object other) =>
      other is MediaBubbleComposition &&
      other.invertMedia == invertMedia &&
      other.hasCaption == hasCaption &&
      other.hasHeader == hasHeader &&
      other.reactionsBelow == reactionsBelow;

  @override
  int get hashCode =>
      Object.hash(invertMedia, hasCaption, hasHeader, reactionsBelow);

  @override
  String toString() =>
      'MediaBubbleComposition(invertMedia: $invertMedia, '
      'hasCaption: $hasCaption, hasHeader: $hasHeader, '
      'reactionsBelow: $reactionsBelow)';
}

/// The bubble a message's media sits in.
enum MediaBubbleShape {
  /// A media bubble: media items with no caption under them (a caption
  /// above included). No tail; the media sits at the bubble inset
  /// (`MediaCornerPolicy.bubbleInset`).
  media,

  /// An ordinary tailed text bubble: a caption under the media, or a link
  /// preview message.
  text;

  /// The shape of a bubble laid out from [input].
  static MediaBubbleShape of(MediaLayoutInput input) =>
      input.items.isNotEmpty &&
          input.linkPreview == null &&
          input.captionPosition != MediaCaptionPosition.below
      ? MediaBubbleShape.media
      : MediaBubbleShape.text;

  /// Whether the bubble draws its tail.
  bool get hasTail => this == MediaBubbleShape.text;
}

/// Where the message's time goes in a media bubble.
enum MediaBubbleTime {
  /// Over the boxes, at `MediaLayout.timePill`: the boxes end the bubble.
  overMedia,

  /// On the last file row (`MediaFileRow.carriesTime`): a file stack ends
  /// the bubble.
  inLastFileRow,

  /// Under the link preview card: the card ends the bubble
  /// (`MediaLayoutInput.cardIsLast`).
  underCard,

  /// The host's text chrome: the caption's last line or a line of its own,
  /// or the reactions' line.
  inText;

  /// Where the time goes in [layout] laid out from [input].
  static MediaBubbleTime of(MediaLayout layout, MediaLayoutInput input) {
    if (input.cardIsLast) return MediaBubbleTime.underCard;
    if (!input.mediaIsBottom) return MediaBubbleTime.inText;
    return switch (layout.blocks) {
      [..., MediaBlock$Mosaic()] => MediaBubbleTime.overMedia,
      [..., MediaBlock$FileStack()] => MediaBubbleTime.inLastFileRow,
      [..., MediaBlock$LinkPreview()] => MediaBubbleTime.underCard,
      [] => MediaBubbleTime.inText,
    };
  }
}
