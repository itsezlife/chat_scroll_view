import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:catalog_assets/frame_pool.dart';
import 'package:flutter_test/flutter_test.dart';

const _side = 8;

ui.Image _image() {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(const ui.Rect.fromLTWH(0, 0, 2, 2), ui.Paint());
  final picture = recorder.endRecording();
  final image = picture.toImageSync(_side, _side);
  picture.dispose();
  return image;
}

/// An uploader that records what it was given and answers when told to.
final class _Uploads {
  final List<({int firstByte, int side, int length})> calls = [];
  final List<ui.Image> made = [];
  final List<Completer<void>> pending = [];
  bool manual = false;

  Future<ui.Image> call(Uint8List pixels, int side) {
    calls.add((firstByte: pixels[0], side: side, length: pixels.length));
    final image = _image();
    made.add(image);
    if (!manual) return Future.value(image);
    // The image is made now but delivered later, as an engine upload is.
    final completer = Completer<void>();
    pending.add(completer);
    return completer.future.then((_) => image);
  }

  void finishAll() {
    for (final completer in pending) {
      completer.complete();
    }
    pending.clear();
  }
}

void main() {
  late ListFramePageMemory memory;
  late _Uploads uploads;
  late FramePageImages images;

  setUp(() {
    memory = ListFramePageMemory();
    uploads = _Uploads();
    images = FramePageImages(memory: memory, upload: uploads.call);
  });
  tearDown(() => images.dispose());

  test('nothing is uploaded until a page is marked dirty', () async {
    await images.flush();

    expect(uploads.calls, isEmpty);
    expect(images.imageOf(0), isNull);
  });

  test('flush uploads each dirty page once with its bytes and side', () async {
    memory.page(0, side: _side)[0] = 7;
    memory.page(1, side: _side)[0] = 9;
    images
      ..markDirty(0)
      ..markDirty(1)
      ..markDirty(1);

    await images.flush();

    expect(uploads.calls.map((c) => c.firstByte), unorderedEquals([7, 9]));
    expect(uploads.calls.every((c) => c.side == _side), isTrue);
    expect(images.imageOf(0), isNotNull);
    expect(images.imageOf(1), isNotNull);
  });

  test('a clean page is not uploaded again', () async {
    memory.page(0, side: _side);
    images.markDirty(0);
    await images.flush();

    await images.flush();

    expect(uploads.calls, hasLength(1));
  });

  test('a new upload replaces the image and disposes the old one', () async {
    memory.page(0, side: _side);
    images.markDirty(0);
    await images.flush();
    final first = images.imageOf(0)!;

    images.markDirty(0);
    await images.flush();

    expect(images.imageOf(0), isNot(same(first)));
    expect(first.debugDisposed, isTrue);
    expect(images.imageOf(0)!.debugDisposed, isFalse);
  });

  test('the old image keeps drawing while its replacement uploads', () async {
    memory.page(0, side: _side);
    images.markDirty(0);
    await images.flush();
    final first = images.imageOf(0)!;
    uploads.manual = true;

    images.markDirty(0);
    final flushing = images.flush();
    await Future<void>.delayed(Duration.zero);

    expect(images.imageOf(0), same(first));
    expect(first.debugDisposed, isFalse);
    uploads.finishAll();
    await flushing;
    expect(first.debugDisposed, isTrue);
  });

  test('release disposes the image and drops the page bytes', () async {
    memory.page(0, side: _side)[0] = 5;
    images.markDirty(0);
    await images.flush();
    final image = images.imageOf(0)!;

    images.release(0);

    expect(image.debugDisposed, isTrue);
    expect(images.imageOf(0), isNull);
    expect(
      memory.page(0, side: _side)[0],
      0,
      reason: 'a later page() is blank',
    );
  });

  test('a released page is no longer dirty', () async {
    images
      ..markDirty(0)
      ..release(0);

    await images.flush();

    expect(uploads.calls, isEmpty);
  });

  test('a page released during its upload does not keep the image', () async {
    memory.page(0, side: _side);
    uploads.manual = true;
    images.markDirty(0);
    final flushing = images.flush();
    await Future<void>.delayed(Duration.zero);

    images.release(0);
    uploads.finishAll();
    await flushing;

    expect(images.imageOf(0), isNull);
    expect(uploads.made.single.debugDisposed, isTrue);
  });

  test('a page marked again during its upload is uploaded again', () async {
    memory.page(0, side: _side);
    uploads.manual = true;
    images.markDirty(0);
    final flushing = images.flush();
    await Future<void>.delayed(Duration.zero);

    images.markDirty(0);
    final second = images.flush();
    uploads.finishAll();
    await flushing;
    await Future<void>.delayed(Duration.zero);
    uploads.finishAll();
    await second;

    expect(uploads.calls, hasLength(2));
  });

  test('residentBytes sums the pages, each at its own side', () async {
    memory
      ..page(0, side: _side)
      ..page(3, side: 2 * _side);
    images
      ..markDirty(0)
      ..markDirty(3);
    await images.flush();

    expect(images.residentBytes, (1 + 4) * _side * _side * 4);
  });

  test('each dirty page is uploaded at exactly its own side', () async {
    memory
      ..page(0, side: _side)
      ..page(1, side: 4 * _side);
    images
      ..markDirty(0)
      ..markDirty(1);

    await images.flush();

    expect(
      uploads.calls.map((c) => (c.side, c.length)),
      unorderedEquals([
        (_side, _side * _side * 4),
        (4 * _side, 16 * _side * _side * 4),
      ]),
    );
  });

  group('rows', () {
    test('a page marked down to some rows uploads only those rows', () async {
      memory.page(0, side: _side);
      images.markDirty(0, rows: 3);

      await images.flush();

      expect(uploads.calls.single.side, _side);
      expect(uploads.calls.single.length, _side * 3 * 4);
      expect(images.residentBytes, _side * 3 * 4);
    });

    test(
      'the rows only grow: what was drawn below stays in the image',
      () async {
        memory.page(0, side: _side);
        images.markDirty(0, rows: 5);
        await images.flush();

        images.markDirty(0, rows: 2);
        await images.flush();

        expect(uploads.calls.last.length, _side * 5 * 4);
      },
    );

    test('a page marked without rows uploads whole, and stays whole', () async {
      memory.page(0, side: _side);
      images
        ..markDirty(0, rows: 2)
        ..markDirty(0);
      await images.flush();

      images.markDirty(0, rows: 1);
      await images.flush();

      expect(uploads.calls.map((c) => c.length), [
        _side * _side * 4,
        _side * _side * 4,
      ]);
    });

    test('rows beyond the page are the page', () async {
      memory.page(0, side: _side);
      images.markDirty(0, rows: 3 * _side);

      await images.flush();

      expect(uploads.calls.single.length, _side * _side * 4);
    });

    test('a released page forgets its rows', () async {
      memory.page(0, side: _side);
      images.markDirty(0, rows: 6);
      await images.flush();
      images.release(0);

      memory.page(0, side: _side);
      images.markDirty(0, rows: 1);
      await images.flush();

      expect(uploads.calls.last.length, _side * 1 * 4);
    });
  });

  test('dispose disposes the images and ignores later work', () async {
    memory
      ..page(0, side: _side)
      ..page(1, side: _side);
    images.markDirty(0);
    await images.flush();
    final image = images.imageOf(0)!;

    images.dispose();
    images.markDirty(1);
    await images.flush();

    expect(image.debugDisposed, isTrue);
    expect(uploads.calls, hasLength(1));
    expect(images.imageOf(0), isNull);
  });

  test('dispose twice is harmless', () {
    images.dispose();

    expect(images.dispose, returnsNormally);
  });

  testWidgets('the engine upload makes an image of the rows it is given', (
    tester,
  ) async {
    final pixels = Uint8List(_side * _side * 4)..fillRange(0, _side * 4, 255);

    final image = (await tester.runAsync(
      () => uploadFramePage(pixels, _side),
    ))!;
    addTearDown(image.dispose);

    expect(image.width, _side);
    expect(image.height, _side);
  });

  testWidgets('the engine upload of fewer rows makes a shorter image', (
    tester,
  ) async {
    final pixels = Uint8List(_side * 3 * 4);

    final image = (await tester.runAsync(
      () => uploadFramePage(pixels, _side),
    ))!;
    addTearDown(image.dispose);

    expect(image.width, _side);
    expect(image.height, 3);
  });
}
