import 'dart:ffi';
import 'dart:typed_data';

import 'package:catalog_assets/frame_pool.dart';
import 'package:ffi/ffi.dart';

/// [FramePageMemory] in native memory, so a render isolate and the UI isolate
/// see the same bytes.
///
/// A Dart-heap `Uint8List` cannot be written from another isolate; a page here
/// is `calloc`ed (zero-filled) and a render job names it by [addressOf].
/// [dispose] frees every page: views from [page] are invalid afterwards.
final class NativeFramePageMemory implements FramePageMemory {
  /// Creates memory of [pageSide] x [pageSide] pixel pages.
  NativeFramePageMemory({required this.pageSide})
    : assert(pageSide > 0, 'pageSide must be positive');

  @override
  final int pageSide;

  final Map<int, Pointer<Uint8>> _pages = <int, Pointer<Uint8>>{};
  bool _disposed = false;

  int get _pageBytes => pageSide * pageSide * FramePageMemory.bytesPerPixel;

  Pointer<Uint8> _pointer(int pageIndex) {
    if (_disposed) throw StateError('The page memory is disposed.');
    return _pages[pageIndex] ??= calloc<Uint8>(_pageBytes);
  }

  @override
  Uint8List page(int pageIndex) => _pointer(pageIndex).asTypedList(_pageBytes);

  /// The address of page [pageIndex]'s first byte, making the page if needed.
  ///
  /// An `int`, because it crosses to a render isolate. Stable until [drop].
  int addressOf(int pageIndex) => _pointer(pageIndex).address;

  @override
  void drop(int pageIndex) {
    final pointer = _pages.remove(pageIndex);
    if (pointer != null) calloc.free(pointer);
  }

  /// Frees every page. Idempotent; [page] and [addressOf] throw afterwards.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _pages.values.forEach(calloc.free);
    _pages.clear();
  }
}
