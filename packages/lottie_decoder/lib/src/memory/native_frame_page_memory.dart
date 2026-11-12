import 'dart:ffi';
import 'dart:typed_data';

import 'package:catalog_assets/frame_pool.dart';
import 'package:ffi/ffi.dart';

/// [FramePageMemory] in native memory, so a render isolate and the UI isolate
/// see the same bytes.
///
/// A Dart-heap `Uint8List` cannot be written from another isolate; a page here
/// is `calloc`ed (zero-filled) at the side its first user asks for, and a
/// render job names it by [addressOf]. [dispose] frees every page: views from
/// [page] are invalid afterwards.
final class NativeFramePageMemory implements FramePageMemory {
  /// Creates memory with no pages; each is made on its first use.
  NativeFramePageMemory();

  final Map<int, _NativePage> _pages = <int, _NativePage>{};
  bool _disposed = false;

  _NativePage _live(int pageIndex, int side) {
    if (_disposed) throw StateError('The page memory is disposed.');
    if (side <= 0) throw ArgumentError.value(side, 'side', 'must be positive');
    final page = _pages[pageIndex];
    if (page == null) {
      return _pages[pageIndex] = _NativePage(
        side,
        calloc<Uint8>(side * side * FramePageMemory.bytesPerPixel),
      );
    }
    if (page.side != side) {
      throw StateError('Page $pageIndex is ${page.side} px, not $side px.');
    }
    return page;
  }

  @override
  Uint8List page(int pageIndex, {required int side}) {
    final page = _live(pageIndex, side);
    return page.pointer.asTypedList(
      side * side * FramePageMemory.bytesPerPixel,
    );
  }

  @override
  int sideOf(int pageIndex) =>
      _pages[pageIndex]?.side ??
      (throw StateError('Page $pageIndex does not exist.'));

  /// The address of page [pageIndex]'s first byte, making the page at [side]
  /// if needed.
  ///
  /// An `int`, because it crosses to a render isolate. Stable until [drop].
  int addressOf(int pageIndex, {required int side}) =>
      _live(pageIndex, side).pointer.address;

  @override
  void drop(int pageIndex) {
    final page = _pages.remove(pageIndex);
    if (page != null) calloc.free(page.pointer);
  }

  /// Frees every page. Idempotent; [page] and [addressOf] throw afterwards.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final page in _pages.values) {
      calloc.free(page.pointer);
    }
    _pages.clear();
  }
}

final class _NativePage {
  _NativePage(this.side, this.pointer);

  final int side;
  final Pointer<Uint8> pointer;
}
