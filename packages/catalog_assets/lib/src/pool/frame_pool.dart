import 'package:catalog_assets/src/pool/frame_slot_allocator.dart';
import 'package:flutter/foundation.dart';

/// One claim on an entry's slot, released exactly once.
///
/// A lease is a count, not pixels: an entry with a live lease keeps its slot,
/// and the pool never moves it. Whoever holds one asks the pool's pages for
/// the image when it draws.
final class FrameLease {
  FrameLease._(this.slot, this._onRelease);

  /// Where the entry's current frame lives.
  final FrameSlot slot;

  void Function()? _onRelease;

  /// Whether [release] was called.
  bool get isReleased => _onRelease == null;

  /// Ends the claim. Idempotent.
  void release() {
    final onRelease = _onRelease;
    _onRelease = null;
    onRelease?.call();
  }
}

/// The residency rules of the dynamic frame pool: which entries have a slot,
/// which are pinned, and who goes when the pool is full.
///
/// An **entry** is whatever the owner keys it by, an animation at one display
/// size; the pool does not look inside [K], it only needs equality. An entry
/// is **pinned** while a [FrameLease] covers it (a binding attached and
/// visible) and **idle** after the last lease is released: an idle entry keeps
/// its slot, so a surface that scrolls back finds its frames, until the room is
/// wanted.
///
/// ## Making room
///
/// [acquire] for a new entry that finds no cell evicts idle entries,
/// least recently used first, until a cell of its size class is free, and
/// answers null when only pinned entries are left. Eviction is the pool's
/// answer to "full"; the caller shows the first-frame still on null instead of
/// animating, never an error. A pinned entry is never evicted.
///
/// The cost of making room is that evicting goes on past cells of a class
/// that is not wanted (a 256 px entry needs a whole page, and a page of
/// 128 px cells empties one cell at a time). A smarter victim choice would
/// free less; nothing measured asks for it yet.
///
/// ## Memory pressure
///
/// [releaseUnpinned] evicts every idle entry at once, as the glyph pages do:
/// pinned entries stay, because releasing what is on screen would be redrawn
/// from nothing within a few frames.
///
/// Knows nothing of images or engines: page images, the renderer that fills a
/// slot and the frame cache are the layers above it.
final class FramePool<K extends Object> {
  /// Creates a pool of the pages [budgetBytes] pays for, each class opening a
  /// page of [pageSideFor] pixels.
  ///
  /// [onEvict] is called with the key of each entry that loses its slot, so
  /// its owner knows the frames are gone; [onPageReleased] with the index of
  /// each page that then has no slot left. Throws an [ArgumentError] when the
  /// budget does not cover the smallest page (see [FrameSlotAllocator]).
  FramePool({
    required int Function(int sizeClass) pageSideFor,
    required this.budgetBytes,
    List<int> sizeClasses = const [64, 128, 256, 512],
    this.onEvict,
    ValueChanged<int>? onPageReleased,
  }) : _allocator = FrameSlotAllocator(
         pageSideFor: pageSideFor,
         budgetBytes: budgetBytes,
         sizeClasses: sizeClasses,
         onPageReleased: onPageReleased,
       );

  /// Called with the key of an entry that lost its slot.
  final ValueChanged<K>? onEvict;

  final FrameSlotAllocator _allocator;

  /// Oldest first: a linked map, so eviction reads the order directly and a
  /// touch is a remove and a re-insert.
  final Map<K, _Entry<K>> _entries = <K, _Entry<K>>{};

  /// What the open pages may cost together, in bytes.
  final int budgetBytes;

  /// Entries that hold a slot, pinned or idle.
  int get residentEntries => _entries.length;

  /// Whether [key] holds a slot, pinned or idle.
  bool contains(K key) => _entries.containsKey(key);

  /// Whether a lease covers [key] now.
  bool isPinned(K key) => (_entries[key]?.leases ?? 0) > 0;

  /// Entries a lease covers now.
  int get pinnedEntries => _entries.values.where((e) => e.leases > 0).length;

  /// A lease on [key]'s slot, allocating one for [width] x [height] pixels if
  /// the entry has none, or null when the pool is full of pinned entries.
  ///
  /// Throws an [ArgumentError] for a size the allocator refuses (no pixels, or
  /// above the largest class).
  FrameLease? acquire(K key, int width, int height) {
    var entry = _entries.remove(key);
    if (entry == null) {
      final slot = _allocateMakingRoom(width, height);
      if (slot == null) return null;
      entry = _Entry<K>(key, slot);
    }
    _entries[key] = entry;
    entry.leases++;
    final held = entry;
    return FrameLease._(held.slot, () => _release(held));
  }

  /// Evicts every idle entry now.
  void releaseUnpinned() {
    final idle = [
      for (final entry in _entries.values)
        if (entry.leases == 0) entry,
    ];
    idle.forEach(_evict);
  }

  FrameSlot? _allocateMakingRoom(int width, int height) {
    while (true) {
      final slot = _allocator.allocate(width, height);
      if (slot != null) return slot;
      _Entry<K>? victim;
      for (final entry in _entries.values) {
        if (entry.leases == 0) {
          victim = entry;
          break;
        }
      }
      if (victim == null) return null;
      _evict(victim);
    }
  }

  void _release(_Entry<K> entry) {
    entry.leases--;
    if (entry.leases > 0) return;
    // Idle now: the most recent of the idle ones, so what was just on screen
    // outlives what was left earlier.
    if (_entries.remove(entry.key) != null) _entries[entry.key] = entry;
  }

  void _evict(_Entry<K> entry) {
    _entries.remove(entry.key);
    _allocator.release(entry.slot);
    onEvict?.call(entry.key);
  }
}

final class _Entry<K> {
  _Entry(this.key, this.slot);

  final K key;
  final FrameSlot slot;
  int leases = 0;
}
