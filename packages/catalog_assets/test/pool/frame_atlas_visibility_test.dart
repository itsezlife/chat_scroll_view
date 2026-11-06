/// When a frame becomes visible (ticket 56): a handle shows a frame only once
/// the upload that holds its pixels has completed, and an entry nobody holds
/// does not show the frame it stopped on.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:catalog_assets/frame_pool.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two 256 px pages: eight 128 px cells.
const _budget = 2 * 256 * 256 * 4;

/// Page uploads that finish when the test says.
final class _GatedUploads {
  final List<Completer<ui.Image>> pending = [];
  int started = 0;

  Future<ui.Image> upload(Uint8List pixels, int side) {
    started++;
    final done = Completer<ui.Image>();
    pending.add(done);
    return done.future;
  }

  /// Finishes the oldest upload that waits.
  void finish() {
    final recorder = ui.PictureRecorder();
    ui.Canvas(
      recorder,
    ).drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2), ui.Paint());
    final picture = recorder.endRecording();
    final image = picture.toImageSync(4, 4);
    picture.dispose();
    pending.removeAt(0).complete(image);
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeFrameRenderer renderer;
  late _GatedUploads uploads;
  late FrameAtlas<String> atlas;

  setUp(() {
    renderer = FakeFrameRenderer();
    uploads = _GatedUploads();
    atlas = FrameAtlas<String>(
      renderer: renderer,
      memory: ListFramePageMemory(),
      budgetBytes: _budget,
      pageSideFor: (_) => 256,
      sizeClasses: const [128, 256],
      upload: uploads.upload,
    );
  });
  tearDown(() => atlas.dispose());

  FrameHandle<String>? acquire(String key) =>
      atlas.acquire(key, source: 'ok', width: 100, height: 90);

  /// Renders [frame] for [handle] and lets its upload finish.
  Future<void> play(FrameHandle<String> handle, int frame) async {
    final batch = atlas.render([(handle: handle, frame: frame)]);
    await _settle();
    uploads.finish();
    await batch;
  }

  group('a frame is shown after its upload', () {
    test('a first frame is not drawable while its page uploads', () async {
      final handle = acquire('a')!;

      final batch = atlas.render([(handle: handle, frame: 0)]);
      await _settle();

      expect(uploads.started, 1);
      expect(handle.hasFrame, isFalse, reason: 'no pixels on the page yet');
      expect(handle.sprite, isNull);
      uploads.finish();
      await batch;
      expect(handle.frame, 0);
      expect(handle.sprite, isNotNull);
    });

    test('a joining cell shows nothing while the page it joins uploads, '
        'although that page already has an image', () async {
      final first = acquire('a')!;
      await play(first, 0);
      final joiner = acquire('b')!;
      expect(joiner.sprite, isNull);

      final batch = atlas.render([(handle: joiner, frame: 0)]);
      await _settle();

      // The old image of the page is still there, with nothing in the
      // joiner's slot: drawing it would paint a blank.
      expect(first.sprite, isNotNull);
      expect(joiner.sprite, isNull);
      uploads.finish();
      await batch;
      expect(joiner.sprite, isNotNull);
    });

    test('a later frame keeps the previous one on show until its upload '
        'completes', () async {
      final handle = acquire('a')!;
      await play(handle, 0);

      final batch = atlas.render([(handle: handle, frame: 1)]);
      await _settle();

      expect(handle.frame, 0);
      expect(handle.sprite, isNotNull);
      uploads.finish();
      await batch;
      expect(handle.frame, 1);
    });

    test('a failed upload admits no frame', () async {
      final handle = acquire('a')!;

      final batch = atlas.render([(handle: handle, frame: 0)]);
      await _settle();
      uploads.pending.removeAt(0).completeError(StateError('gpu lost'));

      await expectLater(batch, throwsStateError);
      expect(handle.hasFrame, isFalse);
    });
  });

  group('an entry nobody holds does not show its last frame', () {
    test('a re-lease starts without a frame, so the still stays up', () async {
      final handle = acquire('a')!;
      await play(handle, 18);
      handle.release();

      final again = acquire('a')!;

      expect(atlas.isResident('a'), isTrue);
      expect(again.hasFrame, isFalse);
      expect(again.sprite, isNull);
    });

    test(
      'a handle released while its batch runs leaves no frame behind',
      () async {
        final handle = acquire('a')!;
        final batch = atlas.render([(handle: handle, frame: 4)]);
        await _settle();
        handle.release();
        uploads.finish();
        await batch;

        final again = acquire('a')!;

        expect(atlas.isResident('a'), isTrue);
        expect(again.hasFrame, isFalse);
      },
    );

    test(
      'a second handle on the key keeps the frame while it is held',
      () async {
        final first = acquire('a')!;
        final second = acquire('a')!;
        await play(first, 2);

        first.release();

        expect(second.frame, 2);
        expect(second.sprite, isNotNull);
      },
    );
  });

  group('a slot is not reused while its upload is in flight', () {
    test('an idle neighbour evicted meanwhile gives its slot to a new cell '
        'that shows nothing until its own frame is uploaded', () async {
      // Fill both pages so a new key must evict.
      final handles = [for (var i = 0; i < 8; i++) acquire('k$i')!];
      final playing = handles.first;
      final batch = atlas.render([(handle: playing, frame: 0)]);
      await _settle();
      for (var i = 1; i < 8; i++) {
        handles[i].release();
      }

      final newcomer = acquire('new')!;

      // The playing cell kept its slot; the newcomer has someone else's
      // pixels there and must not draw them.
      expect(atlas.isResident('k0'), isTrue);
      expect(newcomer.sprite, isNull);
      uploads.finish();
      await batch;
      expect(playing.sprite, isNotNull);
      expect(newcomer.sprite, isNull);
      await play(newcomer, 0);
      expect(newcomer.sprite, isNotNull);
    });
  });
}
