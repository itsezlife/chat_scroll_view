// The scroll trace behind the cache benchmarks: a catalogue scrolled down a
// screen at a time and back, counting the attaches on the way back that find
// their entry still decoded. Counts, not time, so the result is exact.
//
// Cell sizes are decoded RGBA at 3x density: a sticker panel cell of 64 dp,
// a custom emoji of 34 dp (Telegram's keyboard size), an animated sticker of
// 85 dp whose entry costs two frame buffers, as the Android client counts a
// Lottie drawable (width * height * 4 * 2).

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';

const mebibyte = 1024 * 1024;

/// A catalogue the trace scrolls over.
final class TraceWorkload {
  const TraceWorkload({
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

const stickersWorkload = TraceWorkload(
  name: 'stickers (192 px, 144 KiB, 600 cells, 24 visible)',
  cells: 600,
  visible: 24,
  perRow: 4,
  bytesPerCell: 192 * 192 * 4,
  tier: AssetTier.still,
);

const customEmojiWorkload = TraceWorkload(
  name: 'custom emoji (102 px, 40 KiB, 2000 cells, 64 visible)',
  cells: 2000,
  visible: 64,
  perRow: 8,
  bytesPerCell: 102 * 102 * 4,
  tier: AssetTier.still,
);

const animatedWorkload = TraceWorkload(
  name: 'animated stickers (256 px, 512 KiB, 120 cells, 12 visible)',
  cells: 120,
  visible: 12,
  perRow: 3,
  bytesPerCell: 256 * 256 * 4 * 2,
  tier: AssetTier.animated,
);

ContentKey traceKey(int n) => ContentKey.document('doc-$n');

/// What the scroll trace saw.
final class TraceResult {
  TraceResult(this.hitsBack, this.attachesBack, this.peakBytes, this.evictions);

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
TraceResult scrollDownAndBack(
  TraceWorkload workload,
  int budgetBytes,
  int screens,
) {
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
      final hit = scope.contains(traceKey(n), workload.spec);
      if (back) {
        attachesBack++;
        if (hit) hitsBack++;
      }
      bound[n] = scope.attach(traceKey(n), workload.spec, const AssetProfile());
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
  return TraceResult(
    hitsBack,
    attachesBack,
    peak,
    evictions < 0 ? 0 : evictions,
  );
}
