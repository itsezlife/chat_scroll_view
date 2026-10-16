/// The glyph-support probe wired to the baked atlas, over several launches.
///
/// **Seam:** the composition a host writes (`wireEmojiGlyphProbe`) with the
/// real `GlyphAtlas` (persistent, paced by a fake frame source) and the real
/// `MissingGlyphProbe`; the system is a documented fake rasteriser that draws a
/// missing-glyph box for the glyphs it "has no art for" and a solid colour per
/// glyph otherwise, and sentinel pixels from a table. There is no emoji font,
/// so this shows the logic, not any real device's output.
///
/// A launch is the whole set of objects a process builds; the key-value store
/// and the atlas cache are what survives between launches.
library;

import 'dart:ui' as ui;

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_scroll_view_example/src/common/emoji_glyph_probe.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:emoji_data/emoji_data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const _glyphs = ['😀', '😁', '🫩'];
const _newGlyph = '🫨';

/// What a system draws: which glyphs it lacks, and the art it has.
final class _System implements GlyphRasteriser {
  _System({this.lacking = const {'🫩'}, this.artSeed = 1});

  final Set<String> lacking;

  /// Changes whenever the vendor redraws the emoji.
  final int artSeed;

  /// Every glyph painted by the bake, in order.
  final List<String> painted = [];

  final FakeGlyphRasteriser _draw = FakeGlyphRasteriser();

  @override
  void paint(ui.Canvas canvas, String glyph, ui.Rect cell) {
    painted.add(glyph);
    _draw.paint(
      canvas,
      lacking.contains(glyph) || glyph == defaultMissingGlyphReferences.first
          ? 'missing-glyph box'
          : glyph,
      cell,
    );
  }

  Future<Uint8List> sentinelPixels(String glyph) async => Uint8List.fromList([
    for (var i = 0; i < 32; i++) (glyph.hashCode + artSeed * 13 + i) & 0xFF,
  ]);
}

/// One process: a probe, an atlas and what drives them.
final class _Launch {
  _Launch(
    this.system, {
    required KeyValueStore store,
    required FakeGlyphCacheStore cache,
    List<String> glyphs = _glyphs,
    String? osVersion,
  }) : wiring = wireEmojiGlyphProbe(
         glyphs: glyphs,
         store: store,
         sentinelPixelsOf: system.sentinelPixels,
         nextFrame: () async {},
         osVersion: osVersion,
       ) {
    atlas = GlyphAtlas(
      index: GlyphAtlasIndex(glyphs),
      rasteriser: system,
      frames: frames,
      clock: ManualBakeClock().read,
      panelVisible: visible,
      panelOpening: opening,
      persistence: GlyphAtlasPersistence(
        cache: cache,
        artVersion: wiring.artVersion,
        devicePixelRatio: 2,
      ),
      observer: wiring.bakeObserver,
    );
  }

  final _System system;
  final EmojiGlyphProbeWiring wiring;
  final frames = FakeBakeFrameSource();
  final visible = ValueNotifier<bool>(true);
  final opening = ValueNotifier<bool>(false);
  late final GlyphAtlas atlas;

  MissingGlyphProbe get probe => wiring.probe;

  bool supports(String glyph) => probe.supports(ContentKey$Unicode(glyph));

  /// Starts the atlas and delivers frames until it has every page and the
  /// probe has settled, waiting on the engine's real async readbacks.
  Future<void> run() async {
    atlas.start();
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (DateTime.now().isBefore(deadline) &&
        (atlas.cacheReport.allPagesAfterStart == null || !probe.isComplete)) {
      if (frames.hasPendingRequest) frames.pump();
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    // Let the last persisted write land.
    await Future<void>.delayed(const Duration(milliseconds: 30));
  }

  var _ended = false;

  /// The process ends.
  void dispose() {
    if (_ended) return;
    _ended = true;
    atlas.dispose();
    probe.dispose();
    visible.dispose();
    opening.dispose();
  }
}

void main() {
  late FakeKeyValueStore store;
  late FakeGlyphCacheStore cache;
  late List<_Launch> launches;

  setUp(() {
    store = FakeKeyValueStore();
    cache = FakeGlyphCacheStore();
    launches = [];
  });
  tearDown(() async {
    for (final launch in launches) {
      launch.dispose();
    }
    await cache.clear();
  });

  _Launch launch(
    _System system, {
    List<String> glyphs = _glyphs,
    String? osVersion,
  }) {
    final result = _Launch(
      system,
      store: store,
      cache: cache,
      glyphs: glyphs,
      osVersion: osVersion,
    );
    // The process before this one has ended; what it persisted stays.
    for (final earlier in launches) {
      earlier.dispose();
    }
    launches.add(result);
    return result;
  }

  test('the first launch learns the verdicts in the pass that bakes, '
      'rasterising nothing twice', () async {
    final first = launch(_System());

    await first.run();

    expect(first.probe.isComplete, isTrue);
    expect(first.supports('😀'), isTrue);
    expect(first.supports('🫩'), isFalse);
    expect(
      first.system.painted,
      unorderedEquals([..._glyphs, defaultMissingGlyphReferences.first]),
    );
    expect(first.probe.artVersion, isNotNull);
    expect(store.entries.keys, ['emoji_data:glyph_probe']);
  });

  test(
    'a launch that restores the baked pages still has the verdicts',
    () async {
      await launch(_System()).run();

      final second = launch(_System());
      await second.run();

      expect(second.atlas.cacheReport.verdict, GlyphCacheVerdict.hit);
      expect(second.system.painted, isEmpty, reason: 'the bake drew nothing');
      expect(second.probe.isComplete, isTrue);
      expect(second.supports('😀'), isTrue);
      expect(second.supports('🫩'), isFalse);
    },
  );

  test('the atlas cache key and the probe share one art version', () async {
    final first = launch(_System());
    await first.run();

    expect(await first.wiring.artVersion.read(), first.probe.artVersion);
  });

  test('the system redrawing its emoji re-bakes and re-probes under the '
      'new art version', () async {
    await launch(_System()).run();

    // After the update the system lacks another glyph and draws 🫩.
    final updated = launch(_System(lacking: {'😁'}, artSeed: 2));
    await updated.run();

    expect(updated.atlas.cacheReport.verdict, GlyphCacheVerdict.stale);
    expect(updated.probe.isComplete, isTrue);
    expect(updated.supports('🫩'), isTrue);
    expect(updated.supports('😁'), isFalse);
  });

  test('a changed supplementary signal alone re-probes', () async {
    await launch(_System(), osVersion: 'os 14').run();

    final updated = launch(_System(lacking: {'😁'}), osVersion: 'os 15');
    await updated.run();

    expect(updated.supports('😁'), isFalse);
    expect(updated.supports('🫩'), isTrue);
  });

  test('a glyph added to the catalogue is probed, the rest kept', () async {
    await launch(_System()).run();

    final grown = launch(_System(), glyphs: [..._glyphs, _newGlyph]);
    await grown.run();

    expect(grown.probe.isComplete, isTrue);
    expect(grown.supports('🫩'), isFalse);
    expect(grown.system.painted, contains(_newGlyph));
  });

  test('verdicts never change the atlas plan', () async {
    final first = launch(_System());
    await first.run();

    expect(first.atlas.index.glyphs, _glyphs);
    expect(first.atlas.index.placementOf('🫩'), isNotNull);
  });
}
