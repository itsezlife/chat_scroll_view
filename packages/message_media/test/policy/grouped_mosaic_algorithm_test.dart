/// The default mosaic fills its width on every line: for albums of two to
/// ten boxes, no two boxes overlap, a line's boxes meet at one seam, and the
/// outermost boxes touch both sides of the mosaic, with or without a side
/// button.
library;

import 'dart:ui';

import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';

import '../support/media_scopes.dart';

// Mixed aspects: landscape, portrait, square, a panorama (> 2:1, which forces
// the line solver), a tall strip, small landscape, and squares.
const _mixed = <(int, int)>[
  (1280, 853),
  (720, 1080),
  (900, 900),
  (1600, 600),
  (500, 1400),
  (240, 180),
  (1200, 900),
  (1200, 900),
  (512, 512),
  (512, 512),
];

// Every box the same landscape aspect: the line solver's even case.
const _landscape = <(int, int)>[
  (1280, 853),
  (1280, 853),
  (1280, 853),
  (1280, 853),
  (1280, 853),
  (1280, 853),
  (1280, 853),
  (1280, 853),
  (1280, 853),
  (1280, 853),
];

// Portraits, which allow a second line of four.
const _portrait = <(int, int)>[
  (720, 1080),
  (600, 1000),
  (720, 1080),
  (600, 1000),
  (720, 1080),
  (600, 1000),
  (720, 1080),
  (600, 1000),
  (720, 1080),
  (600, 1000),
];

const _width = 300.0;
const _gap = MediaLayoutMetrics.cellGap;

List<MediaItem> _items(List<(int, int)> sizes, int count) => [
  for (var i = 0; i < count; i++)
    MediaItem(
      id: MediaItemId('p$i'),
      descriptor: ContentDescriptor(
        key: ContentKey.document('p$i'),
        size: ContentSize(sizes[i].$1, sizes[i].$2),
      ),
    ),
];

MosaicArrangement _arrange(
  List<(int, int)> sizes,
  int count, {
  bool hasSideButton = false,
}) {
  final items = _items(sizes, count);
  return const GroupedMosaicAlgorithm().arrange(
    items: items,
    width: _width,
    input: MediaLayoutInput(
      text: MediaScopes.text,
      items: items,
      availableWidth: 400,
      maxContentWidth: _width,
      displaySize: const Size(400, 800),
      hasSideButton: hasSideButton,
      correlation: const ChatCorrelation(chatId: 'chat', scrollId: 'm1'),
    ),
  );
}

void _expectFilled(MosaicArrangement arrangement) {
  final placements = arrangement.placements;
  for (final (i, a) in placements.indexed) {
    for (final b in placements.skip(i + 1)) {
      final overlap = a.rect.intersect(b.rect);
      expect(
        overlap.width > 0.01 && overlap.height > 0.01,
        isFalse,
        reason: '${a.itemId} ${a.rect} overlaps ${b.itemId} ${b.rect}',
      );
    }
  }
  for (final p in placements) {
    if (p.edges.contains(GroupedPositionFlags.left)) {
      expect(p.rect.left, closeTo(0, 0.01), reason: '${p.itemId} left edge');
    }
    if (p.edges.contains(GroupedPositionFlags.right)) {
      expect(
        p.rect.right,
        closeTo(_width, 0.01),
        reason: '${p.itemId} ${p.rect} right edge',
      );
      continue;
    }
    // A box short of the right edge meets a neighbour one seam away.
    final neighbour = placements.where(
      (o) =>
          (o.rect.left - p.rect.right - _gap).abs() < 0.01 &&
          o.rect.top < p.rect.bottom &&
          o.rect.bottom > p.rect.top,
    );
    expect(
      neighbour,
      isNotEmpty,
      reason: '${p.itemId} ${p.rect} has a hole to its right',
    );
  }
  var area = 0.0;
  for (final p in placements) {
    area += p.rect.width * p.rect.height;
  }
  // Seams are one pixel; anything more is a hole.
  expect(
    area,
    greaterThan(arrangement.size.width * arrangement.size.height * 0.97),
  );
}

void main() {
  group('GroupedMosaicAlgorithm fills every line', () {
    for (final (name, sizes) in [
      ('mixed', _mixed),
      ('landscape', _landscape),
      ('portrait', _portrait),
    ]) {
      for (var count = 2; count <= 10; count++) {
        test('$count $name boxes', () {
          _expectFilled(_arrange(sizes, count));
        });
        test('$count $name boxes beside a side button', () {
          _expectFilled(_arrange(sizes, count, hasSideButton: true));
        });
      }
    }
  });
}
