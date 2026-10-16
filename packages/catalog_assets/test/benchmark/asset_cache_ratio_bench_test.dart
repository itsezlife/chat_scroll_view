// Headless ratio benchmark of the asset cache: what the nightly job tracks.
//
//   flutter test test/benchmark/asset_cache_ratio_bench_test.dart
//   BENCH_REPORT=out.json flutter test test/benchmark/asset_cache_ratio_bench_test.dart
//
// Four probes, each reduced to numbers that do not depend on the machine:
//
//   * churn: attach + produce + detach (+ evict) cycles, as a ratio against a
//     bare byte-budgeted LRU doing the same bookkeeping on the same machine,
//     and the evicting cycle against the all-resident one;
//   * LRU pressure: hit rates of the scroll trace at the default budgets
//     (counts, so exact);
//   * clock fan-out: one tick to N animated bindings, as cost per binding
//     against N = 10 (a flat line is 1), against N closures called in a loop,
//     and the repaint requests the fps cap lets through;
//   * page holds: glyph bindings holding atlas pages of a real
//     `GlyphPageResidency`, against plain entries, with memory pressure.
//
// The invariants (budget respected, holds balanced, pinned pages survive
// pressure) are asserted because they are deterministic. No time is asserted:
// debug-mode microseconds are inflated by asserts and noisy, ratios are the
// signal, and the nightly comparison (scripts/bench) is where a drift in one
// is judged, never here. It makes no claim about fling smoothness or decode
// cost: no pixel is decoded and nothing is rasterised.

import 'dart:ui';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'ratio_report.dart';
import 'scroll_trace.dart';

const _stillSpec = AssetSpec(pixelWidth: 128, pixelHeight: 128);
const _entryBytes = 64 * 1024;

AssetCacheScope _scope({
  required FakeAssetProducer producer,
  GlyphSpriteSource? glyphSource,
  ManualPlaybackTickSource? ticks,
}) => AssetCacheScope(
  producer: producer,
  glyphSource: glyphSource,
  clock: PlaybackClock(ticks: ticks ?? ManualPlaybackTickSource()),
);

FakeAssetProducer _stillProducer() =>
    FakeAssetProducer()
      ..onProduce = (attempt) =>
          attempt.advance(AssetStage.full, bytes: _entryBytes);

// ---------------------------------------------------------------------------
// Churn
// ---------------------------------------------------------------------------

/// Attach + detach cycles over [distinct] keys, round-robin: with the default
/// budget (24 MiB, 384 entries of 64 KiB) 200 keys stay resident and 5000 are
/// evicted all the time.
double _churnUsPerCycle(int distinct, {GlyphSpriteSource? glyphs}) {
  const operations = 20000;
  final producer = _stillProducer();
  final scope = _scope(producer: producer, glyphSource: glyphs);
  final keys = [
    for (var i = 0; i < distinct; i++) ContentKey.document('doc-$i'),
  ];
  final us = medianUsPerOp(() {
    for (var i = 0; i < operations; i++) {
      scope
          .attach(keys[i % distinct], _stillSpec, const AssetProfile())
          .detach();
    }
    producer.attempts.clear();
  }, operations: operations);
  expect(
    scope.bytesIn(AssetTier.still),
    lessThanOrEqualTo(AssetCacheBudgets.defaults.stillBytes),
    reason: 'idle bytes stay within the budget after $distinct-key churn',
  );
  scope.dispose();
  return us;
}

/// The same loop against the bookkeeping any byte-budgeted LRU must do: a
/// map hit or insert, a move to most-recent, evict oldest while over budget.
/// It is the machine-speed yardstick, not a competitor: the cache does
/// strictly more (pinning, staged readiness, listeners).
double _referenceUsPerCycle(int distinct) {
  const operations = 20000;
  const budget = 24 * mebibyte;
  final lru = <int, int>{};
  var bytes = 0;
  return medianUsPerOp(() {
    for (var i = 0; i < operations; i++) {
      final key = i % distinct;
      final held = lru.remove(key);
      if (held == null) bytes += _entryBytes;
      lru[key] = _entryBytes;
      while (bytes > budget) {
        final oldest = lru.keys.first;
        lru.remove(oldest);
        bytes -= _entryBytes;
      }
    }
  }, operations: operations);
}

// ---------------------------------------------------------------------------
// Clock fan-out
// ---------------------------------------------------------------------------

/// One tick to [bindings] animated bindings: microseconds per tick, and the
/// repaint requests per binding per tick.
({double usPerTick, double repaintsPerBindingTick}) _fanOut(int bindings) {
  const frames = 300;
  final producer = FakeAssetProducer()
    ..onProduce = (attempt) => attempt.advance(
      AssetStage.full,
      bytes: 16 * 1024,
      tier: AssetTier.animated,
      animated: true,
    );
  final source = ManualPlaybackTickSource();
  final scope = _scope(producer: producer, ticks: source);
  var repaints = 0;
  final attached = [
    for (var i = 0; i < bindings; i++)
      scope.attach(
        ContentKey.document('anim-$i'),
        // Small enough for the 30 fps cap: half the ticks reach a surface.
        const AssetSpec(pixelWidth: 100, pixelHeight: 100),
        const AssetProfile(animate: true),
      )..addListener(() => repaints++),
  ];
  var tick = 0;
  void play() {
    for (var i = 0; i < frames; i++) {
      source.tick(Duration(microseconds: ++tick * 16667));
    }
  }

  final us = medianUsPerOp(play, operations: frames);
  final ticks = tick;
  final perBindingTick = repaints / (bindings * ticks);
  for (final binding in attached) {
    binding.detach();
  }
  scope.dispose();
  return (usPerTick: us, repaintsPerBindingTick: perBindingTick);
}

/// Calling [n] closures once each: what a fan-out costs at the very least.
double _closuresUsPerTick(int n) {
  var sink = 0;
  final listeners = <void Function()>[for (var i = 0; i < n; i++) () => sink++];
  const frames = 300;
  final us = medianUsPerOp(() {
    for (var f = 0; f < frames; f++) {
      for (var i = 0; i < listeners.length; i += 2) {
        listeners[i]();
      }
    }
  }, operations: frames);
  expect(sink, greaterThan(0));
  return us;
}

// ---------------------------------------------------------------------------
// Page holds
// ---------------------------------------------------------------------------

/// A glyph source over a real `GlyphPageResidency`: which glyph is on which
/// page is a fixed table, the residency (holds, retention, memory pressure,
/// release) is the production one. The atlas that would bake and plan the
/// pages is not involved, so this measures the cache's side of the seam and
/// the residency, nothing about baking.
final class _ResidencySource implements GlyphSpriteSource {
  _ResidencySource(this.residency, int pages, int glyphsPerPage)
    : _pageOf = {
        for (var i = 0; i < pages * glyphsPerPage; i++)
          String.fromCharCode(0x4E00 + i): i ~/ glyphsPerPage,
      };

  final GlyphPageResidency residency;
  final Map<String, int> _pageOf;

  List<String> get glyphs => _pageOf.keys.toList();

  int pageOf(String glyph) => _pageOf[glyph]!;

  @override
  AtlasSprite? spriteOf(String glyph) {
    final page = _pageOf[glyph];
    final image = page == null ? null : residency.imageOf(page);
    if (page == null || image == null) return null;
    return AtlasSprite(
      pageIndex: page,
      page: image,
      source: const Rect.fromLTWH(0, 0, 1, 1),
    );
  }

  @override
  SpritePageHold? holdPageOf(String glyph) {
    final page = _pageOf[glyph];
    return page == null ? null : residency.hold(page);
  }

  @override
  void addPageListener(void Function(int pageIndex) listener) =>
      residency.addReleaseListener(listener);

  @override
  void removePageListener(void Function(int pageIndex) listener) =>
      residency.removeReleaseListener(listener);
}

Image _pageImage() {
  final recorder = PictureRecorder();
  Canvas(recorder).drawColor(const Color(0xFF000000), BlendMode.src);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(4, 4);
  picture.dispose();
  return image;
}

/// A source over [pages] resident pages of [glyphsPerPage] glyphs each.
({_ResidencySource source, ManualMemoryPressure pressure}) _residency(
  int pages, {
  int glyphsPerPage = 10,
}) {
  final pressure = ManualMemoryPressure();
  final timers = ManualRetentionTimers();
  final residency = GlyphPageResidency(
    memoryPressure: pressure,
    startTimer: timers.start,
  );
  for (var page = 0; page < pages; page++) {
    residency.admit(page, _pageImage());
  }
  addTearDown(() {
    residency.dispose();
    pressure.dispose();
  });
  return (
    source: _ResidencySource(residency, pages, glyphsPerPage),
    pressure: pressure,
  );
}

/// Attach + detach cycles of glyph bindings over [pages] resident pages.
double _glyphHoldUsPerCycle(int pages) {
  const operations = 20000;
  final (:source, pressure: _) = _residency(pages);
  final producer = _stillProducer();
  final scope = _scope(producer: producer, glyphSource: source);
  final keys = [for (final glyph in source.glyphs) ContentKey.unicode(glyph)];
  final us = medianUsPerOp(() {
    for (var i = 0; i < operations; i++) {
      scope
          .attach(keys[i % keys.length], _stillSpec, const AssetProfile())
          .detach();
    }
  }, operations: operations);
  for (var page = 0; page < pages; page++) {
    expect(
      source.residency.holdCount(page),
      0,
      reason: 'every hold taken at attach is given back at detach',
    );
  }
  expect(
    producer.attempts,
    isEmpty,
    reason: 'glyph keys never reach the producer',
  );
  scope.dispose();
  return us;
}

void main() {
  final report = RatioReport('catalog_assets');
  tearDownAll(() {
    report.writeIfRequested();
    // ignore: avoid_print
    print('\nasset-cache ratio benchmark: ${report.keys.length} metrics');
  });

  test('churn: attach, produce, detach and evict', () {
    final resident = _churnUsPerCycle(200);
    final evicting = _churnUsPerCycle(5000);
    final referenceResident = _referenceUsPerCycle(200);
    final referenceEvicting = _referenceUsPerCycle(5000);

    report
      ..ratio('churn.resident.over_reference', resident, referenceResident)
      ..ratio('churn.evicting.over_reference', evicting, referenceEvicting)
      ..ratio('churn.evicting.over_resident', evicting, resident);
    // ignore: avoid_print
    print(
      '\nchurn per cycle: resident ${resident.toStringAsFixed(2)} us '
      '(reference ${referenceResident.toStringAsFixed(2)}), evicting '
      '${evicting.toStringAsFixed(2)} us '
      '(reference ${referenceEvicting.toStringAsFixed(2)})',
    );
  });

  test('LRU pressure: hit rates on the way back at the default budgets', () {
    final stills = AssetCacheBudgets.defaults.stillBytes;
    final animated = AssetCacheBudgets.defaults.animatedBytes;
    final cases = {
      'stickers_4_screens': scrollDownAndBack(stickersWorkload, stills, 4),
      'stickers_8_screens': scrollDownAndBack(stickersWorkload, stills, 8),
      'emoji_4_screens': scrollDownAndBack(customEmojiWorkload, stills, 4),
      'emoji_8_screens': scrollDownAndBack(customEmojiWorkload, stills, 8),
      'animated_1_screen': scrollDownAndBack(animatedWorkload, animated, 1),
      'animated_4_screens': scrollDownAndBack(animatedWorkload, animated, 4),
    };
    for (final entry in cases.entries) {
      report.rate('lru.hit_rate.${entry.key}', entry.value.hitRate);
    }

    // The documented defaults: four screens of stills and one of animations
    // come back from the cache.
    expect(cases['stickers_4_screens']!.hitRate, greaterThanOrEqualTo(0.9));
    expect(cases['emoji_4_screens']!.hitRate, greaterThanOrEqualTo(0.9));
    expect(cases['animated_1_screen']!.hitRate, greaterThanOrEqualTo(0.9));
  });

  test('clock fan-out: one tick to N animated bindings', () {
    final byCount = {
      for (final n in [10, 100, 1000]) n: _fanOut(n),
    };
    final perBinding10 = byCount[10]!.usPerTick / 10;
    final perBinding1000 = byCount[1000]!.usPerTick / 1000;

    report.ratio(
      'fanout.per_binding.1000_over_10',
      perBinding1000,
      perBinding10,
    );
    for (final entry in byCount.entries) {
      final n = entry.key;
      report
        ..ratio(
          'fanout.tick.$n.over_closures',
          entry.value.usPerTick,
          _closuresUsPerTick(n),
        )
        ..count(
          'fanout.repaints_per_binding_tick.$n',
          entry.value.repaintsPerBindingTick,
        );
      // The 30 fps cap lets every other 60 Hz tick through.
      expect(entry.value.repaintsPerBindingTick, closeTo(0.5, 0.01));
    }
  });

  test('page holds: glyph bindings holding atlas pages', () {
    final fewPages = _glyphHoldUsPerCycle(4);
    final manyPages = _glyphHoldUsPerCycle(256);
    final plain = _churnUsPerCycle(200);

    report
      ..ratio('glyph_hold.cycle.4_pages.over_plain', fewPages, plain)
      ..ratio('glyph_hold.cycle.256_pages.over_4_pages', manyPages, fewPages);
  });

  test('page holds: memory pressure releases exactly the unpinned pages', () {
    const pages = 16;
    const pinnedPages = 12;
    final (:source, :pressure) = _residency(pages);
    final scope = _scope(producer: _stillProducer(), glyphSource: source);
    final bindings = [
      for (var page = 0; page < pinnedPages; page++)
        scope.attach(
          ContentKey.unicode(source.glyphs[page * 10]),
          _stillSpec,
          const AssetProfile(),
        ),
    ];
    expect(source.residency.residentPages, hasLength(pages));

    pressure.raise();

    // Pinned pages survive pressure (releasing them would only be re-read
    // within a few frames); the rest go.
    final resident = source.residency.residentPages.length;
    report
      ..count('pressure.pages_resident_after', resident)
      ..count('pressure.pages_released', pages - resident);
    expect(resident, pinnedPages);
    for (final binding in bindings) {
      expect(binding.paintable.sprite, isNotNull);
      binding.detach();
    }
    scope.dispose();
  });
}
