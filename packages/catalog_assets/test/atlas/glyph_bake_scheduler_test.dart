import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const _perPage = 676; // GlyphAtlasLayout().cellsPerPage

// A 120 Hz display.
const _budget = Duration(microseconds: 8333);

/// A pause signal that can say whether anyone still listens to it.
class _Signal extends ValueNotifier<bool> {
  // ignore: avoid_positional_boolean_parameters, mirrors ValueNotifier.
  _Signal(super.value);

  bool get isListenedTo => hasListeners;
}

List<String> _glyphs(int count) => [for (var i = 0; i < count; i++) 'g$i'];

void main() {
  late ManualBakeClock clock;
  late FakeGlyphRasteriser rasteriser;
  late FakeGlyphPageStore store;
  late FakeBakeFrameSource frames;
  late _Signal visible;
  late _Signal scrolling;
  late _Signal opening;
  late List<int> bakedPages;
  late GlyphBakeScheduler scheduler;

  setUp(() {
    clock = ManualBakeClock();
    rasteriser = FakeGlyphRasteriser();
    store = FakeGlyphPageStore();
    frames = FakeBakeFrameSource(budget: _budget);
    visible = _Signal(true);
    scrolling = _Signal(false);
    opening = _Signal(false);
    bakedPages = [];
  });
  tearDown(() async {
    visible.dispose();
    scrolling.dispose();
    opening.dispose();
    await store.clear();
  });

  /// Builds a scheduler over [count] glyphs; disposed with the test.
  GlyphBakeScheduler build(
    int count, {
    GlyphBaker? baker,
    int settleFrames = 2,
    BakeGovernor? governor,
  }) {
    final b =
        baker ??
        GlyphBaker(
          index: GlyphAtlasIndex(_glyphs(count)),
          rasteriser: rasteriser,
          store: store,
        );
    addTearDown(b.dispose);
    scheduler = GlyphBakeScheduler(
      baker: b,
      frames: frames,
      clock: clock.read,
      signals: BakePauseSignals(
        panelVisible: visible,
        scrolling: scrolling,
        panelOpening: opening,
      ),
      governor: governor,
      settleFrames: settleFrames,
      onPageBaked: bakedPages.add,
    );
    addTearDown(scheduler.dispose);
    return scheduler;
  }

  /// One frame: delivers it, then lets the step it started finish.
  Future<void> frame({Duration? cost}) async {
    frames.pump(cost: cost);
    await pumpEventQueue();
  }

  /// Frames until [done] or [limit]; returns how many it took.
  Future<int> framesUntil(bool Function() done, {int limit = 500}) async {
    var n = 0;
    while (!done() && n < limit) {
      await frame();
      n++;
    }
    return n;
  }

  group('pacing', () {
    test('nothing is requested until the scheduler is started', () {
      build(40);

      expect(frames.hasPendingRequest, isFalse);
    });

    test('bakes a full pace of glyphs each frame once started', () async {
      build(100, settleFrames: 0).start();

      await frame();
      expect(rasteriser.painted, hasLength(16));
      await frame();
      expect(rasteriser.painted, hasLength(32));
    });

    test(
      'bakes the whole catalogue and then asks for no more frames',
      () async {
        build(100).start();

        await framesUntil(() => scheduler.isComplete);

        expect(scheduler.isComplete, isTrue);
        expect(bakedPages, [0]);
        expect(frames.hasPendingRequest, isFalse);
      },
    );

    test('the pace falls when the engine reports expensive frames', () async {
      build(2000, settleFrames: 0).start();
      await frame(); // 16 glyphs
      final before = rasteriser.painted.length;

      await frame(cost: _budget * 1.5);
      await frame(cost: _budget * 1.5);
      final afterTwo = rasteriser.painted.length;
      await frame(cost: _budget * 1.5);

      expect(before, 16);
      expect(afterTwo - before, 8 + 4, reason: 'the pace halved per frame');
      expect(scheduler.glyphsPerFrame, 2);
    });

    test('the pace rises again when frames turn cheap', () async {
      build(2000, settleFrames: 0).start();
      for (var i = 0; i < 4; i++) {
        await frame(cost: _budget * 1.5);
      }
      final low = scheduler.glyphsPerFrame;

      for (var i = 0; i < 4; i++) {
        await frame(cost: _budget * 0.1);
      }

      expect(low, lessThan(16));
      expect(scheduler.glyphsPerFrame, greaterThan(low));
    });

    test('a frame with no new measurement leaves the pace alone', () async {
      build(2000, settleFrames: 0).start();

      for (var i = 0; i < 6; i++) {
        await frame();
      }

      expect(scheduler.glyphsPerFrame, 16);
    });

    test('a bake that is costly on its own slows itself down', () async {
      // The engine reports nothing, but each glyph costs 1 ms of the clock,
      // so a 16 glyph step overruns the 8.3 ms budget by itself.
      rasteriser = FakeGlyphRasteriser(
        onPaint: (_) => clock.advance(const Duration(milliseconds: 1)),
      );
      build(2000, settleFrames: 0).start();
      final costs = <Duration>[];

      for (var i = 0; i < 12; i++) {
        final t0 = clock.now;
        await frame();
        costs.add(clock.now - t0);
      }

      expect(scheduler.glyphsPerFrame, lessThan(16));
      // After the first steps the governor found a pace that fits.
      expect(
        costs.skip(4).every((c) => c <= _budget),
        isTrue,
        reason: '$costs',
      );
    });

    test('the visible page lands within one page of work', () async {
      const glyphCount = 2 * _perPage + 10;
      build(glyphCount, settleFrames: 0)
        ..prioritise(['g${_perPage + 5}'])
        ..start();

      final toVisible = await framesUntil(() => bakedPages.isNotEmpty);
      final toAll = toVisible + await framesUntil(() => scheduler.isComplete);

      expect(bakedPages.first, 1);
      // 676 glyphs at 16 a frame is 43 strips, then the page composes.
      expect(toVisible, (_perPage / 16).ceil() + 1);
      expect(toVisible, lessThan(toAll / 2));
      expect(bakedPages, [
        1,
        0,
        2,
      ], reason: 'then the nearest pages, lower index first');
    });

    test('prioritising while running redirects the next page', () async {
      build(2 * _perPage + 10, settleFrames: 0).start();
      for (var i = 0; i < 5; i++) {
        await frame();
      }

      scheduler.prioritise(['g${_perPage + 1}']);
      await framesUntil(() => bakedPages.isNotEmpty);

      expect(bakedPages, [1]);
    });
  });

  group('pausing', () {
    test('a hidden panel bakes nothing', () async {
      visible.value = false;
      build(100).start();

      expect(frames.hasPendingRequest, isFalse);
      await frame();
      await frame();
      expect(rasteriser.painted, isEmpty);
    });

    test('showing the panel starts the bake after the settle frames', () async {
      visible.value = false;
      build(100).start();

      visible.value = true;
      await frame();
      await frame();
      expect(rasteriser.painted, isEmpty, reason: 'settling');
      await frame();
      expect(rasteriser.painted, hasLength(16));
    });

    test('baking pauses at once when scrolling starts', () async {
      build(100, settleFrames: 0).start();
      await frame();
      final painted = rasteriser.painted.length;

      scrolling.value = true;

      expect(frames.hasPendingRequest, isFalse);
      await frame();
      await frame();
      expect(rasteriser.painted, hasLength(painted));
    });

    test('baking resumes after scrolling stops, once frames settle', () async {
      build(100).start();
      await frame();
      await frame();
      await frame();
      final painted = rasteriser.painted.length;
      scrolling.value = true;
      await frame();

      scrolling.value = false;
      await frame();
      await frame();
      expect(rasteriser.painted, hasLength(painted), reason: 'settling');
      await frame();

      expect(rasteriser.painted.length, painted + 16);
    });

    test('settling starts over when scrolling resumes', () async {
      build(100).start();
      scrolling.value = true;
      scrolling.value = false;
      await frame();
      await frame();
      scrolling.value = true;
      scrolling.value = false;

      await frame();
      await frame();

      expect(rasteriser.painted, isEmpty);
    });

    test('the open animation pauses baking and its end resumes it', () async {
      opening.value = true;
      build(100, settleFrames: 0).start();
      await frame();
      await frame();
      expect(rasteriser.painted, isEmpty);
      expect(frames.hasPendingRequest, isFalse);

      opening.value = false;
      await frame();

      expect(rasteriser.painted, hasLength(16));
    });

    test('a step cost from before a pause is not held against the first '
        'frame after it', () async {
      // Each glyph costs 1 ms of the clock, so the first step overruns the
      // budget by itself; the pause comes before anything observes that.
      rasteriser = FakeGlyphRasteriser(
        onPaint: (_) => clock.advance(const Duration(milliseconds: 1)),
      );
      build(2000, settleFrames: 0).start();
      await frame();
      expect(scheduler.glyphsPerFrame, 16);

      scrolling.value = true;
      scrolling.value = false;
      await frame(cost: _budget * 0.1);

      expect(
        scheduler.glyphsPerFrame,
        16,
        reason: 'only the engine\'s cheap frame was observed',
      );
    });

    test('every pause input must be clear for baking to run', () async {
      build(100, settleFrames: 0).start();
      scrolling.value = true;
      opening.value = true;

      scrolling.value = false;
      expect(frames.hasPendingRequest, isFalse, reason: 'still opening');
      opening.value = false;
      expect(frames.hasPendingRequest, isTrue);
    });

    test('a pause keeps the progress: no glyph is rasterised twice', () async {
      build(100, settleFrames: 0).start();
      await frame();
      await frame();
      visible.value = false;
      await frame();
      visible.value = true;

      await framesUntil(() => scheduler.isComplete);

      expect(rasteriser.painted, _glyphs(100));
    });
  });

  group('teardown', () {
    test('dispose cancels the pending frame and leaves no listeners', () {
      build(100).start();
      expect(frames.hasPendingRequest, isTrue);

      scheduler.dispose();

      expect(frames.hasPendingRequest, isFalse);
      expect(visible.isListenedTo, isFalse);
      expect(scrolling.isListenedTo, isFalse);
      expect(opening.isListenedTo, isFalse);
    });

    test('dispose while paused leaves no listeners either', () {
      scrolling.value = true;
      build(100).start();

      scheduler.dispose();

      expect(frames.hasPendingRequest, isFalse);
      expect(scrolling.isListenedTo, isFalse);
    });

    test('a signal after dispose starts nothing', () async {
      build(100, settleFrames: 0).start();
      scheduler.dispose();

      scrolling.value = true;
      scrolling.value = false;
      await frame();

      expect(frames.hasPendingRequest, isFalse);
      expect(rasteriser.painted, isEmpty);
    });

    test('dispose while a step is running requests no further frame', () async {
      build(100, settleFrames: 0).start();
      frames.pump(); // the step starts, and has not finished yet

      scheduler.dispose();
      await pumpEventQueue();

      expect(frames.hasPendingRequest, isFalse);
    });

    test('dispose twice is harmless', () {
      build(100).start();

      scheduler
        ..dispose()
        ..dispose();
    });

    test('a completed bake holds nothing to dispose', () async {
      build(10).start();
      await framesUntil(() => scheduler.isComplete);

      expect(frames.hasPendingRequest, isFalse);
      scheduler.dispose();
      expect(visible.isListenedTo, isFalse);
    });
  });

  group('failure', () {
    test('a failing rasteriser is reported and stops the bake', () async {
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);
      rasteriser = FakeGlyphRasteriser(
        onPaint: (_) => throw StateError('no font'),
      );
      build(100, settleFrames: 0).start();

      await frame();

      expect(reported, hasLength(1));
      expect(reported.single.exception, isA<StateError>());
      expect(frames.hasPendingRequest, isFalse);
    });
  });
}
