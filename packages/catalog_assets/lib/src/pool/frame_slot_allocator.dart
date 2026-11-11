import 'dart:ui';

import 'package:flutter/foundation.dart';

/// One cell of a dynamic page: where an animated asset's current frame lives.
///
/// A slot is a value of the [FrameSlotAllocator] that made it and is only
/// meaningful until it is released there; the pool, not the holder, decides
/// when the page behind [pageIndex] has an image.
@immutable
final class FrameSlot {
  const FrameSlot._({
    required this.pageIndex,
    required this.pageSide,
    required this.rect,
    required Object owner,
  }) : _owner = owner;

  /// Which page the cell is on. Never reused by one allocator, so a slot kept
  /// past its release names a page that no longer exists rather than another
  /// asset's frames.
  final int pageIndex;

  /// Edge in pixels of the page the cell is on. Pages differ in size (see
  /// [FrameSlotAllocator]), so the slot alone says how far apart the rows of
  /// its page are (`pageSide * 4` bytes) and where its cell starts.
  final int pageSide;

  /// The cell in page pixels: its whole size class, which is at least the size
  /// asked for. An asset draws from the top left corner of it.
  final Rect rect;

  final Object _owner;

  @override
  bool operator ==(Object other) =>
      other is FrameSlot &&
      identical(other._owner, _owner) &&
      other.pageIndex == pageIndex &&
      other.pageSide == pageSide &&
      other.rect == rect;

  @override
  int get hashCode =>
      Object.hash(identityHashCode(_owner), pageIndex, pageSide, rect);

  @override
  String toString() => 'FrameSlot(page $pageIndex @ $pageSide px, $rect)';
}

/// Hands out [FrameSlot]s on square pages, up to a byte budget.
///
/// A page holds one **size class** only, as a uniform grid of cells of that
/// class: the longer side of a request picks the smallest class that holds it.
/// Animated assets come in a few display sizes, so a page of equal cells
/// packs without a shelf or a free-list search, and a released cell is reused
/// as it is. The price is the unused part of a cell (a 100 px asset takes a
/// 128 px cell); a general rectangle packer would waste less and fragment, and
/// there is no measurement yet that asks for it.
///
/// ## Pages sized by class
///
/// [pageSideFor] gives the edge of the page a class opens (the atlas's
/// default is twice the class edge, so at most four cells, and one cell from
/// the 512 px class up). A page reaches the
/// GPU whole, so a page much larger than the cells that change makes every
/// tick upload bytes nobody asked for: with one page for every class, one
/// playing 128 px sticker uploaded 64 times what changed. The budget is
/// therefore **bytes**, not a page count: a page opens when its bytes still
/// fit in [budgetBytes], and a small page costs little of it.
///
/// A page whose last cell is released goes back to the budget at once, so a
/// class that is no longer shown does not keep its page. Page indices count
/// up and are never reused.
///
/// Knows nothing of images, bytes or time: the pool owns eviction, pins and
/// what a page is made of.
final class FrameSlotAllocator {
  /// Creates an allocator of pages whose bytes together stay within
  /// [budgetBytes] (four bytes a pixel).
  ///
  /// [sizeClasses] are the cell edges, ascending; [pageSideFor] must give each
  /// a page edge it divides, so that a page is a whole grid. Throws an
  /// [ArgumentError] otherwise, and when the budget does not cover the page of
  /// the smallest class (nothing could ever be allocated).
  FrameSlotAllocator({
    required this.pageSideFor,
    required this.budgetBytes,
    this.sizeClasses = const [64, 128, 256, 384, 512],
    this.onPageReleased,
  }) {
    if (sizeClasses.isEmpty) {
      throw ArgumentError.value(sizeClasses, 'sizeClasses', 'is empty');
    }
    if (!_ascending(sizeClasses) || sizeClasses.first <= 0) {
      throw ArgumentError.value(
        sizeClasses,
        'sizeClasses',
        'must be positive and strictly ascending',
      );
    }
    for (final sizeClass in sizeClasses) {
      final side = pageSideFor(sizeClass);
      if (side <= 0 || side % sizeClass != 0) {
        throw ArgumentError.value(
          side,
          'pageSideFor',
          'is not a whole number of $sizeClass px cells',
        );
      }
    }
    final smallest = bytesOfPage(pageSideFor(sizeClasses.first));
    if (budgetBytes < smallest) {
      throw ArgumentError.value(
        budgetBytes,
        'budgetBytes',
        'does not cover one page of the smallest class ($smallest bytes)',
      );
    }
  }

  /// Bytes of a square page of [side] pixels.
  static int bytesOfPage(int side) => side * side * 4;

  /// The page edge a size class opens.
  final int Function(int sizeClass) pageSideFor;

  /// What the open pages may cost together, in bytes.
  final int budgetBytes;

  /// Cell edges in pixels, ascending.
  final List<int> sizeClasses;

  /// Called with the index of a page that went back to the budget, so its
  /// owner can free what it keeps for that page (its bytes, its image).
  final ValueChanged<int>? onPageReleased;

  final Map<int, _Page> _pages = <int, _Page>{};
  int _nextPageIndex = 0;
  int _used = 0;
  int _pageBytes = 0;
  int _usedBytes = 0;

  /// Pages that exist now.
  int get pageCount => _pages.length;

  /// Bytes of the pages that exist now: the part of [budgetBytes] spent.
  int get pageBytes => _pageBytes;

  /// Bytes of the cells held now, so `usedBytes / pageBytes` is how full the
  /// open pages are.
  int get usedBytes => _usedBytes;

  /// Slots handed out and not yet released.
  int get usedSlots => _used;

  /// A slot for [width] x [height] pixels, or null when no cell of its class
  /// is free and the budget cannot pay for another page of it.
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
      final side = pageSideFor(sizeClass);
      final bytes = bytesOfPage(side);
      if (_pageBytes + bytes > budgetBytes) return null;
      page = _Page(_nextPageIndex++, sizeClass, side);
      _pages[page.index] = page;
      _pageBytes += bytes;
    }
    final cell = page.takeCell();
    _used++;
    _usedBytes += bytesOfPage(sizeClass);
    final side = sizeClass.toDouble();
    return FrameSlot._(
      pageIndex: page.index,
      pageSide: page.side,
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
    _usedBytes -= bytesOfPage(page.sizeClass);
    if (page.isEmpty) {
      _pages.remove(page.index);
      _pageBytes -= bytesOfPage(page.side);
      onPageReleased?.call(page.index);
    }
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
  _Page(this.index, this.sizeClass, this.side)
    : cellsPerSide = side ~/ sizeClass,
      _taken = List<bool>.filled(
        (side ~/ sizeClass) * (side ~/ sizeClass),
        false,
      );

  final int index;
  final int sizeClass;

  /// Edge of the page in pixels.
  final int side;
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
