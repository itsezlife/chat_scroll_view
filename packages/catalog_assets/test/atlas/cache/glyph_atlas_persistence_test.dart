import 'dart:async';

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const _perPage = 676; // GlyphAtlasLayout().cellsPerPage

List<String> _glyphs(int count) => [for (var i = 0; i < count; i++) 'g$i'];

void main() {
  late FakeGlyphCacheStore cache;
  late FakeGlyphArtVersionSource art;
  late FakeBakeFrameSource frames;
  late ManualBakeClock clock;
  late ValueNotifier<bool> visible;
  late ValueNotifier<bool> opening;
  late List<FlutterErrorDetails> errors;

  setUp(() {
    cache = FakeGlyphCacheStore();
    art = FakeGlyphArtVersionSource('art-1');
    frames = FakeBakeFrameSource();
    clock = ManualBakeClock();
    visible = ValueNotifier<bool>(true);
    opening = ValueNotifier<bool>(false);
    errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);
  });
  tearDown(() async {
    visible.dispose();
    opening.dispose();
    await cache.clear();
  });

  /// One launch of the app: a new atlas, a new rasteriser, the same disk.
  ({GlyphAtlas atlas, FakeGlyphRasteriser rasteriser}) launch(
    List<String> glyphs, {
    double density = 2,
    GlyphPageResidency? residency,
    RetiredGlyphArt? predecessor,
  }) {
    final rasteriser = FakeGlyphRasteriser();
    final atlas = GlyphAtlas(
      index: GlyphAtlasIndex(glyphs),
      rasteriser: rasteriser,
      persistence: GlyphAtlasPersistence(
        cache: cache,
        artVersion: art,
        devicePixelRatio: density,
      ),
      frames: frames,
      clock: clock.read,
      panelVisible: visible,
      panelOpening: opening,
      residency: residency,
      predecessor: predecessor,
    );
    addTearDown(atlas.dispose);
    return (atlas: atlas, rasteriser: rasteriser);
  }

  Future<void> frame() async {
    frames.pump();
    await pumpEventQueue();
  }

  Future<int> bakeAll({int limit = 600}) async {
    var n = 0;
    while (n < limit && frames.hasPendingRequest) {
      await frame();
      n++;
    }
    return n;
  }

  /// A full first run, then "the app is closed".
  Future<void> firstRun(List<String> glyphs, {double density = 2}) async {
    final run = launch(glyphs, density: density);
    run.atlas.start();
    await pumpEventQueue();
    await bakeAll();
    expect(run.atlas.spriteOf(glyphs.first), isNotNull);
    run.atlas.dispose();
  }

  group('first run, no cache', () {
    test('shows circles, bakes, and fills in', () async {
      final run = launch(_glyphs(3))..atlas.start();
      await pumpEventQueue();

      expect(run.atlas.spriteOf('g0'), isNull);

      await bakeAll();

      expect(run.atlas.spriteOf('g0'), isNotNull);
      expect(run.atlas.cacheReport.verdict, GlyphCacheVerdict.miss);
      expect(run.rasteriser.painted, ['g0', 'g1', 'g2']);
    });

    test('persists every page, so the bake is paid once', () async {
      await firstRun(_glyphs(_perPage + 1));

      final stored = (await cache.openCommitted())!;
      expect(stored.record.glyphs, _glyphs(_perPage + 1));
      for (final page in [0, 1]) {
        final image = await stored.pages.read(page);
        expect(image, isNotNull, reason: 'page $page');
        image!.dispose();
      }
    });

    test('does not read the pages it has just written', () async {
      await firstRun(_glyphs(_perPage + 1));

      expect(cache.reads, isEmpty);
    });

    test('keeps baking and drawing when the disk refuses writes', () async {
      cache.failWrites = true;
      final run = launch(_glyphs(3))..atlas.start();
      await pumpEventQueue();
      await bakeAll();

      expect(run.atlas.spriteOf('g0'), isNotNull);
      expect(errors, hasLength(1));
    });

    test('waits for the art version and requests no frame meanwhile', () async {
      art.hold();
      final run = launch(_glyphs(2))..atlas.start();
      await pumpEventQueue();

      expect(frames.hasPendingRequest, isFalse);
      expect(run.atlas.spriteOf('g0'), isNull);

      art.release();
      await pumpEventQueue();
      await bakeAll();
      expect(run.atlas.spriteOf('g0'), isNotNull);
    });

    test(
      'an unreadable art version means no persistence this launch',
      () async {
        await firstRun(_glyphs(2));
        final committedBefore = cache.commits;
        art.fail = true;

        final run = launch(_glyphs(2))..atlas.start();
        await pumpEventQueue();
        await bakeAll();

        expect(errors, isNotEmpty);
        expect(run.atlas.spriteOf('g0'), isNotNull);
        expect(
          run.rasteriser.painted,
          isNotEmpty,
          reason: 'baked, not restored',
        );
        expect(cache.commits, committedBefore);
        expect(cache.stages, 1, reason: 'only the first run staged anything');
      },
    );
  });

  group('cache hit on the next launch', () {
    test('draws from the persisted pages and rasterises nothing', () async {
      await firstRun(_glyphs(_perPage + 1));

      final run = launch(_glyphs(_perPage + 1))..atlas.start();
      await pumpEventQueue();
      await bakeAll();

      expect(run.atlas.cacheReport.verdict, GlyphCacheVerdict.hit);
      expect(run.atlas.spriteOf('g0'), isNotNull);
      expect(run.atlas.spriteOf('g$_perPage'), isNotNull);
      expect(run.rasteriser.painted, isEmpty);
      expect(cache.stages, 1, reason: 'a hit stages nothing new');
    });

    test('restores one page per frame', () async {
      await firstRun(_glyphs(_perPage + 1));

      final run = launch(_glyphs(_perPage + 1))..atlas.start();
      await pumpEventQueue();
      expect(run.atlas.spriteOf('g0'), isNull);

      await frame();
      expect(run.atlas.spriteOf('g0'), isNotNull);
      expect(run.atlas.spriteOf('g$_perPage'), isNull);

      await frame();
      expect(run.atlas.spriteOf('g$_perPage'), isNotNull);
    });

    test('hears of each restored page like a baked one', () async {
      await firstRun(_glyphs(_perPage + 1));
      final run = launch(_glyphs(_perPage + 1));
      final seen = <int>[];
      run.atlas
        ..addPageListener(seen.add)
        ..start();
      await pumpEventQueue();
      await bakeAll();

      expect(seen, [0, 1]);
    });

    test('reports how long the circles lasted on the injected clock', () async {
      await firstRun(_glyphs(_perPage + 1));
      final run = launch(_glyphs(_perPage + 1))..atlas.start();
      await pumpEventQueue();
      clock.advance(const Duration(milliseconds: 40));
      await frame();
      clock.advance(const Duration(milliseconds: 60));
      await frame();

      final report = run.atlas.cacheReport;
      expect(report.firstPageAfterStart, const Duration(milliseconds: 40));
      expect(report.allPagesAfterStart, const Duration(milliseconds: 100));
      expect(report.restoredPages, 2);
    });

    test(
      'waits for a scroll or the open animation, not for a hidden panel',
      () async {
        await firstRun(_glyphs(2));
        visible.value = false;
        final run = launch(_glyphs(2))..atlas.start();
        await pumpEventQueue();

        // Hidden: still restores, so the panel opens onto drawn glyphs.
        await frame();
        expect(run.atlas.spriteOf('g0'), isNotNull);

        final second = launch(_glyphs(2))..atlas.start();
        final surface = Object();
        second.atlas.reportScrolling(reporter: surface, scrolling: true);
        await pumpEventQueue();
        expect(frames.hasPendingRequest, isFalse);
        second.atlas.reportScrolling(reporter: surface, scrolling: false);
        await pumpEventQueue();
        await frame();
        expect(second.atlas.spriteOf('g0'), isNotNull);

        final third = launch(_glyphs(2));
        opening.value = true;
        third.atlas.start();
        await pumpEventQueue();
        expect(frames.hasPendingRequest, isFalse);
        opening.value = false;
        await pumpEventQueue();
        await frame();
        expect(third.atlas.spriteOf('g0'), isNotNull);
      },
    );

    test(
      'dispose in the middle of a restore leaves no request behind',
      () async {
        await firstRun(_glyphs(_perPage + 1));
        final run = launch(_glyphs(_perPage + 1))..atlas.start();
        await pumpEventQueue();
        await frame();

        run.atlas.dispose();
        await pumpEventQueue();

        expect(frames.hasPendingRequest, isFalse);
        expect(run.atlas.spriteOf('g0'), isNull);
      },
    );
  });

  group('page residency', () {
    test('a page released after the retention comes back from disk', () async {
      await firstRun(_glyphs(3));
      final timers = ManualRetentionTimers();
      final run = launch(
        _glyphs(3),
        residency: GlyphPageResidency(startTimer: timers.start),
      )..atlas.start();
      await pumpEventQueue();
      await bakeAll();
      expect(run.atlas.spriteOf('g0'), isNotNull);

      visible.value = false;
      timers.elapse(GlyphPageResidency.defaultRetention);
      cache.reads.clear();
      expect(run.atlas.spriteOf('g0'), isNull, reason: 'released, a circle');

      visible.value = true;
      await pumpEventQueue();
      await frame();

      expect(run.atlas.spriteOf('g0'), isNotNull);
      expect(cache.reads, [0], reason: 'one page read, nothing baked');
      expect(run.rasteriser.painted, isEmpty);
    });

    test('after a swap only the new pages are resident', () async {
      final glyphs = _glyphs(_perPage + 1);
      await firstRun(glyphs);
      art.version = 'art-2';
      final run = launch(glyphs)..atlas.start();
      await pumpEventQueue();
      await bakeAll();

      expect(run.atlas.cacheReport.swapped, isTrue);
      expect(run.atlas.residency.residentPages, [0, 1]);
    });
  });

  group('damaged pages are a miss, not a failure', () {
    test(
      'an unreadable page is baked again, the others are restored',
      () async {
        await firstRun(_glyphs(_perPage + 1));
        cache.unreadablePages.add(1);

        final run = launch(_glyphs(_perPage + 1))..atlas.start();
        await pumpEventQueue();
        await bakeAll();

        expect(run.atlas.spriteOf('g0'), isNotNull);
        expect(run.atlas.spriteOf('g$_perPage'), isNotNull);
        expect(run.rasteriser.painted, ['g$_perPage']);
        expect(errors, isEmpty, reason: 'damage is a miss, not an error');
      },
    );

    test('a repaired page is persisted for the launch after', () async {
      await firstRun(_glyphs(_perPage + 1));
      cache.unreadablePages.add(1);
      final run = launch(_glyphs(_perPage + 1))..atlas.start();
      await pumpEventQueue();
      await bakeAll();
      run.atlas.dispose();
      cache.unreadablePages.clear();

      final next = launch(_glyphs(_perPage + 1))..atlas.start();
      await pumpEventQueue();
      await bakeAll();
      expect(next.rasteriser.painted, isEmpty);
    });

    test('a page whose read throws is reported and baked again', () async {
      await firstRun(_glyphs(_perPage + 1));
      cache.throwingPages.add(0);

      final run = launch(_glyphs(_perPage + 1))..atlas.start();
      await pumpEventQueue();
      await bakeAll();

      expect(run.atlas.spriteOf('g0'), isNotNull);
      expect(run.rasteriser.painted.first, 'g0');
      expect(errors, hasLength(1));
    });

    test('a cache that cannot be opened is a first run', () async {
      await firstRun(_glyphs(2));
      cache.failOpen = true;

      final run = launch(_glyphs(2))..atlas.start();
      await pumpEventQueue();
      await bakeAll();

      expect(run.atlas.cacheReport.verdict, GlyphCacheVerdict.miss);
      expect(run.atlas.spriteOf('g0'), isNotNull);
      expect(errors, hasLength(1));
    });
  });

  group('density, glyph size or layout change discards the old pages', () {
    test('a changed density shows circles and bakes afresh', () async {
      await firstRun(_glyphs(3), density: 2);

      final run = launch(_glyphs(3), density: 3)..atlas.start();
      await pumpEventQueue();
      await frame();

      expect(run.atlas.cacheReport.verdict, GlyphCacheVerdict.discard);
      expect(run.atlas.spriteOf('g0'), isNull, reason: 'circles, never stale');
      expect(run.atlas.spriteOf('g1'), isNull);

      await bakeAll();
      expect(run.atlas.spriteOf('g0'), isNotNull);
      expect(run.rasteriser.painted, ['g0', 'g1', 'g2']);
    });

    test('the discarded pages are gone from disk at once', () async {
      await firstRun(_glyphs(3), density: 2);

      launch(_glyphs(3), density: 3).atlas.start();
      await pumpEventQueue();

      final stored = (await cache.openCommitted())!;
      expect(stored.record.key.devicePixelRatio, 3);
      expect(await stored.pages.read(0), isNull);
    });

    test('pages baked by another layout version are discarded', () async {
      final seeded = (await cache.stage(
        GlyphCacheRecord(
          key: GlyphCacheKey(
            artVersion: 'art-1',
            devicePixelRatio: 2,
            glyphSize: GlyphAtlasLayout.forCell(
              logicalExtent: 36,
              devicePixelRatio: 2,
            ).glyphSize,
            layoutVersion: GlyphAtlasLayout.version - 1,
            catalogueHash: GlyphCacheKey.catalogueHashOf(_glyphs(3)),
          ),
          glyphs: _glyphs(3),
        ),
      ));
      expect(seeded, isNotNull);
      await cache.commit();

      final run = launch(_glyphs(3))..atlas.start();
      await pumpEventQueue();
      await frame();

      expect(run.atlas.cacheReport.verdict, GlyphCacheVerdict.discard);
    });
  });

  group('stale-while-rebake', () {
    test('an art change keeps the old pages drawn and swaps once', () async {
      final glyphs = _glyphs(_perPage + 1);
      await firstRun(glyphs);
      art.version = 'art-2';

      final run = launch(glyphs);
      final swaps = <int>[];
      run.atlas
        ..addPageListener(swaps.add)
        ..start();
      await pumpEventQueue();
      await frame();
      await frame();
      expect(run.atlas.cacheReport.verdict, GlyphCacheVerdict.stale);

      // The old art is on screen, page for page.
      final oldFirst = run.atlas.spriteOf('g0')!.page;
      final oldSecond = run.atlas.spriteOf('g$_perPage')!.page;
      expect(swaps, [0, 1], reason: 'the stale pages came in like a restore');
      swaps.clear();

      // While the new set bakes, nothing about what is drawn changes.
      var framesUntilSwap = 0;
      while (swaps.isEmpty && frames.hasPendingRequest) {
        await frame();
        framesUntilSwap++;
        if (swaps.isEmpty) {
          expect(
            identical(run.atlas.spriteOf('g0')!.page, oldFirst),
            isTrue,
            reason: 'frame $framesUntilSwap still shows the old page',
          );
          expect(
            identical(run.atlas.spriteOf('g$_perPage')!.page, oldSecond),
            isTrue,
          );
        }
      }
      expect(framesUntilSwap, greaterThan(10), reason: 'the bake took frames');
      expect(run.rasteriser.painted, hasLength(_perPage + 1));

      // One swap: every page listener heard in the same turn, all new.
      expect(swaps, [0, 1]);
      expect(identical(run.atlas.spriteOf('g0')!.page, oldFirst), isFalse);
      expect(
        identical(run.atlas.spriteOf('g$_perPage')!.page, oldSecond),
        isFalse,
      );
    });

    test('the new set becomes the persisted one only at the swap', () async {
      final glyphs = _glyphs(3);
      await firstRun(glyphs);
      art.version = 'art-2';
      final commitsBefore = cache.commits;

      final run = launch(glyphs)..atlas.start();
      await pumpEventQueue();
      await frame();
      await frame();
      expect(
        (await cache.openCommitted())!.record.key.artVersion,
        'art-1',
        reason: 'killed now, the next launch still finds the old pages',
      );
      expect(cache.commits, commitsBefore);

      await bakeAll();

      expect((await cache.openCommitted())!.record.key.artVersion, 'art-2');
      expect(run.atlas.spriteOf('g0'), isNotNull);
    });

    test(
      'after the swap the next launch is a plain hit on the new art',
      () async {
        final glyphs = _glyphs(3);
        await firstRun(glyphs);
        art.version = 'art-2';
        final run = launch(glyphs)..atlas.start();
        await pumpEventQueue();
        await bakeAll();
        run.atlas.dispose();

        final next = launch(glyphs)..atlas.start();
        await pumpEventQueue();
        await bakeAll();

        expect(next.atlas.cacheReport.verdict, GlyphCacheVerdict.hit);
        expect(next.rasteriser.painted, isEmpty);
      },
    );

    test(
      'a glyph the old plan did not hold is a circle until the swap',
      () async {
        await firstRun(_glyphs(3));

        final run = launch(_glyphs(4))..atlas.start();
        await pumpEventQueue();
        await frame();

        expect(run.atlas.cacheReport.verdict, GlyphCacheVerdict.stale);
        expect(
          run.atlas.spriteOf('g0'),
          isNotNull,
          reason: 'old art, old plan',
        );
        expect(run.atlas.spriteOf('g3'), isNull);

        await bakeAll();
        expect(run.atlas.spriteOf('g3'), isNotNull);
      },
    );

    test(
      'a glyph that left the plan is not offered from the old pages',
      () async {
        await firstRun(_glyphs(4));

        final run = launch(_glyphs(3))..atlas.start();
        await pumpEventQueue();
        await frame();

        expect(run.atlas.spriteOf('g0'), isNotNull);
        expect(run.atlas.spriteOf('g3'), isNull);
      },
    );

    test('a failed disk write still swaps but never commits', () async {
      final glyphs = _glyphs(3);
      await firstRun(glyphs);
      art.version = 'art-2';
      cache.failWrites = true;
      final commitsBefore = cache.commits;

      final run = launch(glyphs)..atlas.start();
      await pumpEventQueue();
      await bakeAll();

      expect(run.atlas.spriteOf('g0'), isNotNull);
      expect(cache.commits, commitsBefore);
      expect((await cache.openCommitted())!.record.key.artVersion, 'art-1');
    });

    test('stale pages that cannot be read leave circles, then bake', () async {
      await firstRun(_glyphs(3));
      art.version = 'art-2';
      cache.unreadablePages.add(0);

      final run = launch(_glyphs(3))..atlas.start();
      await pumpEventQueue();
      await frame();
      expect(run.atlas.spriteOf('g0'), isNull);

      await bakeAll();
      expect(run.atlas.spriteOf('g0'), isNotNull);
    });
  });

  group('stale pages and memory', () {
    // One 2048 px RGBA page.
    const pageBytes = 2048 * 2048 * 4;

    Future<({GlyphAtlas atlas, ManualMemoryPressure pressure})> staleRun(
      List<String> glyphs,
    ) async {
      await firstRun(glyphs);
      art.version = 'art-2';
      final pressure = ManualMemoryPressure();
      addTearDown(pressure.dispose);
      final run = launch(
        glyphs,
        residency: GlyphPageResidency(memoryPressure: pressure),
      )..atlas.start();
      await pumpEventQueue();
      await frame();
      await frame();
      expect(run.atlas.cacheReport.verdict, GlyphCacheVerdict.stale);
      return (atlas: run.atlas, pressure: pressure);
    }

    test('count towards the resident bytes', () async {
      final run = await staleRun(_glyphs(3));

      expect(run.atlas.residency.residentBytes, 0);
      expect(run.atlas.residentBytes, pageBytes);
    });

    test('are released by memory pressure like the resident pages', () async {
      final run = await staleRun(_glyphs(3));
      final stalePage = run.atlas.spriteOf('g0')!.page;
      final heard = <int>[];
      run.atlas.addPageListener(heard.add);

      run.pressure.raise();

      expect(stalePage.debugDisposed, isTrue);
      expect(run.atlas.residentBytes, 0);
      expect(
        run.atlas.spriteOf('g0'),
        isNull,
        reason: 'a circle until the swap',
      );
      expect(heard, [0], reason: 'a surface repaints the lost art');
    });

    test('the new set still swaps and commits after the pressure', () async {
      final run = await staleRun(_glyphs(3));
      final commitsBefore = cache.commits;
      run.pressure.raise();

      await bakeAll();

      expect(run.atlas.spriteOf('g0'), isNotNull);
      expect(run.atlas.cacheReport.swapped, isTrue);
      expect(cache.commits, commitsBefore + 1);
    });
  });

  group('one writer at a time', () {
    test('a successor waits for the retired atlas to finish its disk work '
        'before it stages', () async {
      final gate = Completer<void>();
      cache.writeGate = gate.future;
      final first = launch(_glyphs(2))..atlas.start();
      await pumpEventQueue();
      while (cache.writes.isEmpty && frames.hasPendingRequest) {
        await frame();
      }
      expect(cache.writes, isNotEmpty, reason: 'a write is in flight');
      expect(cache.stages, 1);

      final art = first.atlas.retire();
      final second = launch(_glyphs(3), predecessor: art)..atlas.start();
      await pumpEventQueue();
      expect(cache.stages, 1, reason: 'the old atlas is still writing');

      gate.complete();
      await pumpEventQueue();

      expect(cache.stages, 2);
      await bakeAll();
      expect(second.atlas.spriteOf('g2'), isNotNull);
    });

    test('a successor with nothing in flight does not wait', () async {
      await firstRun(_glyphs(2));
      final first = launch(_glyphs(2))..atlas.start();
      await pumpEventQueue();
      await bakeAll();

      final second = launch(_glyphs(3), predecessor: first.atlas.retire())
        ..atlas.start();
      await pumpEventQueue();

      expect(second.atlas.cacheReport.verdict, isNotNull);
    });
  });

  group('without persistence', () {
    test('an atlas given a plain store behaves as before', () async {
      final store = FakeGlyphPageStore();
      final atlas = GlyphAtlas(
        index: GlyphAtlasIndex(_glyphs(2)),
        rasteriser: FakeGlyphRasteriser(),
        store: store,
        frames: frames,
        clock: clock.read,
        panelVisible: visible,
        panelOpening: opening,
      )..start();
      addTearDown(atlas.dispose);
      await bakeAll();

      expect(atlas.spriteOf('g0'), isNotNull);
      expect(atlas.cacheReport.verdict, isNull);
      await store.clear();
    });
  });

  test('prioritise before the cache is decided is not lost', () async {
    final glyphs = _glyphs(_perPage + 1);
    final run = launch(glyphs)..atlas.start();
    run.atlas.prioritise(['g$_perPage']);
    await pumpEventQueue();
    for (var i = 0; i < 60 && run.atlas.spriteOf('g$_perPage') == null; i++) {
      await frame();
    }

    expect(run.atlas.spriteOf('g$_perPage'), isNotNull);
    expect(run.atlas.spriteOf('g0'), isNull);
  });
}
