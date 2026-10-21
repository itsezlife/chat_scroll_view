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
// The workloads and the scroll trace are in scroll_trace.dart, shared with the
// ratio benchmark the nightly job runs (asset_cache_ratio_bench_test.dart).

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'scroll_trace.dart';

String _row(String label, List<String> cells) =>
    '${label.padRight(9)}${cells.map((c) => c.padLeft(9)).join()}';

void main() {
  const budgetsMiB = [1, 2, 4, 8, 12, 16, 24, 32, 48];

  void sweep(TraceWorkload workload, int screens) {
    test('hit rate on the way back, ${workload.name}, $screens screens', () {
      final rates = <double>[];
      final lines = <String>[
        _row('budget', [for (final b in budgetsMiB) '$b MiB']),
      ];
      for (final mib in budgetsMiB) {
        final result = scrollDownAndBack(workload, mib * mebibyte, screens);
        rates.add(result.hitRate);
        // The invariant under test: the unattached part never exceeds the
        // budget; the only bytes above it are what a window of visible cells
        // pins.
        final pinned = workload.visible * workload.bytesPerCell;
        expect(
          result.peakBytes,
          lessThanOrEqualTo(mib * mebibyte + pinned),
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
    sweep(stickersWorkload, 4);
    sweep(stickersWorkload, 8);
    sweep(customEmojiWorkload, 4);
    sweep(customEmojiWorkload, 8);
    sweep(animatedWorkload, 1);
    sweep(animatedWorkload, 2);
    sweep(animatedWorkload, 4);
  });

  group('the documented defaults', () {
    test('keep four screens of stills and one screen of animations', () {
      // Scrolling back four screens of stickers or custom emoji, or the
      // screen of animations just scrolled past, is the pager keep-alive and
      // scroll-back case the budget exists for. Further back, decoding again
      // is the expected price: an animation costs half a MiB, so 12 MiB is
      // one screen of them behind the visible one.
      final stickers = scrollDownAndBack(
        stickersWorkload,
        AssetCacheBudgets.defaults.stillBytes,
        4,
      );
      final emoji = scrollDownAndBack(
        customEmojiWorkload,
        AssetCacheBudgets.defaults.stillBytes,
        4,
      );
      final animated = scrollDownAndBack(
        animatedWorkload,
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
        scope.attach(traceKey(i % 5000), spec, const AssetProfile()).detach();
      }

      watch.stop();
      final perOp = watch.elapsedMicroseconds / operations;
      // ignore: avoid_print
      print(
        '\nchurn: $operations attach+produce+detach+evict cycles, '
        '${perOp.toStringAsFixed(2)} us each, '
        '${scope.entryCount} entries and '
        '${(scope.bytesIn(AssetTier.still) / mebibyte).toStringAsFixed(1)} '
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
              traceKey(i),
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
