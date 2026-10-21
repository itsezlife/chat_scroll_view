import 'dart:ui';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const _keyboardSpec = AssetSpec(pixelWidth: 72, pixelHeight: 72);
const _messageSpec = AssetSpec(pixelWidth: 36, pixelHeight: 36);
const _profile = AssetProfile();

ContentKey _glyph(String glyph) => ContentKey.unicode(glyph);

void main() {
  late FakeBakeFrameSource frames;
  late FakeGlyphPageStore store;
  late ManualRetentionTimers timers;
  late ValueNotifier<bool> visible;
  late ValueNotifier<bool> opening;
  late FakeAssetProducer producer;

  setUp(() {
    frames = FakeBakeFrameSource();
    store = FakeGlyphPageStore();
    timers = ManualRetentionTimers();
    visible = ValueNotifier<bool>(true);
    opening = ValueNotifier<bool>(false);
    producer = FakeAssetProducer();
  });
  tearDown(() async {
    visible.dispose();
    opening.dispose();
    await store.clear();
  });

  GlyphAtlas atlasOf(List<String> glyphs) {
    final atlas = GlyphAtlas(
      index: GlyphAtlasIndex(glyphs),
      rasteriser: FakeGlyphRasteriser(),
      store: store,
      frames: frames,
      clock: ManualBakeClock().read,
      panelVisible: visible,
      panelOpening: opening,
      residency: GlyphPageResidency(startTimer: timers.start),
    );
    addTearDown(atlas.dispose);
    return atlas;
  }

  AssetCacheScope scopeOf([GlyphSpriteSource? source]) {
    final scope = AssetCacheScope(
      producer: producer,
      glyphSource: source,
      clock: PlaybackClock(ticks: ManualPlaybackTickSource()),
    );
    addTearDown(scope.dispose);
    return scope;
  }

  Future<void> bakeAll() async {
    while (frames.hasPendingRequest) {
      frames.pump();
      await pumpEventQueue();
    }
  }

  group('a scope without a glyph source', () {
    test('hands unicode keys to the producer like any other content', () {
      final scope = scopeOf();

      final binding = scope.attach(_glyph('a'), _keyboardSpec, _profile);

      expect(binding.paintable.sprite, isNull);
      expect(binding.readiness.stage, AssetStage.none);
      expect(producer.attempts, hasLength(1));
    });

    test('has none to report', () {
      expect(scopeOf().glyphSource, isNull);
    });
  });

  group('a scope with an atlas', () {
    test('reports the source that was registered', () {
      final atlas = atlasOf(['a']);

      expect(scopeOf(atlas).glyphSource, same(atlas));
    });

    test('never asks the producer and keeps nothing in the cache', () {
      final scope = scopeOf(atlasOf(['a']));

      scope.attach(_glyph('a'), _keyboardSpec, _profile);

      expect(producer.attempts, isEmpty);
      expect(scope.entryCount, 0);
      expect(scope.bytesIn(AssetTier.still), 0);
    });

    test(
      'a unicode binding is a placeholder, then final with a sprite',
      () async {
        final atlas = atlasOf(['a', 'b'])..start();
        final binding = scopeOf(
          atlas,
        ).attach(_glyph('b'), _keyboardSpec, _profile);

        expect(binding.paintable.sprite, isNull);
        expect(binding.readiness, const AssetReadiness(AssetStage.placeholder));

        await bakeAll();

        expect(binding.paintable.sprite, isNotNull);
        expect(binding.paintable.sprite!.pageIndex, 0);
        expect(
          binding.readiness,
          const AssetReadiness(AssetStage.full, isFinal: true),
        );
      },
    );

    test('a glyph outside the plan is drawn as text, never a circle', () async {
      final atlas = atlasOf(['a'])..start();
      final binding = scopeOf(
        atlas,
      ).attach(_glyph('z'), _keyboardSpec, _profile);

      await bakeAll();

      expect(binding.paintable.sprite, isNull);
      expect(
        binding.readiness,
        const AssetReadiness(AssetStage.firstFrame),
        reason: 'drawable now, a sprite may still come',
      );
      expect(
        (Canvas canvas) =>
            binding.paint(canvas, const Rect.fromLTWH(0, 0, 32, 32)),
        paints..paragraph(),
      );
    });

    test('a planned glyph keeps its circle while the bake runs: no paragraph '
        'in a scrolled frame', () async {
      final atlas = atlasOf(['a']);
      final binding = scopeOf(
        atlas,
      ).attach(_glyph('a'), _keyboardSpec, _profile);

      expect(binding.readiness.stage, AssetStage.placeholder);
      expect(
        (Canvas canvas) =>
            binding.paint(canvas, const Rect.fromLTWH(0, 0, 32, 32)),
        isNot(paints..paragraph()),
      );
    });

    test(
      'a document key never has a sprite and goes to the producer',
      () async {
        final atlas = atlasOf(['a'])..start();
        final binding = scopeOf(
          atlas,
        ).attach(const ContentKey.document('a'), _keyboardSpec, _profile);

        await bakeAll();

        expect(binding.paintable.sprite, isNull);
        expect(producer.attempts, hasLength(1));
      },
    );

    test('the sprite capability is the same object across reads', () async {
      final atlas = atlasOf(['a'])..start();
      final binding = scopeOf(
        atlas,
      ).attach(_glyph('a'), _keyboardSpec, _profile);
      await bakeAll();

      expect(binding.paintable, same(binding.paintable));
      expect(binding.paintable.sprite, same(binding.paintable.sprite));
    });

    test('binding listeners hear a page being baked', () async {
      final atlas = atlasOf(['a'])..start();
      final binding = scopeOf(
        atlas,
      ).attach(_glyph('a'), _keyboardSpec, _profile);
      var heard = 0;
      binding.addListener(() => heard++);

      await bakeAll();

      expect(heard, 1);
    });

    test('a detached binding hears nothing', () async {
      final atlas = atlasOf(['a'])..start();
      final binding = scopeOf(
        atlas,
      ).attach(_glyph('a'), _keyboardSpec, _profile);
      var heard = 0;
      binding
        ..addListener(() => heard++)
        ..detach();

      await bakeAll();

      expect(heard, 0);
    });

    test(
      'after the scope is disposed the atlas is no longer listened to',
      () async {
        final atlas = atlasOf(['a'])..start();
        final scope = scopeOf(atlas);
        final binding = scope.attach(_glyph('a'), _keyboardSpec, _profile);
        var heard = 0;
        binding.addListener(() => heard++);

        scope.dispose();
        await bakeAll();

        expect(heard, 0);
      },
    );

    test('a binding whose atlas is gone has no sprite', () async {
      final atlas = atlasOf(['a'])..start();
      final binding = scopeOf(
        atlas,
      ).attach(_glyph('a'), _keyboardSpec, _profile);
      await bakeAll();
      expect(binding.paintable.sprite, isNotNull);

      atlas.dispose();

      expect(binding.paintable.sprite, isNull);
    });
  });

  group('page holds', () {
    // Counts are per page and belong to the binding that took them, so what
    // happens to the cache under a live binding cannot change them.
    test('a binding holds its glyph page from attach to detach', () {
      final atlas = atlasOf(['a', 'b']);
      final scope = scopeOf(atlas);
      const key = ContentKey.unicode('a');

      final first = scope.attach(key, _keyboardSpec, _profile);
      final second = scope.attach(key, _messageSpec, _profile);
      // The open panel holds every page as well: 1 here, plus one per binding.
      expect(atlas.residency.holdCount(0), 3);

      first.detach();
      expect(atlas.residency.holdCount(0), 2);
      second.detach();
      expect(atlas.residency.holdCount(0), 1);
    });

    test('detaching twice gives the page back once', () {
      final atlas = atlasOf(['a']);
      final scope = scopeOf(atlas);
      const key = ContentKey.unicode('a');
      final first = scope.attach(key, _keyboardSpec, _profile);
      scope.attach(key, _keyboardSpec, _profile);

      first
        ..detach()
        ..detach();

      expect(atlas.residency.holdCount(0), 2);
    });

    test('clearAll with live bindings leaves the counts alone', () {
      final atlas = atlasOf(['a', 'b']);
      final scope = scopeOf(atlas);
      final a = scope.attach(_glyph('a'), _keyboardSpec, _profile);
      final b = scope.attach(_glyph('b'), _keyboardSpec, _profile);

      scope.clearAll();
      expect(atlas.residency.holdCount(0), 3);

      a.detach();
      b.detach();
      expect(atlas.residency.holdCount(0), 1);
    });

    test(
      'pressure on the budget with live bindings leaves the counts alone',
      () {
        final atlas = atlasOf(['a']);
        final scope = scopeOf(atlas);
        final stale = scope.attach(_glyph('a'), _keyboardSpec, _profile);

        scope.budgets = const AssetCacheBudgets(
          stillBytes: 0,
          animatedBytes: 0,
        );
        expect(atlas.residency.holdCount(0), 2);

        final fresh = scope.attach(_glyph('a'), _keyboardSpec, _profile);
        stale.detach();
        expect(atlas.residency.holdCount(0), 2, reason: 'fresh still holds');

        fresh.detach();
        expect(atlas.residency.holdCount(0), 1);
      },
    );

    test(
      'a page a binding holds survives its retention while closed',
      () async {
        final atlas = atlasOf(['a'])..start();
        final binding = scopeOf(
          atlas,
        ).attach(_glyph('a'), _keyboardSpec, _profile);
        await bakeAll();
        visible.value = false;

        timers.elapse(const Duration(minutes: 5));
        expect(binding.paintable.sprite, isNotNull);

        binding.detach();
        timers.elapse(const Duration(seconds: 60));
        expect(binding.paintable.sprite, isNull);
      },
    );

    test('disposing the scope gives back the holds of live bindings', () {
      final atlas = atlasOf(['a']);
      final scope = scopeOf(atlas);
      final binding = scope.attach(_glyph('a'), _keyboardSpec, _profile);
      expect(atlas.residency.holdCount(0), 2);

      scope.dispose();
      expect(atlas.residency.holdCount(0), 1);

      binding.detach();
      expect(atlas.residency.holdCount(0), 1);
    });

    test('a document, a glyph outside the plan and no atlas hold nothing', () {
      final atlas = atlasOf(['a']);
      final scope = scopeOf(atlas);

      scope
        ..attach(const ContentKey.document('a'), _keyboardSpec, _profile)
        ..attach(_glyph('zzz'), _keyboardSpec, _profile);
      scopeOf().attach(_glyph('a'), _keyboardSpec, _profile);

      expect(atlas.residency.holdCount(0), 1);
    });
  });

  group('replacing the source of live bindings', () {
    test('moves the hold and the sprite to the new source and signals', () {
      final first = FakeGlyphSpriteSource(['a'])..bakePage(0);
      final second = FakeGlyphSpriteSource(['a']);
      final scope = scopeOf(first);
      final binding = scope.attach(_glyph('a'), _keyboardSpec, _profile);
      var heard = 0;
      binding.addListener(() => heard++);
      expect(first.holdCount(0), 1);
      expect(binding.paintable.sprite, isNotNull);

      scope.glyphSource = second;

      expect(first.holdCount(0), 0);
      expect(second.holdCount(0), 1);
      expect(heard, 1);
      expect(binding.paintable.sprite, isNull, reason: 'not baked yet');
      second.bakePage(0);
      expect(binding.paintable.sprite, isNotNull);
      expect(heard, 2);
    });

    test('stops listening to the old source and listens to the new', () {
      final first = FakeGlyphSpriteSource(['a']);
      final second = FakeGlyphSpriteSource(['a']);
      final scope = scopeOf(first);
      expect(first.listenerCount, 1);

      scope.glyphSource = second;

      expect(first.listenerCount, 0);
      expect(second.listenerCount, 1);
    });

    test('removing the source gives the hold back and draws as text again', () {
      final source = FakeGlyphSpriteSource(['a'])..bakePage(0);
      final scope = scopeOf(source);
      final binding = scope.attach(_glyph('a'), _keyboardSpec, _profile);
      var heard = 0;
      binding.addListener(() => heard++);

      scope.glyphSource = null;

      expect(source.holdCount(0), 0);
      expect(binding.paintable.sprite, isNull);
      expect(heard, 1);
      expect(producer.attempts, hasLength(1), reason: 'the producer path');
      final glyph = producer.last.advance(AssetStage.full);
      expect(binding.paintable, same(glyph), reason: 'never a stuck circle');
      expect(binding.readiness.stage, AssetStage.full);
      binding.detach();
      expect(source.holdCount(0), 0);
    });

    test('a binding that went back to the producer can move to a source', () {
      final source = FakeGlyphSpriteSource(['a'])..bakePage(0);
      final scope = scopeOf(source);
      final binding = scope.attach(_glyph('a'), _keyboardSpec, _profile);
      scope.glyphSource = null;
      expect(scope.isAttached(_glyph('a'), _keyboardSpec), isTrue);

      scope.glyphSource = source;

      expect(scope.isAttached(_glyph('a'), _keyboardSpec), isFalse);
      expect(source.holdCount(0), 1);
      expect(binding.paintable.sprite, isNotNull);
      binding.detach();
      expect(source.holdCount(0), 0);
    });

    test('a detached binding is not moved to the new source', () {
      final first = FakeGlyphSpriteSource(['a']);
      final second = FakeGlyphSpriteSource(['a']);
      final scope = scopeOf(first);
      scope.attach(_glyph('a'), _keyboardSpec, _profile).detach();

      scope.glyphSource = second;

      expect(second.holdCount(0), 0);
    });
  });

  group('registering the source after bindings attached', () {
    // A unicode leaf can attach before the atlas exists (a source that pages
    // its collections plans it late). It must not stay a paragraph for good.
    test('moves a binding made without a source onto it, with its hold', () {
      final scope = scopeOf();
      final binding = scope.attach(_glyph('a'), _keyboardSpec, _profile);
      producer.last.advance(AssetStage.full);
      var heard = 0;
      binding.addListener(() => heard++);
      final source = FakeGlyphSpriteSource(['a']);

      scope.glyphSource = source;

      expect(source.holdCount(0), 1);
      expect(heard, 1);
      expect(binding.paintable.sprite, isNull, reason: 'a circle until baked');
      expect(binding.readiness.stage, AssetStage.placeholder);
      source.bakePage(0);
      expect(binding.paintable.sprite, isNotNull);
      expect(heard, 2);
    });

    test('draws no paragraph from the moment it is registered', () {
      final scope = scopeOf();
      final binding = scope.attach(_glyph('a'), _keyboardSpec, _profile);
      final paragraph = producer.last.advance(AssetStage.full);
      expect(binding.paintable, same(paragraph));

      scope.glyphSource = FakeGlyphSpriteSource(['a']);

      expect(binding.paintable, isNot(same(paragraph)));
      expect(binding.paintable.sprite, isNull);
    });

    test('a slow, paged source: placeholders until each page bakes', () {
      final source = FakeGlyphSpriteSource(['a', 'b', 'c', 'd']);
      final scope = scopeOf();
      final first = scope.attach(_glyph('a'), _keyboardSpec, _profile);
      final last = scope.attach(_glyph('d'), _keyboardSpec, _profile);
      scope.glyphSource = source;

      expect(first.paintable.sprite, isNull);
      expect(last.paintable.sprite, isNull);
      source.bakePage(0);
      expect(first.paintable.sprite, isNotNull);
      expect(last.paintable.sprite, isNull);
      source.bakePage(1);
      expect(last.paintable.sprite, isNotNull);
    });

    test('a binding detached before the source arrives takes no hold', () {
      final scope = scopeOf();
      scope.attach(_glyph('a'), _keyboardSpec, _profile).detach();
      final source = FakeGlyphSpriteSource(['a']);

      scope.glyphSource = source;

      expect(source.holdCount(0), 0);
    });

    test('is ignored, and listens to nothing, after the scope is disposed', () {
      final source = FakeGlyphSpriteSource(['a']);
      final scope = scopeOf()..dispose();

      scope.glyphSource = source;

      expect(source.listenerCount, 0);
      expect(source.holdCount(0), 0);
    });
  });

  group('a glyph the source bakes on demand', () {
    test('is drawn as text until its sprite is there, then as the sprite', () {
      final source = FakeGlyphSpriteSource(['a', 'b'], onDemand: {'b'});
      final binding = scopeOf(
        source,
      ).attach(_glyph('b'), _keyboardSpec, _profile);

      expect(binding.readiness, const AssetReadiness(AssetStage.firstFrame));
      expect(
        (Canvas canvas) =>
            binding.paint(canvas, const Rect.fromLTWH(0, 0, 32, 32)),
        paints..paragraph(),
      );

      source.bakePage(0);

      expect(
        binding.readiness,
        const AssetReadiness(AssetStage.full, isFinal: true),
      );
      expect(binding.paintable.sprite, isNotNull);
    });

    test('a glyph the source learns after the attach takes a hold on its '
        'page once it can be drawn', () {
      final source = FakeGlyphSpriteSource(['a']);
      final binding = scopeOf(
        source,
      ).attach(_glyph('b'), _keyboardSpec, _profile);
      expect(binding.readiness.stage, AssetStage.firstFrame);

      source
        ..learn('b')
        ..bakePage(0);

      expect(binding.paintable.sprite, isNotNull);
      expect(source.holdCount(0), 1);

      binding.detach();
      expect(source.holdCount(0), 0);
    });
  });

  group('painting a glyph binding', () {
    Future<int> alphaAtCentre(AssetBinding binding) async {
      final recorder = PictureRecorder();
      binding.paint(Canvas(recorder), const Rect.fromLTWH(0, 0, 8, 8));
      final picture = recorder.endRecording();
      final image = await picture.toImage(8, 8);
      final data = (await image.toByteData())!;
      image.dispose();
      picture.dispose();
      return data.getUint8((4 * 8 + 4) * 4 + 3);
    }

    test(
      'draws the sprite rectangle once baked, a soft circle before',
      () async {
        final source = FakeGlyphSpriteSource(['a']);
        final binding = scopeOf(
          source,
        ).attach(_glyph('a'), _keyboardSpec, _profile);

        final before = await alphaAtCentre(binding);
        source.bakePage(0);
        final after = await alphaAtCentre(binding);

        expect(before, inInclusiveRange(1, 254), reason: 'translucent circle');
        expect(after, 255, reason: 'the opaque sprite');
      },
    );
  });
}
