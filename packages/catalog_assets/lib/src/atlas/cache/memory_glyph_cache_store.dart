import 'package:catalog_assets/src/atlas/cache/glyph_cache_key.dart';
import 'package:catalog_assets/src/atlas/cache/glyph_cache_store.dart';
import 'package:catalog_assets/src/atlas/glyph_page_store.dart';
import 'package:catalog_assets/src/atlas/memory_glyph_page_store.dart';

/// A [GlyphCacheStore] that lives and dies with the process: the store of a
/// platform with no disk (the web strategy) and the base of the test fake.
final class MemoryGlyphCacheStore implements GlyphCacheStore {
  GlyphCacheRecord? _committedRecord;
  GlyphPageStore? _committedPages;
  GlyphCacheRecord? _stagedRecord;
  GlyphPageStore? _stagedPages;

  @override
  Future<GlyphCacheGeneration?> openCommitted() async {
    final record = _committedRecord;
    final pages = _committedPages;
    if (record == null || pages == null) return null;
    return GlyphCacheGeneration(record: record, pages: pages);
  }

  @override
  Future<GlyphPageStore> stage(GlyphCacheRecord record) async {
    await _stagedPages?.clear();
    _stagedRecord = record;
    return _stagedPages = MemoryGlyphPageStore();
  }

  @override
  Future<void> commit() async {
    final record = _stagedRecord;
    final pages = _stagedPages;
    if (record == null || pages == null) {
      throw StateError('commit() without a staged generation');
    }
    final old = _committedPages;
    _committedRecord = record;
    _committedPages = pages;
    _stagedRecord = null;
    _stagedPages = null;
    await old?.clear();
  }

  @override
  Future<void> clear() async {
    await _committedPages?.clear();
    await _stagedPages?.clear();
    _committedRecord = _stagedRecord = null;
    _committedPages = _stagedPages = null;
  }
}
