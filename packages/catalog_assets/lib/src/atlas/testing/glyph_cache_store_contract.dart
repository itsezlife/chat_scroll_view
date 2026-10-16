import 'dart:ui';

import 'package:catalog_assets/src/atlas/cache/glyph_cache_key.dart';
import 'package:catalog_assets/src/atlas/cache/glyph_cache_store.dart';
import 'package:catalog_assets/src/atlas/testing/image_pixels.dart';
import 'package:flutter_test/flutter_test.dart';

/// Behaviour every [GlyphCacheStore] must have, for adapter authors and hosts.
///
/// [create] makes a fresh, empty store. [reopen] makes a store over the same
/// backing as the one it is given, as the next launch of the app would see it;
/// leave it null for a store that does not outlive its instance (the memory
/// store), which then has the same instance stand in for the next launch.
void runGlyphCacheStoreContract(
  String name,
  GlyphCacheStore Function() create, {
  GlyphCacheStore Function(GlyphCacheStore previous)? reopen,
}) {
  group('GlyphCacheStore contract: $name', () {
    late GlyphCacheStore store;

    const key = GlyphCacheKey(
      artVersion: 'art-1',
      devicePixelRatio: 2.5,
      glyphSize: 72,
      layoutVersion: 1,
      catalogueHash: 'aaaa',
    );
    const record = GlyphCacheRecord(
      key: key,
      glyphs: ['😀', '👨‍👩‍👧‍👦', 'a'],
    );
    final other = GlyphCacheRecord(
      key: key.copyWith(artVersion: 'art-2'),
      glyphs: const ['b'],
    );

    Image imageOf(Color color) {
      final recorder = PictureRecorder();
      Canvas(recorder)
        ..drawColor(const Color(0x00000000), BlendMode.src)
        ..drawRect(
          const Rect.fromLTWH(0, 0, 8, 8),
          Paint()
            ..color = color
            ..isAntiAlias = false,
        );
      final picture = recorder.endRecording();
      final image = picture.toImageSync(16, 16);
      picture.dispose();
      return image;
    }

    Future<void> put(GlyphCacheGeneration g, int page, Color color) async {
      final image = imageOf(color);
      await g.pages.write(page, image);
      image.dispose();
    }

    Future<Color?> colorOf(GlyphCacheGeneration g, int page) async {
      final image = await g.pages.read(page);
      if (image == null) return null;
      final color = (await ImagePixels.of(image)).at(1, 1);
      image.dispose();
      return color;
    }

    GlyphCacheStore nextLaunch() => reopen == null ? store : reopen(store);

    Future<GlyphCacheGeneration> openStaged(GlyphCacheRecord r) async =>
        GlyphCacheGeneration(record: r, pages: await store.stage(r));

    setUp(() => store = create());
    tearDown(() => store.clear());

    test('nothing is committed in a fresh store', () async {
      expect(await store.openCommitted(), isNull);
    });

    test('a committed generation is found by the next launch, whole', () async {
      final staged = await openStaged(record);
      await put(staged, 0, const Color(0xFFFF0000));
      await put(staged, 1, const Color(0xFF00FF00));
      await store.commit();

      final found = (await nextLaunch().openCommitted())!;
      expect(found.record.key, key);
      expect(found.record.glyphs, record.glyphs);
      expect(await colorOf(found, 0), const Color(0xFFFF0000));
      expect(await colorOf(found, 1), const Color(0xFF00FF00));
      expect(await colorOf(found, 2), isNull);
    });

    test('a staged generation is invisible until it is committed', () async {
      final staged = await openStaged(record);
      await put(staged, 0, const Color(0xFFFF0000));

      expect(await nextLaunch().openCommitted(), isNull);

      await store.commit();
      expect(await nextLaunch().openCommitted(), isNotNull);
    });

    test('commit replaces the committed record and pages together', () async {
      final first = await openStaged(record);
      await put(first, 0, const Color(0xFFFF0000));
      await put(first, 1, const Color(0xFFFF0000));
      await store.commit();

      final second = await openStaged(other);
      await put(second, 0, const Color(0xFF0000FF));

      // Until the commit the first generation is whole.
      var found = (await nextLaunch().openCommitted())!;
      expect(found.record.key, key);
      expect(await colorOf(found, 1), const Color(0xFFFF0000));

      await store.commit();
      found = (await nextLaunch().openCommitted())!;
      expect(found.record.key, other.key);
      expect(await colorOf(found, 0), const Color(0xFF0000FF));
      expect(await colorOf(found, 1), isNull);
    });

    test('staging again forgets the earlier uncommitted generation', () async {
      final abandoned = await openStaged(other);
      await put(abandoned, 0, const Color(0xFF0000FF));

      final staged = await openStaged(record);
      expect(await colorOf(staged, 0), isNull);
      await store.commit();

      expect((await nextLaunch().openCommitted())!.record.key, key);
    });

    test('a page written to the committed generation is kept', () async {
      final staged = await openStaged(record);
      await put(staged, 0, const Color(0xFFFF0000));
      await store.commit();

      await put((await store.openCommitted())!, 1, const Color(0xFF00FF00));

      final found = (await nextLaunch().openCommitted())!;
      expect(await colorOf(found, 0), const Color(0xFFFF0000));
      expect(await colorOf(found, 1), const Color(0xFF00FF00));
    });

    test('commit without a staged generation throws', () async {
      await expectLater(store.commit(), throwsStateError);
    });

    test('clear removes the committed and the staged generation', () async {
      final first = await openStaged(record);
      await put(first, 0, const Color(0xFFFF0000));
      await store.commit();
      await openStaged(other);

      await store.clear();

      expect(await nextLaunch().openCommitted(), isNull);
      await expectLater(store.commit(), throwsStateError);
    });
  });
}
