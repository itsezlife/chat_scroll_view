/// The atlas a page keeps for its glyphs: when it is planned, replanned and
/// released, and what it is told about the panel.
///
/// **Seam:** [GlyphAtlasHost] with a fake frame source, rasteriser, stores and
/// atlas factory, driven by [GlyphPlan]s and the presence observables, and
/// observed through the atlas it exposes, the requests the factory received
/// and the frames the bake asked for.
library;

import 'dart:async';

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_pages/panel_pages.dart';

/// The box emoji are drawn in on a 45 px cell (the glyph box fraction of it).
const _glyphBox = 45 * 0.72;

const _tone = '👍\u{1F3FD}';

GlyphPlan _plan([List<String> extra = const []]) =>
    GlyphPlan(['😀', '😁', '👍', ...extra]);

void main() {
  late FakeBakeFrameSource frames;
  late ObservableValue<bool> visible;
  late ObservableValue<bool> opening;
  late List<GlyphAtlas> created;
  late List<GlyphPageResidency> residencies;
  late List<GlyphPageStore?> stores;

  setUp(() {
    frames = FakeBakeFrameSource();
    visible = ObservableValue(false);
    opening = ObservableValue(false);
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
      ..sync(GlyphPlan(['😂']));

    expect(h.atlas.value, same(first));
    expect(notified, 0);
  });

  test(
    'plans again, and says so, when a glyph appears that is not planned',
    () {
      final h = host()..sync(_plan());
      final first = h.atlas.value!;
      var notified = 0;
      h.atlas.addListener(() => notified++);

      h.sync(GlyphPlan(['😀', '😁', _tone]));

      expect(h.atlas.value, isNot(same(first)));
      expect(h.atlas.value!.index.placementOf(_tone), isNotNull);
      expect(notified, 1);
      // The replaced atlas is released, not left baking.
      expect(first.spriteOf('😀'), isNull);
      expect(frames.hasPendingRequest, isFalse);
    },
  );

  group('planning again keeps the grid drawn', () {
    test('the successor draws the old art in the frame it is built', () async {
      final h = host()..sync(_plan());
      visible.value = true;
      await bake();
      expect(h.atlas.value!.spriteOf('😀'), isNotNull);

      h.sync(GlyphPlan(['😀', '😁', _tone]));

      expect(
        h.atlas.value!.spriteOf('😀'),
        isNotNull,
        reason: 'no blank frame',
      );
      expect(h.atlas.value!.spriteOf(_tone), isNull);

      await bake();
      expect(h.atlas.value!.spriteOf(_tone), isNotNull);
    });

    test('each atlas has a store of its own', () {
      final h = host()..sync(_plan());
      h.sync(GlyphPlan(['😀', '😁', _tone]));

      expect(stores, hasLength(2));
      expect(stores[0], isNotNull);
      expect(stores[1], isNot(same(stores[0])));
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
      h.sync(GlyphPlan(['😀', _tone]));

      expect(residencies, hasLength(2));
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

        h.sync(GlyphPlan(['😀', '😁', _tone]));
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

    test('a tone chosen for the first time keeps the old art drawn', () async {
      final h = host(persistence: persistence())..sync(_plan());
      visible.value = true;
      await pumpEventQueue();
      await bake();
      expect(h.atlas.value!.spriteOf('😀'), isNotNull);

      // A new tone is a new glyph: the plan is made again.
      h.sync(GlyphPlan(['😀', '😁', _tone]));
      await pumpEventQueue();
      frames.pump();
      await pumpEventQueue();

      expect(
        h.atlas.value!.spriteOf('😀'),
        isNotNull,
        reason: 'old pages, no gap',
      );
      expect(h.atlas.value!.spriteOf(_tone), isNull);

      await bake();
      expect(h.atlas.value!.spriteOf(_tone), isNotNull);
    });
  });
}
