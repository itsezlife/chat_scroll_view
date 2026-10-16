import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/legacy_shim.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const _keyboard = CatalogAssetCacheType.keyboard;

void main() {
  late FakeBakeFrameSource frames;
  late FakeGlyphPageStore store;
  late ManualRetentionTimers timers;
  late ValueNotifier<bool> visible;
  late ValueNotifier<bool> opening;

  setUp(() {
    frames = FakeBakeFrameSource();
    store = FakeGlyphPageStore();
    timers = ManualRetentionTimers();
    visible = ValueNotifier<bool>(true);
    opening = ValueNotifier<bool>(false);
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

  Future<void> bakeAll() async {
    while (frames.hasPendingRequest) {
      frames.pump();
      await pumpEventQueue();
    }
  }

  group('a cache without an atlas', () {
    test('has none and its bindings carry no sprite', () {
      final cache = MemoryCatalogAssetCache();
      final binding = cache.attach(
        const CatalogAssetKey.unicode('a'),
        _keyboard,
      );

      expect(cache.glyphAtlas, isNull);
      expect(binding.sprite, isNull);
    });
  });

  group('a cache with an atlas', () {
    test('exposes it to the surfaces that bind through it', () {
      final atlas = atlasOf(['a']);
      final cache = MemoryCatalogAssetCache(glyphAtlas: atlas);
      addTearDown(cache.dispose);

      expect(cache.glyphAtlas, same(atlas));
    });

    test('a unicode binding has a sprite once its page is baked', () async {
      final atlas = atlasOf(['a', 'b'])..start();
      final cache = MemoryCatalogAssetCache(glyphAtlas: atlas);
      addTearDown(cache.dispose);
      final binding = cache.attach(
        const CatalogAssetKey.unicode('b'),
        _keyboard,
      );

      expect(binding.sprite, isNull);

      await bakeAll();

      expect(binding.sprite, isNotNull);
      expect(binding.sprite!.pageIndex, 0);
    });

    test('a glyph outside the catalogue has no sprite', () async {
      final atlas = atlasOf(['a'])..start();
      final cache = MemoryCatalogAssetCache(glyphAtlas: atlas);
      addTearDown(cache.dispose);
      final binding = cache.attach(
        const CatalogAssetKey.unicode('z'),
        _keyboard,
      );

      await bakeAll();

      expect(binding.sprite, isNull);
    });

    test('a document binding never has a sprite', () async {
      final atlas = atlasOf(['a'])..start();
      final cache = MemoryCatalogAssetCache(glyphAtlas: atlas);
      addTearDown(cache.dispose);
      final binding = cache.attach(
        const CatalogAssetKey.document('a'),
        _keyboard,
      );

      await bakeAll();

      expect(binding.sprite, isNull);
    });

    test('binding listeners hear a page being baked', () async {
      final atlas = atlasOf(['a'])..start();
      final cache = MemoryCatalogAssetCache(glyphAtlas: atlas);
      addTearDown(cache.dispose);
      final binding = cache.attach(
        const CatalogAssetKey.unicode('a'),
        _keyboard,
      );
      var heard = 0;
      binding.addListener(() => heard++);

      await bakeAll();

      expect(heard, 1);
    });

    test('a detached binding hears nothing', () async {
      final atlas = atlasOf(['a'])..start();
      final cache = MemoryCatalogAssetCache(glyphAtlas: atlas);
      addTearDown(cache.dispose);
      final binding = cache.attach(
        const CatalogAssetKey.unicode('a'),
        _keyboard,
      );
      var heard = 0;
      binding.addListener(() => heard++);
      binding.detach();

      await bakeAll();

      expect(heard, 0);
    });

    test(
      'after the cache is disposed the atlas is no longer listened to',
      () async {
        final atlas = atlasOf(['a'])..start();
        final cache = MemoryCatalogAssetCache(glyphAtlas: atlas);
        final binding = cache.attach(
          const CatalogAssetKey.unicode('a'),
          _keyboard,
        );
        var heard = 0;
        binding.addListener(() => heard++);

        cache.dispose();
        await bakeAll();

        expect(heard, 0);
      },
    );

    test('a binding whose atlas is gone has no sprite', () async {
      final atlas = atlasOf(['a'])..start();
      final cache = MemoryCatalogAssetCache(glyphAtlas: atlas);
      addTearDown(cache.dispose);
      final binding = cache.attach(
        const CatalogAssetKey.unicode('a'),
        _keyboard,
      );
      await bakeAll();
      expect(binding.sprite, isNotNull);

      atlas.dispose();

      expect(binding.sprite, isNull);
    });
  });

  group('page holds', () {
    // Counts are per page and belong to the binding that took them, so what
    // happens to the cache entry under a live binding cannot change them.
    test('a binding holds its glyph page from attach to detach', () {
      final atlas = atlasOf(['a', 'b']);
      final cache = MemoryCatalogAssetCache(glyphAtlas: atlas);
      addTearDown(cache.dispose);
      const key = CatalogAssetKey.unicode('a');

      final first = cache.attach(key, _keyboard);
      final second = cache.attach(key, CatalogAssetCacheType.messages);
      // The open panel holds every page as well: 1 here, plus one per binding.
      expect(atlas.residency.holdCount(0), 3);

      first.detach();
      expect(atlas.residency.holdCount(0), 2);
      second.detach();
      expect(atlas.residency.holdCount(0), 1);
    });

    test('detaching twice gives the page back once', () {
      final atlas = atlasOf(['a']);
      final cache = MemoryCatalogAssetCache(glyphAtlas: atlas);
      addTearDown(cache.dispose);
      const key = CatalogAssetKey.unicode('a');
      final first = cache.attach(key, _keyboard);
      cache.attach(key, _keyboard);

      first
        ..detach()
        ..detach();

      expect(atlas.residency.holdCount(0), 2);
    });

    test('evict with a live binding leaves the counts alone', () {
      final atlas = atlasOf(['a']);
      final cache = MemoryCatalogAssetCache(glyphAtlas: atlas);
      addTearDown(cache.dispose);
      const key = CatalogAssetKey.unicode('a');
      final stale = cache.attach(key, _keyboard);

      cache.evict(key, _keyboard);
      expect(atlas.residency.holdCount(0), 2);

      final fresh = cache.attach(key, _keyboard);
      stale.detach();
      expect(atlas.residency.holdCount(0), 2, reason: 'fresh still holds');
      expect(cache.isRetained(key, _keyboard), isTrue);

      fresh.detach();
      expect(atlas.residency.holdCount(0), 1);
      expect(cache.isRetained(key, _keyboard), isFalse);
    });

    test('clear with live bindings leaves the counts alone', () {
      final atlas = atlasOf(['a', 'b']);
      final cache = MemoryCatalogAssetCache(glyphAtlas: atlas);
      addTearDown(cache.dispose);
      final a = cache.attach(const CatalogAssetKey.unicode('a'), _keyboard);
      final b = cache.attach(const CatalogAssetKey.unicode('b'), _keyboard);

      cache.clear();
      expect(atlas.residency.holdCount(0), 3);

      a.detach();
      b.detach();
      expect(atlas.residency.holdCount(0), 1);
    });

    test(
      'a page a binding holds survives its retention while closed',
      () async {
        final atlas = atlasOf(['a'])..start();
        final cache = MemoryCatalogAssetCache(glyphAtlas: atlas);
        addTearDown(cache.dispose);
        final binding = cache.attach(
          const CatalogAssetKey.unicode('a'),
          _keyboard,
        );
        await bakeAll();
        visible.value = false;

        timers.elapse(const Duration(minutes: 5));
        expect(binding.sprite, isNotNull);

        binding.detach();
        timers.elapse(const Duration(seconds: 60));
        expect(binding.sprite, isNull);
      },
    );

    test('disposing the cache gives back the holds of live bindings', () {
      final atlas = atlasOf(['a']);
      final cache = MemoryCatalogAssetCache(glyphAtlas: atlas);
      final binding = cache.attach(
        const CatalogAssetKey.unicode('a'),
        _keyboard,
      );
      expect(atlas.residency.holdCount(0), 2);

      cache.dispose();
      expect(atlas.residency.holdCount(0), 1);

      binding.detach();
      expect(atlas.residency.holdCount(0), 1);
    });

    test('a document, a glyph outside the plan and no atlas hold nothing', () {
      final atlas = atlasOf(['a']);
      final cache = MemoryCatalogAssetCache(glyphAtlas: atlas);
      addTearDown(cache.dispose);

      cache.attach(const CatalogAssetKey.document('a'), _keyboard);
      cache.attach(const CatalogAssetKey.unicode('zzz'), _keyboard);
      MemoryCatalogAssetCache()
        ..attach(const CatalogAssetKey.unicode('a'), _keyboard)
        ..dispose();

      expect(atlas.residency.holdCount(0), 1);
    });
  });
}
