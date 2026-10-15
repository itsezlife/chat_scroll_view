import 'dart:async';
import 'dart:ui';

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

const _perPage = 676; // GlyphAtlasLayout().cellsPerPage

List<String> _glyphs(int count) => [for (var i = 0; i < count; i++) 'g$i'];

void main() {
  late FakeGlyphRasteriser rasteriser;
  late FakeGlyphPageStore store;
  late FakeBakeFrameSource frames;
  late ManualBakeClock clock;
  late ValueNotifier<bool> visible;
  late ValueNotifier<bool> opening;

  setUp(() {
    rasteriser = FakeGlyphRasteriser();
    store = FakeGlyphPageStore();
    frames = FakeBakeFrameSource();
    clock = ManualBakeClock();
    visible = ValueNotifier<bool>(true);
    opening = ValueNotifier<bool>(false);
  });
  tearDown(() async {
    visible.dispose();
    opening.dispose();
    await store.clear();
  });

  GlyphAtlas build(List<String> glyphs) {
    final atlas = GlyphAtlas(
      index: GlyphAtlasIndex(glyphs),
      rasteriser: rasteriser,
      store: store,
      frames: frames,
      clock: clock.read,
      panelVisible: visible,
      panelOpening: opening,
    );
    addTearDown(atlas.dispose);
    return atlas;
  }

  /// One frame, then lets the step and the page load it started finish.
  Future<void> frame() async {
    frames.pump();
    await pumpEventQueue();
  }

  /// Frames until nothing more is requested, at most [limit].
  Future<void> bakeAll({int limit = 400}) async {
    for (var i = 0; i < limit && frames.hasPendingRequest; i++) {
      await frame();
    }
  }

  group('sprites', () {
    test('a glyph has no sprite until its page is baked and loaded', () async {
      final atlas = build(_glyphs(3))..start();

      expect(atlas.spriteOf('g0'), isNull);

      await bakeAll();

      final sprite = atlas.spriteOf('g0')!;
      expect(sprite.pageIndex, 0);
      expect(
        sprite.source,
        GlyphAtlasIndex(_glyphs(3)).placementOf('g0')!.source,
      );
      expect(atlas.spriteOf('unknown'), isNull);
    });

    test('the sprite carries the page image the store holds', () async {
      final atlas = build(_glyphs(2))..start();
      await bakeAll();

      final stored = (await store.read(0))!;
      addTearDown(stored.dispose);

      expect(atlas.spriteOf('g1')!.page.isCloneOf(stored), isTrue);
    });

    test('glyphs of one page share its image, pages differ', () async {
      final atlas = build(_glyphs(_perPage + 2))..start();
      await bakeAll();

      final first = atlas.spriteOf('g0')!;
      final sameFirst = atlas.spriteOf('g5')!;
      final second = atlas.spriteOf('g$_perPage')!;
      expect(first.pageIndex, sameFirst.pageIndex);
      expect(first.page.isCloneOf(sameFirst.page), isTrue);
      expect(second.pageIndex, 1);
      expect(second.page.isCloneOf(first.page), isFalse);
    });
  });

  group('page listeners', () {
    test('are told each page once it can be drawn', () async {
      final atlas = build(_glyphs(_perPage + 1));
      final seen = <int>[];
      final drawable = <bool>[];
      atlas.addPageListener((page) {
        seen.add(page);
        drawable.add(atlas.spriteOf('g${page * _perPage}') != null);
      });
      atlas.start();

      await bakeAll();

      expect(seen, [0, 1]);
      expect(drawable, [true, true]);
    });

    test('stop hearing after removal', () async {
      final atlas = build(_glyphs(2));
      var calls = 0;
      void listener(int page) => calls++;
      atlas
        ..addPageListener(listener)
        ..removePageListener(listener)
        ..start();

      await bakeAll();

      expect(calls, 0);
    });
  });

  group('when baking runs', () {
    test('nothing is baked before start', () async {
      build(_glyphs(2));
      await pumpEventQueue();

      expect(frames.requested, 0);
      expect(rasteriser.painted, isEmpty);
    });

    test('a hidden panel bakes nothing', () async {
      visible.value = false;
      final atlas = build(_glyphs(2))..start();

      expect(frames.hasPendingRequest, isFalse);

      visible.value = true;
      await bakeAll();
      expect(atlas.spriteOf('g0'), isNotNull);
    });

    test('the open animation pauses baking', () async {
      opening.value = true;
      build(_glyphs(2)).start();

      expect(frames.hasPendingRequest, isFalse);

      opening.value = false;
      expect(frames.hasPendingRequest, isTrue);
    });

    test('a reported scroll pauses baking until it settles', () async {
      final atlas = build(_glyphs(2))..start();
      expect(frames.hasPendingRequest, isTrue);

      atlas.reportScrolling(scrolling: true);
      expect(frames.hasPendingRequest, isFalse);

      atlas.reportScrolling(scrolling: false);
      expect(frames.hasPendingRequest, isTrue);
    });

    test('the page of the prioritised glyphs bakes first', () async {
      final atlas = build(_glyphs(_perPage + 1))..start();
      atlas.prioritise(['g$_perPage']);

      // Settling frames, then strips, then the page: a bounded number.
      for (var i = 0; i < 60 && atlas.spriteOf('g$_perPage') == null; i++) {
        await frame();
      }

      expect(atlas.spriteOf('g$_perPage'), isNotNull);
      expect(atlas.spriteOf('g0'), isNull);
    });
  });

  group('teardown', () {
    test('dispose stops baking and drops every sprite', () async {
      final atlas = build(_glyphs(2))..start();
      await bakeAll();
      expect(atlas.spriteOf('g0'), isNotNull);

      atlas.dispose();

      expect(atlas.spriteOf('g0'), isNull);
      expect(frames.hasPendingRequest, isFalse);
    });

    test('a page that loads after dispose is released, not kept', () async {
      final gate = Completer<void>();
      final gated = _GatedStore(store, gate.future);
      final atlas = GlyphAtlas(
        index: GlyphAtlasIndex(_glyphs(2)),
        rasteriser: rasteriser,
        store: gated,
        frames: frames,
        clock: clock.read,
        panelVisible: visible,
        panelOpening: opening,
      )..start();
      final seen = <int>[];
      atlas.addPageListener(seen.add);

      // Frames until the page is composed and its load is waiting on the gate.
      while (!gated.readRequested && frames.hasPendingRequest) {
        await frame();
      }
      expect(gated.readRequested, isTrue);

      atlas.dispose();
      gate.complete();
      await pumpEventQueue();

      expect(atlas.spriteOf('g0'), isNull);
      expect(seen, isEmpty);
      expect(gated.handedOut.single.debugDisposed, isTrue);
    });

    test('dispose is idempotent and the pause notifiers survive it', () {
      final atlas = build(_glyphs(1))..start();

      atlas
        ..dispose()
        ..dispose();

      // The host owns the notifiers: they still work for it.
      expect(() => visible.value = false, returnsNormally);
    });
  });

  test('a failing store is reported and does not crash the app', () async {
    final failing = _ReadReturnsNull();
    final atlas = GlyphAtlas(
      index: GlyphAtlasIndex(_glyphs(1)),
      rasteriser: rasteriser,
      store: failing,
      frames: frames,
      clock: clock.read,
      panelVisible: visible,
      panelOpening: opening,
    )..start();
    addTearDown(atlas.dispose);

    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);

    await bakeAll();

    expect(errors, isNotEmpty);
    expect(atlas.spriteOf('g0'), isNull);
  });
}

/// A store that accepts pages but cannot hand them back.
class _ReadReturnsNull implements GlyphPageStore {
  @override
  Future<void> write(int pageIndex, Image page) async {}

  @override
  Future<Image?> read(int pageIndex) async => null;

  @override
  Future<void> clear() async {}
}

/// A store whose reads wait for [gate], and remembers what it handed out.
class _GatedStore implements GlyphPageStore {
  _GatedStore(this._inner, this.gate);

  final GlyphPageStore _inner;
  final Future<void> gate;
  bool readRequested = false;
  final List<Image> handedOut = <Image>[];

  @override
  Future<void> write(int pageIndex, Image page) =>
      _inner.write(pageIndex, page);

  @override
  Future<Image?> read(int pageIndex) async {
    readRequested = true;
    await gate;
    final image = await _inner.read(pageIndex);
    if (image != null) handedOut.add(image);
    return image;
  }

  @override
  Future<void> clear() => _inner.clear();
}
