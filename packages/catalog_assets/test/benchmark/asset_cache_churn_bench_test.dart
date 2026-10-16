// Headless churn micro-benchmark of the asset cache core. It is the
// measurement behind the default byte budgets (AssetCacheBudgets.defaults) and
// the playback fps caps (PlaybackPolicy); results are in the package README.
//
//   flutter test test/benchmark/asset_cache_churn_bench_test.dart
//
// What it measures, and what it does not:
//   * Hit rates of the byte-budgeted LRU on a scroll trace: counts, not time,
//     so they are exact and repeatable. The default budgets are read off the
//     sweep tables below.
//   * Cost of attach / detach / eviction churn and of one playback frame
//     fanned out to many bindings: debug-mode microseconds, inflated by
//     asserts. Ratios between runs are the signal, never the absolute number,
//     and nothing here asserts a time.
//   * It makes no claim about fling smoothness or decode cost: no pixels are
//     decoded and nothing is rasterised.
//
// Cell sizes are decoded RGBA at 3x density: a sticker panel cell of 64 dp,
// a custom emoji of 34 dp (Telegram's keyboard size), an animated sticker of
// 85 dp whose entry costs two frame buffers, as the Android client counts a
// Lottie drawable (width * height * 4 * 2).

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _mebibyte = 1024 * 1024;

/// A catalogue the trace scrolls over.
final class _Workload {
  const _Workload({
    required this.name,
    required this.cells,
    required this.visible,
    required this.perRow,
    required this.bytesPerCell,
    required this.tier,
  });

  final String name;
  final int cells;
  final int visible;
  final int perRow;
  final int bytesPerCell;
  final AssetTier tier;

  AssetSpec get spec => const AssetSpec(pixelWidth: 192, pixelHeight: 192);
}

const _stickers = _Workload(
  name: 'stickers (192 px, 144 KiB, 600 cells, 24 visible)',
  cells: 600,
  visible: 24,
  perRow: 4,
  bytesPerCell: 192 * 192 * 4,
  tier: AssetTier.still,
);

const _customEmoji = _Workload(
  name: 'custom emoji (102 px, 40 KiB, 2000 cells, 64 visible)',
  cells: 2000,
  visible: 64,
  perRow: 8,
  bytesPerCell: 102 * 102 * 4,
  tier: AssetTier.still,
);

const _animated = _Workload(
  name: 'animated stickers (256 px, 512 KiB, 120 cells, 12 visible)',
  cells: 120,
  visible: 12,
  perRow: 3,
  bytesPerCell: 256 * 256 * 4 * 2,
  tier: AssetTier.animated,
);

ContentKey _id(int n) => ContentKey.document('doc-$n');

/// What the scroll trace saw.
final class _Result {
  _Result(this.hitsBack, this.attachesBack, this.peakBytes, this.evictions);

  final int hitsBack;
  final int attachesBack;
  final int peakBytes;
  final int evictions;

  double get hitRate => attachesBack == 0 ? 0 : hitsBack / attachesBack;
}

/// Scrolls [screens] screens down a catalogue one row at a time, then back up
/// the same way, and counts how many attaches on the way back find their entry
/// already decoded. The entry is made at once when missing, as a memory-only
/// producer would.
_Result _scrollDownAndBack(_Workload workload, int budgetBytes, int screens) {
  final producer = FakeAssetProducer();
  final scope = AssetCacheScope(
    producer: producer,
    budgets: AssetCacheBudgets(
      stillBytes: budgetBytes,
      animatedBytes: budgetBytes,
    ),
    clock: PlaybackClock(ticks: ManualPlaybackTickSource()),
  );
  producer.onProduce = (attempt) => attempt.advance(
    AssetStage.full,
    bytes: workload.bytesPerCell,
    tier: workload.tier,
  );
  final bound = <int, AssetBinding>{};
  var hitsBack = 0;
  var attachesBack = 0;
  var peak = 0;
  var evictions = 0;

  void show(int first, {required bool back}) {
    final wanted = {
      for (var n = first; n < first + workload.visible; n++)
        if (n >= 0 && n < workload.cells) n,
    };
    for (final n in bound.keys.toList()) {
      if (!wanted.contains(n)) bound.remove(n)!.detach();
    }
    for (final n in wanted) {
      if (bound.containsKey(n)) continue;
      final hit = scope.contains(_id(n), workload.spec);
      if (back) {
        attachesBack++;
        if (hit) hitsBack++;
      }
      bound[n] = scope.attach(_id(n), workload.spec, const AssetProfile());
    }
    final bytes = scope.bytesIn(workload.tier);
    if (bytes > peak) peak = bytes;
  }

  final lastRow = screens * workload.visible ~/ workload.perRow;
  for (var row = 0; row <= lastRow; row++) {
    show(row * workload.perRow, back: false);
  }
  final entriesAtTurn = scope.entryCount;
  for (var row = lastRow; row >= 0; row--) {
    show(row * workload.perRow, back: true);
  }
  evictions = entriesAtTurn - scope.entryCount;
  for (final binding in bound.values) {
    binding.detach();
  }
  scope.dispose();
  return _Result(hitsBack, attachesBack, peak, evictions < 0 ? 0 : evictions);
}

String _row(String label, List<String> cells) =>
    '${label.padRight(9)}${cells.map((c) => c.padLeft(9)).join()}';

void main() {
  const budgetsMiB = [1, 2, 4, 8, 12, 16, 24, 32, 48];

  void sweep(_Workload workload, int screens) {
    test('hit rate on the way back, ${workload.name}, $screens screens', () {
      final rates = <double>[];
      final lines = <String>[
        _row('budget', [for (final b in budgetsMiB) '$b MiB']),
      ];
      for (final mib in budgetsMiB) {
        final result = _scrollDownAndBack(workload, mib * _mebibyte, screens);
        rates.add(result.hitRate);
        // The invariant under test: the unattached part never exceeds the
        // budget; the only bytes above it are what a window of visible cells
        // pins.
        final pinned = workload.visible * workload.bytesPerCell;
        expect(
          result.peakBytes,
          lessThanOrEqualTo(mib * _mebibyte + pinned),
          reason: 'peak bytes at $mib MiB',
        );
      }
      lines.add(
        _row('hit rate', [for (final r in rates) '${(r * 100).round()}%']),
      );
      // ignore: avoid_print
      print(
        '\n${workload.name}, scroll down $screens screens and back\n'
        '${lines.join('\n')}',
      );

      for (var i = 1; i < rates.length; i++) {
        expect(
          rates[i],
          greaterThanOrEqualTo(rates[i - 1]),
          reason: 'a larger budget never hits less often',
        );
      }
    });
  }

  group('hit-rate sweep', () {
    sweep(_stickers, 4);
    sweep(_stickers, 8);
    sweep(_customEmoji, 4);
    sweep(_customEmoji, 8);
    sweep(_animated, 1);
    sweep(_animated, 2);
    sweep(_animated, 4);
  });

  group('the documented defaults', () {
    test('keep four screens of stills and one screen of animations', () {
      // Scrolling back four screens of stickers or custom emoji, or the
      // screen of animations just scrolled past, is the pager keep-alive and
      // scroll-back case the budget exists for. Further back, decoding again
      // is the expected price: an animation costs half a MiB, so 12 MiB is
      // one screen of them behind the visible one.
      final stickers = _scrollDownAndBack(
        _stickers,
        AssetCacheBudgets.defaults.stillBytes,
        4,
      );
      final emoji = _scrollDownAndBack(
        _customEmoji,
        AssetCacheBudgets.defaults.stillBytes,
        4,
      );
      final animated = _scrollDownAndBack(
        _animated,
        AssetCacheBudgets.defaults.animatedBytes,
        1,
      );

      expect(stickers.hitRate, greaterThanOrEqualTo(0.9));
      expect(emoji.hitRate, greaterThanOrEqualTo(0.9));
      expect(animated.hitRate, greaterThanOrEqualTo(0.9));
    });
  });

  group('churn cost (debug-mode microseconds; ratios only)', () {
    test('attach, produce, detach and evict 20000 times', () {
      final producer = FakeAssetProducer();
      final scope = AssetCacheScope(
        producer: producer,
        clock: PlaybackClock(ticks: ManualPlaybackTickSource()),
      );
      producer.onProduce = (attempt) =>
          attempt.advance(AssetStage.full, bytes: 64 * 1024);
      const spec = AssetSpec(pixelWidth: 128, pixelHeight: 128);
      const operations = 20000;
      final watch = Stopwatch()..start();

      for (var i = 0; i < operations; i++) {
        // 5000 distinct entries cycled: far more than the budget keeps.
        scope.attach(_id(i % 5000), spec, const AssetProfile()).detach();
      }

      watch.stop();
      final perOp = watch.elapsedMicroseconds / operations;
      // ignore: avoid_print
      print(
        '\nchurn: $operations attach+produce+detach+evict cycles, '
        '${perOp.toStringAsFixed(2)} us each, '
        '${scope.entryCount} entries and '
        '${(scope.bytesIn(AssetTier.still) / _mebibyte).toStringAsFixed(1)} '
        'MiB resident at the end',
      );
      expect(
        scope.bytesIn(AssetTier.still),
        lessThanOrEqualTo(AssetCacheBudgets.defaults.stillBytes),
      );
      scope.dispose();
    });

    test('one frame fanned out to 100 playing bindings', () {
      final producer = FakeAssetProducer();
      final source = ManualPlaybackTickSource();
      final scope = AssetCacheScope(
        producer: producer,
        clock: PlaybackClock(ticks: source),
      );
      producer.onProduce = (attempt) => attempt.advance(
        AssetStage.full,
        bytes: 64 * 1024,
        tier: AssetTier.animated,
        animated: true,
      );
      var repaints = 0;
      for (var i = 0; i < 100; i++) {
        scope
            .attach(
              _id(i),
              const AssetSpec(pixelWidth: 100, pixelHeight: 100),
              const AssetProfile(animate: true),
            )
            .addListener(() => repaints++);
      }
      const frames = 600;
      final watch = Stopwatch()..start();

      for (var frame = 1; frame <= frames; frame++) {
        source.tick(Duration(microseconds: frame * 16667));
      }

      watch.stop();
      // ignore: avoid_print
      print(
        '\nplayback: $frames frames at 60 Hz, 100 small (30 fps cap) '
        'bindings: ${(watch.elapsedMicroseconds / frames).toStringAsFixed(1)} '
        'us per frame, $repaints repaint requests where an uncapped clock '
        'would make ${100 * frames}',
      );
      // Half the frames: the cap is doing its job.
      expect(repaints, 100 * frames ~/ 2);
      scope.dispose();
    });
  });
}
