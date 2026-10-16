/// The pixel fingerprint of sentinel glyphs as the cache key's art version:
/// a changed fingerprint makes the persisted pages stale.
///
/// **Seam:** `GlyphAtlas(persistence:)` whose art version source is
/// `ComputedGlyphArtVersion` over a fingerprint of the sentinels' pixels
/// (`_fingerprint`, the shape of the data layer's fingerprint without its
/// package) and `GlyphPixelReader` over a `FakeGlyphRasteriser`. "The system updates its emoji art" is a
/// rasteriser that paints the sentinels in another colour; no emoji font.
library;

import 'dart:ui';

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const _sentinels = ['s1', 's2'];

/// Joins a hash of each sentinel's pixels, one sentinel per frame: any change
/// in how one is drawn changes the string.
Future<String> _fingerprint({
  required Iterable<String> sentinels,
  required Future<Uint8List> Function(String glyph) pixelsOf,
  required Future<void> Function() nextFrame,
}) async {
  final hashes = <int>[];
  for (final glyph in sentinels) {
    await nextFrame();
    hashes.add(Object.hashAll(await pixelsOf(glyph)));
  }
  return 'art1-${hashes.join('.')}';
}

/// A system whose sentinels look like [art]; everything else looks the same.
final class _System implements GlyphRasteriser {
  _System(this.art);

  String art;
  final FakeGlyphRasteriser _inner = FakeGlyphRasteriser();

  @override
  void paint(Canvas canvas, String glyph, Rect cell) => _inner.paint(
    canvas,
    _sentinels.contains(glyph) ? '$glyph$art' : glyph,
    cell,
  );
}

void main() {
  late FakeGlyphCacheStore cache;
  late FakeBakeFrameSource frames;
  late ValueNotifier<bool> visible;
  late ValueNotifier<bool> opening;

  setUp(() {
    cache = FakeGlyphCacheStore();
    frames = FakeBakeFrameSource();
    visible = ValueNotifier<bool>(true);
    opening = ValueNotifier<bool>(false);
  });
  tearDown(() async {
    visible.dispose();
    opening.dispose();
    await cache.clear();
  });

  /// One launch on a system drawing the sentinels as [art]; the fingerprint is
  /// computed from the pixels, one sentinel per frame.
  ({GlyphAtlas atlas, FakeGlyphRasteriser baked}) launch(String art) {
    final system = _System(art);
    final reader = GlyphPixelReader(system, size: 16);
    final source = ComputedGlyphArtVersion(
      () => _fingerprint(
        sentinels: _sentinels,
        pixelsOf: reader.pixelsOf,
        nextFrame: () async {},
      ),
    );
    final baked = FakeGlyphRasteriser();
    final atlas = GlyphAtlas(
      index: GlyphAtlasIndex(['a', 'b']),
      rasteriser: baked,
      persistence: GlyphAtlasPersistence(
        cache: cache,
        artVersion: source,
        devicePixelRatio: 2,
      ),
      frames: frames,
      clock: ManualBakeClock().read,
      panelVisible: visible,
      panelOpening: opening,
    );
    addTearDown(atlas.dispose);
    return (atlas: atlas, baked: baked);
  }

  Future<void> run(GlyphAtlas atlas) async {
    atlas.start();
    // Reading the pixels of the sentinels takes real engine time, so wait for
    // the end of the work, not for a fixed time.
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (atlas.cacheReport.allPagesAfterStart == null &&
        DateTime.now().isBefore(deadline)) {
      if (frames.hasPendingRequest) frames.pump();
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(atlas.cacheReport.allPagesAfterStart, isNotNull);
    // Let the last persisted write land.
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }

  /// A launch that runs to the end and is closed: the next one starts cold.
  Future<void> firstLaunch(String art) async {
    final first = launch(art);
    await run(first.atlas);
    expect(first.atlas.spriteOf('a'), isNotNull);
    first.atlas.dispose();
  }

  test('the same system art on the next launch is a cache hit', () async {
    await firstLaunch('v1');

    final second = launch('v1');
    await run(second.atlas);

    expect(second.atlas.cacheReport.verdict, GlyphCacheVerdict.hit);
    expect(second.baked.painted, isEmpty);
  });

  test('a changed sentinel fingerprint makes the persisted pages stale, '
      'and they are baked again', () async {
    await firstLaunch('v1');

    final second = launch('v2');
    await run(second.atlas);

    expect(second.atlas.cacheReport.verdict, GlyphCacheVerdict.stale);
    expect(second.baked.painted, ['a', 'b']);
    expect(second.atlas.spriteOf('a'), isNotNull);
  });

  test('the first run records the fingerprint it was baked under', () async {
    await firstLaunch('v1');

    final stored = (await cache.openCommitted())!;
    expect(stored.record.key.artVersion, startsWith('art1-'));
  });
}
