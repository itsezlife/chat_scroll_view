import 'dart:ui';

import 'package:meta/meta.dart';

/// One cell of a dynamic page: where an animated asset's current frame lives.
///
/// A slot is a value of the [FrameSlotAllocator] that made it and is only
/// meaningful until it is released there; the pool, not the holder, decides
/// when the page behind [pageIndex] has an image.
@immutable
final class FrameSlot {
  const FrameSlot._({
    required this.pageIndex,
    required this.rect,
    required Object owner,
  }) : _owner = owner;

  /// Which page the cell is on. Never reused by one allocator, so a slot kept
  /// past its release names a page that no longer exists rather than another
  /// asset's frames.
  final int pageIndex;

  /// The cell in page pixels: its whole size class, which is at least the size
  /// asked for. An asset draws from the top left corner of it.
  final Rect rect;

  final Object _owner;

  @override
  bool operator ==(Object other) =>
      other is FrameSlot &&
      identical(other._owner, _owner) &&
      other.pageIndex == pageIndex &&
      other.rect == rect;

  @override
  int get hashCode => Object.hash(identityHashCode(_owner), pageIndex, rect);

  @override
  String toString() => 'FrameSlot(page $pageIndex, $rect)';
}

/// Hands out [FrameSlot]s on square pages, up to a page budget.
///
/// A page holds one **size class** only, as a uniform grid of cells of that
/// class: the longer side of a request picks the smallest class that holds it.
/// Animated assets come in a few display sizes, so a page of equal cells
/// packs without a shelf or a free-list search, and a released cell is reused
/// as it is. The price is the unused part of a cell (a 100 px asset takes a
/// 128 px cell); a general rectangle packer would waste less and fragment, and
/// there is no measurement yet that asks for it.
///
/// A page whose last cell is released goes back to the budget at once, so a
/// class that is no longer shown does not keep its page. Page indices count
/// up and are never reused.
///
/// Knows nothing of images, bytes or time: the pool owns eviction, pins and
/// what a page is made of.
final class FrameSlotAllocator {
  /// Creates an allocator of at most [maxPages] pages of [pageSide] pixels.
  ///
  /// [sizeClasses] are the cell edges, ascending; every one must divide
  /// [pageSide] so that a page is a whole grid.
  FrameSlotAllocator({
    required this.pageSide,
    required this.maxPages,
    this.sizeClasses = const [64, 128, 256, 512],
  }) : assert(pageSide > 0, 'pageSide must be positive'),
       assert(maxPages > 0, 'maxPages must be positive'),
       assert(sizeClasses.isNotEmpty, 'sizeClasses must not be empty'),
       assert(
         sizeClasses.every((c) => c > 0 && pageSide % c == 0),
         'every size class must divide pageSide',
       ),
       assert(
         _ascending(sizeClasses),
         'sizeClasses must be strictly ascending',
       );

  /// Page edge in pixels.
  final int pageSide;

  /// The most pages that exist at once.
  final int maxPages;

  /// Cell edges in pixels, ascending.
  final List<int> sizeClasses;

  final Map<int, _Page> _pages = <int, _Page>{};
  int _nextPageIndex = 0;
  int _used = 0;

  /// Pages that exist now.
  int get pageCount => _pages.length;

  /// Slots handed out and not yet released.
  int get usedSlots => _used;

  /// A slot for [width] x [height] pixels, or null when no cell of its class
  /// is free and every page of the budget is open.
  ///
  /// Throws an [ArgumentError] for a size without pixels or one above the
  /// largest class: that asset is not animated here, and saying so to the
  /// caller beats a null it would read as "pool full".
  FrameSlot? allocate(int width, int height) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError.value('${width}x$height', 'size', 'needs pixels');
    }
    final longer = width > height ? width : height;
    final sizeClass = sizeClasses.firstWhere(
      (c) => c >= longer,
      orElse: () => throw ArgumentError.value(
        '${width}x$height',
        'size',
        'is above the largest size class (${sizeClasses.last})',
      ),
    );

    _Page? page;
    for (final candidate in _pages.values) {
      if (candidate.sizeClass == sizeClass && candidate.hasFreeCell) {
        page = candidate;
        break;
      }
    }
    if (page == null) {
      if (_pages.length >= maxPages) return null;
      page = _Page(_nextPageIndex++, sizeClass, pageSide ~/ sizeClass);
      _pages[page.index] = page;
    }
    final cell = page.takeCell();
    _used++;
    final side = sizeClass.toDouble();
    return FrameSlot._(
      pageIndex: page.index,
      rect: Rect.fromLTWH(
        (cell % page.cellsPerSide) * side,
        (cell ~/ page.cellsPerSide) * side,
        side,
        side,
      ),
      owner: this,
    );
  }

  /// Gives [slot] back. Throws a [StateError] for a slot of another allocator
  /// or one already released: either is a bookkeeping bug to see, not to
  /// absorb.
  void release(FrameSlot slot) {
    final page = _pages[slot.pageIndex];
    if (!identical(slot._owner, this) || page == null) {
      throw StateError('$slot is not held by this allocator.');
    }
    final side = page.sizeClass;
    final cell =
        (slot.rect.top ~/ side) * page.cellsPerSide + slot.rect.left ~/ side;
    if (!page.giveCell(cell)) {
      throw StateError('$slot is not held by this allocator.');
    }
    _used--;
    if (page.isEmpty) _pages.remove(page.index);
  }

  static bool _ascending(List<int> values) {
    for (var i = 1; i < values.length; i++) {
      if (values[i] <= values[i - 1]) return false;
    }
    return true;
  }
}

/// A page: a grid of equal cells and which of them are taken.
final class _Page {
  _Page(this.index, this.sizeClass, this.cellsPerSide)
    : _taken = List<bool>.filled(cellsPerSide * cellsPerSide, false);

  final int index;
  final int sizeClass;
  final int cellsPerSide;
  final List<bool> _taken;
  int _count = 0;

  bool get hasFreeCell => _count < _taken.length;
  bool get isEmpty => _count == 0;

  /// The lowest free cell, so a page fills from the top left.
  int takeCell() {
    final cell = _taken.indexOf(false);
    _taken[cell] = true;
    _count++;
    return cell;
  }

  /// Frees [cell]; false when it was not taken.
  bool giveCell(int cell) {
    if (cell < 0 || cell >= _taken.length || !_taken[cell]) return false;
    _taken[cell] = false;
    _count--;
    return true;
  }
}
