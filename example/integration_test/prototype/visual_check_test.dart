// PROTOTYPE - throwaway, wipe me. Phase 2 of the glyph-pipeline spec:
// visual check of baked emoji at 98 px (DPR-exact) vs 72 px (capped, upscaled).
//
// One screenshot, rows top to bottom, 16 emoji in two groups of 8:
//   P  system drawParagraph (ground truth, today's on-screen path)
//   B98 baked at 98 px, drawn 1:1
//   B72 baked at 72 px, drawn 1.35x with bilinear filtering
// Each trio is shown at scale 1.0 and again at 0.8 (the leaf press scale).
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _groups = [
  ['😀', '😍', '🥹', '🫠', '🤯', '🥶', '😈', '💀'],
  ['👍🏽', '🫶', '🧑‍🚀', '👨‍👩‍👧‍👦', '🇯🇵', '🇺🇿', '❤️‍🔥', '🦋'],
];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('visual check', (tester) async {
    await binding.convertFlutterSurfaceToImage();
    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(backgroundColor: Color(0xFF17212B), body: _Scene()),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await binding.takeScreenshot('visual_check');
  });
}

class _Scene extends StatefulWidget {
  const _Scene();

  @override
  State<_Scene> createState() => _SceneState();
}

class _SceneState extends State<_Scene> {
  late final Map<int, List<ui.Image>> _baked = {};
  var _ready = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_ready) return;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    for (final px in const [98, 72]) {
      _baked[px] = [for (final group in _groups) _bake(group, px, dpr)];
    }
    _ready = true;
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: CustomPaint(size: Size.infinite, painter: _P(_baked)),
  );
}

ui.Image _bake(List<String> glyphs, int glyphPx, double dpr) {
  final cellPx = glyphPx + 4;
  final glyphLogical = glyphPx / dpr;
  final pitch = cellPx / dpr;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(dpr);
  for (var i = 0; i < glyphs.length; i++) {
    final p =
        (ui.ParagraphBuilder(
            ui.ParagraphStyle(
              textAlign: TextAlign.center,
              fontSize: glyphLogical * 0.85,
            ),
          )..addText(glyphs[i])).build()
          ..layout(ui.ParagraphConstraints(width: glyphLogical));
    canvas.drawParagraph(
      p,
      Offset(i * pitch + (pitch - glyphLogical) / 2, (pitch - p.height) / 2),
    );
  }
  final picture = recorder.endRecording();
  final image = picture.toImageSync(glyphs.length * cellPx, cellPx);
  picture.dispose();
  return image;
}

class _P extends CustomPainter {
  _P(this.baked);
  final Map<int, List<ui.Image>> baked;

  @override
  void paint(Canvas canvas, Size size) {
    final dpr = ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
    final w = size.width;
    final pitch = w / 8;
    final glyphLogical = 98 / dpr;
    final label = TextPainter(textDirection: TextDirection.ltr);
    var y = 4.0;
    for (var g = 0; g < _groups.length; g++) {
      for (final scale in const [1.0, 0.8]) {
        for (final mode in const ['P', 'B98', 'B72']) {
          for (var i = 0; i < 8; i++) {
            final cx = i * pitch + pitch / 2;
            final cy = y + pitch / 2;
            canvas
              ..save()
              ..translate(cx, cy)
              ..scale(scale)
              ..translate(-cx, -cy);
            final dst = Rect.fromCenter(
              center: Offset(cx, cy),
              width: glyphLogical,
              height: glyphLogical,
            );
            if (mode == 'P') {
              final p =
                  (ui.ParagraphBuilder(
                      ui.ParagraphStyle(
                        textAlign: TextAlign.center,
                        fontSize: glyphLogical * 0.85,
                      ),
                    )..addText(_groups[g][i])).build()
                    ..layout(ui.ParagraphConstraints(width: glyphLogical));
              canvas.drawParagraph(
                p,
                Offset(dst.left, dst.top + (glyphLogical - p.height) / 2),
              );
            } else {
              final px = mode == 'B98' ? 98 : 72;
              final cell = px + 4;
              canvas.drawImageRect(
                baked[px]![g],
                Rect.fromLTWH(i * cell + 2.0, 2, px.toDouble(), px.toDouble()),
                dst,
                Paint()..filterQuality = FilterQuality.low,
              );
            }
            canvas.restore();
          }
          label
            ..text = TextSpan(
              text: '$mode ${scale == 1.0 ? '1.0' : '0.8'}',
              style: const TextStyle(color: Color(0xAAFFFFFF), fontSize: 8),
            )
            ..layout();
          label.paint(canvas, Offset(1, y + 1));
          y += pitch;
        }
      }
      y += 6;
    }
  }

  @override
  bool shouldRepaint(_P old) => false;
}
