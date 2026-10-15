import 'dart:ui';

import 'package:catalog_assets/src/atlas/cache/glyph_cache_key.dart';
import 'package:catalog_assets/src/atlas/cache/glyph_cache_store.dart';
import 'package:catalog_assets/src/atlas/cache/memory_glyph_cache_store.dart';
import 'package:catalog_assets/src/atlas/glyph_page_store.dart';

/// A [GlyphCacheStore] for tests: in memory, with the damage a disk can suffer
/// and the counts a test asserts on.
///
/// Damage is applied to the pages a store hands out, so it models what the
/// atlas sees: [unreadablePages] come back as null (a corrupt or truncated
/// page file, which a real store reports as a miss), [throwingPages] throw (a
/// store that failed outright), and [failWrites] makes every page write throw
/// (a full disk).
final class FakeGlyphCacheStore implements GlyphCacheStore {
  final MemoryGlyphCacheStore _inner = MemoryGlyphCacheStore();

  /// Page indices whose reads return null.
  final Set<int> unreadablePages = <int>{};

  /// Page indices whose reads throw.
  final Set<int> throwingPages = <int>{};

  /// Whether page writes throw.
  bool failWrites = false;

  /// Whether [openCommitted] throws.
  bool failOpen = false;

  /// Page reads made through any generation, in order.
  final List<int> reads = <int>[];

  /// Page writes made through any generation, in order.
  final List<int> writes = <int>[];

  /// Number of [commit] calls that succeeded.
  int commits = 0;

  /// Number of [stage] calls.
  int stages = 0;

  @override
  Future<GlyphCacheGeneration?> openCommitted() async {
    if (failOpen) throw StateError('fake cache cannot be opened');
    final generation = await _inner.openCommitted();
    if (generation == null) return null;
    return GlyphCacheGeneration(
      record: generation.record,
      pages: _FaultyPages(this, generation.pages),
    );
  }

  @override
  Future<GlyphPageStore> stage(GlyphCacheRecord record) async {
    stages++;
    return _FaultyPages(this, await _inner.stage(record));
  }

  @override
  Future<void> commit() async {
    await _inner.commit();
    commits++;
  }

  @override
  Future<void> clear() => _inner.clear();
}

final class _FaultyPages implements GlyphPageStore {
  _FaultyPages(this._owner, this._pages);

  final FakeGlyphCacheStore _owner;
  final GlyphPageStore _pages;

  @override
  Future<void> write(int pageIndex, Image page) async {
    _owner.writes.add(pageIndex);
    if (_owner.failWrites) throw StateError('fake cache is full');
    await _pages.write(pageIndex, page);
  }

  @override
  Future<Image?> read(int pageIndex) async {
    _owner.reads.add(pageIndex);
    if (_owner.throwingPages.contains(pageIndex)) {
      throw StateError('fake cache page $pageIndex failed');
    }
    if (_owner.unreadablePages.contains(pageIndex)) return null;
    return _pages.read(pageIndex);
  }

  @override
  Future<void> clear() => _pages.clear();
}
