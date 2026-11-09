/// A surface that stands over the others (a content preview): it plays its
/// own pass from the first frame each time it attaches, and a background hold
/// stills every other surface of the scope while it plays.
///
/// **Seam:** an [AssetCacheScope] over a [FakeAssetProducer] whose
/// paintables play a frame sequence, a [PlaybackClock] on a
/// [ManualPlaybackTickSource], and the frame each paint draws
/// ([FakeAssetPaintable.frameShown]).
library;

import 'dart:ui';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

const _a = ContentKey.document('sticker-a');
const _b = ContentKey.document('sticker-b');
const _cell = AssetSpec(pixelWidth: 160, pixelHeight: 160);
const _preview = AssetSpec(pixelWidth: 600, pixelHeight: 600);
const _plays = AssetProfile(animate: true);
const _foreground = AssetProfile(animate: true, foreground: true);

// Ten frames of 100 ms: a pass is a second.
final _frames = List.filled(10, const Duration(milliseconds: 100));

void main() {
  late FakeAssetProducer producer;
  late ManualPlaybackTickSource ticks;
  late AssetCacheScope scope;
  var now = Duration.zero;

  setUp(() {
    producer = FakeAssetProducer();
    ticks = ManualPlaybackTickSource();
    scope = AssetCacheScope(
      producer: producer,
      clock: PlaybackClock(ticks: ticks),
    );
    now = Duration.zero;
  });
  tearDown(() => scope.dispose());

  void paint(AssetBinding binding) =>
      binding.paint(Canvas(PictureRecorder()), const Rect.fromLTWH(0, 0, 8, 8));

  // Attaches [key] at [spec]; a first attach decodes it into a sequence.
  (AssetBinding, FakeAssetPaintable) attach(
    ContentKey key,
    AssetSpec spec,
    AssetProfile profile,
  ) {
    final binding = scope.attach(key, spec, profile);
    final attempts = producer.attemptsFor(AssetRequest(key, spec));
    if (attempts.isNotEmpty && attempts.last.paintables.isEmpty) {
      attempts.last.advance(
        AssetStage.full,
        tier: AssetTier.animated,
        frames: _frames,
      );
    }
    final paintable = attempts.last.paintables.last;
    return (binding, paintable);
  }

  // Runs the clock for [span] in 50 ms frames, painting [bindings] on each
  // and recording the frame each paintable drew.
  Map<FakeAssetPaintable, List<int>> run(
    Duration span,
    List<(AssetBinding, FakeAssetPaintable)> bindings,
  ) {
    final shown = {for (final (_, p) in bindings) p: <int>[]};
    final end = now + span;
    while (now < end) {
      now += const Duration(milliseconds: 50);
      ticks.tick(now);
      for (final (binding, paintable) in bindings) {
        paint(binding);
        shown[paintable]!.add(paintable.frameShown);
      }
    }
    return shown;
  }

  Matcher startsAtZeroAndAdvances() => predicate<List<int>>((frames) {
    if (frames.isEmpty || frames.first != 0) return false;
    for (var i = 1; i < frames.length; i++) {
      if (frames[i] < frames[i - 1]) return false;
    }
    return true;
  }, 'starts at frame 0 and only advances');

  group('a foreground surface', () {
    test('plays from the first frame each time it opens, whatever its entry '
        'played before: open, slide to another cell and back', () {
      final cellA = attach(_a, _cell, _plays);
      final cellB = attach(_b, _cell, _plays);
      run(const Duration(milliseconds: 700), [cellA, cellB]);

      final previewA = attach(_a, _preview, _foreground);
      final first = run(const Duration(milliseconds: 450), [previewA]);
      expect(first[previewA.$2], startsAtZeroAndAdvances());

      // The finger slides to B: A's preview detaches, B's attaches.
      previewA.$1.detach();
      final previewB = attach(_b, _preview, _foreground);
      final second = run(const Duration(milliseconds: 300), [previewB]);
      expect(second[previewB.$2], startsAtZeroAndAdvances());

      // And back to A: its entry is still cached, half way into its pass.
      previewB.$1.detach();
      final again = attach(_a, _preview, _foreground);
      expect(
        identical(again.$2, previewA.$2),
        isTrue,
        reason: 'the cached entry is reused, not decoded again',
      );
      final third = run(const Duration(milliseconds: 300), [again]);
      expect(third[again.$2], startsAtZeroAndAdvances());
    });

    test('a surface that is not in the foreground goes on from its frame', () {
      final cell = attach(_a, _cell, _plays);
      run(const Duration(milliseconds: 400), [cell]);
      final at = cell.$2.frameShown;
      cell.$1.detach();

      final back = attach(_a, _cell, _plays);
      final frames = run(const Duration(milliseconds: 100), [back]);

      expect(frames[back.$2]!.first, greaterThanOrEqualTo(at));
    });
  });

  group('a background hold', () {
    test('stills every surface but the foreground one, without pausing the '
        'clock; released, they go on from their frame', () {
      final cell = attach(_a, _cell, _plays);
      run(const Duration(milliseconds: 300), [cell]);
      final at = cell.$2.frameShown;

      final hold = scope.holdBackground();
      final preview = attach(_a, _preview, _foreground);
      final during = run(const Duration(milliseconds: 600), [cell, preview]);

      expect(cell.$1.isPlaying, isFalse);
      expect(cell.$2.keepsFrame, isTrue, reason: 'its frame stays on screen');
      expect(during[cell.$2], everyElement(at));
      expect(preview.$1.isPlaying, isTrue);
      expect(during[preview.$2], startsAtZeroAndAdvances());
      expect(during[preview.$2]!.last, greaterThan(0));
      expect(scope.clock.isPaused, isFalse);

      preview.$1.detach();
      hold.release();
      final after = run(const Duration(milliseconds: 100), [cell]);

      expect(cell.$1.isPlaying, isTrue);
      expect(after[cell.$2]!.first, at, reason: 'not the clock time missed');
      expect(after[cell.$2]!.last, greaterThanOrEqualTo(at));
    });

    test('holds a surface that attaches while it is on', () {
      final hold = scope.holdBackground();
      final cell = attach(_a, _cell, _plays);

      expect(cell.$1.isPlaying, isFalse);

      hold.release();
      expect(cell.$1.isPlaying, isTrue);
    });

    test('holds count; a release is idempotent; a surface held on its own '
        'stays held', () {
      final cell = attach(_a, _cell, _plays);
      final own = attach(_b, _cell, _plays);
      own.$1.held = true;

      final first = scope.holdBackground();
      final second = scope.holdBackground();
      first
        ..release()
        ..release();
      expect(cell.$1.isPlaying, isFalse);

      second.release();
      expect(cell.$1.isPlaying, isTrue);
      expect(own.$1.isPlaying, isFalse);
      expect(own.$1.held, isTrue);
    });

    test('is honoured by a glyph drawn as an entry', () {
      const glyph = ContentKey.unicode('😀');
      final binding = scope.attach(glyph, _cell, _plays);
      producer.last.advance(
        AssetStage.full,
        tier: AssetTier.animated,
        frames: _frames,
      );
      expect(binding.isPlaying, isTrue);

      final hold = scope.holdBackground();
      expect(binding.isPlaying, isFalse);
      hold.release();
      expect(binding.isPlaying, isTrue);
    });
  });
}
