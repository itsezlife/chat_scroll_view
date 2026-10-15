import 'dart:ui' as ui;

/// A least-recently-used cache of laid-out paragraphs with a hard size bound.
///
/// The painter keys paragraphs by content and layout width. Without a bound a
/// window that is resized step by step adds a full visible band of paragraphs
/// per step and never gives one back; with [limit] the oldest unused entry is
/// dropped instead. A lookup moves its entry to the newest end, so everything
/// the current frame draws survives as long as one frame draws fewer than
/// [limit] paragraphs.
///
/// A paragraph holds engine memory outside the Dart heap, so an entry that
/// leaves the cache, by eviction or [clear], is disposed. Drawing it records
/// its glyphs into the canvas at once, so a picture already recorded does not
/// depend on the paragraph staying alive.
final class CatalogParagraphCache<K extends Object> {
  /// Creates an empty cache holding at most [limit] paragraphs.
  CatalogParagraphCache({required this.limit})
    : assert(limit > 0, 'A cache that holds nothing lays out every draw.');

  /// Most paragraphs held at once.
  final int limit;

  // A Dart map iterates in insertion order, so the first key is the oldest.
  final Map<K, ui.Paragraph> _entries = {};

  /// Paragraphs held right now.
  int get length => _entries.length;

  /// The paragraph for [key], created by [create] when absent.
  ui.Paragraph obtain(K key, ui.Paragraph Function() create) {
    final hit = _entries.remove(key);
    if (hit != null) {
      _entries[key] = hit;
      return hit;
    }
    final paragraph = create();
    _entries[key] = paragraph;
    if (_entries.length > limit) {
      _entries.remove(_entries.keys.first)?.dispose();
    }
    return paragraph;
  }

  /// Drops and disposes every paragraph.
  void clear() {
    for (final paragraph in _entries.values) {
      paragraph.dispose();
    }
    _entries.clear();
  }
}
