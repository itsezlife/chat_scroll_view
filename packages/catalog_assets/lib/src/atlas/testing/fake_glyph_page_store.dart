import 'dart:ui';

import 'package:catalog_assets/src/atlas/glyph_page_store.dart';

/// An in-memory [GlyphPageStore] for tests.
final class FakeGlyphPageStore implements GlyphPageStore {
  final Map<int, Image> _pages = <int, Image>{};

  /// Indices currently stored, ascending.
  List<int> get storedPages => _pages.keys.toList()..sort();

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
