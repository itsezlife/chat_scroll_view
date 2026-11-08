import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:catalog_assets/src/pool/frame_renderer.dart';
import 'package:catalog_assets/src/pool/pixel_upload.dart';

/// Turns the bytes of one page into a GPU image. [pixels] is premultiplied
/// RGBA, [side] pixels wide and as many rows from the top of the page as
/// `pixels.length ~/ (side * 4)`: the whole page, or its top rows when the
/// rest holds nothing drawn (see [FramePageImages.markDirty]); an uploader
/// copies it before it returns, because the bytes belong to the
/// [FramePageMemory] and are written again.
typedef FramePageUploader =
    Future<ui.Image> Function(Uint8List pixels, int side);

/// The engine's upload of a page of [format] pixels (RGBA unless told
/// otherwise), through [PixelUpload], which copies the bytes when called.
Future<ui.Image> uploadFramePage(
  Uint8List pixels,
  int side, {
  ui.PixelFormat format = ui.PixelFormat.rgba8888,
}) => _engineUpload(
  pixels,
  side,
  pixels.length ~/ (side * FramePageMemory.bytesPerPixel),
  format,
);

final _engineUpload = PixelUpload();

/// The images of the dynamic pages, made from their bytes when they change.
///
/// A renderer writes into [FramePageMemory]; nothing is drawable until the
/// page it wrote on becomes an image, so the owner calls [markDirty] for each
/// page a batch touched and [flush] once per tick: one upload per changed page,
/// however many slots changed on it.
///
/// ## Lifetime
///
/// A page image lives exactly as long as its page: [release] ends both, and an
/// allocator gives a page back when its last slot goes. There is no retention
/// timer here, unlike the baked glyph pages: a glyph page is expensive to bake
/// and cheap to hold, while a frame page is rewritten every tick, so keeping an
/// image whose slots are gone would only hold memory for frames nobody draws.
/// Memory pressure needs no hook of its own either: the pool evicts its idle
/// entries, that empties pages, and the pages come back through [release].
///
/// ## Replacing an image
///
/// The old image keeps drawing until the new one has been uploaded, then the
/// old one is disposed: a surface never sees a page without an image between
/// two frames. A page released while its upload is in flight drops the late
/// image instead of admitting it.
///
/// ## Rows
///
/// A page reaches the GPU whole, and the engine copies it on the UI isolate,
/// so an upload costs what it holds. A frame is drawn from the top left corner
/// of its cell and is often shorter than the cell (a 16:9 clip in a square
/// one), and a page of one cell is empty below it. [markDirty] therefore says
/// how many rows from the top the changed frame reaches, and the image is made
/// of the rows down to the lowest any frame of the page ever reached: rows are
/// contiguous in the page bytes, so that is a view and not a copy. The extent
/// only grows, never shrinks while the page lives: the new image replaces the
/// old whole, so a cell below the changed one, drawn earlier, must still be in
/// it.
///
/// ## Ordering
///
/// [flush] reads the bytes of the dirty pages when it starts, so the owner
/// calls it while no renderer is writing: a frame is rendered, flushed, and
/// only then is the next batch started. Calls to [flush] run one after the
/// other. Within one flush each page starts its upload in an event-loop turn
/// of its own, so the copies of a flush do not hold off a frame together.
final class FramePageImages {
  /// Creates images over [memory], uploading with [upload].
  FramePageImages({
    required this.memory,
    FramePageUploader upload = uploadFramePage,
  }) : _upload = upload;

  /// The bytes the images are made from.
  final FramePageMemory memory;

  final FramePageUploader _upload;
  final Map<int, ui.Image> _images = <int, ui.Image>{};

  /// The bytes each image was made of.
  final Map<int, int> _imageBytes = <int, int>{};
  final Set<int> _dirty = <int>{};

  /// How many rows from the top each live page has been drawn on, or
  /// [_wholePage] after a change that named no rows.
  final Map<int, int> _rows = <int, int>{};
  static const int _wholePage = 1 << 30;

  /// Bumped on every release, so an upload that started before one can tell
  /// that its page is gone.
  final Map<int, int> _epochs = <int, int>{};

  Future<void> _chain = Future<void>.value();
  bool _disposed = false;

  /// The image of page [pageIndex], or null before its first upload. Read it
  /// when drawing and never keep it: the next flush replaces and disposes it.
  ui.Image? imageOf(int pageIndex) => _images[pageIndex];

  /// Bytes of the page images that exist.
  int get residentBytes =>
      _imageBytes.values.fold(0, (sum, bytes) => sum + bytes);

  /// Notes that the bytes of page [pageIndex] changed, down to row [rows]
  /// (counted from the top of the page) or, without it, anywhere on the page.
  void markDirty(int pageIndex, {int? rows}) {
    if (_disposed) return;
    _dirty.add(pageIndex);
    final reached = rows ?? _wholePage;
    final known = _rows[pageIndex] ?? 0;
    if (reached > known) _rows[pageIndex] = reached;
  }

  /// Uploads every dirty page and completes when each image is in place.
  /// An upload error reaches the caller; the page stays as it was.
  Future<void> flush() {
    if (_disposed) return Future<void>.value();
    return _chain = _chain.then((_) => _flushOnce());
  }

  /// Ends page [pageIndex]: disposes its image and drops its bytes.
  void release(int pageIndex) {
    _dirty.remove(pageIndex);
    _rows.remove(pageIndex);
    _epochs[pageIndex] = (_epochs[pageIndex] ?? 0) + 1;
    _images.remove(pageIndex)?.dispose();
    _imageBytes.remove(pageIndex);
    memory.drop(pageIndex);
  }

  /// Disposes every image and ignores later work. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _imageBytes.clear();
    _rows.clear();
    _dirty.clear();
  }

  Future<void> _flushOnce() async {
    if (_disposed || _dirty.isEmpty) return;
    final pages = _dirty.toList()..sort();
    _dirty.clear();
    // The engine copies a page on this isolate the moment its upload starts.
    // Started together, a flush of several pages was one block of copies
    // between two frames, long enough to start the next frame a vsync late
    // while a grid of stickers played. Each page after the first starts in
    // an event-loop turn of its own, so a frame due meanwhile runs between
    // two copies; the uploads still run side by side.
    // A page released while it waited for its turn has no bytes to upload.
    final epochs = {for (final page in pages) page: _epochs[page] ?? 0};
    final uploads = <Future<void>>[];
    for (final page in pages) {
      if (uploads.isNotEmpty) await Future<void>.delayed(Duration.zero);
      if (_disposed) break;
      if ((_epochs[page] ?? 0) != epochs[page]) continue;
      uploads.add(_uploadPage(page));
    }
    await Future.wait(uploads);
  }

  Future<void> _uploadPage(int pageIndex) async {
    final epoch = _epochs[pageIndex] ?? 0;
    // The side is read with the bytes, so an upload is always as wide as its
    // own page: a page a quarter of a 1 MiB one costs a quarter.
    final side = memory.sideOf(pageIndex);
    final rows = (_rows[pageIndex] ?? side).clamp(1, side);
    final bytes = side * rows * FramePageMemory.bytesPerPixel;
    final page = memory.page(pageIndex, side: side);
    final image = await _upload(
      bytes == page.length ? page : Uint8List.sublistView(page, 0, bytes),
      side,
    );
    if (_disposed || (_epochs[pageIndex] ?? 0) != epoch) {
      image.dispose();
      return;
    }
    final previous = _images[pageIndex];
    _images[pageIndex] = image;
    _imageBytes[pageIndex] = bytes;
    previous?.dispose();
  }
}
