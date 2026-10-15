import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:catalog_assets/src/atlas/glyph_page_store.dart';

/// A [GlyphPageStore] that keeps each page as one file in [directory].
///
/// ## File format
///
/// A 16-byte header (magic `GLPG`, width, height and payload length as
/// little-endian unsigned 32-bit integers) followed by the raw RGBA pixels.
/// Raw rather than PNG on purpose: a page is mostly transparent but encoding
/// and decoding 16 MiB as PNG costs far more than the disk space it saves,
/// and reading a page must stay cheap enough to do one per frame.
///
/// ## Damage is a miss
///
/// A page is written to a temporary name and renamed into place, so a process
/// killed mid-write leaves no half page under the real name. A page that is
/// still wrong on read (missing, truncated, wrong magic or a length that does
/// not match its size) is reported as `null`, never thrown. Content is not
/// hashed: that would be a pass over 16 MiB on the root isolate per page, more
/// than the frame it is paced into; truncation and format drift are what the
/// length and header catch.
///
/// Disk work uses the asynchronous `dart:io` API, so it runs off the UI
/// thread; the Dart-side cost per page is the copy of the pixels in and out.
/// The caller paces it (the atlas moves one page per frame).
final class FileGlyphPageStore implements GlyphPageStore {
  /// Creates a store keeping its pages in [directory], created on first write.
  FileGlyphPageStore(this.directory);

  /// Where the pages are.
  final Directory directory;

  static const int _magic = 0x47504C47; // "GLPG" little-endian
  static const int _headerBytes = 16;

  File _file(int pageIndex) => File(
    '${directory.path}${Platform.pathSeparator}page_$pageIndex.glyphpage',
  );

  @override
  Future<void> write(int pageIndex, Image page) async {
    final pixels = await page.toByteData();
    if (pixels == null) {
      throw StateError('page $pageIndex could not be read back from the GPU');
    }
    final header = ByteData(_headerBytes)
      ..setUint32(0, _magic, Endian.little)
      ..setUint32(4, page.width, Endian.little)
      ..setUint32(8, page.height, Endian.little)
      ..setUint32(12, pixels.lengthInBytes, Endian.little);
    await directory.create(recursive: true);
    final target = _file(pageIndex);
    final temp = File('${target.path}.tmp');
    final out = await temp.open(mode: FileMode.write);
    try {
      await out.writeFrom(header.buffer.asUint8List());
      await out.writeFrom(
        pixels.buffer.asUint8List(pixels.offsetInBytes, pixels.lengthInBytes),
      );
    } finally {
      await out.close();
    }
    await temp.rename(target.path);
  }

  @override
  Future<Image?> read(int pageIndex) async {
    final file = _file(pageIndex);
    final Uint8List bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException {
      return null;
    }
    if (bytes.length < _headerBytes) return null;
    final header = ByteData.sublistView(bytes, 0, _headerBytes);
    final width = header.getUint32(4, Endian.little);
    final height = header.getUint32(8, Endian.little);
    final length = header.getUint32(12, Endian.little);
    if (header.getUint32(0, Endian.little) != _magic ||
        width == 0 ||
        height == 0 ||
        length != width * height * 4 ||
        bytes.length != _headerBytes + length) {
      return null;
    }
    final done = Completer<Image?>();
    try {
      decodeImageFromPixels(
        Uint8List.sublistView(bytes, _headerBytes),
        width,
        height,
        PixelFormat.rgba8888,
        done.complete,
      );
    } on Object {
      return null;
    }
    return done.future;
  }

  @override
  Future<void> clear() async {
    try {
      await directory.delete(recursive: true);
    } on FileSystemException {
      // Already gone.
    }
  }
}
