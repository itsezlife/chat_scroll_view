/// The iOS mosaic: frames for traced albums of two to ten boxes, the rows
/// fallback, its registration in the iOS policy, the inner item radius and
/// its diagnostics events.
library;

import 'dart:ui';

import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';

import '../support/media_scopes.dart';

/// One expected box: its rect and the mosaic edges it lies on, as letters
/// (`t`op, `b`ottom, `l`eft, `r`ight).
typedef _Frame = ({Rect rect, String edges});

_Frame _f(double left, double top, double width, double height, String e) =>
    (rect: Rect.fromLTWH(left, top, width, height), edges: e);

final class _Case {
  const _Case(
    this.name, {
    required this.listWidth,
    required this.sizes,
    required this.size,
    required this.frames,
    this.contentWidth,
  });

  final String name;
  final double listWidth;
  final double? contentWidth;
  final List<(int, int)> sizes;
  final Size size;
  final List<_Frame> frames;
}

// Expected frames from a line-by-line trace of the reference algorithm,
// computed apart from this implementation. The block width is the list
// class's max width capped by the bubble's content width.
final _cases = [
  _Case(
    'two squares side by side',
    listWidth: 375,
    sizes: [(1, 1), (1, 1)],
    size: const Size(300, 149),
    frames: [_f(0, 0, 149.5, 149, 'tlb'), _f(150.5, 0, 149.5, 149, 'trb')],
  ),
  _Case(
    'two wide stacked',
    listWidth: 375,
    sizes: [(2, 1), (2, 1)],
    size: const Size(300, 301),
    frames: [_f(0, 0, 300, 150, 'tlr'), _f(0, 151, 300, 150, 'blr')],
  ),
  _Case(
    'wide and narrow by aspect',
    listWidth: 375,
    sizes: [(4, 3), (3, 4)],
    size: const Size(300, 143),
    frames: [_f(0, 0, 191, 143, 'tlb'), _f(192, 0, 108, 143, 'trb')],
  ),
  _Case(
    'a panorama forces rows',
    listWidth: 375,
    sizes: [(3, 1), (1, 1)],
    size: const Size(301, 478),
    frames: [_f(0, 0, 301, 177, 'tlr'), _f(0, 178, 301, 300, 'blr')],
  ),
  _Case(
    'three, narrow first: column and stack',
    listWidth: 375,
    sizes: [(3, 4), (1, 1), (4, 3)],
    size: const Size(301, 380),
    frames: [
      _f(0, 0, 150, 380, 'tlb'),
      _f(151, 0, 149.5, 251, 'rt'),
      _f(151, 252, 149.5, 128, 'rb'),
    ],
  ),
  _Case(
    'three, wide first: top and pair',
    listWidth: 375,
    sizes: [(16, 9), (1, 1), (3, 4)],
    size: const Size(300, 319),
    frames: [
      _f(0, 0, 300, 168, 'tlr'),
      _f(0, 169, 149.5, 150, 'lb'),
      _f(150.5, 169, 149.5, 150, 'rb'),
    ],
  ),
  _Case(
    'four, wide first: top and row of three',
    listWidth: 375,
    sizes: [(16, 9), (1, 1), (3, 4), (4, 3)],
    size: const Size(300, 267),
    frames: [
      _f(0, 0, 300, 169, 'tlr'),
      _f(0, 170, 97, 97, 'lb'),
      _f(98, 170, 71.66666666666669, 97, 'b'),
      _f(170.66666666666669, 170, 129.33333333333331, 97, 'rb'),
    ],
  ),
  _Case(
    'four, narrow first: column and stack of three',
    listWidth: 375,
    sizes: [(9, 16), (1, 1), (4, 3), (3, 4)],
    size: const Size(300, 380),
    frames: [
      _f(0, 0, 179, 380, 'tlb'),
      _f(180, 0, 120, 123, 'rt'),
      _f(180, 124, 120, 92, 'r'),
      _f(180, 217, 120, 163, 'rb'),
    ],
  ),
  _Case(
    'five mixed in rows',
    listWidth: 375,
    sizes: [(4, 3), (3, 4), (1, 1), (16, 9), (9, 16)],
    size: const Size(301, 488),
    frames: [
      _f(0, 0, 301, 225, 'tlr'),
      _f(0, 226, 150, 150, 'l'),
      _f(151, 226, 150, 150, 'r'),
      _f(0, 377, 189, 111, 'bl'),
      _f(190, 377, 111, 111, 'br'),
    ],
  ),
  _Case(
    'six portrait in rows',
    listWidth: 375,
    sizes: [(3, 4), (3, 4), (9, 16), (3, 4), (1, 1), (3, 4)],
    size: const Size(303, 259),
    frames: [
      _f(0, 0, 104, 138, 'tl'),
      _f(105, 0, 104, 138, 't'),
      _f(210, 0, 93, 138, 'tr'),
      _f(0, 139, 90, 120, 'bl'),
      _f(91, 139, 120, 120, 'b'),
      _f(212, 139, 91, 120, 'br'),
    ],
  ),
  _Case(
    'seven landscape in rows',
    listWidth: 375,
    sizes: [(16, 9), (4, 3), (16, 9), (3, 2), (4, 3), (16, 9), (1, 1)],
    size: const Size(302, 431),
    frames: [
      _f(0, 0, 108, 63, 'tl'),
      _f(109, 0, 84, 63, 't'),
      _f(194, 0, 108, 63, 'tr'),
      _f(0, 64, 99, 66, 'l'),
      _f(100, 64, 88, 66, ''),
      _f(189, 64, 113, 66, 'r'),
      _f(0, 131, 302, 300, 'blr'),
    ],
  ),
  _Case(
    'ten mixed in rows',
    listWidth: 375,
    sizes: [
      (4, 3),
      (3, 4),
      (1, 1),
      (16, 9),
      (9, 16),
      (4, 3),
      (3, 4),
      (1, 1),
      (16, 9),
      (9, 16),
    ],
    size: const Size(302, 405),
    frames: [
      _f(0, 0, 120, 90, 'tl'),
      _f(121, 0, 90, 90, 't'),
      _f(212, 0, 90, 90, 'tr'),
      _f(0, 91, 189, 111, 'l'),
      _f(190, 91, 112, 111, 'r'),
      _f(0, 203, 120, 90, 'l'),
      _f(121, 203, 90, 90, ''),
      _f(212, 203, 90, 90, 'r'),
      _f(0, 294, 189, 111, 'bl'),
      _f(190, 294, 112, 111, 'br'),
    ],
  ),
  _Case(
    'three on a regular list',
    listWidth: 800,
    sizes: [(16, 9), (1, 1), (3, 4)],
    size: const Size(440, 440),
    frames: [
      _f(0, 0, 440, 247, 'tlr'),
      _f(0, 248, 219.5, 192, 'lb'),
      _f(220.5, 248, 219.5, 192, 'rb'),
    ],
  ),
  _Case(
    'two in a narrow bubble',
    listWidth: 375,
    contentWidth: 250,
    sizes: [(4, 3), (3, 4)],
    size: const Size(250, 119),
    frames: [_f(0, 0, 159, 119, 'tlb'), _f(160, 0, 90, 119, 'trb')],
  ),
  _Case(
    'four, narrow first beside wide ones',
    listWidth: 375,
    sizes: [(9, 16), (2, 1), (2, 1), (2, 1)],
    size: const Size(300, 380),
    frames: [
      _f(0, 0, 179, 380, 'tlb'),
      _f(180, 0, 120, 126, 'rt'),
      _f(180, 127, 120, 126, 'r'),
      _f(180, 254, 120, 126, 'rb'),
    ],
  ),
];

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

List<MediaItem> _photos(List<(int, int)?> sizes) => [
  for (final (index, size) in sizes.indexed) _photo('p$index', size),
];

MediaLayoutInput _input(
  List<MediaItem> items, {
  double listWidth = 375,
  double? contentWidth,
  MediaCaptionPosition captionPosition = MediaCaptionPosition.none,
}) => MediaLayoutInput(
  text: MediaScopes.text,
  items: items,
  availableWidth: listWidth,
  maxContentWidth: contentWidth,
  displaySize: Size(listWidth, 800),
  captionPosition: captionPosition,
  chrome: const MediaLayoutChrome(bubbleRadius: 16),
  correlation: const ChatCorrelation(chatId: 'chat', scrollId: 'm1'),
);

String _edgesOf(GroupedPositionFlags edges) => _sorted(
  [
    if (edges.hasTop) 't',
    if (edges.hasBottom) 'b',
    if (edges.hasLeft) 'l',
    if (edges.hasRight) 'r',
  ].join(),
);

String _sorted(String edges) => (edges.split('')..sort()).join();

Matcher _rectCloseTo(Rect expected) => predicate<Rect>(
  (r) =>
      (r.left - expected.left).abs() < 1e-9 &&
      (r.top - expected.top).abs() < 1e-9 &&
      (r.width - expected.width).abs() < 1e-9 &&
      (r.height - expected.height).abs() < 1e-9,
  'a rect close to $expected',
);

void _expectFrames(MosaicArrangement arrangement, List<_Frame> frames) {
  for (final (index, frame) in frames.indexed) {
    final placement = arrangement.placements[index];
    expect(placement.rect, _rectCloseTo(frame.rect), reason: 'box $index');
    expect(
      _edgesOf(placement.edges),
      _sorted(frame.edges),
      reason: 'edges of box $index',
    );
  }
}

const _ios = MessageMediaPolicy.ios();

void main() {
  group('traced frames', () {
    for (final c in _cases) {
      test('${c.sizes.length} boxes: ${c.name}', () {
        final items = _photos(c.sizes);
        final input = _input(
          items,
          listWidth: c.listWidth,
          contentWidth: c.contentWidth,
        );
        final arrangement = const IosMosaicAlgorithm().arrange(
          items: items,
          width: const MediaBoxSizing.ios().blockWidth(input),
          input: input,
        );
        expect(arrangement.size, c.size);
        expect(
          [for (final p in arrangement.placements) p.itemId],
          [for (final item in items) item.id],
          reason: 'every item in one cell, in item order',
        );
        _expectFrames(arrangement, c.frames);
      });
    }
  });

  group('rows fallback', () {
    test('a pattern that leaves a box no area lays the album in rows', () {
      final items = _photos(const [(16, 9), (1, 5), (1, 5), (2, 1)]);
      final arrangement = const IosMosaicAlgorithm().arrange(
        items: items,
        width: 300,
        input: _input(items),
      );
      // The wide-first pattern would give the second narrow box a width of
      // -18; the rows give every box an area.
      expect(arrangement.size, const Size(302, 259));
      _expectFrames(arrangement, [
        _f(0, 0, 302, 177, 'tlr'),
        _f(0, 178, 81, 81, 'bl'),
        _f(82, 178, 81, 81, 'b'),
        _f(164, 178, 138, 81, 'br'),
      ]);
    });

    test('an item without dimensions is a square', () {
      final input = _input(const []);
      Rect lastOf(List<(int, int)?> sizes) => const IosMosaicAlgorithm()
          .arrange(items: _photos(sizes), width: 300, input: input)
          .placements
          .last
          .rect;

      final square = lastOf(const [(1, 1), (1, 1)]);
      expect(lastOf(const [(1, 1), null]), square);
    });
  });

  group('max mosaic', () {
    const algorithm = IosMosaicAlgorithm();

    test('the list class picks the max size, scaled down to the width', () {
      expect(
        algorithm.maxSizeFor(width: 300, listWidth: 375),
        const Size(300, 380),
      );
      expect(
        algorithm.maxSizeFor(width: 440, listWidth: 800),
        const Size(440, 440),
      );
      expect(
        algorithm.maxSizeFor(width: 250, listWidth: 375),
        const Size(250, 316),
      );
      expect(
        algorithm.maxSizeFor(width: 500, listWidth: 375),
        const Size(300, 380),
        reason: 'never scaled up',
      );
      expect(
        algorithm.maxSizeFor(width: 440, listWidth: 680),
        const Size(300, 380),
        reason: 'a list of 680 is still compact',
      );
    });

    test('copyWith replaces one value and keeps the others', () {
      final changed = algorithm.copyWith(cellGap: 2);
      expect(changed.cellGap, 2);
      expect(changed.compactMaxSize, algorithm.compactMaxSize);
      expect(changed, isNot(algorithm));
      expect(changed.copyWith(cellGap: 1), algorithm);
      expect(algorithm.name, 'ios');
    });
  });

  group('the iOS policy', () {
    test('lays albums with the iOS mosaic and names it', () {
      final step = _ios.layoutStep as MediaLayoutPolicy;
      expect(step.mosaicAlgorithm, const IosMosaicAlgorithm());
      final recorder = RecordingDiagnostics.install();
      _ios.layout(_input(_photos(const [(1, 1), (1, 1)])));
      expect(
        recorder.whereOp(MediaOp.layoutComputed).single.fields,
        containsPair('mosaicAlgorithm', 'ios'),
      );
    });

    test('the Android family keeps its mosaic', () {
      final step =
          const MessageMediaPolicy.android().layoutStep as MediaLayoutPolicy;
      expect(step.mosaicAlgorithm, const GroupedMosaicAlgorithm());
    });

    test('inner corners take the item radius: 0 compact, 5 regular', () {
      expect(
        const MediaCornerPolicy.ios().item,
        const MediaListRadius(compact: 0, regular: 5),
      );
      for (final (listWidth, inner) in const [(375.0, 0.0), (800.0, 5.0)]) {
        final layout = _ios.layout(
          _input(_photos(const [(1, 1), (1, 1)]), listWidth: listWidth),
        );
        final [left, right] = layout.cells.toList();
        // The bubble's radius 16 less the iOS inset of 1 on the bubble edge.
        expect(
          left.radii,
          MediaCornerRadii(
            topLeft: 15,
            topRight: inner,
            bottomLeft: 15,
            bottomRight: inner,
          ),
          reason: 'list $listWidth',
        );
        expect(
          right.radii,
          MediaCornerRadii(
            topLeft: inner,
            topRight: 15,
            bottomLeft: inner,
            bottomRight: 15,
          ),
          reason: 'list $listWidth',
        );
      }
    });

    test('every item of a ten-box album has exactly one cell', () {
      final items = _photos(const [
        (4, 3),
        (3, 4),
        (1, 1),
        (16, 9),
        (9, 16),
        (4, 3),
        (3, 4),
        (1, 1),
        (16, 9),
        (9, 16),
      ]);
      final layout = _ios.layout(_input(items));
      expect(layout.blocks, hasLength(1));
      expect(
        [for (final cell in layout.cells) cell.itemId],
        [for (final item in items) item.id],
      );
    });
  });

  group('diagnostics', () {
    test('the rows fallback reports layoutFallback for the box left with '
        'no area', () {
      final recorder = RecordingDiagnostics.install();
      _ios.layout(_input(_photos(const [(16, 9), (1, 5), (1, 5), (2, 1)])));
      expect(recorder.whereOp(MediaOp.layoutFallback), [
        isChatEvent(
          level: ChatEventLevel.debug,
          category: ChatEventCategory.media,
          correlation: const ChatCorrelation(
            chatId: 'chat',
            scrollId: 'm1',
            mediaItemId: 'item:p2',
          ),
          fields: {
            'rule': MediaLayoutFallbackRule.mosaicRows,
            'width': -18.0,
            'height': 124.0,
          },
        ),
      ]);
    });

    test('an album item without dimensions reports noDimensions', () {
      final recorder = RecordingDiagnostics.install();
      _ios.layout(_input(_photos(const [(4, 3), null])));
      expect(
        recorder
            .whereOp(MediaOp.layoutFallback)
            .map((event) => event.fields['rule']),
        [MediaLayoutFallbackRule.noDimensions],
      );
    });

    test('no event carries user content', () {
      final recorder = RecordingDiagnostics.install();
      _ios
        ..layout(
          _input(
            _photos(const [(16, 9), (1, 5), (1, 5), (2, 1), null]),
            captionPosition: MediaCaptionPosition.below,
          ),
        )
        ..layout(_input(_photos(const [(16, 9), (1, 5), (1, 5), (2, 1)])));
      expect(recorder.events, isNotEmpty);
      for (final event in recorder.events) {
        for (final value in event.fields.values) {
          expect('$value', isNot(contains('secret')));
        }
      }
    });
  });
}
