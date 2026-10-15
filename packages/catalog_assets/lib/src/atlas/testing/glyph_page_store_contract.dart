import 'dart:ui';

import 'package:catalog_assets/src/atlas/glyph_page_store.dart';
import 'package:catalog_assets/src/atlas/testing/image_pixels.dart';
import 'package:flutter_test/flutter_test.dart';

/// Behaviour every [GlyphPageStore] must have, for adapter authors and hosts.
///
/// [create] makes a fresh, empty store.
void runGlyphPageStoreContract(String name, GlyphPageStore Function() create) {
  group('GlyphPageStore contract: $name', () {
    late GlyphPageStore store;

    // A small page-shaped image whose pixels differ by [color].
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

    Future<Color> topLeft(Image image) async =>
        (await ImagePixels.of(image)).at(1, 1);

    setUp(() => store = create());
    tearDown(() => store.clear());

    test('reads back what was written', () async {
      final page = imageOf(const Color(0xFFFF0000));
      await store.write(2, page);
      page.dispose();

      final read = (await store.read(2))!;
      expect(read.width, 16);
      expect(await topLeft(read), const Color(0xFFFF0000));
      read.dispose();
    });

    test('reads null for a page that was never written', () async {
      expect(await store.read(0), isNull);
    });

    test('writing an index again replaces the page', () async {
      final red = imageOf(const Color(0xFFFF0000));
      final green = imageOf(const Color(0xFF00FF00));
      await store.write(0, red);
      await store.write(0, green);
      red.dispose();
      green.dispose();

      final read = (await store.read(0))!;
      expect(await topLeft(read), const Color(0xFF00FF00));
      read.dispose();
    });

    test(
      'disposing the written handle leaves the stored page readable',
      () async {
        final page = imageOf(const Color(0xFF0000FF));
        await store.write(0, page);
        page.dispose();

        final read = (await store.read(0))!;
        expect(await topLeft(read), const Color(0xFF0000FF));
        read.dispose();
      },
    );

    test('disposing a read handle leaves the stored page readable', () async {
      final page = imageOf(const Color(0xFF0000FF));
      await store.write(0, page);
      page.dispose();

      (await store.read(0))!.dispose();

      final again = (await store.read(0))!;
      expect(await topLeft(again), const Color(0xFF0000FF));
      again.dispose();
    });

    test('clear drops every page', () async {
      final page = imageOf(const Color(0xFFFF0000));
      await store.write(0, page);
      await store.write(1, page);
      page.dispose();

      await store.clear();

      expect(await store.read(0), isNull);
      expect(await store.read(1), isNull);
    });
  });
}
