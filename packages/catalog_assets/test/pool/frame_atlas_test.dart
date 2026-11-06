import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:catalog_assets/frame_pool.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two 256 px pages: eight 128 px cells, or two 256 px cells.
const _budget = 2 * 256 * 256 * 4;

Future<ui.Image> _upload(Uint8List pixels, int side) {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2), ui.Paint());
  final picture = recorder.endRecording();
  final image = picture.toImageSync(4, 4);
  picture.dispose();
  return Future.value(image);
}

/// Fills slots through [_inner] but answers with fixed [answer] indices and
/// copied jobs, as a renderer across an isolate boundary would.
final class _IndexOnlyRenderer implements FrameRenderer {
  _IndexOnlyRenderer(this._inner, {required this.answer});

  final FrameRenderer _inner;
  final List<int> answer;

  @override
  Future<List<int>> render(List<FrameJob> jobs, FramePageMemory memory) async {
    await _inner.render([
      for (final job in jobs)
        FrameJob(
          slot: job.slot,
          frame: job.frame,
          width: job.width,
          height: job.height,
          source: job.source,
        ),
    ], memory);
    return answer;
  }
}

void main() {
  late FakeFrameRenderer renderer;
  late ListFramePageMemory memory;
  late FrameAtlas<String> atlas;

  setUp(() {
    renderer = FakeFrameRenderer();
    memory = ListFramePageMemory();
    atlas = FrameAtlas<String>(
      renderer: renderer,
      memory: memory,
      budgetBytes: _budget,
      pageSideFor: (_) => 256,
      sizeClasses: const [128, 256],
      upload: _upload,
    );
  });
  tearDown(() => atlas.dispose());

  FrameHandle<String>? acquire(String key, {Object source = 'ok'}) =>
      atlas.acquire(key, source: source, width: 100, height: 90);

  group('defaults', () {
    test('the default budget is 48 MiB', () {
      expect(FrameAtlas.defaultBudgetBytes, 48 * 1024 * 1024);
    });

    test('a class opens a page of twice its edge', () {
      expect(FrameAtlas.pageSideFor(64), 128);
      expect(FrameAtlas.pageSideFor(128), 256);
      expect(FrameAtlas.pageSideFor(256), 512);
      expect(FrameAtlas.pageSideFor(512), 1024);
    });

    test('every default size class divides its default page', () {
      for (final sizeClass in FrameAtlas.defaultSizeClasses) {
        expect(FrameAtlas.pageSideFor(sizeClass) % sizeClass, 0);
      }
    });

    test('the default budget pays for the largest page twelve times', () {
      final largest = FrameAtlas.pageSideFor(
        FrameAtlas.defaultSizeClasses.last,
      );

      expect(FrameAtlas.defaultBudgetBytes ~/ (largest * largest * 4), 12);
    });
  });

  group('before a frame', () {
    test('a handle has no frame and no sprite', () {
      final handle = acquire('a')!;

      expect(handle.hasFrame, isFalse);
      expect(handle.frame, isNull);
      expect(handle.sprite, isNull);
    });

    test('a full atlas of pinned handles answers null', () {
      for (var i = 0; i < 8; i++) {
        acquire('a$i');
      }

      expect(acquire('b'), isNull);
    });
  });

  group('render', () {
    test(
      'a rendered handle has a sprite on its page, cut to its size',
      () async {
        final handle = acquire('a')!;

        final batch = await atlas.render([(handle: handle, frame: 3)]);

        expect(batch.rendered, [handle]);
        expect(handle.frame, 3);
        final sprite = handle.sprite!;
        expect(sprite.pageIndex, 0);
        expect(sprite.source, const ui.Rect.fromLTWH(0, 0, 100, 90));
        expect(sprite.page, isNotNull);
      },
    );

    test('handles on one page get distinct, non-overlapping sprites', () async {
      final a = acquire('a')!;
      final b = acquire('b')!;

      await atlas.render([(handle: a, frame: 0), (handle: b, frame: 0)]);

      expect(a.sprite!.pageIndex, b.sprite!.pageIndex);
      expect(a.sprite!.source.overlaps(b.sprite!.source), isFalse);
      expect(
        identical(a.sprite!.page, b.sprite!.page),
        isTrue,
        reason: 'one image per page',
      );
    });

    test('many handles are one renderer call', () async {
      final handles = [for (var i = 0; i < 4; i++) acquire('a$i')!];

      await atlas.render([
        for (final handle in handles) (handle: handle, frame: 1),
      ]);

      expect(renderer.batches, hasLength(1));
      expect(renderer.batches.single, [1, 1, 1, 1]);
    });

    test('a later frame keeps the sprite and moves the frame on', () async {
      final handle = acquire('a')!;
      await atlas.render([(handle: handle, frame: 0)]);

      await atlas.render([(handle: handle, frame: 1)]);

      expect(handle.frame, 1);
      expect(handle.sprite, isNotNull);
    });

    test('a handle the renderer could not render is reported failed', () async {
      final bad = acquire('bad', source: FakeFrameRenderer.rejected)!;
      final good = acquire('good')!;

      final batch = await atlas.render([
        (handle: bad, frame: 0),
        (handle: good, frame: 0),
      ]);

      expect(batch.failed, [bad]);
      expect(batch.rendered, [good]);
      expect(bad.sprite, isNull);
      expect(good.sprite, isNotNull);
    });

    test(
      'a renderer on another thread answers by index, not identity',
      () async {
        final remote = _IndexOnlyRenderer(FakeFrameRenderer(), answer: [1]);
        final remoteAtlas = FrameAtlas<String>(
          renderer: remote,
          memory: ListFramePageMemory(),
          budgetBytes: _budget,
          pageSideFor: (_) => 256,
          sizeClasses: const [128, 256],
          upload: _upload,
        );
        addTearDown(remoteAtlas.dispose);
        final first = remoteAtlas.acquire(
          'first',
          source: 'ok',
          width: 100,
          height: 90,
        )!;
        final second = remoteAtlas.acquire(
          'second',
          source: 'ok',
          width: 100,
          height: 90,
        )!;

        final batch = await remoteAtlas.render([
          (handle: first, frame: 0),
          (handle: second, frame: 0),
        ]);

        expect(batch.rendered, [second]);
        expect(batch.failed, [first]);
      },
    );

    test('a released handle in a batch is a state error', () async {
      final handle = acquire('a')!;
      handle.release();

      expect(
        () => atlas.render([(handle: handle, frame: 0)]),
        throwsStateError,
      );
    });

    test('a handle twice in one batch is an argument error', () async {
      final handle = acquire('a')!;

      expect(
        () => atlas.render([
          (handle: handle, frame: 0),
          (handle: handle, frame: 1),
        ]),
        throwsArgumentError,
      );
    });

    test('batches run one after the other', () async {
      final handle = acquire('a')!;
      renderer.pause();

      final first = atlas.render([(handle: handle, frame: 0)]);
      final second = atlas.render([(handle: handle, frame: 1)]);
      await Future<void>.delayed(Duration.zero);
      expect(renderer.batches, isEmpty);
      renderer.resume();
      await first;
      await second;

      expect(renderer.batches, [
        [0],
        [1],
      ]);
      expect(handle.frame, 1);
    });

    test('a slot is not given away while a batch that names it runs', () async {
      final handle = acquire('a')!;
      renderer.pause();

      final batch = atlas.render([(handle: handle, frame: 0)]);
      await Future<void>.delayed(Duration.zero);
      handle.release();
      // Idle now, but the batch still pins the entry: a full pool of new
      // entries must not evict it.
      for (var i = 0; i < 8; i++) {
        acquire('other$i');
      }
      renderer.resume();
      await batch;

      // Still resident, with the frame the batch rendered: had the entry been
      // evicted meanwhile, its state would be gone.
      expect(atlas.isResident('a'), isTrue);
      expect(acquire('a')!.frame, 0);
    });
  });

  group('residency', () {
    test('a released handle that is still resident keeps its frame', () async {
      final handle = acquire('a')!;
      await atlas.render([(handle: handle, frame: 5)]);
      handle.release();

      final again = acquire('a')!;

      expect(again.frame, 5);
      expect(again.sprite, isNotNull);
    });

    test('an evicted entry comes back without a frame', () async {
      final a = acquire('a')!;
      await atlas.render([(handle: a, frame: 5)]);
      a.release();
      final fillers = [for (var i = 0; i < 8; i++) acquire('fill$i')!];
      expect(atlas.isResident('a'), isFalse);
      fillers.first.release();

      final again = acquire('a')!;

      expect(again.hasFrame, isFalse);
      expect(again.sprite, isNull);
    });

    test('releaseUnpinned frees idle entries and their pages', () async {
      final handle = acquire('a')!;
      await atlas.render([(handle: handle, frame: 0)]);
      handle.release();
      expect(atlas.residentBytes, greaterThan(0));

      atlas.releaseUnpinned();

      expect(atlas.isResident('a'), isFalse);
      expect(atlas.residentBytes, 0);
    });

    test(
      'memory pressure releases idle entries, and dispose stops listening',
      () async {
        final pressure = ManualMemoryPressure();
        final pressured = FrameAtlas<String>(
          renderer: renderer,
          memory: ListFramePageMemory(),
          budgetBytes: _budget,
          pageSideFor: (_) => 256,
          sizeClasses: const [128, 256],
          upload: _upload,
          memoryPressure: pressure,
        );
        final handle = pressured.acquire(
          'a',
          source: 'ok',
          width: 100,
          height: 90,
        )!;
        await pressured.render([(handle: handle, frame: 0)]);
        handle.release();
        expect(pressured.isResident('a'), isTrue);

        pressure.raise();

        expect(pressured.isResident('a'), isFalse);
        expect(pressure.isListened, isTrue);
        pressured.dispose();
        expect(pressure.isListened, isFalse);
      },
    );

    test('a pinned handle survives releaseUnpinned', () async {
      final handle = acquire('a')!;
      await atlas.render([(handle: handle, frame: 0)]);

      atlas.releaseUnpinned();

      expect(handle.sprite, isNotNull);
    });
  });

  group('dispose', () {
    test(
      'disposing drops every image and sprite, and later renders are noops',
      () async {
        final handle = acquire('a')!;
        await atlas.render([(handle: handle, frame: 0)]);

        atlas.dispose();

        expect(handle.sprite, isNull);
        expect(atlas.residentBytes, 0);
        final batch = await atlas.render([(handle: handle, frame: 1)]);
        expect(batch.rendered, isEmpty);
      },
    );

    test('dispose twice is harmless', () {
      atlas.dispose();

      expect(atlas.dispose, returnsNormally);
    });
  });

  group('upload size', () {
    // An atlas on the default sizes, recording the length of every upload.
    late List<int> uploaded;
    late FrameAtlas<String> sized;

    setUp(() {
      uploaded = <int>[];
      sized = FrameAtlas<String>(
        renderer: FakeFrameRenderer(),
        memory: ListFramePageMemory(),
        upload: (pixels, side) {
          uploaded.add(pixels.length);
          expect(pixels.length % (side * 4), 0, reason: 'whole rows');
          return _upload(pixels, side);
        },
      );
      addTearDown(sized.dispose);
    });

    FrameHandle<String> sticker(String key, int edge) =>
        sized.acquire(key, source: 'ok', width: edge, height: edge)!;

    test('each dirty page uploads the rows its cells reach', () async {
      final small = sticker('small', 60);
      final large = sticker('large', 500);

      await sized.render([
        (handle: small, frame: 0),
        (handle: large, frame: 0),
      ]);

      // Rows down to each frame's bottom: 60 of 128, 500 of 1024.
      expect(uploaded, unorderedEquals([128 * 60 * 4, 1024 * 500 * 4]));
    });

    test('one 128 px sticker uploads 128 KiB a tick, not 4 MiB', () async {
      final handle = sticker('a', 128);

      await sized.render([(handle: handle, frame: 0)]);
      uploaded.clear();
      await sized.render([(handle: handle, frame: 1)]);

      expect(uploaded, [256 * 128 * 4]);
    });

    test('a frame shorter than its cell uploads only its rows', () async {
      final handle = sized.acquire(
        'wide',
        source: 'ok',
        width: 120,
        height: 50,
      )!;

      await sized.render([(handle: handle, frame: 0)]);

      expect(uploaded, [256 * 50 * 4]);
    });

    test('rows already drawn below stay in the image', () async {
      // Cells 0 and 1 of a 256 px page are its top row, 2 and 3 the next.
      final top = sticker('top', 128);
      sticker('beside', 128);
      final below = sticker('below', 128);
      await sized.render([(handle: top, frame: 0)]);
      await sized.render([(handle: below, frame: 0)]);
      uploaded.clear();

      await sized.render([(handle: top, frame: 1)]);

      // The cell on top moved again; the image still reaches the lower row.
      expect(uploaded, [256 * 256 * 4]);
    });

    test('four stickers of a class share one small page', () async {
      final handles = [for (var i = 0; i < 4; i++) sticker('a$i', 64)];
      uploaded.clear();

      await sized.render([
        for (final handle in handles) (handle: handle, frame: 0),
      ]);

      expect(uploaded, [64 * 1024]);
    });

    test('five stickers of a class upload two small pages', () async {
      final handles = [for (var i = 0; i < 5; i++) sticker('a$i', 64)];

      await sized.render([
        for (final handle in handles) (handle: handle, frame: 0),
      ]);

      // The second page holds one cell: its top 64 rows, not the 128 of a page.
      expect(uploaded, [64 * 1024, 32 * 1024]);
      expect(sized.residentBytes, 96 * 1024);
    });
  });
}
