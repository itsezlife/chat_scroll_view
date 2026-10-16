import 'dart:ui';

import 'package:catalog_assets/src/atlas/glyph_page_store.dart';

/// A [GlyphPageStore] that keeps pages in memory, for as long as it lives.
///
/// The simplest store that satisfies the contract: pages are GPU image
/// handles, cloned on write and on read. A host that persists pages across
/// launches puts a disk-backed store in its place.
final class MemoryGlyphPageStore implements GlyphPageStore {
  final Map<int, Image> _pages = <int, Image>{};

  @override
  Future<void> write(int pageIndex, Image page) async {
    _pages.remove(pageIndex)?.dispose();
    _pages[pageIndex] = page.clone();
  }

  @override
  Future<Image?> read(int pageIndex) async => _pages[pageIndex]?.clone();

  @override
  Future<void> clear() async {
    for (final page in _pages.values) {
      page.dispose();
    }
    _pages.clear();
  }
}
