// Playback benchmark of the Lottie frame path over the real native library:
// what one clock tick costs while 1, 8 and 32 animated stickers play, split
// into the pieces of the path.
//
//   LOTTIE_PLAYBACK_BENCH=1 flutter test --concurrency 40 \
//     test/benchmark/lottie_playback_bench_test.dart
//   LOTTIE_PLAYBACK_BENCH=1 LOTTIE_BENCH_WRITE_BASELINE=1 flutter test ...
//
// Gated twice: the `benchmark` tag (dart_test.yaml) names it, and without
// LOTTIE_PLAYBACK_BENCH the measuring test is skipped, so the package's unit
// entrypoint (which imports every test file) never pays for 900 real ticks.
// The comparison tests below run always: they are cheap and deterministic.
//
// What a tick is here, per sticker count N, 128 px stickers of the
// hand-authored fixture, 300 manual clock ticks after 10 warm-up ticks:
//   * tick: the synchronous part on the UI isolate, the manual tick source's
//     `tick` to its return (the scheduler building the batch and handing it
//     to the atlas);
//   * settled: the same tick until the frame is in a GPU image (render
//     isolate round trip + upload + the continuations in between);
//   * round trip: `LottieEngine.renderBatch` as the UI isolate sees it, which
//     includes the hop to the render isolate and back;
//   * upload: first to last call of the real uploader in one tick
//     (`decodeImageFromPixels`, under `tester.runAsync`), and the bytes it was
//     given.
//
// Not a gate and not asserted: absolute times on a development machine in
// debug (JIT) mode are noisy and inflated by asserts, so the table is read as
// a shape (what grows with N, what does not), and the comparison with
// test/benchmark/baseline.json is ratios that only report. What is asserted
// is deterministic: every tick sent one batch, nothing failed.

@Tags(['benchmark'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/frame_pool.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/lottie_decoder.dart';
import 'package:lottie_native/lottie_native.dart';

import 'playback_bench_report.dart';

const _gate = 'LOTTIE_PLAYBACK_BENCH';
const _writeBaseline = 'LOTTIE_BENCH_WRITE_BASELINE';
const _baselinePath = 'test/benchmark/baseline.json';
const _outputPath = 'build/bench/lottie_playback.json';

const _stickerCounts = [1, 8, 32];
const _displayEdge = 128;
const _warmupTicks = 10;
const _measuredTicks = 300;
const _tickStep = Duration(milliseconds: 16);

/// A hand-authored 100x100, 30 fps, 60 frame animation: one rotating 60x60
/// square filled with 50% opaque orange. Not a corpus sticker. The same
/// document as `lottie_frame_renderer_test.dart`, copied because that
/// constant is private to its file.
const _fixture = '''
{"v":"5.5.2","fr":30,"ip":0,"op":60,"w":100,"h":100,"nm":"fixture","ddd":0,
"assets":[],
"layers":[{"ddd":0,"ind":1,"ty":4,"nm":"square","sr":1,
"ks":{"o":{"a":0,"k":100},
"r":{"a":1,"k":[{"t":0,"s":[0],"i":{"x":[0.5],"y":[1]},"o":{"x":[0.5],"y":[0]}},{"t":60,"s":[90]}]},
"p":{"a":0,"k":[50,50,0]},"a":{"a":0,"k":[0,0,0]},"s":{"a":0,"k":[100,100,100]}},
"ao":0,
"shapes":[{"ty":"gr","it":[
{"ty":"rc","d":1,"s":{"a":0,"k":[60,60]},"p":{"a":0,"k":[0,0]},"r":{"a":0,"k":0}},
{"ty":"fl","c":{"a":0,"k":[1,0.5,0.25,1]},"o":{"a":0,"k":50},"r":1},
{"ty":"tr","p":{"a":0,"k":[0,0]},"a":{"a":0,"k":[0,0]},"s":{"a":0,"k":[100,100]},"r":{"a":0,"k":0},"o":{"a":0,"k":100}}
]}],"ip":0,"op":60,"st":0,"bm":0}]}''';

// ---------------------------------------------------------------------------
// Meters: the real parts of the path, wrapped to time them
// ---------------------------------------------------------------------------

/// The real engine, timing each render call as the UI isolate sees it (this
/// benchmark has no frame cache, so that is `renderBatch`).
final class _MeteredEngine implements LottieSlotEngine {
  _MeteredEngine(this._inner);

  final LottieSlotEngine _inner;
  final List<int> roundTripsUs = [];

  @override
  Future<LottieLoadResult> load(Uint8List bytes) => _inner.load(bytes);

  Future<T> _timed<T>(Future<T> Function() call) async {
    final watch = Stopwatch()..start();
    try {
      return await call();
    } finally {
      roundTripsUs.add(watch.elapsedMicroseconds);
    }
  }

  @override
  Future<List<LottiePixels?>> renderPixels(List<LottiePixelJob> jobs) =>
      _timed(() => _inner.renderPixels(jobs));

  @override
  Future<List<LottieRenderStatus>> renderBatch(List<LottieEngineJob> jobs) =>
      _timed(() => _inner.renderBatch(jobs));

  @override
  Future<List<LottieCapture>> renderCapturing(List<LottieEngineJob> jobs) =>
      _timed(() => _inner.renderCapturing(jobs));

  @override
  Future<List<LottieRenderStatus>> restore(List<LottieRestoreJob> jobs) =>
      _timed(() => _inner.restore(jobs));

  @override
  Future<List<LottieTextureResult>> writeTextures(
    FrameTextureEntryPoints entryPoints,
    FrameTextureFormat format,
    List<LottieTextureJob> jobs,
  ) => _timed(() => _inner.writeTextures(entryPoints, format, jobs));

  @override
  Future<void> dispose(LottieHandle handle) => _inner.dispose(handle);

  @override
  Future<void> close() => _inner.close();
}

/// The real uploader, counting what it is given and when.
final class _MeteredUploader {
  _MeteredUploader(this._timeline);

  final Stopwatch _timeline;
  int started = 0;
  int completed = 0;
  int bytes = 0;
  int? _firstStartUs;
  int _lastEndUs = 0;

  int get inFlight => started - completed;

  /// Forgets the previous tick's window.
  void beginTick() {
    bytes = 0;
    _firstStartUs = null;
  }

  /// The span from the first upload of the tick starting to the last ending.
  int get flushUs => _firstStartUs == null ? 0 : _lastEndUs - _firstStartUs!;

  Future<ui.Image> call(Uint8List pixels, int side) async {
    started++;
    bytes += pixels.lengthInBytes;
    _firstStartUs ??= _timeline.elapsedMicroseconds;
    final image = await uploadFramePage(pixels, side);
    completed++;
    _lastEndUs = _timeline.elapsedMicroseconds;
    return image;
  }
}

// ---------------------------------------------------------------------------
// One scenario
// ---------------------------------------------------------------------------

/// What one sticker count measured, one entry per measured tick.
final class _Samples {
  final List<int> tickUs = [];
  final List<int> settledUs = [];
  final List<int> roundTripUs = [];
  final List<int> flushUs = [];
  final List<int> uploadedBytes = [];
  int peakPages = 0;
}

double _median(List<int> values) {
  final sorted = [...values]..sort();
  return sorted[sorted.length ~/ 2].toDouble();
}

double _p95(List<int> values) {
  final sorted = [...values]..sort();
  return sorted[(sorted.length * 95 ~/ 100).clamp(0, sorted.length - 1)]
      .toDouble();
}

Future<_Samples> _play(int stickers) async {
  final timeline = Stopwatch()..start();
  final meter = _MeteredUploader(timeline);
  final engine = _MeteredEngine(await IsolateLottieEngine.spawn());
  final memory = NativeFramePageMemory();
  final ticks = ManualPlaybackTickSource();
  final clock = PlaybackClock(ticks: ticks);
  final atlas = FrameAtlas<Object>(
    renderer: LottieFrameRenderer(engine: engine, memory: memory),
    memory: memory,
    upload: meter.call,
  );
  final scheduler = LottieFrameScheduler(
    atlas: atlas,
    clock: clock,
    startTimer: ManualRetentionTimers().start,
  );
  final samples = _Samples();
  try {
    final loaded = await engine.load(Uint8List.fromList(utf8.encode(_fixture)));
    final handle = (loaded as LottieLoaded).handle;
    final leases = [
      for (var i = 0; i < stickers; i++)
        scheduler.acquire(
          'sticker-$i',
          LottieSource(handle, frameCount: 60),
          _displayEdge,
          _displayEdge,
        )!,
    ];
    final pageSide = FrameAtlas.pageSideFor(_displayEdge);
    final pageBytes = pageSide * pageSide * 4;
    var time = Duration.zero;

    for (var tick = 0; tick < _warmupTicks + _measuredTicks; tick++) {
      // What painting does: ask for the frame of the moment, a new one each
      // tick, so every tick has a batch to send.
      for (var i = 0; i < stickers; i++) {
        scheduler.want(leases[i], (tick + i) % 60);
      }
      final batchesBefore = engine.roundTripsUs.length;
      final startedBefore = meter.started;
      meter.beginTick();
      time += _tickStep;
      final watch = Stopwatch()..start();
      ticks.tick(time);
      final tickUs = watch.elapsedMicroseconds;
      // A timer hop lets every pending microtask run first, so "nothing in
      // flight" cannot be read between a render ending and its upload
      // starting.
      final deadline = Stopwatch()..start();
      while (engine.roundTripsUs.length == batchesBefore ||
          meter.started == startedBefore ||
          meter.inFlight > 0) {
        if (deadline.elapsed > const Duration(seconds: 10)) {
          fail('tick $tick with $stickers stickers never settled');
        }
        await Future<void>.delayed(Duration.zero);
      }
      await Future<void>.delayed(Duration.zero);
      final settledUs = watch.elapsedMicroseconds;

      if (tick >= _warmupTicks) {
        final pages = atlas.residentBytes ~/ pageBytes;
        samples
          ..tickUs.add(tickUs)
          ..settledUs.add(settledUs)
          ..roundTripUs.add(engine.roundTripsUs.last)
          ..flushUs.add(meter.flushUs)
          ..uploadedBytes.add(meter.bytes)
          ..peakPages = pages > samples.peakPages ? pages : samples.peakPages;
      }
    }

    expect(
      engine.roundTripsUs,
      hasLength(_warmupTicks + _measuredTicks),
      reason: 'one batch per tick',
    );
    expect(
      leases.where((lease) => lease.isFailed || lease.sprite == null),
      isEmpty,
      reason: 'every sticker has a frame and none failed',
    );
  } finally {
    scheduler.dispose();
    clock.dispose();
    await engine.close();
    memory.dispose();
  }
  return samples;
}

// ---------------------------------------------------------------------------
// The report
// ---------------------------------------------------------------------------

double _toMs(double us) => us / 1000;

String _msText(double us) => _toMs(us).toStringAsFixed(2);

BenchReport _reportOf(Map<int, _Samples> byCount) {
  final metrics = <String, BenchMetric>{};
  for (final MapEntry(key: n, value: s) in byCount.entries) {
    final prefix = 'n$n';
    final changedBytes = n * _displayEdge * _displayEdge * 4;
    metrics
      ..['$prefix.tick_sync_ms'] = BenchMetric(
        MetricKind.milliseconds,
        _toMs(_median(s.tickUs)),
      )
      ..['$prefix.tick_settled_ms'] = BenchMetric(
        MetricKind.milliseconds,
        _toMs(_median(s.settledUs)),
      )
      ..['$prefix.render_round_trip_ms'] = BenchMetric(
        MetricKind.milliseconds,
        _toMs(_median(s.roundTripUs)),
      )
      ..['$prefix.upload_flush_ms'] = BenchMetric(
        MetricKind.milliseconds,
        _toMs(_median(s.flushUs)),
      )
      ..['$prefix.upload_bytes_per_tick'] = BenchMetric(
        MetricKind.count,
        _median(s.uploadedBytes),
      )
      ..['$prefix.upload_over_changed_bytes'] = BenchMetric(
        MetricKind.count,
        _median(s.uploadedBytes) / changedBytes,
      )
      ..['$prefix.peak_pages'] = BenchMetric(
        MetricKind.count,
        s.peakPages.toDouble(),
      );
  }
  return BenchReport(metrics);
}

String _table(Map<int, _Samples> byCount) {
  String cell(String text) => text.padLeft(14);
  final lines = [
    [
      'stickers',
      'tick ms',
      'settled ms',
      'settled p95',
      'round trip ms',
      'upload ms',
      'MiB / tick',
      'peak pages',
    ].map(cell).join(),
  ];
  for (final MapEntry(key: n, value: s) in byCount.entries) {
    lines.add(
      [
        '$n',
        _msText(_median(s.tickUs)),
        _msText(_median(s.settledUs)),
        _msText(_p95(s.settledUs)),
        _msText(_median(s.roundTripUs)),
        _msText(_median(s.flushUs)),
        (_median(s.uploadedBytes) / (1024 * 1024)).toStringAsFixed(2),
        '${s.peakPages}',
      ].map(cell).join(),
    );
  }
  return lines.join('\n');
}

/// What the numbers say about uploading the whole page every tick.
String _uploadVerdict(Map<int, _Samples> byCount) {
  final lines = <String>[];
  for (final MapEntry(key: n, value: s) in byCount.entries) {
    final changed = n * _displayEdge * _displayEdge * 4;
    final uploaded = _median(s.uploadedBytes);
    lines.add(
      '  $n sticker${n == 1 ? '' : 's'}: ${(changed / 1024).toStringAsFixed(0)}'
      ' KiB of pixels change, ${(uploaded / 1024).toStringAsFixed(0)} KiB are '
      'uploaded (${(uploaded / changed).toStringAsFixed(1)}x), '
      '${_msText(_median(s.flushUs))} ms',
    );
  }
  return lines.join('\n');
}

String _comparison(BenchReport current, BenchReport baseline) {
  final lines = <String>[
    'against $_baselinePath (ratios, report only; worse means more than '
        '${MetricKind.milliseconds.tolerance}x for times, '
        '${MetricKind.count.tolerance}x for counts)',
  ];
  for (final c in current.compareTo(baseline)) {
    final ratio = c.baseline != null && c.current != null && c.baseline != 0
        ? (c.current! / c.baseline!).toStringAsFixed(2)
        : '-';
    lines.add('  ${c.key.padRight(34)} ${ratio.padLeft(6)}x  ${c.drift.name}');
  }
  return lines.join('\n');
}

String _pretty(BenchReport report) =>
    '${const JsonEncoder.withIndent('  ').convert(report.toJson())}\n';

void main() {
  final enabled = Platform.environment[_gate] == '1';
  final native = NativeLottieBinding.probe().isAvailable;

  final skipReason = !enabled
      ? 'Set $_gate=1 to run the playback benchmark.'
      : !native
      ? 'The native library is absent or speaks another ABI version: the '
            'build hook compiles it with cargo on macOS only (rustup.rs).'
      : null;
  const title = 'plays 1, 8 and 32 stickers and reports what a tick costs';
  if (skipReason != null) {
    test(title, () {}, skip: skipReason);
  } else {
    testWidgets(title, (tester) async {
      final byCount = <int, _Samples>{};
      await tester.runAsync(() async {
        for (final n in _stickerCounts) {
          byCount[n] = await _play(n);
        }
      });

      final report = _reportOf(byCount);
      File(_outputPath)
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(_pretty(report));
      final baselineFile = File(_baselinePath);
      if (Platform.environment[_writeBaseline] == '1') {
        baselineFile.writeAsStringSync(_pretty(report));
      }
      final comparison = baselineFile.existsSync()
          ? _comparison(
              report,
              BenchReport.fromJson(
                jsonDecode(baselineFile.readAsStringSync())
                    as Map<String, Object?>,
              ),
            )
          : 'no $_baselinePath yet: run with $_writeBaseline=1 to make one';

      // ignore: avoid_print
      print(
        '\nLottie playback, $_displayEdge px stickers, $_measuredTicks ticks '
        '(+$_warmupTicks warm-up), real native library, debug (JIT) mode.\n'
        'Absolute timings on a development machine are noisy: read the shape '
        'and the ratios, not the milliseconds.\n\n'
        '${_table(byCount)}\n\n'
        'Whole-page upload (each tick uploads every dirty page in full):\n'
        '${_uploadVerdict(byCount)}\n\n'
        '$comparison\n\nwrote $_outputPath',
      );
    }, timeout: const Timeout(Duration(minutes: 5)));
  }

  group('BenchReport.compareTo', () {
    final baseline = _report({
      'tick': (MetricKind.milliseconds, 2.0),
      'bytes': (MetricKind.count, 1000),
      'gone': (MetricKind.ratio, 1.0),
    });

    test('a timing within 50 percent of the baseline is the same', () {
      final current = _report({'tick': (MetricKind.milliseconds, 2.9)});
      expect(_drift(current, baseline, 'tick'), Drift.same);
    });

    test('a timing over 50 percent above the baseline is worse', () {
      final current = _report({'tick': (MetricKind.milliseconds, 3.2)});
      expect(_drift(current, baseline, 'tick'), Drift.worse);
    });

    test('a timing under two thirds of the baseline is better', () {
      final current = _report({'tick': (MetricKind.milliseconds, 1.0)});
      expect(_drift(current, baseline, 'tick'), Drift.better);
    });

    test('a count is held to 5 percent', () {
      expect(
        _drift(_report({'bytes': (MetricKind.count, 1049)}), baseline, 'bytes'),
        Drift.same,
      );
      expect(
        _drift(_report({'bytes': (MetricKind.count, 1060)}), baseline, 'bytes'),
        Drift.worse,
      );
    });

    test('a metric the run no longer reports is missing, a new one added', () {
      final current = _report({'fresh': (MetricKind.ratio, 1)});
      expect(_drift(current, baseline, 'gone'), Drift.missing);
      expect(_drift(current, baseline, 'fresh'), Drift.added);
    });

    test('a baseline of zero is the same only at zero', () {
      final zero = _report({'bytes': (MetricKind.count, 0)});
      expect(_drift(zero, zero, 'bytes'), Drift.same);
      expect(
        _drift(_report({'bytes': (MetricKind.count, 1)}), zero, 'bytes'),
        Drift.worse,
      );
    });

    test('survives a trip through json', () {
      final decoded = BenchReport.fromJson(baseline.toJson());
      expect(decoded.compareTo(baseline).map((c) => c.drift).toSet(), {
        Drift.same,
      });
    });
  });
}

BenchReport _report(Map<String, (MetricKind, double)> metrics) => BenchReport({
  for (final e in metrics.entries) e.key: BenchMetric(e.value.$1, e.value.$2),
});

Drift _drift(BenchReport current, BenchReport baseline, String key) =>
    current.compareTo(baseline).singleWhere((c) => c.key == key).drift;
