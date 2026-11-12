import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/frame_pool.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/lottie_decoder.dart';
import 'package:lottie_native/lottie_native.dart';

/// One 128 px page: four 64 px cells, so a pool of four leases.
const _budget = 128 * 128 * 4;

const _info = LottieInfo(
  width: 64,
  height: 64,
  frameCount: 30,
  frameRate: 60,
  features: LottieFeatures.none,
);

const _spec = AssetSpec(pixelWidth: 64, pixelHeight: 64);
const _plays = AssetProfile(animate: true);

ui.Image _image() {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2), ui.Paint());
  final picture = recorder.endRecording();
  final image = picture.toImageSync(4, 4);
  picture.dispose();
  return image;
}

Future<ui.Image> _upload(Uint8List pixels, int side) => Future.value(_image());

/// Answers every request at once with a Lottie animation played through
/// [scheduler], as a memory hit of the decoder does.
final class _LottieProducer implements AssetProducer {
  _LottieProducer(this.scheduler);

  final LottieFrameScheduler scheduler;

  @override
  AssetTask produce(
    AssetRequest request,
    AssetProgress progress,
    AssetDemand demand,
  ) {
    progress.advance(
      AssetStage.full,
      LottieAnimationPaintable(
        key: request.key,
        handle: const LottieHandle(1),
        info: _info,
        firstFrame: _image(),
        scheduler: scheduler,
        renderEdge: 48,
      ),
      bytes: 1,
      tier: AssetTier.animated,
    );
    return const _NoTask();
  }
}

final class _NoTask implements AssetTask {
  const _NoTask();

  @override
  void cancel() {}
}

/// The leases of a surface's cells as a fling moves them: the scope, the
/// scheduler and the paintables together, on one manual clock.
void main() {
  late ManualPlaybackTickSource ticks;
  late PlaybackClock clock;
  late ManualRetentionTimers timers;
  late LottieFrameScheduler scheduler;
  late AssetCacheScope scope;
  var now = Duration.zero;

  setUp(() {
    now = Duration.zero;
    ticks = ManualPlaybackTickSource();
    clock = PlaybackClock(ticks: ticks);
    timers = ManualRetentionTimers();
    scheduler = LottieFrameScheduler(
      atlas: FrameAtlas<Object>(
        renderer: FakeFrameRenderer(),
        memory: ListFramePageMemory(),
        budgetBytes: _budget,
        sizeClasses: const [64],
        upload: _upload,
      ),
      clock: clock,
      startTimer: timers.start,
    );
    scope = AssetCacheScope(producer: _LottieProducer(scheduler), clock: clock);
  });
  tearDown(() {
    scope.dispose();
    scheduler.dispose();
    clock.dispose();
  });

  ContentKey cell(int index) => ContentKey.document('cell-$index');

  /// One display frame of a surface: the clock ticks (the scheduler sends
  /// what was wanted), the surface paints what it shows, the frame ends and
  /// the event loop runs what it left behind.
  Future<void> frame(Iterable<AssetBinding> painted) async {
    now += const Duration(milliseconds: 16);
    ticks.tick(now);
    for (final binding in painted) {
      binding.advancePlayback();
    }
    timers.elapse(Duration.zero);
    await pumpEventQueue();
  }

  bool leased(AssetBinding binding) {
    final paintable = binding.paintable;
    return paintable.sprite != null || paintable.texture != null;
  }

  group('a fling through more cells than the pool holds', () {
    test('every cell on screen gets a frame while cells that left hold '
        'leases', () async {
      // Two cells on screen at a time, one new each frame: twelve cells
      // pass through a pool of four, far faster than the sweep runs.
      final shown = <int, AssetBinding>{};
      final starved = <int>[];
      for (var top = 0; top < 12; top++) {
        // The cell that scrolled out detaches, the one that scrolled in
        // attaches, as a surface's binding pool does at layout.
        shown.remove(top - 1)?.detach();
        shown.putIfAbsent(top, () => scope.attach(cell(top), _spec, _plays));
        shown.putIfAbsent(
          top + 1,
          () => scope.attach(cell(top + 1), _spec, _plays),
        );
        await frame(shown.values);
        // The frame wanted at the paint is rendered on the next tick.
        await frame(shown.values);
        for (final MapEntry(:key, :value) in shown.entries) {
          if (!leased(value)) starved.add(key);
        }
      }

      expect(starved, isEmpty, reason: 'cells on screen without a frame');
      expect(scheduler.leaseCount, lessThanOrEqualTo(4));
    });

    test(
      'cells hidden for the fling but still drawn keep their frames',
      () async {
        final cells = [
          for (var i = 0; i < 4; i++) scope.attach(cell(i), _spec, _plays),
        ];
        await frame(cells);
        await frame(cells);
        expect(cells.map(leased), everyElement(isTrue));

        // A panel hides its animated cells while a fling runs, and keeps
        // drawing them.
        for (final binding in cells) {
          binding.visible = false;
        }
        for (var i = 0; i < 4; i++) {
          await frame(cells);
        }

        expect(cells.map(leased), everyElement(isTrue));
        expect(scheduler.leaseCount, 4);
      },
    );

    test('cells that stay attached but are no longer drawn give their slots '
        'to the ones on screen', () async {
      final away = [
        for (var i = 0; i < 4; i++) scope.attach(cell(i), _spec, _plays),
      ];
      await frame(away);
      await frame(away);
      // Out of the painted band but inside the attach window: still
      // visible as far as their bindings say, and never painted again.
      for (var i = 0; i < 12; i++) {
        await frame(const []);
      }

      final shown = [
        for (var i = 4; i < 6; i++) scope.attach(cell(i), _spec, _plays),
      ];
      await frame(shown);
      await frame(shown);

      expect(shown.map(leased), everyElement(isTrue));
    });
  });

  group('a held panel', () {
    test('keeps the leases of its cells however long it is hidden', () async {
      final cells = [
        for (var i = 0; i < 4; i++) scope.attach(cell(i), _spec, _plays),
      ];
      await frame(cells);
      await frame(cells);

      // Hidden: the panel holds every binding, and nothing paints them.
      for (final binding in cells) {
        binding
          ..held = true
          ..visible = false;
      }
      final other = scope.attach(cell(9), _spec, _plays);
      for (var i = 0; i < 20; i++) {
        await frame([other]);
      }
      timers.elapse(const Duration(seconds: 3)); // the sweep, twice over

      expect(cells.map(leased), everyElement(isTrue));
      expect(leased(other), isFalse, reason: 'the pool is the held cells');
    });
  });
}
