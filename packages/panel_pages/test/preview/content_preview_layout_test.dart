/// Where the content preview draws: the reference client's geometry.
///
/// **Seam:** [ContentPreviewLayout] as a pure function of the window.
library;

import 'package:content_model/content_model.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_pages/panel_pages.dart';

void main() {
  const window = Size(800, 600);

  test('a sticker is a square of M / 1.8, centred over the keyboard', () {
    final layout = ContentPreviewLayout(
      window: window,
      padding: EdgeInsets.zero,
      kind: ContentPreviewKind.sticker,
    );

    expect(layout.square.width, closeTo(600 / 1.8, 1e-9));
    expect(layout.square.center.dx, 400);
    expect(layout.square.center.dy, closeTo(200, 1e-9));
    expect(layout.content, layout.square);
    expect(layout.menuTop, closeTo(200 + 300 / 1.8 + 24, 1e-9));
  });

  test('the emoji above makes room and sits 30 above the square', () {
    final layout = ContentPreviewLayout(
      window: window,
      padding: const EdgeInsets.only(top: 24),
      kind: ContentPreviewKind.customEmoji,
      emoji: true,
    );

    const side = 576 / 1.8;
    expect(layout.square.center.dy, closeTo(side / 2 + 24 + 40, 1e-9));
    expect(layout.emoji.top, closeTo(layout.square.top - 30, 1e-9));
    expect(layout.emoji.width, 200);
    expect(layout.emoji.center.dx, 400);
  });

  test('a GIF is M - 40 wide, fitted to its proportions, and moves with its '
      'swipe', () {
    final layout = ContentPreviewLayout(
      window: window,
      padding: EdgeInsets.zero,
      kind: ContentPreviewKind.gif,
      contentSize: const ContentSize(400, 200),
      swipe: -20,
    );

    expect(layout.square.size, const Size(560, 560));
    expect(layout.square.center.dx, 400);
    expect(layout.square.center.dy, closeTo(280 - 20, 1e-9));
    expect(layout.content.size, const Size(560, 280));
    expect(layout.content.center, layout.square.center);
  });

  test('a GIF keeps one extent at every swipe, in a window of fractional '
      'size', () {
    ContentPreviewLayout at(double swipe) => ContentPreviewLayout(
      window: const Size(411.43, 890.29),
      padding: EdgeInsets.zero,
      kind: ContentPreviewKind.gif,
      contentSize: const ContentSize(480, 270),
      swipe: swipe,
    );
    final rest = at(0);

    expect(rest.extent, const Size(371.43, 371.43 * 270 / 480));
    for (var i = 1; i <= 600; i++) {
      final dragged = at(-i / 10);
      expect(dragged.extent, rest.extent);
      expect(
        dragged.content.center.dy,
        closeTo(rest.content.center.dy - i / 10, 1e-9),
      );
    }
  });
}
