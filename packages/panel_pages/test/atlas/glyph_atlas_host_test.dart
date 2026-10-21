/// The atlas a page keeps for its glyphs: when it is planned, replanned and
/// released, and what it is told about the panel.
///
/// **Seam:** [GlyphAtlasHost] with a fake frame source, rasteriser, stores and
/// atlas factory, driven by [GlyphPlan]s and the presence listenables, and
/// observed through the atlas it exposes, the requests the factory received
/// and the frames the bake asked for.
library;

import 'dart:async';

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen/listen.dart' as listen;
import 'package:panel_pages/panel_pages.dart';

/// The box emoji are drawn in on a 45 px cell (the glyph box fraction of it).
const _glyphBox = 45 * 0.72;

const _tone = '👍\u{1F3FD}';

GlyphPlan _plan([List<String> extra = const []]) =>
    GlyphPlan(['😀', '😁', '👍', ...extra]);

void main() {
  late FakeBakeFrameSource frames;
  late listen.ValueNotifier<bool> visible;
  late listen.ValueNotifier<bool> opening;
  late List<GlyphAtlas> created;
  late List<GlyphPageResidency> residencies;
  late List<GlyphPageStore?> stores;

  setUp(() {
    frames = FakeBakeFrameSource();
    visible = listen.ValueNotifier(false);
    opening = listen.ValueNotifier(false);
    created = [];
    residencies = [];
    stores = [];
  });

  GlyphAtlasHost host({
    bool bakes = true,
    GlyphAtlasPersistence? persistence,
    FakeGlyphRasteriser? rasteriser,
    Duration? pageRetention,
    Listenable? memoryPressure,
    double devicePixelRatio = 2,
  }) {
    final host = GlyphAtlasHost(
      pageRetention: pageRetention ?? GlyphPageResidency.defaultRetention,
      memoryPressure: memoryPressure,
      frames: frames,
      devicePixelRatio: devicePixelRatio,
      glyphBoxExtent: _glyphBox,
      visible: visible,
      opening: opening,
      rasteriser: rasteriser ?? FakeGlyphRasteriser(),
      newStore: FakeGlyphPageStore.new,
      persistence: persistence,
      atlasFactory: (request) {
        residencies.add(request.residency!);
        stores.add(request.store);
        if (!bakes) return null;
        final atlas = request.build();
        created.add(atlas);
        return atlas;
      },
    );
    addTearDown(host.dispose);
    return host;
  }

  Future<void> bake() async {
    for (var i = 0; i < 200 && frames.hasPendingRequest; i++) {
      frames.pump();
      await pumpEventQueue();
    }
  }

  test('has no atlas until it is told what to plan', () {
    final h = host();

    expect(h.atlas.value, isNull);
    expect(created, isEmpty);

    h.sync(_plan());
    expect(h.atlas.value, isNotNull);
  });

  test('plans the glyphs in the order it is given', () {
    final h = host()..sync(_plan(['🔥']));

    final index = h.atlas.value!.index;
    expect(index.glyphs, ['😀', '😁', '👍', '🔥']);
    expect(index.placementOf('😀')!.source, index.layout.glyphRect(0));
  });

  test('keeps its atlas while every glyph is still planned', () {
    final h = host()..sync(_plan(['😂']));
    final first = h.atlas.value;
    var notified = 0;
    h.atlas.addListener(() => notified++);

    h
      ..sync(_plan(['😂']))
      ..sync(_plan())
      ..sync(GlyphPlan(const ['😂']));

    expect(h.atlas.value, same(first));
    expect(notified, 0);
  });

  group('a glyph the atlas does not hold joins in a layer of its own', () {
    const other = '👍\u{1F3FF}';

    test('the atlas stays and only the new glyph is planned', () {
      final h = host()..sync(_plan());
      final first = h.atlas.value!;
      final source = h.source.value;
      var notified = 0;
      h.atlas.addListener(() => notified++);

      h.sync(GlyphPlan(const ['😀', '😁', _tone]));

      expect(h.atlas.value, same(first));
      expect(notified, 0);
      expect(created, hasLength(2));
      expect(created.last.index.glyphs, [_tone]);
      expect(h.source.value, same(source), reason: 'one source for the scope');
    });

    test('the grid keeps its art and nothing it had is baked again', () async {
      final rasteriser = FakeGlyphRasteriser();
      final h = host(rasteriser: rasteriser)..sync(_plan());
      visible.value = true;
      await bake();
      final painted = rasteriser.painted.length;

      h.sync(GlyphPlan(const ['😀', '😁', _tone]));
      expect(h.source.value!.spriteOf('😀'), isNotNull, reason: 'no gap');
      await bake();

      expect(h.source.value!.spriteOf(_tone), isNotNull);
      expect(rasteriser.painted.skip(painted), [_tone]);
    });

    test('until it is baked a surface draws it as text, not a circle', () {
      final h = host()..sync(_plan());

      h.sync(GlyphPlan(const ['😀', '😁', _tone]));

      expect(h.source.value!.waitsForSprite(_tone), isFalse);
      expect(h.source.value!.waitsForSprite('😀'), isTrue);
    });

    test('a glyph that leaves the plan stays drawn: a composer may still '
        'show it', () async {
      final h = host()..sync(_plan());
      visible.value = true;
      h.sync(GlyphPlan(const ['😀', '😁', _tone]));
      await bake();

      h.sync(GlyphPlan(const ['😀', '😁', other]));
      await bake();

      expect(h.source.value!.spriteOf(_tone), isNotNull);
      expect(h.source.value!.spriteOf(other), isNotNull);
    });

    test('each layer has a store of its own', () {
      final h = host()..sync(_plan());
      h.sync(GlyphPlan(const ['😀', '😁', _tone]));

      expect(stores, hasLength(2));
      expect(stores[1], isNotNull);
      expect(stores[1], isNot(same(stores[0])));
    });

    test('scrolling reaches every layer, also one added while it lasts', () {
      final h = host()..sync(_plan());
      visible.value = true;
      h.reportScrolling(reporter: 'grid', scrolling: true);

      h.sync(GlyphPlan(const ['😀', '😁', _tone]));
      expect(frames.hasPendingRequest, isFalse, reason: 'every layer waits');

      h.reportScrolling(reporter: 'grid', scrolling: false);
      expect(frames.hasPendingRequest, isTrue);
    });
  });

  group('density', () {
    test('a changed density plans again at the new size', () {
      final h = host()..sync(_plan());
      final first = h.atlas.value!;
      var notified = 0;
      h.atlas.addListener(() => notified++);

      h.devicePixelRatio = 3;

      expect(h.atlas.value, isNot(same(first)));
      expect(
        h.atlas.value!.index.layout.glyphSize,
        greaterThan(first.index.layout.glyphSize),
      );
      expect(h.atlas.value!.index.glyphs, first.index.glyphs);
      expect(notified, 1);
    });

    test('plans again for the glyphs the atlas holds, not a narrower plan', () {
      final h = host()..sync(_plan(['😂']));
      h.sync(_plan());

      h.devicePixelRatio = 3;

      expect(h.atlas.value!.index.glyphs, contains('😂'));
    });

    test('folds the layers into the atlas it plans again', () {
      final h = host()..sync(_plan());
      h.sync(GlyphPlan(const ['😀', '😁', _tone]));

      h.devicePixelRatio = 3;

      expect(h.atlas.value!.index.glyphs, contains(_tone));
      expect(h.source.value!.waitsForSprite(_tone), isTrue);
    });

    test('the same density plans nothing', () {
      final h = host()..sync(_plan());
      final first = h.atlas.value;

      h.devicePixelRatio = 2;

      expect(h.atlas.value, same(first));
    });

    test('before there is a plan it only remembers the density', () {
      final h = host();

      h.devicePixelRatio = 3;
      expect(h.atlas.value, isNull);

      h.sync(_plan());
      expect(
        h.atlas.value!.index.layout.glyphSize,
        GlyphAtlasLayout.forCell(
          logicalExtent: _glyphBox,
          devicePixelRatio: 3,
        ).glyphSize,
      );
    });
  });

  test('a platform that does not bake gets no atlas and starts no bake', () {
    final h = host(bakes: false)
      ..sync(_plan())
      ..sync(_plan(['🔥']));

    expect(h.atlas.value, isNull);
    expect(frames.requested, 0);
    expect(residencies, hasLength(1), reason: 'it asked once and was told no');
  });

  test('bakes only while the panel is visible and not opening', () {
    host().sync(_plan());

    expect(frames.hasPendingRequest, isFalse, reason: 'hidden');

    visible.value = true;
    expect(frames.hasPendingRequest, isTrue);

    opening.value = true;
    expect(frames.hasPendingRequest, isFalse);

    opening.value = false;
    expect(frames.hasPendingRequest, isTrue);
  });

  test('a panel that is already visible bakes as soon as there is a plan', () {
    visible.value = true;

    host().sync(_plan());

    expect(frames.hasPendingRequest, isTrue);
  });

  group('page residency', () {
    test('keeps pages for 60 seconds by default', () {
      host().sync(_plan());

      expect(residencies.single.retention, const Duration(seconds: 60));
    });

    test('takes the retention the host configures, for every plan', () {
      final h = host(pageRetention: const Duration(seconds: 5))..sync(_plan());
      h.sync(GlyphPlan(const ['😀', _tone]));
      h.devicePixelRatio = 3;

      expect(residencies, hasLength(3));
      expect(
        residencies.map((r) => r.retention),
        everyElement(const Duration(seconds: 5)),
      );
    });

    test('memory pressure releases the pages of a closed panel', () async {
      final pressure = ManualMemoryPressure();
      addTearDown(pressure.dispose);
      final h = host(memoryPressure: pressure)..sync(_plan());
      visible.value = true;
      await bake();
      expect(h.atlas.value!.residency.residentPages, isNotEmpty);

      pressure.raise();
      expect(
        h.atlas.value!.residency.residentPages,
        isNotEmpty,
        reason: 'an open panel is drawing them',
      );

      visible.value = false;
      pressure.raise();

      expect(h.atlas.value!.residency.residentPages, isEmpty);
    });

    test('a disposed host stops listening to memory pressure', () {
      final pressure = ManualMemoryPressure();
      addTearDown(pressure.dispose);
      final h = host(memoryPressure: pressure)..sync(_plan());
      expect(pressure.isListened, isTrue);

      h.dispose();

      expect(pressure.isListened, isFalse);
    });

    test('a platform that does not bake keeps no residency listening', () {
      final pressure = ManualMemoryPressure();
      addTearDown(pressure.dispose);

      host(bakes: false, memoryPressure: pressure).sync(_plan());

      expect(pressure.isListened, isFalse);
    });
  });

  test('dispose releases the atlas and stops following the panel', () {
    final h = host()..sync(_plan());
    final atlas = h.atlas.value!;

    h
      ..dispose()
      ..dispose();

    expect(atlas.spriteOf('😀'), isNull);
    expect(h.atlas.value, isNull);
    expect(() => visible.value = true, returnsNormally);
    expect(frames.hasPendingRequest, isFalse);
  });

  test('a plan after dispose is ignored', () {
    final h = host()..dispose();

    h.sync(_plan());

    expect(h.atlas.value, isNull);
    expect(created, isEmpty);
  });

  group('with a persistent cache', () {
    late FakeGlyphCacheStore cache;
    late FakeGlyphArtVersionSource art;

    GlyphAtlasPersistence persistence() => GlyphAtlasPersistence(
      cache: cache,
      artVersion: art,
      devicePixelRatio: 2,
    );

    setUp(() {
      cache = FakeGlyphCacheStore();
      art = FakeGlyphArtVersionSource();
    });
    tearDown(() => cache.clear());

    test('the next launch restores the pages instead of baking', () async {
      final first = FakeGlyphRasteriser();
      final h1 = host(persistence: persistence(), rasteriser: first)
        ..sync(_plan());
      visible.value = true;
      await pumpEventQueue();
      await bake();
      expect(h1.atlas.value!.spriteOf('😀'), isNotNull);
      expect(first.painted, isNotEmpty);
      h1.dispose();

      final second = FakeGlyphRasteriser();
      final h2 = host(persistence: persistence(), rasteriser: second)
        ..sync(_plan());
      await pumpEventQueue();
      await bake();

      expect(h2.atlas.value!.spriteOf('😀'), isNotNull);
      expect(second.painted, isEmpty);
    });

    test('disposing the host keeps the persisted pages', () async {
      final h = host(persistence: persistence())..sync(_plan());
      visible.value = true;
      await pumpEventQueue();
      await bake();

      h.dispose();

      expect(await cache.openCommitted(), isNotNull);
    });

    test(
      'planning again waits for the replaced atlas to stop writing',
      () async {
        final gate = Completer<void>();
        cache.writeGate = gate.future;
        final h = host(persistence: persistence())..sync(_plan());
        visible.value = true;
        await pumpEventQueue();
        while (cache.writes.isEmpty && frames.hasPendingRequest) {
          frames.pump();
          await pumpEventQueue();
        }
        expect(cache.stages, 1);

        h.devicePixelRatio = 3;
        await pumpEventQueue();
        expect(
          cache.stages,
          1,
          reason: 'the first atlas still has a write out',
        );

        gate.complete();
        await pumpEventQueue();
        expect(cache.stages, 2);
      },
    );

    test('a changed density re-keys the cache', () async {
      final h = host(persistence: persistence())..sync(_plan());
      visible.value = true;
      await pumpEventQueue();
      await bake();

      h.devicePixelRatio = 3;
      await pumpEventQueue();
      await bake();

      expect(h.atlas.value!.cacheReport.verdict, GlyphCacheVerdict.discard);
      expect((await cache.openCommitted())!.record.key.devicePixelRatio, 3);
      expect(h.atlas.value!.spriteOf('😀'), isNotNull);
    });

    test('a tone chosen for the first time leaves the persisted atlas as it '
        'is', () async {
      final h = host(persistence: persistence())..sync(_plan());
      visible.value = true;
      await pumpEventQueue();
      await bake();
      final committed = (await cache.openCommitted())!.record.key;

      h.sync(GlyphPlan(const ['😀', '😁', _tone]));
      await pumpEventQueue();
      await bake();

      expect(h.source.value!.spriteOf('😀'), isNotNull);
      expect(h.source.value!.spriteOf(_tone), isNotNull);
      expect((await cache.openCommitted())!.record.key, committed);
      expect(cache.stages, 1, reason: 'nothing staged again');
    });
  });
}
