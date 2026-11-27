/// The desktop family's mosaic: the traced cases as frames, scaling, the
/// slot on the desktop policy, square inner corners and the diagnostics.
library;

import 'dart:ui';

import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';

MediaItem _photo(String id, (int, int)? size) => MediaItem(
  id: MediaItemId(id),
  kind: MediaItemKind.photo,
  descriptor: ContentDescriptor(
    key: ContentKey.document(id),
    fileName: 'secret-$id.jpg',
    size: switch (size) {
      (final w, final h) => ContentSize(w, h),
      null => null,
    },
  ),
);

List<MediaItem> _album(List<(int, int)?> sizes) => [
  for (final (index, size) in sizes.indexed) _photo('i$index', size),
];

MediaLayoutInput _input(
  List<MediaItem> items, {
  double availableWidth = 430,
  MediaCaptionPosition captionPosition = MediaCaptionPosition.none,
  bool joinedBelow = false,
}) => MediaLayoutInput(
  items: items,
  availableWidth: availableWidth,
  captionPosition: captionPosition,
  joinedBelow: joinedBelow,
  chrome: const MediaLayoutChrome(bubbleRadius: 16),
  correlation: const ChatCorrelation(chatId: 'chat', scrollId: 'm1'),
);

/// The edges of a bit set: 1 left, 2 right, 4 top, 8 bottom.
GroupedPositionFlags _edges(int bits) => GroupedPositionFlags.values.fold(
  GroupedPositionFlags.none,
  (edges, flag) => bits & (1 << GroupedPositionFlags.values.indexOf(flag)) == 0
      ? edges
      : edges | flag,
);

MediaCornerRadii _radii(double tl, double tr, double bl, double br) =>
    MediaCornerRadii(
      topLeft: tl,
      topRight: tr,
      bottomLeft: bl,
      bottomRight: br,
    );

typedef _Case = ({
  String name,
  List<(int, int)> sizes,
  double width,
  Size size,
  List<(int, int, int, int, int)> cells,
});

/// Frames traced through the family's grouped layout: left, top,
/// width, height and edge bits per item.
const List<_Case> _cases = [
  (
    name: 'two square',
    sizes: [(1000, 1000), (1200, 1100)],
    width: 430,
    size: Size(430, 195),
    cells: [(0, 0, 213, 195, 13), (217, 0, 213, 195, 14)],
  ),
  (
    name: 'two wide alike stacked',
    sizes: [(1600, 800), (1500, 750)],
    width: 430,
    size: Size(430, 430),
    cells: [(0, 0, 430, 213, 7), (0, 217, 430, 213, 11)],
  ),
  (
    name: 'two wide side by side',
    sizes: [(1300, 1000), (1900, 1000)],
    width: 430,
    size: Size(430, 112),
    cells: [(0, 0, 213, 112, 13), (217, 0, 213, 112, 14)],
  ),
  (
    name: 'two narrow and wide',
    sizes: [(600, 1000), (1600, 900)],
    width: 430,
    size: Size(430, 155),
    cells: [(0, 0, 150, 155, 13), (154, 0, 276, 155, 14)],
  ),
  (
    name: 'three narrow first',
    sizes: [(600, 1000), (1000, 1000), (1600, 900)],
    width: 430,
    size: Size(430, 430),
    cells: [
      (0, 0, 213, 430, 13),
      (217, 0, 213, 273, 6),
      (217, 277, 213, 153, 10),
    ],
  ),
  (
    name: 'three wide first',
    sizes: [(1600, 900), (1000, 1000), (600, 1000)],
    width: 430,
    size: Size(430, 430),
    cells: [
      (0, 0, 430, 242, 7),
      (0, 246, 213, 184, 9),
      (217, 246, 213, 184, 10),
    ],
  ),
  (
    name: 'four wide first',
    sizes: [(1600, 900), (1000, 1000), (600, 1000), (1600, 900)],
    width: 430,
    size: Size(430, 371),
    cells: [
      (0, 0, 430, 242, 7),
      (0, 246, 125, 125, 9),
      (129, 246, 75, 125, 8),
      (208, 246, 222, 125, 10),
    ],
  ),
  (
    name: 'four narrow first',
    sizes: [(600, 1000), (1600, 900), (1000, 1000), (600, 1000)],
    width: 430,
    size: Size(391, 430),
    cells: [
      (0, 0, 256, 430, 13),
      (260, 0, 131, 74, 6),
      (260, 78, 131, 131, 2),
      (260, 213, 131, 217, 10),
    ],
  ),
  (
    name: 'three with a panorama',
    sizes: [(3000, 1000), (1000, 1000), (600, 1000)],
    width: 430,
    size: Size(430, 548),
    cells: [(0, 0, 312, 114, 5), (316, 0, 114, 114, 6), (0, 118, 430, 430, 11)],
  ),
  (
    name: 'five mixed',
    sizes: [(1600, 900), (600, 1000), (1000, 1000), (1600, 900), (900, 1600)],
    width: 430,
    size: Size(430, 616),
    cells: [
      (0, 0, 430, 242, 7),
      (0, 246, 213, 213, 1),
      (217, 246, 213, 213, 2),
      (0, 463, 273, 153, 9),
      (277, 463, 153, 153, 10),
    ],
  ),
  (
    name: 'ten mixed',
    sizes: [
      (1600, 900),
      (600, 1000),
      (1000, 1000),
      (1600, 900),
      (900, 1600),
      (1000, 1000),
      (1600, 900),
      (600, 1000),
      (1200, 900),
      (900, 1200),
    ],
    width: 430,
    size: Size(430, 572),
    cells: [
      (0, 0, 273, 153, 5),
      (277, 0, 153, 153, 6),
      (0, 157, 112, 112, 1),
      (116, 157, 199, 112, 0),
      (319, 157, 111, 112, 2),
      (0, 273, 112, 112, 1),
      (116, 273, 199, 112, 0),
      (319, 273, 111, 112, 2),
      (0, 389, 243, 183, 9),
      (247, 389, 183, 183, 10),
    ],
  ),
  (
    name: 'three wide first at 300',
    sizes: [(1600, 900), (1000, 1000), (600, 1000)],
    width: 300,
    size: Size(300, 300),
    cells: [
      (0, 0, 300, 169, 7),
      (0, 172, 148, 128, 9),
      (151, 172, 149, 128, 10),
    ],
  ),
  (
    name: 'ten mixed at 300',
    sizes: [
      (1600, 900),
      (600, 1000),
      (1000, 1000),
      (1600, 900),
      (900, 1600),
      (1000, 1000),
      (1600, 900),
      (600, 1000),
      (1200, 900),
      (900, 1200),
    ],
    width: 300,
    size: Size(300, 399),
    cells: [
      (0, 0, 190, 107, 5),
      (193, 0, 107, 107, 6),
      (0, 110, 78, 77, 1),
      (81, 110, 139, 77, 0),
      (223, 110, 77, 77, 2),
      (0, 190, 78, 78, 1),
      (81, 190, 139, 78, 0),
      (223, 190, 77, 78, 2),
      (0, 271, 169, 128, 9),
      (172, 271, 128, 128, 10),
    ],
  ),
];

const _algorithm = DesktopMosaicAlgorithm();
const _desktop = MessageMediaPolicy.desktop();

void main() {
  group('traced cases', () {
    for (final c in _cases) {
      test(c.name, () {
        final items = _album(c.sizes);
        final arrangement = _algorithm.arrange(
          items: items,
          width: c.width,
          input: _input(items),
        );
        expect(arrangement.size, c.size);
        expect(
          arrangement.placements.map((p) => p.itemId),
          items.map((item) => item.id),
          reason: 'every item in exactly one cell, in item order',
        );
        for (final (index, (l, t, w, h, bits)) in c.cells.indexed) {
          final placement = arrangement.placements[index];
          expect(
            placement.rect,
            Rect.fromLTWH(
              l.toDouble(),
              t.toDouble(),
              w.toDouble(),
              h.toDouble(),
            ),
            reason: 'item $index',
          );
          expect(placement.edges, _edges(bits), reason: 'item $index');
        }
      });
    }
  });

  group('scaling', () {
    final sizes = <(int, int)>[(1600, 900), (1000, 1000), (600, 1000)];

    test('the album is never scaled up', () {
      final items = _album(sizes);
      final wide = _algorithm.arrange(
        items: items,
        width: 900,
        input: _input(items),
      );
      final own = _algorithm.arrange(
        items: items,
        width: 430,
        input: _input(items),
      );
      expect(wide.size, own.size);
      expect(wide.placements, own.placements);
    });

    test('seams stay aligned between boxes at any width', () {
      for (var width = 120.0; width <= 430; width += 7) {
        final items = _album([
          ...sizes,
          (1600, 900),
          (900, 1600),
          (1000, 1000),
          (1200, 900),
        ]);
        final arrangement = _algorithm.arrange(
          items: items,
          width: width,
          input: _input(items),
        );
        for (final p in arrangement.placements) {
          if (p.edges.hasRight) {
            expect(p.rect.right, arrangement.size.width, reason: '$width');
          }
          if (p.edges.hasLeft) expect(p.rect.left, 0, reason: '$width');
        }
      }
    });

    test('an extreme ratio never gives a negative box', () {
      final items = _album([(1500, 1000), (1, 100), (1, 100), (2000, 1000)]);
      final arrangement = _algorithm.arrange(
        items: items,
        width: 430,
        input: _input(items),
      );
      expect(arrangement.placements, hasLength(4));
      for (final p in arrangement.placements) {
        expect(p.rect.width, greaterThanOrEqualTo(0));
        expect(p.rect.height, greaterThanOrEqualTo(0));
      }
    });

    test('an item without dimensions counts as a square', () {
      final unknown = _algorithm.arrange(
        items: _album([null, (1000, 1000)]),
        width: 430,
        input: _input(const []),
      );
      final square = _algorithm.arrange(
        items: _album([(1000, 1000), (1000, 1000)]),
        width: 430,
        input: _input(const []),
      );
      expect(
        unknown.placements.map((p) => p.rect),
        square.placements.map((p) => p.rect),
      );
    });
  });

  group('the desktop policy', () {
    test('albums go through the desktop mosaic', () {
      expect(
        (_desktop.layoutStep as MediaLayoutPolicy).mosaicAlgorithm,
        const DesktopMosaicAlgorithm(),
      );
      expect(_algorithm.name, 'desktop');
      expect(
        _algorithm.copyWith(spacing: 2),
        const DesktopMosaicAlgorithm(spacing: 2),
      );
    });

    test('the block takes the arrangement at the bubble width', () {
      final items = _album([(1600, 900), (1000, 1000), (600, 1000)]);
      final layout = _desktop.layout(_input(items, availableWidth: 300));
      final block = layout.blocks.single;
      expect(block.rect, const Rect.fromLTWH(0, 0, 300, 300));
      expect(block.cells.map((cell) => cell.rect), [
        const Rect.fromLTWH(0, 0, 300, 169),
        const Rect.fromLTWH(0, 172, 148, 128),
        const Rect.fromLTWH(151, 172, 149, 128),
      ]);
    });

    test('corners between boxes are square, outer corners the bubble', () {
      // Joined below, so the bottom corners show the bubble's own rounding
      // (the sender's corner the joined 6) rather than the square tail.
      final items = _album([(1600, 900), (1000, 1000), (600, 1000)]);
      final radii = [
        for (final cell
            in _desktop.layout(_input(items, joinedBelow: true)).cells)
          cell.radii,
      ];
      expect(radii, [
        _radii(16, 16, 0, 0),
        _radii(0, 0, 6, 0),
        _radii(0, 0, 0, 16),
      ]);
      expect(
        const MediaCornerPolicy.desktop().item,
        const MediaListRadius.all(0),
      );
    });

    test('a caption below squares the bottom corners', () {
      final items = _album([(1000, 1000), (1000, 1000)]);
      final radii = [
        for (final cell
            in _desktop
                .layout(
                  _input(items, captionPosition: MediaCaptionPosition.below),
                )
                .cells)
          cell.radii,
      ];
      expect(radii, [_radii(16, 0, 0, 0), _radii(0, 16, 0, 0)]);
    });
  });

  group('diagnostics', () {
    test('layoutComputed names the desktop mosaic', () {
      final recorder = RecordingDiagnostics.install();
      _desktop.layout(_input(_album([(1000, 1000), (1600, 900)])));
      final event = recorder.whereOp(MediaOp.layoutComputed).single;
      expect(
        event,
        isChatEvent(
          level: ChatEventLevel.trace,
          category: ChatEventCategory.media,
          correlation: const ChatCorrelation(chatId: 'chat', scrollId: 'm1'),
        ),
      );
      expect(event.fields, containsPair('mosaicAlgorithm', 'desktop'));
      expect(event.fields, containsPair('items', 2));
    });

    test('an album item without dimensions reports layoutFallback', () {
      final recorder = RecordingDiagnostics.install();
      _desktop.layout(_input(_album([null, (1000, 1000)])));
      final event = recorder.whereOp(MediaOp.layoutFallback).single;
      expect(event.level, ChatEventLevel.debug);
      expect(event.correlation.mediaItemId, const MediaItemId('i0').toString());
      expect(
        event.fields,
        containsPair('rule', MediaLayoutFallbackRule.noDimensions),
      );
    });

    test('no event carries user content', () {
      final recorder = RecordingDiagnostics.install();
      _desktop.layout(
        _input(_album([null, (1000, 1000), (600, 1000), (1600, 900)])),
      );
      expect(recorder.events, isNotEmpty);
      for (final event in recorder.events) {
        for (final value in event.fields.values) {
          expect('$value', isNot(contains('secret')));
        }
      }
    });
  });
}
