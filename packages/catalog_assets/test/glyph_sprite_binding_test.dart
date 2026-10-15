import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const _keyboard = CatalogAssetCacheType.keyboard;

void main() {
  late FakeBakeFrameSource frames;
  late FakeGlyphPageStore store;
  late ValueNotifier<bool> visible;
  late ValueNotifier<bool> opening;

  setUp(() {
    frames = FakeBakeFrameSource();
    store = FakeGlyphPageStore();
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
}
