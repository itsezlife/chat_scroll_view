import 'dart:math' as math;

import 'package:message_media/src/layout/media_corner_radii.dart';
import 'package:message_media/src/layout/media_layout.dart';
import 'package:message_media/src/layout/media_layout_input.dart';
import 'package:meta/meta.dart';

/// A radius that may differ between a compact list and a regular (wide)
/// one.
@immutable
final class MediaListRadius {
  /// [compact] on a compact list, [regular] on a regular one.
  const MediaListRadius({required this.compact, required this.regular});

  /// The same [radius] on every list.
  const MediaListRadius.all(double radius)
    : this(compact: radius, regular: radius);

  /// On a compact list.
  final double compact;

  /// On a regular list.
  final double regular;

  /// The radius on a list that [isCompact] or not.
  double on({required bool isCompact}) => isCompact ? compact : regular;

  @override
  bool operator ==(Object other) =>
      other is MediaListRadius &&
      other.compact == compact &&
      other.regular == regular;

  @override
  int get hashCode => Object.hash(compact, regular);

  @override
  String toString() => 'MediaListRadius($compact, $regular)';
}

/// When a bubble has a tail at its bottom corner on the sender's side.
enum MediaTailPresence {
  /// Never: the tail corner follows the neighbour rule.
  never,

  /// When the message has text next to its media (a media-only bubble has
  /// no tail).
  withText,

  /// When the bubble is not joined to the bubble below it.
  unlessJoinedBelow,
}

/// What a bubble's tail does to the media corner under it.
///
/// The tail corner is the bottom corner on the sender's side (left for an
/// incoming message, right for an outgoing one), of a cell whose side on
/// that edge is the bubble's edge and whose bottom is not another item.
@immutable
final class MediaTailRule {
  /// The tail corner takes [radius] when the bubble has a tail per
  /// [presence], only on incoming messages when [incomingOnly].
  const MediaTailRule({
    required this.presence,
    required this.radius,
    this.incomingOnly = false,
  });

  /// No tail rule: the tail corner follows the neighbour rule.
  static const none = MediaTailRule(
    presence: MediaTailPresence.never,
    radius: MediaTailRadius.adjacentBubble,
  );

  /// The Android family: an incoming bubble with text has a tail, and its
  /// bottom-left corner takes the joined-bubble radius.
  static const android = MediaTailRule(
    presence: MediaTailPresence.withText,
    radius: MediaTailRadius.adjacentBubble,
    incomingOnly: true,
  );

  /// The desktop family: the tail of a bubble that ends its group squares
  /// the corner under it.
  static const desktop = MediaTailRule(
    presence: MediaTailPresence.unlessJoinedBelow,
    radius: MediaTailRadius.square,
  );

  /// When the bubble has a tail.
  final MediaTailPresence presence;

  /// What the tail corner takes.
  final MediaTailRadius radius;

  /// Whether only an incoming message's tail counts.
  final bool incomingOnly;

  /// Whether a bubble laid out from [input] has a tail.
  bool hasTail(MediaLayoutInput input) {
    if (incomingOnly && input.isOutgoing) return false;
    return switch (presence) {
      MediaTailPresence.never => false,
      MediaTailPresence.withText => input.hasText,
      MediaTailPresence.unlessJoinedBelow => !input.joinedBelow,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is MediaTailRule &&
      other.presence == presence &&
      other.radius == radius &&
      other.incomingOnly == incomingOnly;

  @override
  int get hashCode => Object.hash(presence, radius, incomingOnly);
}

/// The radius a tail corner takes.
enum MediaTailRadius {
  /// The joined-bubble radius ([MediaCornerPolicy.adjacentBubble]).
  adjacentBubble,

  /// Square: 0.
  square,
}

/// How a cell's corners are rounded from what its sides touch, with each
/// platform's values.
///
/// ## The rule
///
/// A corner takes the bubble-edge radius only when both of its sides touch
/// the bubble's edge. When either side touches text or another item, it
/// takes the inner radius: [text] or [item], the smaller when it touches
/// both. Inner radii never exceed the bubble-edge radius.
///
/// A side joined to the next or previous bubble ([MediaNeighbour.adjacentBubble])
/// rounds only its corner on the sender's side ([adjacentBubble]); its
/// other corner keeps the bubble-edge radius, as the bubble's own outline
/// does. Last, the [tail] rule may change the tail corner.
///
/// | Value | Android | iOS | Desktop |
/// | --- | --- | --- | --- |
/// | [bubbleInset] | 2 | 2 | 0 (flush) |
/// | bubble edge | bubble radius − 2 (when over 2) | bubble radius − 1 | bubble radius |
/// | [adjacentBubble] | 3 | 7 compact / 8 regular | 6 |
/// | [text] | 4 | 0 compact / 5 regular | 0 |
/// | [item] | 4 | 0 compact / 5 regular | 0 |
/// | [tail] | incoming with text: joined radius | none | ends its group: square |
///
/// The bubble radius is the input's `MediaLayoutChrome.bubbleRadius`. A list
/// is compact while its width is at most [compactListMaxWidth]. Sides are
/// physical, the sender's side left for incoming and right for outgoing.
@immutable
final class MediaCornerPolicy {
  /// A corner policy of the given values.
  const MediaCornerPolicy({
    required this.bubbleInset,
    required this.bubbleEdgeInset,
    required this.adjacentBubble,
    required this.text,
    required this.item,
    required this.tail,
    this.compactListMaxWidth = 680,
  });

  /// The Android family's corners.
  const MediaCornerPolicy.android()
    : this(
        bubbleInset: 2,
        bubbleEdgeInset: 2,
        adjacentBubble: const MediaListRadius.all(3),
        text: const MediaListRadius.all(4),
        item: const MediaListRadius.all(4),
        tail: MediaTailRule.android,
      );

  /// The iOS family's corners.
  const MediaCornerPolicy.ios()
    : this(
        bubbleInset: 2,
        bubbleEdgeInset: 1,
        adjacentBubble: const MediaListRadius(compact: 7, regular: 8),
        text: const MediaListRadius(compact: 0, regular: 5),
        item: const MediaListRadius(compact: 0, regular: 5),
        tail: MediaTailRule.none,
      );

  /// The desktop family's corners: square between the boxes of an album.
  const MediaCornerPolicy.desktop()
    : this(
        bubbleInset: 0,
        bubbleEdgeInset: 0,
        adjacentBubble: const MediaListRadius.all(6),
        text: const MediaListRadius.all(0),
        item: const MediaListRadius.all(0),
        tail: MediaTailRule.desktop,
      );

  /// The inset of the media from the bubble's edge in a media-only bubble,
  /// which the bubble composition reads.
  final double bubbleInset;

  /// How much smaller than the bubble's radius the bubble-edge corner is
  /// (applied only to a bubble radius above it).
  final double bubbleEdgeInset;

  /// The corner on the sender's side of a side joined to another bubble.
  final MediaListRadius adjacentBubble;

  /// A corner touching text.
  final MediaListRadius text;

  /// A corner touching another item.
  final MediaListRadius item;

  /// What the bubble's tail does to its corner.
  final MediaTailRule tail;

  /// The widest list that is compact.
  final double compactListMaxWidth;

  /// The bubble-edge radius of a bubble rounded by [bubbleRadius].
  double bubbleEdgeOf(double bubbleRadius) => bubbleRadius > bubbleEdgeInset
      ? bubbleRadius - bubbleEdgeInset
      : bubbleRadius;

  /// The radii of [cell] in a layout of [input].
  MediaCornerRadii radiiOf(MediaCell cell, MediaLayoutInput input) {
    final edge = bubbleEdgeOf(input.chrome.bubbleRadius);
    final compact = input.availableWidth <= compactListMaxWidth;
    final joined = math.min(edge, adjacentBubble.on(isCompact: compact));
    double? inner(MediaNeighbour side) => switch (side) {
      MediaNeighbour.text => text.on(isCompact: compact),
      MediaNeighbour.item => item.on(isCompact: compact),
      MediaNeighbour.bubbleEdge || MediaNeighbour.adjacentBubble => null,
    };
    // The sender's side: where a joined side's corner and the tail are.
    final senderLeft = !input.isOutgoing;
    double corner(
      MediaNeighbour horizontal,
      MediaNeighbour vertical, {
      required bool left,
    }) {
      final inners = [?inner(horizontal), ?inner(vertical)];
      if (inners.isNotEmpty) return math.min(edge, inners.reduce(math.min));
      final joinedHere =
          vertical == MediaNeighbour.adjacentBubble ||
          (horizontal == MediaNeighbour.adjacentBubble && left == senderLeft);
      return joinedHere ? joined : edge;
    }

    final n = cell.neighbours;
    var radii = MediaCornerRadii(
      topLeft: corner(n.top, n.left, left: true),
      topRight: corner(n.top, n.right, left: false),
      bottomLeft: corner(n.bottom, n.left, left: true),
      bottomRight: corner(n.bottom, n.right, left: false),
    );
    final senderSide = senderLeft ? n.left : n.right;
    if (tail.hasTail(input) &&
        senderSide == MediaNeighbour.bubbleEdge &&
        n.bottom != MediaNeighbour.item) {
      final value = switch (tail.radius) {
        MediaTailRadius.adjacentBubble => joined,
        MediaTailRadius.square => 0.0,
      };
      radii = senderLeft
          ? MediaCornerRadii(
              topLeft: radii.topLeft,
              topRight: radii.topRight,
              bottomLeft: value,
              bottomRight: radii.bottomRight,
            )
          : MediaCornerRadii(
              topLeft: radii.topLeft,
              topRight: radii.topRight,
              bottomLeft: radii.bottomLeft,
              bottomRight: value,
            );
    }
    return radii;
  }

  /// [layout] with every cell's radii resolved for [input].
  MediaLayout resolve(MediaLayout layout, MediaLayoutInput input) =>
      layout.mapCells((cell) => cell.copyWith(radii: radiiOf(cell, input)));

  /// A copy with the given values replaced.
  MediaCornerPolicy copyWith({
    double? bubbleInset,
    double? bubbleEdgeInset,
    MediaListRadius? adjacentBubble,
    MediaListRadius? text,
    MediaListRadius? item,
    MediaTailRule? tail,
    double? compactListMaxWidth,
  }) => MediaCornerPolicy(
    bubbleInset: bubbleInset ?? this.bubbleInset,
    bubbleEdgeInset: bubbleEdgeInset ?? this.bubbleEdgeInset,
    adjacentBubble: adjacentBubble ?? this.adjacentBubble,
    text: text ?? this.text,
    item: item ?? this.item,
    tail: tail ?? this.tail,
    compactListMaxWidth: compactListMaxWidth ?? this.compactListMaxWidth,
  );

  @override
  bool operator ==(Object other) =>
      other is MediaCornerPolicy &&
      other.bubbleInset == bubbleInset &&
      other.bubbleEdgeInset == bubbleEdgeInset &&
      other.adjacentBubble == adjacentBubble &&
      other.text == text &&
      other.item == item &&
      other.tail == tail &&
      other.compactListMaxWidth == compactListMaxWidth;

  @override
  int get hashCode => Object.hash(
    bubbleInset,
    bubbleEdgeInset,
    adjacentBubble,
    text,
    item,
    tail,
    compactListMaxWidth,
  );
}
