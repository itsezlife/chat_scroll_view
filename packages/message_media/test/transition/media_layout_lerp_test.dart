/// `MediaLayout.lerp`: cells matched by item interpolate, the rest enter or
/// exit, blocks and the size follow.
library;

import 'dart:ui';

import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';

MediaCell _cell(
  String id,
  Rect rect, {
  MediaItemKind kind = MediaItemKind.photo,
  MediaFit? fit = const MediaFit.crop(),
  MediaCornerRadii radii = MediaCornerRadii.zero,
}) => MediaCell(
  itemId: MediaItemId(id),
  kind: kind,
  rect: rect,
  fit: fit,
  neighbours: MediaNeighbours.bubble,
  radii: radii,
);

MediaLayout _layout(
  List<MediaCell> cells, {
  Size? size,
  MediaWidthMetrics? metrics,
  Rect? timePill,
}) {
  final bounds = cells
      .map((cell) => cell.rect)
      .reduce((a, b) => a.expandToInclude(b));
  return MediaLayout(
    size: size ?? bounds.size,
    blocks: [MediaBlock.mosaic(rect: bounds, cells: cells)],
    widthMetrics: metrics,
    timePill: timePill,
  );
}

void main() {
  const a = MediaItemId('a');
  const b = MediaItemId('b');

  test('a cell in both interpolates its rect and each corner', () {
    final from = _layout([
      _cell(
        'a',
        const Rect.fromLTWH(0, 0, 100, 100),
        radii: const MediaCornerRadii(
          topLeft: 10,
          topRight: 10,
          bottomLeft: 4,
          bottomRight: 4,
        ),
      ),
    ]);
    final to = _layout([
      _cell(
        'a',
        const Rect.fromLTWH(0, 0, 200, 150),
        radii: const MediaCornerRadii(
          topLeft: 20,
          topRight: 0,
          bottomLeft: 4,
          bottomRight: 12,
        ),
      ),
    ]);

    final mid = MediaLayout.lerp(from, to, 0.5);

    final cell = mid.cellOf(a)!;
    expect(cell.rect, const Rect.fromLTWH(0, 0, 150, 125));
    expect(
      cell.radii,
      const MediaCornerRadii(
        topLeft: 15,
        topRight: 5,
        bottomLeft: 4,
        bottomRight: 8,
      ),
    );
    expect(mid.size, const Size(150, 125));
    expect(mid.blocks.single.rect, const Rect.fromLTWH(0, 0, 150, 125));
    expect(mid.exiting, isEmpty);
  });

  test('without radii the corners snap to the new layout', () {
    final from = _layout([
      _cell(
        'a',
        const Rect.fromLTWH(0, 0, 100, 100),
        radii: const MediaCornerRadii.all(10),
      ),
    ]);
    final to = _layout([
      _cell(
        'a',
        const Rect.fromLTWH(0, 0, 200, 100),
        radii: const MediaCornerRadii.all(2),
      ),
    ]);

    final mid = MediaLayout.lerp(from, to, 0.5, radii: false);

    expect(mid.cellOf(a)!.radii, const MediaCornerRadii.all(2));
    expect(mid.cellOf(a)!.rect.width, 150);
  });

  test('fit and kind snap to the new layout', () {
    final from = _layout([_cell('a', const Rect.fromLTWH(0, 0, 100, 100))]);
    final to = _layout([
      _cell(
        'a',
        const Rect.fromLTWH(0, 0, 100, 50),
        kind: MediaItemKind.video,
        fit: const MediaFit.blurFit(),
      ),
    ]);

    final early = MediaLayout.lerp(from, to, 0.1).cellOf(a)!;

    expect(early.kind, MediaItemKind.video);
    expect(early.fit, const MediaFit.blurFit());
  });

  test('a cell only in the new layout sits at its new rect', () {
    final from = _layout([_cell('a', const Rect.fromLTWH(0, 0, 100, 100))]);
    final to = _layout([
      _cell('a', const Rect.fromLTWH(0, 0, 100, 100)),
      _cell('b', const Rect.fromLTWH(0, 100, 100, 50)),
    ]);

    final mid = MediaLayout.lerp(from, to, 0.3);

    expect(mid.cellOf(b)!.rect, const Rect.fromLTWH(0, 100, 100, 50));
  });

  test('a cell only in the old layout exits at its last rect', () {
    final from = _layout([
      _cell('a', const Rect.fromLTWH(0, 0, 100, 100)),
      _cell('b', const Rect.fromLTWH(0, 100, 100, 50)),
    ]);
    final to = _layout([_cell('a', const Rect.fromLTWH(0, 0, 100, 150))]);

    final mid = MediaLayout.lerp(from, to, 0.5);

    expect(mid.cellOf(b), isNull, reason: 'an exiting cell is not laid out');
    expect(mid.cells.map((cell) => cell.itemId), [a]);
    expect(mid.exiting.single.itemId, b);
    expect(mid.exiting.single.rect, const Rect.fromLTWH(0, 100, 100, 50));
    expect(MediaLayout.lerp(from, to, 1).exiting.single.itemId, b);
  });

  test('an exiting cell back in the new layout moves from its exit rect', () {
    final from = _layout([
      _cell('a', const Rect.fromLTWH(0, 0, 100, 100)),
    ]).withExiting([_cell('b', const Rect.fromLTWH(0, 100, 100, 100))]);
    final to = _layout([
      _cell('a', const Rect.fromLTWH(0, 0, 100, 100)),
      _cell('b', const Rect.fromLTWH(100, 0, 100, 100)),
    ]);

    final mid = MediaLayout.lerp(from, to, 0.5);

    expect(mid.cellOf(b)!.rect, const Rect.fromLTWH(50, 50, 100, 100));
    expect(mid.exiting, isEmpty);
  });

  test('width metrics and the time pill interpolate; the rule snaps', () {
    final from = _layout(
      [_cell('a', const Rect.fromLTWH(0, 0, 100, 100))],
      metrics: const MediaWidthMetrics(
        rule: MediaCaptionWidthRule.widenMedia,
        captionMaxWidth: 100,
      ),
      timePill: const Rect.fromLTWH(50, 80, 40, 16),
    );
    final to = _layout(
      [_cell('a', const Rect.fromLTWH(0, 0, 200, 100))],
      metrics: const MediaWidthMetrics(
        rule: MediaCaptionWidthRule.wrapAtMedia,
        captionMaxWidth: 200,
      ),
      timePill: const Rect.fromLTWH(150, 80, 40, 16),
    );

    final mid = MediaLayout.lerp(from, to, 0.5);

    expect(
      mid.widthMetrics,
      const MediaWidthMetrics(
        rule: MediaCaptionWidthRule.wrapAtMedia,
        captionMaxWidth: 150,
      ),
    );
    expect(mid.timePill, const Rect.fromLTWH(100, 80, 40, 16));

    final noPill = _layout([_cell('a', const Rect.fromLTWH(0, 0, 200, 100))]);
    expect(MediaLayout.lerp(from, noPill, 0.5).timePill, isNull);
    expect(MediaLayout.lerp(noPill, to, 0.5).timePill, to.timePill);
  });

  test('a link preview card interpolates its rect from the old card', () {
    final page = LinkPreview(url: Uri.parse('https://example.com/a'));
    MediaLayout card(Rect rect) => MediaLayout(
      size: rect.size,
      blocks: [MediaBlock.linkPreview(rect: rect, page: page)],
    );

    final mid = MediaLayout.lerp(
      card(const Rect.fromLTWH(0, 0, 200, 60)),
      card(const Rect.fromLTWH(0, 0, 200, 160)),
      0.5,
    );

    expect(mid.blocks.single.rect, const Rect.fromLTWH(0, 0, 200, 110));
  });

  test('a block without a match takes its new rect', () {
    final from = _layout([_cell('a', const Rect.fromLTWH(0, 0, 100, 100))]);
    final to = MediaLayout(
      size: const Size(100, 160),
      blocks: [
        from.blocks.single,
        MediaBlock.fileStack(
          rect: const Rect.fromLTWH(0, 100, 100, 60),
          cells: [
            _cell(
              'f',
              const Rect.fromLTWH(0, 100, 100, 60),
              kind: MediaItemKind.file,
              fit: null,
            ),
          ],
        ),
      ],
    );

    final mid = MediaLayout.lerp(from, to, 0.5);

    expect(mid.blocks[1].rect, const Rect.fromLTWH(0, 100, 100, 60));
    expect(mid.size, const Size(100, 130));
  });
}
