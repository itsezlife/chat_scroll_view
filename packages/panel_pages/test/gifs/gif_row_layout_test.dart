/// The justified rows of the GIF page: which clips share a row and how wide
/// each is.
///
/// **Seam:** [GifRowLayout.of], over the sizes of clips and a width. The
/// expected spans are worked by hand (100 spans, a preferred row of
/// 100, the last row stretched to full width), with the arithmetic in each
/// test.
library;

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:panel_pages/panel_pages.dart';

const _square = Size(100, 100);
const _wide = Size(1600, 900);
const _tall = Size(300, 600);

List<List<int>> _indices(List<GifRow> rows) => [
  for (final row in rows) [for (final cell in row.cells) cell.index],
];

void main() {
  test('is empty for no clips', () {
    expect(GifRowLayout.of(const [], width: 400), isEmpty);
  });

  test('puts squares four to a row at 400 wide: 100 * (100 / 400) is 25 spans '
      'each', () {
    final rows = GifRowLayout.of(List.filled(8, _square), width: 400);

    expect(_indices(rows), [
      [0, 1, 2, 3],
      [4, 5, 6, 7],
    ]);
    // 25 spans of 400 is 100 px, less the 2 px gap after all but the last.
    expect(rows.first.cells.map((cell) => cell.width), [98, 98, 98, 100]);
    expect(rows.first.cells.map((cell) => cell.left), [0, 100, 200, 300]);
  });

  test('stretches the last row to the full width', () {
    final rows = GifRowLayout.of(List.filled(5, _square), width: 400);

    // The fifth takes the 75 spans the row has left: the whole width.
    expect(_indices(rows), [
      [0, 1, 2, 3],
      [4],
    ]);
    expect(rows.last.cells.single.width, 400);
    expect(rows.last.cells.single.left, 0);
  });

  test('stretches a short last row by sharing the spans left, the last clip '
      'taking the remainder', () {
    // A wide clip needs floor(100 * 1.7778 * 100 / 400) = 44 spans. Three
    // squares (25 each) and a wide one (44) do not fit in 100: the row of
    // three has 25 left, shared 8 each with the last taking 9.
    final rows = GifRowLayout.of([
      _square,
      _square,
      _square,
      _wide,
    ], width: 400);

    expect(_indices(rows), [
      [0, 1, 2],
      [3],
    ]);
    // 25 + 8, 25 + 8, 25 + 9 spans: 33, 33 and 34 of 400, so cells end at
    // 132 - 2, 264 - 2 and 400 (the last has no gap after it).
    expect(rows.first.cells.map((cell) => cell.left + cell.width), [
      closeTo(130, .001),
      closeTo(262, .001),
      closeTo(400, .001),
    ]);
  });

  test('puts two wide clips in a row and shares the 12 spans left between '
      'them', () {
    final rows = GifRowLayout.of([_wide, _wide, _wide], width: 400);

    // 44 + 44 = 88 and a third needs 44 with 12 left (12 < 44 - 15): a new
    // row. The 12 are shared 6 and 6: 50 spans each.
    expect(_indices(rows), [
      [0, 1],
      [2],
    ]);
    expect(rows.first.cells.map((cell) => cell.left), [0, 200]);
    expect(rows.first.cells.first.width, 198);
    expect(rows.last.cells.single.width, 400);
  });

  test('lets a clip squeeze into a row when little is missing', () {
    // A wide one needs 44. After a wide one and a tall one (floor(100 * .5 *
    // .25) = 12) 44 are left: it fits exactly.
    final rows = GifRowLayout.of([_wide, _tall, _wide], width: 400);

    expect(_indices(rows), [
      [0, 1, 2],
    ]);
  });

  test('takes a clip beyond 4:1 or below 1:5 for a square of its longer '
      'side', () {
    const strip = Size(1000, 100);
    const sliver = Size(40, 400);

    expect(
      _indices(GifRowLayout.of([strip, strip, strip, strip], width: 400)),
      _indices(
        GifRowLayout.of(List.filled(4, const Size(1000, 1000)), width: 400),
      ),
    );
    expect(
      _indices(GifRowLayout.of([sliver, sliver, sliver, sliver], width: 400)),
      [
        [0, 1, 2, 3],
      ],
    );
  });

  test('takes a side of 0 for 100', () {
    expect(
      _indices(GifRowLayout.of(const [Size.zero, Size.zero], width: 400)),
      [
        [0, 1],
      ],
    );
  });

  test('is 100 tall a row with 2 px above it', () {
    final rows = GifRowLayout.of(List.filled(4, _square), width: 400);

    expect(GifRowLayout.rowExtent, 100);
    expect(GifRowLayout.gap, 2);
    expect(rows.single.height, 102);
  });

  test('puts every clip in a row exactly once, in order', () {
    final sizes = [
      for (var i = 0; i < 40; i++)
        Size(100.0 + (i * 37) % 300, 100.0 + (i * 53) % 200),
    ];

    final rows = GifRowLayout.of(sizes, width: 360);

    expect(
      [for (final row in rows) ...row.cells.map((cell) => cell.index)],
      [for (var i = 0; i < 40; i++) i],
    );
    for (final row in rows) {
      expect(row.cells.last.left + row.cells.last.width, closeTo(360, .001));
    }
  });

  group('grouped at a width of its own', () {
    test('keeps every row\'s clips at any width and scales the cells', () {
      final sizes = [
        for (var i = 0; i < 12; i++) Size(100.0 + 37 * (i % 4), 100),
      ];
      final at = GifRowLayout.of(sizes, width: 334, groupWidth: 334);
      for (final width in [300.0, 420.0, 520.0]) {
        final rows = GifRowLayout.of(sizes, width: width, groupWidth: 334);
        expect(
          [
            for (final row in rows) [for (final c in row.cells) c.index],
          ],
          [
            for (final row in at) [for (final c in row.cells) c.index],
          ],
        );
        for (final (r, row) in rows.indexed) {
          for (final (c, cell) in row.cells.indexed) {
            final was = at[r].cells[c];
            expect(cell.left, closeTo(was.left * width / 334, 1e-9));
          }
        }
      }
    });

    test('decodes a clip for its own proportions at the row height', () {
      expect(
        GifRowLayout.decodeBoxOf(const Size(200, 100)),
        const Size(200, 100),
      );
      expect(GifRowLayout.decodeBoxOf(null), const Size(100, 100));
      // Beyond 4:1 a clip is the square of its longer side.
      expect(
        GifRowLayout.decodeBoxOf(const Size(500, 100)),
        const Size(100, 100),
      );
    });
  });
}
