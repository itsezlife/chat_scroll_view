import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'panel_perf/shipped_glyphs.dart';

/// On-device check of the glyph atlas baker (baked-atlas ticket 05).
///
/// Bakes the whole current catalogue with the real [ParagraphGlyphRasteriser]
/// next to a spinner, at the default pace, and records what the ticket asks:
///
/// - `bake_n16`: frame timing during the bake, wall time, pages and bytes. The
///   reference-device bar is a bake in about a second with no dropped frame;
///   spec reference (prototype, 16 per frame): 0.93 s, 0 dropped.
/// - `visual_check`: baked sprites drawn at the display size against the same
///   glyphs drawn directly by the system font, as a mean per-channel
///   difference out of 255 (spec reference: 4.3 at the 72 px cap, 3.7 at full
///   size, one device), plus per-glyph figures and the natural width of each
///   glyph against its cell (a width over 1.0 means the paragraph is clipped
///   to the cell, a candidate cause of an edge artefact on wide sequences).
///   A screenshot, `glyph_atlas_visual_check`, shows both rows magnified 3x
///   with no smoothing.
///
/// Run in `--profile` with `tool/run_panel_perf.sh` (the script takes
/// `TARGET=`); debug timings say nothing about raster cost:
///
///   TARGET=integration_test/glyph_atlas_bake_test.dart \
///   DEFINES="--dart-define=GLYPH_ATLAS_ENFORCE=true" \
///   tool/run_panel_perf.sh DEVICE_ID LABEL
///
/// Only the reference device gates. On other platforms (`flutter test -d
/// macos`) the numbers are indicative and the dropped-frame assertion is off
/// unless `GLYPH_ATLAS_ENFORCE` is set.
const _enforce = bool.fromEnvironment('GLYPH_ATLAS_ENFORCE');

/// The rasteriser's default font scale (see [ParagraphGlyphRasteriser]).
const _fontScale = 0.85;

/// Desktop only: also write the visual-check image as a PNG to the system
/// temp directory and print the path (device screenshots go through the
/// driver instead).
const _dump = bool.fromEnvironment('GLYPH_ATLAS_DUMP');

const _glyphsPerFrame = int.fromEnvironment(
  'GLYPH_ATLAS_PER_FRAME',
  defaultValue: 16,
);

/// Glyphs whose look the ticket cares about, all in the catalogue: plain, flag,
/// ZWJ sequences (the family sequence, index 5, showed a faint dark edge at 3x
/// zoom in the prototype).
const _visualGlyphs = <String>[
  '😀',
  '👍',
  '❤️',
  '🇯🇵',
  '🏳️‍🌈',
  '👨‍👩‍👧‍👦',
  '👩‍⚕️',
  '🧙‍♂️',
];

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  // The rasteriser contract against the real system font, where it matters:
  // wide sequences must stay inside their cell.
  runGlyphRasteriserContract(
    'ParagraphGlyphRasteriser (system font)',
    ParagraphGlyphRasteriser.new,
    glyphs: _visualGlyphs,
  );

  testWidgets('glyph atlas bake', (tester) async {
    final glyphs = await loadShippedGlyphs();
    const layout = GlyphAtlasLayout();
    final index = GlyphAtlasIndex(glyphs, layout: layout);
    final store = FakeGlyphPageStore();
    final baker = GlyphBaker(
      index: index,
      rasteriser: ParagraphGlyphRasteriser(),
      store: store,
    );
    final visual = ValueNotifier<ui.Image?>(null);

    await tester.pumpWidget(_Host(visual: visual));
    await tester.pump(const Duration(milliseconds: 500));

    final meta = <String, Object?>{
      'glyphs': glyphs.length,
      'glyphsPerFrame': _glyphsPerFrame,
      'glyphSizePx': layout.glyphSize,
      'cellsPerPage': layout.cellsPerPage,
      'dpr': tester.view.devicePixelRatio,
      'refreshHz': tester.view.display.refreshRate,
      'mode': kProfileMode ? 'profile' : (kReleaseMode ? 'release' : 'debug'),
      'platform': defaultTargetPlatform.name,
    };

    // --- bake the whole catalogue at the default pace ------------------------
    final wall = Stopwatch();
    var frames = 0;
    final bakeSummary = await _measure(tester, () async {
      wall.start();
      await baker.bakeAll(
        glyphsPerFrame: _glyphsPerFrame,
        nextFrame: () {
          frames++;
          return WidgetsBinding.instance.endOfFrame;
        },
      );
      wall.stop();
    });
    _record(binding, 'bake_n$_glyphsPerFrame', {
      ...meta,
      'bakeWallMs': wall.elapsedMilliseconds,
      'framesUsed': frames,
      'pages': index.pageCount,
      'residentBytes': layout.residentBytesFor(glyphs.length),
    }, bakeSummary);
    expect(baker.isComplete, isTrue);
    expect(index.pageCount, 3);
    if (_enforce) {
      expect(
        bakeSummary['jankFrames'],
        0,
        reason: 'the bake dropped frames at $_glyphsPerFrame glyphs per frame',
      );
    }

    // --- visual check against the system rendering ---------------------------
    final check = await _visualCheck(tester, baker, store, layout);
    visual.value = check.image;
    await tester.pump(const Duration(milliseconds: 300));
    final screenshotError = await _screenshot(binding, tester);
    if (_dump) {
      final png = await check.image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
        '${Directory.systemTemp.path}/glyph_atlas_visual_check.png',
      )..writeAsBytesSync(png!.buffer.asUint8List());
      debugPrint('[glyph_atlas] wrote ${file.path}');
    }
    _record(binding, 'visual_check', {
      ...meta,
      'sampleGlyphs': _visualGlyphs,
      'meanChannelDiffPerGlyph': check.diffs,
      'meanChannelDiff':
          check.diffs.values.reduce((a, b) => a + b) / check.diffs.length,
      'naturalWidthOverCell': check.naturalWidth,
      'screenshotError': screenshotError,
    }, const {});

    baker.dispose();
    await store.clear();
    visual.value?.dispose();
  });
}

// ---- visual check ------------------------------------------------------------

/// Draws each sample glyph twice at [shown] px, on white: from its baked sprite
/// (top row) and directly by the system font (bottom row), and compares them.
Future<
  ({
    ui.Image image,
    Map<String, double> diffs,
    Map<String, double> naturalWidth,
  })
>
_visualCheck(
  WidgetTester tester,
  GlyphBaker baker,
  GlyphPageStore store,
  GlyphAtlasLayout layout,
) async {
  // The display size of a catalogue cell at this density is wider than the
  // capped bake, so the sprite is upscaled exactly as it would be on screen.
  final shown = (34.84 * tester.view.devicePixelRatio).round();
  final cell = shown + 8;
  final width = cell * _visualGlyphs.length;
  final pagesById = <int, ui.Image>{};

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)..drawColor(Colors.white, BlendMode.src);
  final sprites = ui.PictureRecorder();
  final spriteCanvas = ui.Canvas(sprites)
    ..drawColor(Colors.white, BlendMode.src);
  for (var i = 0; i < _visualGlyphs.length; i++) {
    final glyph = _visualGlyphs[i];
    final target = ui.Rect.fromLTWH(
      i * cell + 4,
      4,
      shown.toDouble(),
      shown.toDouble(),
    );
    _paintSystem(canvas, glyph, target);
    final sprite = baker.spriteOf(glyph);
    if (sprite != null) {
      final page = pagesById[sprite.pageIndex] ??= (await store.read(
        sprite.pageIndex,
      ))!;
      spriteCanvas.drawImageRect(
        page,
        sprite.source,
        target,
        Paint()..filterQuality = FilterQuality.low,
      );
    }
  }
  final directImage = recorder.endRecording().toImageSync(width, cell);
  final spriteImage = sprites.endRecording().toImageSync(width, cell);
  for (final page in pagesById.values) {
    page.dispose();
  }

  final a = await ImagePixels.of(spriteImage);
  final b = await ImagePixels.of(directImage);
  final diffs = <String, double>{};
  final naturalWidth = <String, double>{};
  for (var i = 0; i < _visualGlyphs.length; i++) {
    var sum = 0;
    for (var y = 0; y < cell; y++) {
      for (var x = i * cell; x < (i + 1) * cell; x++) {
        final p = a.at(x, y);
        final q = b.at(x, y);
        sum +=
            (p.r * 255 - q.r * 255).abs().round() +
            (p.g * 255 - q.g * 255).abs().round() +
            (p.b * 255 - q.b * 255).abs().round();
      }
    }
    diffs[_visualGlyphs[i]] = sum / (cell * cell * 3);
    naturalWidth[_visualGlyphs[i]] =
        _naturalWidth(_visualGlyphs[i], layout.glyphSize * _fontScale) /
        layout.glyphSize;
  }

  // One image for the screenshot: both rows at actual size (sprites on top),
  // and under them the family sequence magnified 3x without smoothing.
  const familyAt = 5;
  final both = ui.PictureRecorder();
  final bothCanvas = Canvas(both)
    ..drawImage(spriteImage, ui.Offset.zero, Paint())
    ..drawImage(directImage, ui.Offset(0, cell.toDouble()), Paint());
  final zoomPaint = Paint()..filterQuality = FilterQuality.none;
  for (var row = 0; row < 2; row++) {
    bothCanvas.drawImageRect(
      row == 0 ? spriteImage : directImage,
      ui.Rect.fromLTWH(
        familyAt * cell.toDouble(),
        0,
        cell.toDouble(),
        cell.toDouble(),
      ),
      ui.Rect.fromLTWH(row * cell * 3.0, cell * 2.0, cell * 3.0, cell * 3.0),
      zoomPaint,
    );
  }
  final composite = both.endRecording().toImageSync(width, cell * 5);
  spriteImage.dispose();
  directImage.dispose();
  return (image: composite, diffs: diffs, naturalWidth: naturalWidth);
}

/// The system rendering the sprites are compared with: the same paragraph the
/// rasteriser draws, but unclipped and at the display size.
void _paintSystem(Canvas canvas, String glyph, ui.Rect target) {
  final paragraph =
      (ui.ParagraphBuilder(
          ui.ParagraphStyle(
            textAlign: TextAlign.center,
            fontSize: target.height * _fontScale,
          ),
        )..addText(glyph)).build()
        ..layout(ui.ParagraphConstraints(width: target.width));
  canvas.drawParagraph(
    paragraph,
    ui.Offset(target.left, target.top + (target.height - paragraph.height) / 2),
  );
  paragraph.dispose();
}

double _naturalWidth(String glyph, double fontSize) {
  final paragraph =
      (ui.ParagraphBuilder(
          ui.ParagraphStyle(fontSize: fontSize),
        )..addText(glyph)).build()
        ..layout(const ui.ParagraphConstraints(width: double.infinity));
  final width = paragraph.longestLine;
  paragraph.dispose();
  return width;
}

Future<String?> _screenshot(
  IntegrationTestWidgetsFlutterBinding binding,
  WidgetTester tester,
) async {
  try {
    if (defaultTargetPlatform == TargetPlatform.android) {
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
    }
    await binding.takeScreenshot('glyph_atlas_visual_check');
    return null;
  } on Object catch (error) {
    // A device without screenshot support still yields the numbers.
    return '$error';
  }
}

// ---- host ----------------------------------------------------------------------

class _Host extends StatefulWidget {
  const _Host({required this.visual});

  final ValueNotifier<ui.Image?> visual;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with SingleTickerProviderStateMixin {
  // A spinner keeps frames flowing so dropped frames during the bake show up.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          const SizedBox(height: 60),
          RotationTransition(
            turns: _spin,
            child: const Icon(Icons.refresh, size: 40),
          ),
          Expanded(
            child: ValueListenableBuilder<ui.Image?>(
              valueListenable: widget.visual,
              builder: (context, image, _) => image == null
                  ? const SizedBox.expand()
                  : Align(
                      alignment: Alignment.topLeft,
                      // One image pixel per physical pixel.
                      child: RawImage(
                        image: image,
                        scale: MediaQuery.devicePixelRatioOf(context),
                        filterQuality: FilterQuality.none,
                      ),
                    ),
            ),
          ),
        ],
      ),
    ),
  );
}

// ---- measurement -----------------------------------------------------------------

Future<Map<String, Object?>> _measure(
  WidgetTester tester,
  Future<void> Function() body,
) async {
  final timings = <FrameTiming>[];
  void on(List<FrameTiming> batch) => timings.addAll(batch);
  SchedulerBinding.instance.addTimingsCallback(on);
  await body();
  await tester.pump(const Duration(milliseconds: 1500));
  SchedulerBinding.instance.removeTimingsCallback(on);

  final budget = 1000 / tester.view.display.refreshRate;
  double ms(Duration d) => d.inMicroseconds / 1000;
  final build = timings.map((f) => ms(f.buildDuration)).toList();
  final raster = timings.map((f) => ms(f.rasterDuration)).toList();
  Map<String, double> stats(List<double> v) {
    if (v.isEmpty) return const {};
    final s = [...v]..sort();
    double q(double p) => s[math.min(s.length - 1, (p * s.length).floor())];
    return {'p50': q(0.5), 'p90': q(0.9), 'p99': q(0.99), 'max': s.last};
  }

  var jank = 0;
  for (var i = 0; i < timings.length; i++) {
    if (math.max(build[i], raster[i]) > budget) jank++;
  }
  return {
    'frames': timings.length,
    'budgetMs': budget,
    'jankFrames': jank,
    'buildMs': stats(build),
    'rasterMs': stats(raster),
  };
}

void _record(
  IntegrationTestWidgetsFlutterBinding binding,
  String name,
  Map<String, Object?> meta,
  Map<String, Object?> summary,
) {
  binding.reportData ??= <String, dynamic>{};
  binding.reportData![name] = {'meta': meta, 'summary': summary};
  debugPrint('[glyph_atlas] $name $meta $summary');
}
