import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:catalog_assets/src/pool/frame_renderer.dart';

/// Turns the bytes of one page into a GPU image. [pixels] is premultiplied
/// RGBA, [side] x [side]; an uploader copies it before it returns, because the
/// bytes belong to the [FramePageMemory] and are written again.
typedef FramePageUploader =
    Future<ui.Image> Function(Uint8List pixels, int side);

/// The engine's upload: `decodeImageFromPixels`, which copies the bytes into
/// its own buffer when called.
Future<ui.Image> uploadFramePage(Uint8List pixels, int side) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    side,
    side,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

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
/// ## Ordering
///
/// [flush] reads the bytes of the dirty pages when it starts, so the owner
/// calls it while no renderer is writing: a frame is rendered, flushed, and
/// only then is the next batch started. Calls to [flush] run one after the
/// other.
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
  final Set<int> _dirty = <int>{};

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
      _images.length *
      memory.pageSide *
      memory.pageSide *
      FramePageMemory.bytesPerPixel;

  /// Notes that the bytes of page [pageIndex] changed.
  void markDirty(int pageIndex) {
    if (!_disposed) _dirty.add(pageIndex);
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
    _epochs[pageIndex] = (_epochs[pageIndex] ?? 0) + 1;
    _images.remove(pageIndex)?.dispose();
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
    _dirty.clear();
  }

  Future<void> _flushOnce() async {
    if (_disposed || _dirty.isEmpty) return;
    final pages = _dirty.toList()..sort();
    _dirty.clear();
    await Future.wait([for (final page in pages) _uploadPage(page)]);
  }

  Future<void> _uploadPage(int pageIndex) async {
    final epoch = _epochs[pageIndex] ?? 0;
    final image = await _upload(memory.page(pageIndex), memory.pageSide);
    if (_disposed || (_epochs[pageIndex] ?? 0) != epoch) {
      image.dispose();
      return;
    }
    final previous = _images[pageIndex];
    _images[pageIndex] = image;
    previous?.dispose();
  }
}
