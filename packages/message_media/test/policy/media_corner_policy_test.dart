/// The corner rule: radii from each side's neighbour, per platform.
library;

import 'dart:math' as math;
import 'dart:ui';

import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';

import '../support/media_scopes.dart';

/// One platform's expected values, written out as numbers.
typedef _Values = ({
  MediaCornerPolicy policy,
  double edge,
  double joined,
  double text,
  double item,
});

const _bubbleRadius = 17.0;

final _platforms = <String, _Values>{
  'android': (
    policy: const MediaCornerPolicy.android(),
    edge: 15,
    joined: 3,
    text: 4,
    item: 4,
  ),
  'ios compact': (
    policy: const MediaCornerPolicy.ios(),
    edge: 16,
    joined: 7,
    text: 0,
    item: 0,
  ),
  'desktop': (
    policy: const MediaCornerPolicy.desktop(),
    edge: 17,
    joined: 6,
    text: 0,
    item: 0,
  ),
};

MediaLayoutInput _input({
  bool outgoing = false,
  MediaCaptionPosition caption = MediaCaptionPosition.none,
  bool joinedBelow = false,
  double width = 400,
  double bubbleRadius = _bubbleRadius,
}) => MediaLayoutInput(
  text: MediaScopes.text,
  items: const [],
  availableWidth: width,
  isOutgoing: outgoing,
  captionPosition: caption,
  joinedBelow: joinedBelow,
  chrome: MediaLayoutChrome(bubbleRadius: bubbleRadius),
);

MediaCell _cell(MediaNeighbours neighbours) => MediaCell(
  itemId: const MediaItemId('a'),
  kind: MediaItemKind.photo,
  rect: const Rect.fromLTWH(0, 0, 100, 100),
  neighbours: neighbours,
);

void main() {
  group('every neighbour combination, before the tail rule', () {
    for (final MapEntry(key: name, value: v) in _platforms.entries) {
      for (final outgoing in [false, true]) {
        test('$name, ${outgoing ? 'outgoing' : 'incoming'}', () {
          // No tail anywhere: the plain neighbour rule.
          final policy = v.policy.copyWith(tail: MediaTailRule.none);
          final input = _input(outgoing: outgoing);
          double? inner(MediaNeighbour side) => switch (side) {
            MediaNeighbour.text => v.text,
            MediaNeighbour.item => v.item,
            _ => null,
          };
          double expected(
            MediaNeighbour horizontal,
            MediaNeighbour vertical, {
            required bool left,
          }) {
            final inners = [?inner(horizontal), ?inner(vertical)];
            if (inners.isNotEmpty) return inners.reduce(math.min);
            final senderSide = left != outgoing;
            if (vertical == MediaNeighbour.adjacentBubble ||
                (horizontal == MediaNeighbour.adjacentBubble && senderSide)) {
              return v.joined;
            }
            return v.edge;
          }

          for (final top in MediaNeighbour.values) {
            for (final bottom in MediaNeighbour.values) {
              for (final left in MediaNeighbour.values) {
                for (final right in MediaNeighbour.values) {
                  final n = MediaNeighbours(
                    top: top,
                    bottom: bottom,
                    left: left,
                    right: right,
                  );
                  expect(
                    policy.radiiOf(_cell(n), input),
                    MediaCornerRadii(
                      topLeft: expected(top, left, left: true),
                      topRight: expected(top, right, left: false),
                      bottomLeft: expected(bottom, left, left: true),
                      bottomRight: expected(bottom, right, left: false),
                    ),
                    reason: '$n',
                  );
                }
              }
            }
          }
        });
      }
    }
  });

  group('the rule', () {
    test('a lone box in a media-only bubble takes the bubble-edge radius '
        'on every corner', () {
      for (final v in _platforms.values) {
        expect(
          v.policy
              .copyWith(tail: MediaTailRule.none)
              .radiiOf(_cell(MediaNeighbours.bubble), _input()),
          MediaCornerRadii.all(v.edge),
        );
      }
    });

    test('a joined side rounds only its corner on the sender\'s side', () {
      const policy = MediaCornerPolicy.android();
      const joinedTop = MediaNeighbours(
        top: MediaNeighbour.adjacentBubble,
        bottom: MediaNeighbour.bubbleEdge,
        left: MediaNeighbour.bubbleEdge,
        right: MediaNeighbour.bubbleEdge,
      );
      final incoming = policy.radiiOf(_cell(joinedTop), _input());
      expect((incoming.topLeft, incoming.topRight), (3, 15));
      final outgoing = policy.radiiOf(_cell(joinedTop), _input(outgoing: true));
      expect((outgoing.topLeft, outgoing.topRight), (15, 3));
    });

    test('inner radii never exceed the bubble-edge radius', () {
      const policy = MediaCornerPolicy.android();
      final radii = policy.radiiOf(
        _cell(
          const MediaNeighbours(
            top: MediaNeighbour.text,
            bottom: MediaNeighbour.item,
            left: MediaNeighbour.adjacentBubble,
            right: MediaNeighbour.bubbleEdge,
          ),
        ),
        _input(bubbleRadius: 2),
      );
      // A bubble radius of 2 is not over the inset: the edge is 2.
      expect(radii, const MediaCornerRadii.all(2));
    });

    test('the bubble-edge radius per platform', () {
      expect(const MediaCornerPolicy.android().bubbleEdgeOf(17), 15);
      expect(const MediaCornerPolicy.android().bubbleEdgeOf(2), 2);
      expect(const MediaCornerPolicy.ios().bubbleEdgeOf(16), 15);
      expect(const MediaCornerPolicy.desktop().bubbleEdgeOf(16), 16);
    });

    test('iOS takes its compact values up to 680 and its regular ones '
        'beyond', () {
      const policy = MediaCornerPolicy.ios();
      const captionBelowJoinedAbove = MediaNeighbours(
        top: MediaNeighbour.adjacentBubble,
        bottom: MediaNeighbour.text,
        left: MediaNeighbour.bubbleEdge,
        right: MediaNeighbour.bubbleEdge,
      );
      final compact = policy.radiiOf(
        _cell(captionBelowJoinedAbove),
        _input(width: 680),
      );
      expect(
        compact,
        const MediaCornerRadii(
          topLeft: 7,
          topRight: 16,
          bottomLeft: 0,
          bottomRight: 0,
        ),
      );
      final regular = policy.radiiOf(
        _cell(captionBelowJoinedAbove),
        _input(width: 681),
      );
      expect(
        regular,
        const MediaCornerRadii(
          topLeft: 8,
          topRight: 16,
          bottomLeft: 5,
          bottomRight: 5,
        ),
      );
    });

    test('the per-platform values', () {
      const android = MediaCornerPolicy.android();
      expect(android.bubbleInset, 2);
      expect(android.bubbleEdgeInset, 2);
      expect(android.adjacentBubble, const MediaListRadius.all(3));
      expect(android.text, const MediaListRadius.all(4));
      expect(android.item, const MediaListRadius.all(4));
      expect(android.tail, MediaTailRule.android);
      const ios = MediaCornerPolicy.ios();
      expect(ios.bubbleInset, 2);
      expect(ios.bubbleEdgeInset, 1);
      expect(ios.adjacentBubble, const MediaListRadius(compact: 7, regular: 8));
      expect(ios.text, const MediaListRadius(compact: 0, regular: 5));
      expect(ios.item, const MediaListRadius(compact: 0, regular: 5));
      expect(ios.tail, MediaTailRule.none);
      expect(ios.compactListMaxWidth, 680);
      const desktop = MediaCornerPolicy.desktop();
      expect(desktop.bubbleInset, 0);
      expect(desktop.bubbleEdgeInset, 0);
      expect(desktop.adjacentBubble, const MediaListRadius.all(6));
      expect(desktop.text, const MediaListRadius.all(0));
      expect(desktop.item, const MediaListRadius.all(0));
      expect(desktop.tail, MediaTailRule.desktop);
    });
  });

  group('the tail', () {
    const captionBelow = MediaNeighbours(
      top: MediaNeighbour.bubbleEdge,
      bottom: MediaNeighbour.text,
      left: MediaNeighbour.bubbleEdge,
      right: MediaNeighbour.bubbleEdge,
    );

    test('Android: an incoming bubble with a caption below has bottom '
        'corners 4 and its bottom-left the joined radius', () {
      const policy = MediaCornerPolicy.android();
      expect(
        policy.radiiOf(
          _cell(captionBelow),
          _input(caption: MediaCaptionPosition.below),
        ),
        const MediaCornerRadii(
          topLeft: 15,
          topRight: 15,
          bottomLeft: 3,
          bottomRight: 4,
        ),
      );
      expect(
        policy.radiiOf(
          _cell(captionBelow),
          _input(caption: MediaCaptionPosition.below, outgoing: true),
        ),
        const MediaCornerRadii(
          topLeft: 15,
          topRight: 15,
          bottomLeft: 4,
          bottomRight: 4,
        ),
      );
    });

    test('Android: a media-only bubble has no tail', () {
      expect(
        const MediaCornerPolicy.android().radiiOf(
          _cell(MediaNeighbours.bubble),
          _input(),
        ),
        const MediaCornerRadii.all(15),
      );
    });

    test('Android: an album cell off the sender\'s edge keeps its corner', () {
      const policy = MediaCornerPolicy.android();
      const rightCell = MediaNeighbours(
        top: MediaNeighbour.item,
        bottom: MediaNeighbour.text,
        left: MediaNeighbour.item,
        right: MediaNeighbour.bubbleEdge,
      );
      expect(
        policy
            .radiiOf(
              _cell(rightCell),
              _input(caption: MediaCaptionPosition.below),
            )
            .bottomLeft,
        4,
      );
      const upperCell = MediaNeighbours(
        top: MediaNeighbour.bubbleEdge,
        bottom: MediaNeighbour.item,
        left: MediaNeighbour.bubbleEdge,
        right: MediaNeighbour.item,
      );
      expect(
        policy
            .radiiOf(
              _cell(upperCell),
              _input(caption: MediaCaptionPosition.above),
            )
            .bottomLeft,
        4,
      );
    });

    test('desktop: a bubble that ends its group squares its tail corner', () {
      const policy = MediaCornerPolicy.desktop();
      expect(
        policy.radiiOf(_cell(MediaNeighbours.bubble), _input()),
        const MediaCornerRadii(
          topLeft: 17,
          topRight: 17,
          bottomLeft: 0,
          bottomRight: 17,
        ),
      );
      expect(
        policy.radiiOf(_cell(MediaNeighbours.bubble), _input(outgoing: true)),
        const MediaCornerRadii(
          topLeft: 17,
          topRight: 17,
          bottomLeft: 17,
          bottomRight: 0,
        ),
      );
      expect(
        policy.radiiOf(
          _cell(
            const MediaNeighbours(
              top: MediaNeighbour.bubbleEdge,
              bottom: MediaNeighbour.adjacentBubble,
              left: MediaNeighbour.bubbleEdge,
              right: MediaNeighbour.bubbleEdge,
            ),
          ),
          _input(joinedBelow: true),
        ),
        const MediaCornerRadii(
          topLeft: 17,
          topRight: 17,
          bottomLeft: 6,
          bottomRight: 17,
        ),
      );
    });

    test('iOS: the tail corner follows the neighbour rule', () {
      expect(
        const MediaCornerPolicy.ios().radiiOf(
          _cell(captionBelow),
          _input(caption: MediaCaptionPosition.below),
        ),
        const MediaCornerRadii(
          topLeft: 16,
          topRight: 16,
          bottomLeft: 0,
          bottomRight: 0,
        ),
      );
    });
  });

  group('the policy carries numeric radii per cell', () {
    MediaItem photo(String id) => MediaItem(
      id: MediaItemId(id),
      kind: MediaItemKind.photo,
      descriptor: ContentDescriptor(
        key: ContentKey.document(id),
        size: const ContentSize(1, 1),
      ),
    );

    test('an album with a caption below', () {
      final layout = const MessageMediaPolicy.android().layout(
        MediaLayoutInput(
          text: MediaScopes.text,
          items: [photo('a'), photo('b')],
          availableWidth: 375,
          displaySize: const Size(375, 610.5),
          captionPosition: MediaCaptionPosition.below,
        ),
      );
      expect(
        layout.cellOf(const MediaItemId('a'))!.radii,
        const MediaCornerRadii(
          topLeft: 15,
          topRight: 4,
          bottomLeft: 3,
          bottomRight: 4,
        ),
      );
      expect(
        layout.cellOf(const MediaItemId('b'))!.radii,
        const MediaCornerRadii(
          topLeft: 4,
          topRight: 15,
          bottomLeft: 4,
          bottomRight: 4,
        ),
      );
    });

    test('a host layout step still gets its radii resolved', () {
      final cell = _cell(MediaNeighbours.bubble);
      final policy = const MessageMediaPolicy.ios().copyWith(
        layoutStep: _OneCellStep(cell),
      );
      expect(
        policy.layout(_input()).cellOf(cell.itemId)!.radii,
        const MediaCornerRadii.all(16),
      );
    });

    test('a layout whose radii are already resolved is kept as it is', () {
      final layout = const MessageMediaPolicy.android().layout(
        MediaLayoutInput(
          text: MediaScopes.text,
          items: [photo('a')],
          availableWidth: 364,
        ),
      );
      expect(
        const MediaCornerPolicy.android().resolve(
          layout,
          MediaLayoutInput(
            text: MediaScopes.text,
            items: [photo('a')],
            availableWidth: 364,
          ),
        ),
        same(layout),
      );
    });

    test('radii interpolate corner by corner and never go below 0', () {
      const a = MediaCornerRadii.all(4);
      const b = MediaCornerRadii(
        topLeft: 14,
        topRight: 4,
        bottomLeft: 0,
        bottomRight: 8,
      );
      expect(
        MediaCornerRadii.lerp(a, b, 0.5),
        const MediaCornerRadii(
          topLeft: 9,
          topRight: 4,
          bottomLeft: 2,
          bottomRight: 6,
        ),
      );
      expect(MediaCornerRadii.lerp(a, b, 2).bottomLeft, 0);
    });
  });
}

final class _OneCellStep implements MediaLayoutStep {
  const _OneCellStep(this.cell);

  final MediaCell cell;

  @override
  MediaLayout layout(
    MediaLayoutInput input, {
    required MediaFileStackPolicy fileStack,
    required LinkPreviewCardPolicy linkPreview,
  }) => MediaLayout(
    size: cell.rect.size,
    blocks: [
      MediaBlock.mosaic(rect: cell.rect, cells: [cell]),
    ],
  );
}
