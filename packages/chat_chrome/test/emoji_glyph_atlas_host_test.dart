import 'dart:async';

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_chrome/src/panel/emoji_glyph_atlas_host.dart';
import 'package:emoji_data/emoji_data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// An emoji source that is ready at once and whose tones the test sets.
class _Data extends EmojiDataSource with EmojiDataListenerMixin {
  _Data(this.categories);

  @override
  final List<EmojiCategorySpec> categories;

  bool ready = true;
  final Map<String, int> tones = {};

  @override
  bool get isReady => ready;

  void changed() => notifyDataChanged();

  @override
  int skinToneFor(String base) => tones[base] ?? 0;

  @override
  List<String> get recentGlyphs => const [];
  @override
  Future<void> load() async {}
  @override
  FutureOr<List<EmojiItem>> search(String query) => const [];
  @override
  Future<void> recordPick(EmojiItem item, {required EmojiPickSource source}) =>
      Future.value();
  @override
  Future<void> clearRecents() => Future.value();
  @override
  Future<void> setSkinTone(String base, int toneIndex) => Future.value();
  @override
  void dispose() => disposeDataListeners();
}

EmojiCategorySpec _category(String id, List<EmojiItem> items) =>
    EmojiCategorySpec(id: id, title: id, items: items);

void main() {
  late FakeBakeFrameSource frames;
  late _Data data;
  late List<GlyphAtlas> created;
  late List<GlyphPageResidency> residencies;

  setUp(() {
    frames = FakeBakeFrameSource();
    created = [];
    residencies = [];
    data = _Data([
      _category('faces', const [
        EmojiItem.unicode(glyph: '😀'),
        EmojiItem.unicode(glyph: '😁'),
      ]),
      _category('hands', const [
        EmojiItem.unicode(glyph: '👍', supportsSkinTone: true),
      ]),
    ]);
  });
  tearDown(() => data.dispose());

  EmojiGlyphAtlasHost host({
    bool bakes = true,
    GlyphAtlasPersistence? persistence,
    FakeGlyphRasteriser? rasteriser,
    Duration? pageRetention,
    Listenable? memoryPressure,
  }) {
    final host = EmojiGlyphAtlasHost(
      pageRetention: pageRetention ?? GlyphPageResidency.defaultRetention,
      memoryPressure: memoryPressure,
      dataSource: data,
      frames: frames,
      devicePixelRatio: 2,
      rasteriser: rasteriser ?? FakeGlyphRasteriser(),
      store: persistence == null ? FakeGlyphPageStore() : null,
      persistence: persistence,
      atlasFactory:
          ({
            required index,
            required rasteriser,
            store,
            persistence,
            required frames,
            required clock,
            required panelVisible,
            required panelOpening,
            residency,
          }) {
            residencies.add(residency!);
            if (!bakes) return null;
            final atlas = GlyphAtlas(
              index: index,
              rasteriser: rasteriser,
              store: store,
              persistence: persistence,
              frames: frames,
              clock: clock,
              panelVisible: panelVisible,
              panelOpening: panelOpening,
              residency: residency,
            );
            created.add(atlas);
            return atlas;
          },
    );
    addTearDown(host.dispose);
    return host;
  }

  test('has no atlas until the data is ready', () {
    data.ready = false;
    final h = host()..sync(recents: const []);

    expect(h.atlas, isNull);
    expect(created, isEmpty);

    data.ready = true;
    h.sync(recents: const []);
    expect(h.atlas, isNotNull);
  });

  test('plans the glyphs the grid will show, recents first', () {
    final h = host()..sync(recents: const ['🔥']);

    final index = h.atlas!.index;
    expect(index.glyphCount, 4);
    expect(index.placementOf('🔥')!.source, index.layout.glyphRect(0));
    for (final glyph in ['😀', '😁', '👍']) {
      expect(index.placementOf(glyph), isNotNull, reason: glyph);
    }
  });

  test('plans the tone the user chose, not the base glyph', () {
    data.tones['👍'] = 2;
    final h = host()..sync(recents: const []);

    final tone = EmojiSkinTone.apply('👍', 2);
    expect(h.atlas!.index.placementOf(tone), isNotNull);
    expect(h.atlas!.index.placementOf('👍'), isNull);
  });

  test('keeps its atlas while every glyph is still planned', () {
    final h = host()..sync(recents: const ['😀']);
    final first = h.atlas;
    var notified = 0;
    h.addListener(() => notified++);

    h.sync(recents: const ['😁']);
    h.sync(recents: const []);

    expect(h.atlas, same(first));
    expect(notified, 0);
  });

  test(
    'plans again, and says so, when a glyph appears that is not planned',
    () {
      final h = host()..sync(recents: const []);
      final first = h.atlas!;
      var notified = 0;
      h.addListener(() => notified++);

      data.tones['👍'] = 3;
      h.sync(recents: const []);

      expect(h.atlas, isNot(same(first)));
      expect(
        h.atlas!.index.placementOf(EmojiSkinTone.apply('👍', 3)),
        isNotNull,
      );
      expect(notified, 1);
      // The replaced atlas is released, not left baking.
      expect(first.spriteOf('😀'), isNull);
      expect(frames.hasPendingRequest, isFalse);
    },
  );

  test('a platform that does not bake gets no atlas and starts no bake', () {
    final h = host(bakes: false)..sync(recents: const []);

    expect(h.atlas, isNull);
    expect(frames.requested, 0);
  });

  test('bakes only while the panel is visible and not opening', () {
    final h = host()..sync(recents: const []);

    expect(frames.hasPendingRequest, isFalse, reason: 'hidden');

    h.panelVisible.value = true;
    expect(frames.hasPendingRequest, isTrue);

    h.panelOpening.value = true;
    expect(frames.hasPendingRequest, isFalse);

    h.panelOpening.value = false;
    expect(frames.hasPendingRequest, isTrue);
  });

  group('page residency', () {
    test('keeps pages for 60 seconds by default', () {
      host().sync(recents: const []);

      expect(residencies.single.retention, const Duration(seconds: 60));
    });

    test('takes the retention the host configures, for every plan', () {
      final h = host(pageRetention: const Duration(seconds: 5))
        ..sync(recents: const []);
      data.tones['👍'] = 3;
      h.sync(recents: const []);

      expect(residencies, hasLength(2));
      expect(
        residencies.map((r) => r.retention),
        everyElement(const Duration(seconds: 5)),
      );
    });

    test('memory pressure releases the baked pages', () async {
      final pressure = ManualMemoryPressure();
      addTearDown(pressure.dispose);
      final h = host(memoryPressure: pressure)..sync(recents: const []);
      h.panelVisible.value = true;
      while (frames.hasPendingRequest) {
        frames.pump();
        await pumpEventQueue();
      }
      expect(h.atlas!.residency.residentPages, isNotEmpty);

      pressure.raise();

      expect(h.atlas!.residency.residentPages, isEmpty);
    });

    test('a replaced atlas stops listening to memory pressure', () {
      final pressure = ManualMemoryPressure();
      addTearDown(pressure.dispose);
      final h = host(memoryPressure: pressure)..sync(recents: const []);
      expect(pressure.isListened, isTrue);

      h.dispose();

      expect(pressure.isListened, isFalse);
    });

    test('a platform that does not bake keeps no residency listening', () {
      final pressure = ManualMemoryPressure();
      addTearDown(pressure.dispose);

      host(bakes: false, memoryPressure: pressure).sync(recents: const []);

      expect(pressure.isListened, isFalse);
    });
  });

  test('dispose releases the atlas and the pause notifiers', () {
    final h = host()..sync(recents: const []);
    final atlas = h.atlas!;

    h
      ..dispose()
      ..dispose();

    expect(atlas.spriteOf('😀'), isNull);
    expect(h.atlas, isNull);
    expect(() => h.panelVisible.value = true, throwsFlutterError);
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

    Future<void> bake() async {
      for (var i = 0; i < 200 && frames.hasPendingRequest; i++) {
        frames.pump();
        await pumpEventQueue();
      }
    }

    test('the next launch restores the pages instead of baking', () async {
      final first = FakeGlyphRasteriser();
      final h1 = host(persistence: persistence(), rasteriser: first)
        ..sync(recents: const [])
        ..panelVisible.value = true;
      await pumpEventQueue();
      await bake();
      expect(h1.atlas!.spriteOf('😀'), isNotNull);
      expect(first.painted, isNotEmpty);
      h1.dispose();

      final second = FakeGlyphRasteriser();
      final h2 = host(persistence: persistence(), rasteriser: second)
        ..sync(recents: const [])
        ..panelVisible.value = true;
      await pumpEventQueue();
      await bake();

      expect(h2.atlas!.spriteOf('😀'), isNotNull);
      expect(second.painted, isEmpty);
    });

    test('disposing the host keeps the persisted pages', () async {
      final h = host(persistence: persistence())
        ..sync(recents: const [])
        ..panelVisible.value = true;
      await pumpEventQueue();
      await bake();

      h.dispose();

      expect(await cache.openCommitted(), isNotNull);
    });

    test('a tone chosen for the first time keeps the old art drawn', () async {
      final h = host(persistence: persistence())
        ..sync(recents: const [])
        ..panelVisible.value = true;
      await pumpEventQueue();
      await bake();
      expect(h.atlas!.spriteOf('😀'), isNotNull);

      // A new tone is a new glyph: the plan is made again.
      data.tones['👍'] = 3;
      h.sync(recents: const []);
      await pumpEventQueue();
      frames.pump();
      await pumpEventQueue();

      expect(h.atlas!.spriteOf('😀'), isNotNull, reason: 'old pages, no gap');
      expect(h.atlas!.spriteOf(EmojiSkinTone.apply('👍', 3)), isNull);

      await bake();
      expect(h.atlas!.spriteOf(EmojiSkinTone.apply('👍', 3)), isNotNull);
    });
  });
}
