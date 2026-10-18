/// The edit crossfade of a body that paints on a layer of its own.
///
/// A body whose render object is a repaint boundary (the markdown body is one
/// once it has a selection controller) is composited apart from the canvas the
/// transition paints on, so a canvas-level `saveLayer` fade or `clipRect` does
/// not reach it: the old text lost its fade and its clip. The transition fades
/// and clips through layers instead, so a body looks the same with or without
/// a boundary of its own.
///
/// **Seam:** `ChatMessageChangeTransition` over a content that is, or is not,
/// wrapped in a `RepaintBoundary`, compared by the pixels it paints midway.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final shot = GlobalKey();

  // Two bars the text of the old and the new content stand for: wide and short
  // against narrow and tall, so each leaves pixels the other does not cover.
  Widget bar(Color color, double width, double height, {required bool layer}) {
    final box = SizedBox(
      width: width,
      height: height,
      child: ColoredBox(color: color),
    );
    return layer ? RepaintBoundary(child: box) : box;
  }

  Widget harness(
    String identity, {
    required bool layer,
    Offset inset = Offset.zero,
  }) => MaterialApp(
    home: RepaintBoundary(
      key: shot,
      child: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: EdgeInsets.only(left: inset.dx, top: inset.dy),
            child: ChatMessageChangeTransition(
              contentIdentity: identity,
              content: identity == 'old'
                  ? bar(Colors.white, 120, 14, layer: layer)
                  : bar(Colors.redAccent, 40, 44, layer: layer),
              edited: false,
              outgoing: false,
              color: const Color(0xFF2B5278),
              borderRadius: BorderRadius.circular(12),
              padding: const EdgeInsets.all(10),
              metaBuilder: (context, editedOpacity) =>
                  const SizedBox(width: 30, height: 10),
            ),
          ),
        ),
      ),
    ),
  );

  // The pixels of the edit [elapsed] into its crossfade, and its progress.
  Future<({Uint8List pixels, int width, double progress})> midway(
    WidgetTester tester, {
    required bool layer,
    Duration elapsed = const Duration(milliseconds: 90),
    Offset inset = Offset.zero,
  }) async {
    await tester.pumpWidget(harness('old', layer: layer, inset: inset));
    await tester.pumpAndSettle();
    await tester.pumpWidget(harness('new', layer: layer, inset: inset));
    await tester.pump();
    await tester.pump(elapsed);
    final progress = tester
        .renderObject<RenderChatMessageChangeTransition>(
          find.byType(ChatMessageChangeTransition),
        )
        .params
        .progress;
    final width = shot.currentContext!.size!.width.toInt();
    final bytes = await tester.runAsync(() async {
      final boundary =
          shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return data!.buffer.asUint8List();
    });
    await tester.pumpAndSettle();
    return (pixels: bytes!, width: width, progress: progress);
  }

  testWidgets('a body on a layer of its own crossfades as one that is not', (
    tester,
  ) async {
    final plain = await midway(tester, layer: false);
    final composited = await midway(tester, layer: true);

    expect(composited.pixels, plain.pixels);
  });

  testWidgets('the old content fades out as 1 - p and the new in as p, '
      'wherever the bubble sits', (tester) async {
    // A bubble below and to the right of the origin: the fade layer paints at
    // absolute positions, so a parent offset must not move the content off it.
    for (final inset in const [Offset.zero, Offset(37, 23)]) {
      for (final layer in [false, true]) {
        final shot = await midway(tester, layer: layer, inset: inset);
        // The red channel: the bubble is 0x2B, the old bar white, the new bar
        // 0xFF too, so a bar at opacity a shows 0x2B + (0xFF - 0x2B) * a. Over
        // both bars, the opacities compose as 1 - (1 - a)(1 - b).
        int red(int x, int y) =>
            shot.pixels[((y + inset.dy.toInt()) * shot.width +
                    x +
                    inset.dx.toInt()) *
                4];
        int shown(double opacity) => (0x2B + (0xFF - 0x2B) * opacity).round();
        final p = shot.progress;
        final reason = 'inset $inset, layer $layer';

        expect(
          red(100, 15),
          closeTo(shown(1 - p), 1),
          reason: 'old only, $reason',
        );
        expect(red(20, 30), closeTo(shown(p), 1), reason: 'new only, $reason');
        expect(
          red(12, 12),
          closeTo(shown(1 - (1 - (1 - p)) * (1 - p)), 1),
          reason: 'both, $reason',
        );
      }
    }
  });

  testWidgets('the crossfade has begun at that moment: the pixels are not '
      'those of the settled bubble', (tester) async {
    final during = await midway(tester, layer: false);
    final settled = await midway(
      tester,
      layer: false,
      elapsed: const Duration(seconds: 1),
    );

    expect(during.pixels, isNot(settled.pixels));
  });
}
