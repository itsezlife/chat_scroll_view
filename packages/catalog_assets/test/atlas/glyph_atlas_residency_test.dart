import 'dart:ui';

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const _retention = Duration(seconds: 60);
const _mebibyte = 1024 * 1024;

void main() {
  late FakeGlyphRasteriser rasteriser;
  late _CountingStore store;
  late FakeBakeFrameSource frames;
  late ManualRetentionTimers timers;
  late ManualMemoryPressure pressure;
  late ValueNotifier<bool> visible;
  late ValueNotifier<bool> opening;

  setUp(() {
    rasteriser = FakeGlyphRasteriser();
    store = _CountingStore();
    frames = FakeBakeFrameSource();
    timers = ManualRetentionTimers();
    pressure = ManualMemoryPressure();
    visible = ValueNotifier<bool>(true);
    opening = ValueNotifier<bool>(false);
  });
  tearDown(() async {
    visible.dispose();
    opening.dispose();
    pressure.dispose();
    await store.clear();
  });

  GlyphAtlas build(List<String> glyphs) {
    final atlas = GlyphAtlas(
      index: GlyphAtlasIndex(glyphs),
      rasteriser: rasteriser,
      store: store,
      frames: frames,
      clock: ManualBakeClock().read,
      panelVisible: visible,
      panelOpening: opening,
      residency: GlyphPageResidency(
        retention: _retention,
        memoryPressure: pressure,
        startTimer: timers.start,
      ),
    );
    addTearDown(atlas.dispose);
    return atlas;
  }

  Future<void> frame() async {
    frames.pump();
    await pumpEventQueue();
  }

  Future<void> bakeAll() async {
    while (frames.hasPendingRequest) {
      await frame();
    }
  }

  Future<GlyphAtlas> baked(List<String> glyphs) async {
    final atlas = build(glyphs)..start();
    await bakeAll();
    expect(atlas.spriteOf(glyphs.first), isNotNull);
    return atlas;
  }

  group('the panel closes', () {
    test('pages stay for 60 seconds, then go', () async {
      final atlas = await baked(['a', 'b']);

      visible.value = false;
      timers.elapse(_retention - const Duration(seconds: 1));
      expect(atlas.spriteOf('a'), isNotNull);

      timers.elapse(const Duration(seconds: 1));
      expect(atlas.residency.residentPages, isEmpty);
      expect(atlas.spriteOf('a'), isNull);
    });

    test('reopening within 60 seconds needs no reload', () async {
      final atlas = await baked(['a']);
      final reads = store.reads;

      visible.value = false;
      timers.elapse(const Duration(seconds: 59));
      visible.value = true;
      timers.elapse(_retention * 2);
      await pumpEventQueue();

      expect(atlas.spriteOf('a'), isNotNull);
      expect(store.reads, reads);
    });

    test('reopening after 60 seconds reloads from the store', () async {
      final atlas = await baked(['a']);
      final reads = store.reads;
      visible.value = false;
      timers.elapse(_retention);
      expect(atlas.spriteOf('a'), isNull);
      final heard = <int>[];
      atlas.addPageListener(heard.add);

      visible.value = true;
      await pumpEventQueue();
      expect(store.reads, reads, reason: 'reading waits for a frame');
      await frame();

      expect(store.reads, reads + 1);
      expect(atlas.spriteOf('a'), isNotNull);
      expect(heard, contains(0));
      expect(rasteriser.painted.length, 1, reason: 'reload does not rebake');
    });

    test('reopening reloads the released pages one per frame', () async {
      final atlas = await baked([for (var i = 0; i < 1400; i++) 'g$i']);
      expect(atlas.index.pageCount, 3);
      final reads = store.reads;
      visible.value = false;
      timers.elapse(_retention);
      expect(atlas.residency.residentPages, isEmpty);

      visible.value = true;
      await pumpEventQueue();
      expect(store.reads, reads, reason: 'nothing is read before a frame');

      for (var page = 1; page <= 3; page++) {
        await frame();
        expect(store.reads, reads + page, reason: 'frame $page');
      }
      expect(atlas.residency.residentPages, [0, 1, 2]);
    });

    test('reloading waits for a scroll to end', () async {
      final atlas = await baked(['a']);
      final reads = store.reads;
      visible.value = false;
      timers.elapse(_retention);
      final surface = Object();
      atlas.reportScrolling(reporter: surface, scrolling: true);

      visible.value = true;
      await frame();
      expect(store.reads, reads);

      atlas.reportScrolling(reporter: surface, scrolling: false);
      await pumpEventQueue();
      await frame();
      expect(store.reads, reads + 1);
    });

    test('a page a binding holds outlives the retention', () async {
      final atlas = await baked(['a']);
      final hold = atlas.holdPageOf('a')!;

      visible.value = false;
      timers.elapse(_retention * 3);
      expect(atlas.spriteOf('a'), isNotNull);

      hold.release();
      timers.elapse(_retention);
      expect(atlas.spriteOf('a'), isNull);
    });

    test('a glyph outside the plan has no page to hold', () async {
      final atlas = await baked(['a']);

      expect(atlas.holdPageOf('zzz'), isNull);
    });
  });

  group('memory pressure', () {
    test('releases the pages at once while the panel is closed', () async {
      final atlas = await baked(['a']);
      visible.value = false;
      final image = atlas.spriteOf('a')!.page;

      pressure.raise();

      expect(atlas.residency.residentPages, isEmpty);
      expect(image.debugDisposed, isTrue);
      expect(atlas.residency.imageOf(0), isNull);
      await pumpEventQueue();
      expect(
        atlas.residency.residentPages,
        isEmpty,
        reason: 'a closed panel does not reload by itself',
      );
    });

    test('keeps the pages while the panel is open', () async {
      final atlas = await baked(['a']);
      final image = atlas.spriteOf('a')!.page;
      final reads = store.reads;

      pressure.raise();
      await pumpEventQueue();

      expect(atlas.residency.residentBytes, isNot(0));
      expect(image.debugDisposed, isFalse);
      expect(atlas.spriteOf('a'), isNotNull, reason: 'drawn, no placeholder');
      expect(store.reads, reads, reason: 'nothing is read back');
    });

    test(
      'a page released for a closed panel loads again when it opens',
      () async {
        final atlas = await baked(['a']);
        visible.value = false;
        final reads = store.reads;
        final heard = <int>[];
        atlas.addPageListener(heard.add);
        pressure.raise();
        visible.value = true;

        expect(atlas.spriteOf('a'), isNull);
        expect(atlas.spriteOf('a'), isNull, reason: 'one load, not two');
        await frame();

        expect(store.reads, reads + 1);
        expect(atlas.spriteOf('a'), isNotNull);
        expect(heard, [0, 0], reason: 'released, then drawable again');
      },
    );

    test('a page the store lost is reported once and baked again', () async {
      final atlas = await baked(['a']);
      visible.value = false;
      await store.clear();
      pressure.raise();
      visible.value = true;
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);

      expect(atlas.spriteOf('a'), isNull);
      await frame();
      expect(atlas.spriteOf('a'), isNull);
      expect(errors, hasLength(1));

      await bakeAll();

      expect(atlas.spriteOf('a'), isNotNull, reason: 'not lost for good');
      expect(rasteriser.painted, ['a', 'a']);
      expect(errors, hasLength(1));
    });
  });

  group('teardown', () {
    test('dispose releases the pages and the timers', () async {
      final atlas = await baked(['a']);
      final residency = atlas.residency;
      visible.value = false;
      expect(timers.pending, 1);

      atlas.dispose();

      expect(residency.residentPages, isEmpty);
      expect(timers.pending, 0);
      pressure.raise();
    });

    test('a page loaded for a closed panel starts its retention', () async {
      visible.value = false;
      final atlas = build(['a']);
      // Bake with the panel open, then close before the page lands.
      visible.value = true;
      atlas.start();
      while (!store.readRequested && frames.hasPendingRequest) {
        frames.pump();
        await Future<void>.delayed(Duration.zero);
      }
      visible.value = false;
      await pumpEventQueue();

      timers.elapse(_retention);

      expect(atlas.residency.residentPages, isEmpty);
    });
  });

  group('the memory ceiling', () {
    test(
      'the current catalogue stays within 64 MiB of resident pages',
      () async {
        final atlas = await baked(SampleGlyphCatalogue.glyphs());
        final layout = atlas.index.layout;

        final bytes = atlas.residency.residentBytes;

        expect(atlas.residency.residentPages, hasLength(atlas.index.pageCount));
        expect(
          bytes,
          lessThanOrEqualTo(64 * _mebibyte),
          reason:
              'Resident emoji pages take ${bytes / _mebibyte} MiB '
              '(${atlas.index.pageCount} pages of '
              '${GlyphAtlasLayout.pageSize} px at a ${layout.glyphSize} px '
              'glyph), over the 64 MiB ceiling. The glyph size is capped by '
              'GlyphAtlasLayout.maxGlyphSize '
              '(${GlyphAtlasLayout.maxGlyphSize} px): raising it, or the page '
              'size, needs windowed residency rather than a higher ceiling.',
        );
      },
    );
  });
}

/// A store that counts how often a page is read back.
class _CountingStore implements GlyphPageStore {
  final FakeGlyphPageStore _inner = FakeGlyphPageStore();
  int reads = 0;
  bool get readRequested => reads > 0;

  @override
  Future<void> write(int pageIndex, Image page) =>
      _inner.write(pageIndex, page);

  @override
  Future<Image?> read(int pageIndex) {
    reads++;
    return _inner.read(pageIndex);
  }

  @override
  Future<void> clear() => _inner.clear();
}
