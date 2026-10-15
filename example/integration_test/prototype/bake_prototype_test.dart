// PROTOTYPE - throwaway, wipe me. Ticket 11 (.scratch/panel-catalog-glyph-perf).
//
// Question: can the system emoji font be baked into atlas pages on the device,
// paced across frames, without breaking the 0-jank criterion, and is
// drawRawAtlas worth it over per-leaf drawImageRect?
//
// Not production code: no error handling, no abstractions. One process runs one
// pace (`--dart-define=PROTO_N=<glyphs per frame>`) because Impeller's glyph
// atlas is per process and a second pass in the same process is already warm.
//
// Phases, each a separate report key:
//   bake_n<N>      glyphs baked N per frame into strips (frame timing during it)
//   compose_n<N>   strips composed into 2048^2 pages (one page per frame)
//   draw_atlas / draw_rect (x2 each)  full-catalog sweeps over the baked pages
//   persist_page0 / reload_page0      readback + write, then read + re-upload
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:chat_chrome/chat_chrome.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _n = int.fromEnvironment('PROTO_N', defaultValue: 4);

const _cellPx = 102; // 98 px glyph + 2 px gutter on each side
const _glyphPx = 98;
const _pagePx = 2048;
const _cols = _pagePx ~/ _cellPx; // 20
const _perPage = _cols * _cols; // 400 cells per page

final _mode = ValueNotifier<String>('spin');
final _offset = ValueNotifier<double>(0);
late List<ui.Image> _pages;
late List<String> _glyphs;
late double _dpr;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('bake prototype', (tester) async {
    final data = DefaultEmojiDataSource(
      catalog: LocaleEmojiCatalogProvider(
        locale: const Locale('ru'),
        categoryTitles: EmojiCategoryTitles.russian,
        stripIconFor: EmojiTabAssets.stripIconForId,
      ),
    );
    await data.load();
    _glyphs = {
      for (final c in data.categories)
        for (final item in c.items)
          if (item case UnicodeEmojiItem(:final glyph)) glyph,
    }.toList();
    _dpr = tester.view.devicePixelRatio;

    await tester.pumpWidget(const _Host());
    await tester.pump(const Duration(milliseconds: 500));

    final meta = <String, Object?>{
      'protoN': _n,
      'glyphs': _glyphs.length,
      'dpr': _dpr,
      'cellPx': _cellPx,
      'glyphPx': _glyphPx,
      'cellsPerPage': _perPage,
      'refreshHz': tester.view.display.refreshRate,
    };

    // --- bake: N glyphs per frame into strips -----------------------------
    final strips = <ui.Image>[];
    final bakeWatch = Stopwatch();
    var bakeFrames = 0;
    await _scenario(
      tester,
      binding,
      'bake_n$_n',
      meta,
      () async {
        bakeWatch.start();
        for (var i = 0; i < _glyphs.length; i += _n) {
          await WidgetsBinding.instance.endOfFrame;
          strips.add(
            _bakeStrip(_glyphs.sublist(i, math.min(i + _n, _glyphs.length))),
          );
          bakeFrames++;
        }
        bakeWatch.stop();
      },
      extra: () => {
        'bakeWallMs': bakeWatch.elapsedMilliseconds,
        'framesUsed': bakeFrames,
        'strips': strips.length,
      },
    );

    // --- compose: one 2048^2 page per frame --------------------------------
    final pageCount = (_glyphs.length / _perPage).ceil();
    _pages = [];
    final composeWatch = Stopwatch();
    await _scenario(
      tester,
      binding,
      'compose_n$_n',
      meta,
      () async {
        composeWatch.start();
        for (var p = 0; p < pageCount; p++) {
          await WidgetsBinding.instance.endOfFrame;
          _pages.add(_composePage(strips, p));
        }
        composeWatch.stop();
      },
      extra: () => {
        'composeWallMs': composeWatch.elapsedMilliseconds,
        'pages': pageCount,
        'rawBytes': pageCount * _pagePx * _pagePx * 4,
        'withMipsBytes': (pageCount * _pagePx * _pagePx * 4 * 4 / 3).round(),
        'tightRawBytes': _glyphs.length * _cellPx * _cellPx * 4,
      },
    );
    for (final s in strips) {
      s.dispose();
    }

    // --- draw: drawRawAtlas vs per-leaf drawImageRect ----------------------
    for (final mode in const ['atlas', 'rect', 'atlas', 'rect']) {
      _mode.value = mode;
      await tester.pump(const Duration(milliseconds: 300));
      final key = 'draw_$mode${_seen.add(mode) ? '' : '_2'}';
      await _scenario(tester, binding, key, meta, () => _sweep(tester));
    }

    // --- persist and reload one page ---------------------------------------
    final file = File('${Directory.systemTemp.path}/proto_page0.rgba');
    Uint8List? bytes;
    final persistWatch = Stopwatch();
    await _scenario(
      tester,
      binding,
      'persist_page0',
      meta,
      () async {
        persistWatch.start();
        final bd = await _pages[0].toByteData();
        bytes = bd!.buffer.asUint8List();
        await file.writeAsBytes(bytes!);
        persistWatch.stop();
      },
      extra: () => {'persistWallMs': persistWatch.elapsedMilliseconds},
    );

    final reloadWatch = Stopwatch();
    await _scenario(
      tester,
      binding,
      'reload_page0',
      meta,
      () async {
        reloadWatch.start();
        final read = await file.readAsBytes();
        final buffer = await ui.ImmutableBuffer.fromUint8List(read);
        final descriptor = ui.ImageDescriptor.raw(
          buffer,
          width: _pagePx,
          height: _pagePx,
          pixelFormat: ui.PixelFormat.rgba8888,
        );
        final codec = await descriptor.instantiateCodec();
        final frame = await codec.getNextFrame();
        frame.image.dispose();
        codec.dispose();
        descriptor.dispose();
        buffer.dispose();
        reloadWatch.stop();
      },
      extra: () => {'reloadWallMs': reloadWatch.elapsedMilliseconds},
    );
    await file.delete();
  });
}

final _seen = <String>{};

// ---- baking ----------------------------------------------------------------

ui.Image _bakeStrip(List<String> glyphs) {
  final glyphLogical = _glyphPx / _dpr;
  final pitchLogical = _cellPx / _dpr;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(_dpr);
  for (var i = 0; i < glyphs.length; i++) {
    final paragraph =
        (ui.ParagraphBuilder(
            ui.ParagraphStyle(
              textAlign: TextAlign.center,
              fontSize: glyphLogical * 0.85,
            ),
          )..addText(glyphs[i])).build()
          ..layout(ui.ParagraphConstraints(width: glyphLogical));
    canvas.drawParagraph(
      paragraph,
      Offset(
        i * pitchLogical + (pitchLogical - glyphLogical) / 2,
        (pitchLogical - paragraph.height) / 2,
      ),
    );
  }
  final picture = recorder.endRecording();
  final image = picture.toImageSync(_n * _cellPx, _cellPx);
  picture.dispose();
  return image;
}

ui.Image _composePage(List<ui.Image> strips, int page) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint();
  for (var k = 0; k < _perPage; k++) {
    final g = page * _perPage + k;
    if (g >= _glyphs.length) break;
    final src = Rect.fromLTWH(
      (g % _n) * _cellPx.toDouble(),
      0,
      _cellPx.toDouble(),
      _cellPx.toDouble(),
    );
    final dst = Rect.fromLTWH(
      (k % _cols) * _cellPx.toDouble(),
      (k ~/ _cols) * _cellPx.toDouble(),
      _cellPx.toDouble(),
      _cellPx.toDouble(),
    );
    canvas.drawImageRect(strips[g ~/ _n], src, dst, paint);
  }
  final picture = recorder.endRecording();
  final image = picture.toImageSync(_pagePx, _pagePx);
  picture.dispose();
  return image;
}

// ---- host + painter --------------------------------------------------------

class _Host extends StatefulWidget {
  const _Host();

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with SingleTickerProviderStateMixin {
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
      backgroundColor: Colors.black,
      body: Column(
        children: [
          const SizedBox(height: 60),
          RotationTransition(
            turns: _spin,
            child: const Icon(Icons.refresh, size: 40, color: Colors.white),
          ),
          Expanded(
            child: ValueListenableBuilder<String>(
              valueListenable: _mode,
              builder: (context, mode, _) => mode == 'spin'
                  ? const SizedBox.expand()
                  : RepaintBoundary(
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _GridPainter(mode),
                      ),
                    ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.mode) : super(repaint: _offset);
  final String mode;

  static const _cols8 = 8;

  @override
  void paint(Canvas canvas, Size size) {
    // CustomPaint's canvas is already in logical pixels.
    canvas.clipRect(Offset.zero & size);
    final w = size.width;
    final h = size.height;
    final pitch = w / _cols8;
    final glyphLogical = _glyphPx / _dpr;
    final scale = glyphLogical / _glyphPx;
    final firstRow = math.max(0, (_offset.value / pitch).floor());
    final lastRow = ((_offset.value + h) / pitch).ceil();
    final paint = Paint()..filterQuality = FilterQuality.low;

    final perPageRects = <int, List<double>>{};
    final perPageXforms = <int, List<double>>{};
    for (var row = firstRow; row <= lastRow; row++) {
      for (var col = 0; col < _cols8; col++) {
        final g = row * _cols8 + col;
        if (g >= _glyphs.length) break;
        final page = g ~/ _perPage;
        final k = g % _perPage;
        final sx = (k % _cols) * _cellPx + 2.0;
        final sy = (k ~/ _cols) * _cellPx + 2.0;
        final dx = col * pitch + (pitch - glyphLogical) / 2;
        final dy = row * pitch - _offset.value + (pitch - glyphLogical) / 2;
        if (mode == 'rect') {
          canvas.drawImageRect(
            _pages[page],
            Rect.fromLTWH(sx, sy, _glyphPx.toDouble(), _glyphPx.toDouble()),
            Rect.fromLTWH(dx, dy, glyphLogical, glyphLogical),
            paint,
          );
        } else {
          (perPageRects[page] ??= []).addAll([
            sx,
            sy,
            sx + _glyphPx,
            sy + _glyphPx,
          ]);
          (perPageXforms[page] ??= []).addAll([scale, 0, dx, dy]);
        }
      }
    }
    if (mode == 'atlas') {
      for (final page in perPageRects.keys) {
        canvas.drawRawAtlas(
          _pages[page],
          Float32List.fromList(perPageXforms[page]!),
          Float32List.fromList(perPageRects[page]!),
          null,
          null,
          null,
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.mode != mode;
}

/// Triangle-wave sweep over the whole catalog at fling speed, 3 round trips.
Future<void> _sweep(WidgetTester tester) async {
  final pitch = (tester.view.physicalSize.width / _dpr) / 8;
  final extent = (_glyphs.length / 8).ceil() * pitch;
  final maxOffset = extent - 380;
  const speed = 7000.0; // logical px/s
  final period = maxOffset / speed;
  final watch = Stopwatch()..start();
  final totalSeconds = period * 6;
  while (watch.elapsedMilliseconds / 1000 < totalSeconds) {
    final t = watch.elapsedMilliseconds / 1000 / period;
    final phase = t % 2;
    _offset.value = (phase <= 1 ? phase : 2 - phase) * maxOffset;
    await WidgetsBinding.instance.endOfFrame;
  }
  _offset.value = 0;
}

// ---- measurement -----------------------------------------------------------

Future<void> _scenario(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  String name,
  Map<String, Object?> meta,
  Future<void> Function() body, {
  Map<String, Object?> Function()? extra,
}) async {
  final timings = <FrameTiming>[];
  void on(List<FrameTiming> b) => timings.addAll(b);
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
  var severe = 0;
  for (var i = 0; i < timings.length; i++) {
    final worst = math.max(build[i], raster[i]);
    if (worst > budget) jank++;
    if (worst > budget * 2) severe++;
  }
  final summary = {
    'frames': timings.length,
    'budgetMs': budget,
    'jankFrames': jank,
    'severeFrames(>2x)': severe,
    'buildMs': stats(build),
    'rasterMs': stats(raster),
  };
  binding.reportData ??= <String, dynamic>{};
  binding.reportData![name] = {
    'meta': {
      ...meta,
      'scenario': name,
      'mode': kProfileMode ? 'profile' : (kReleaseMode ? 'release' : 'debug'),
      ...?extra?.call(),
    },
    'summary': summary,
    'frames': {
      'buildMs': build.map((v) => double.parse(v.toStringAsFixed(3))).toList(),
      'rasterMs': raster
          .map((v) => double.parse(v.toStringAsFixed(3)))
          .toList(),
    },
  };
  debugPrint('[proto] $name ${binding.reportData![name]['meta']} $summary');
}
