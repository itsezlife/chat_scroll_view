import 'dart:async';
import 'dart:ui';

import 'package:catalog_assets/src/atlas/atlas_sprite.dart';
import 'package:catalog_assets/src/pool/frame_page_images.dart';
import 'package:catalog_assets/src/pool/frame_pool.dart';
import 'package:catalog_assets/src/pool/frame_renderer.dart';
import 'package:flutter/foundation.dart' show Listenable;

/// What an entry has rendered, shared by every handle on it.
final class _FrameState {
  int? frame;
}

/// A claim on an animation's slot in a [FrameAtlas].
///
/// What a paintable holds while it is attached: [sprite] says where its
/// current frame is, or null while there is none to draw. Released exactly
/// once; an entry that outlives its last handle keeps its frame until the room
/// is wanted.
final class FrameHandle<K extends Object> {
  FrameHandle._(
    this._atlas,
    this.key,
    this._lease,
    this._state, {
    required this.width,
    required this.height,
    required this.source,
  });

  final FrameAtlas<K> _atlas;
  final FrameLease _lease;
  final _FrameState _state;

  /// The entry this handle claims.
  final K key;

  /// Pixels of a frame.
  final int width;

  /// Pixels of a frame.
  final int height;

  /// What the renderer renders, as it understands it.
  final Object source;

  /// Whether [release] was called.
  bool get isReleased => _lease.isReleased;

  /// The frame the slot holds, or null before the first one was rendered.
  int? get frame => _state.frame;

  /// Whether the slot holds a frame to draw.
  bool get hasFrame => _state.frame != null;

  /// Where the current frame is, or null while there is nothing to draw: no
  /// frame yet, no image of the page yet, a released handle, a disposed
  /// atlas. A late frame leaves the last good one in place, so a sprite that
  /// exists keeps drawing.
  ///
  /// Read it when painting and never keep it: the page image is replaced on
  /// every flush.
  AtlasSprite? get sprite {
    if (isReleased || _atlas._disposed || _state.frame == null) return null;
    final slot = _lease.slot;
    final page = _atlas._images.imageOf(slot.pageIndex);
    if (page == null) return null;
    return AtlasSprite(
      pageIndex: slot.pageIndex,
      page: page,
      source: Rect.fromLTWH(
        slot.rect.left,
        slot.rect.top,
        width.toDouble(),
        height.toDouble(),
      ),
    );
  }

  /// Ends the claim. Idempotent.
  void release() => _lease.release();
}

/// One frame to render for one handle.
typedef FrameRequest<K extends Object> = ({FrameHandle<K> handle, int frame});

/// What a batch did: the handles that now hold their frame and those the
/// renderer could not render.
typedef FrameBatch<K extends Object> = ({
  List<FrameHandle<K>> rendered,
  List<FrameHandle<K>> failed,
});

/// The dynamic frame pages of animated assets: slots, the renderer that fills
/// them, and the images that make them drawable.
///
/// Joins the pieces under one owner, as `GlyphAtlas` does for baked glyphs:
/// a [FramePool] decides who has a slot, a [FrameRenderer] writes frames into
/// the [FramePageMemory], [FramePageImages] uploads the pages that changed,
/// and a [FrameHandle] exposes the result as an `AtlasSprite`. A page whose
/// last entry went is freed, bytes and image, through the pool.
///
/// ## A tick
///
/// The owner (the playback clock's consumer) works out which frame each
/// attached handle should show and calls [render] once: one batch to the
/// renderer, one upload per page that changed, then the sprites are current.
/// Batches run one after the other, so a late batch never overlaps the next
/// and [FramePageImages.flush] never reads bytes a renderer is writing. A
/// batch that is slow just means the handles keep their last good frame.
///
/// ## Pins during a batch
///
/// Each batch takes its own claim on every entry it names, from the moment
/// [render] is called until the batch ends. A handle released meanwhile
/// cannot let its slot go to another entry that the running renderer would
/// then overwrite.
///
/// Single-threaded on the UI isolate; the renderer may work elsewhere.
final class FrameAtlas<K extends Object> {
  /// Creates an atlas of the pages [budgetBytes] pays for.
  ///
  /// [memoryPressure], when given, releases every idle entry each time it
  /// fires; [dispose] stops listening.
  ///
  /// A factory: the pool's callbacks close over the states and the images, so
  /// those are built first, in order, and the private constructor receives
  /// finished objects.
  factory FrameAtlas({
    required FrameRenderer renderer,
    required FramePageMemory memory,
    int budgetBytes = defaultBudgetBytes,
    List<int> sizeClasses = defaultSizeClasses,
    FramePageUploader upload = uploadFramePage,
    Listenable? memoryPressure,
  }) {
    final states = <K, _FrameState>{};
    final images = FramePageImages(memory: memory, upload: upload);
    final pool = FramePool<K>(
      pageSideFor: (_) => memory.pageSide,
      budgetBytes: budgetBytes,
      sizeClasses: sizeClasses,
      onEvict: states.remove,
      onPageReleased: images.release,
    );
    return FrameAtlas._(
      renderer,
      memory,
      budgetBytes,
      states,
      images,
      pool,
      memoryPressure,
    );
  }

  FrameAtlas._(
    this.renderer,
    this._memory,
    this.budgetBytes,
    this._states,
    this._images,
    this._pool,
    this._memoryPressure,
  ) {
    _memoryPressure?.addListener(releaseUnpinned);
  }

  /// Page edge a host gives its [FramePageMemory]: 1024 px, so the default
  /// budget is twelve pages. A page holds one size class only, and at 2048 px
  /// (the glyph pages' size) the same budget would be three pages for four
  /// classes, too coarse to hold a few of each at once.
  static const int defaultPageSide = 1024;

  /// Default byte budget of the pages, apart from the glyph pages' own.
  static const int defaultBudgetBytes = 48 * 1024 * 1024;

  /// Default cell edges: the display sizes animated assets come in, capped at
  /// 512 px like the reference clients' render size.
  static const List<int> defaultSizeClasses = [64, 128, 256, 512];

  /// Draws the frames.
  final FrameRenderer renderer;

  /// What the pages may cost together.
  final int budgetBytes;

  final FramePageMemory _memory;
  final FramePageImages _images;
  final FramePool<K> _pool;
  final Map<K, _FrameState> _states;
  final Listenable? _memoryPressure;
  Future<void> _chain = Future<void>.value();
  bool _disposed = false;

  /// Bytes of the page images that exist.
  int get residentBytes => _images.residentBytes;

  /// Whether [key] holds a slot, pinned or idle.
  bool isResident(K key) => _pool.contains(key);

  /// A handle on [key]'s slot, or null when every page is open and every cell
  /// pinned. The caller then shows the first-frame still instead of
  /// animating: never an error.
  ///
  /// [source] is what the renderer renders; [width] and [height] the pixels of
  /// a frame. Throws an [ArgumentError] for a size the pool refuses.
  FrameHandle<K>? acquire(
    K key, {
    required Object source,
    required int width,
    required int height,
  }) {
    final lease = _pool.acquire(key, width, height);
    if (lease == null) return null;
    final state = _states.putIfAbsent(key, _FrameState.new);
    return FrameHandle<K>._(
      this,
      key,
      lease,
      state,
      width: width,
      height: height,
      source: source,
    );
  }

  /// Renders [requests] in one batch and uploads the pages it changed.
  ///
  /// Throws a [StateError] for a released handle and an [ArgumentError] for
  /// one named twice. After [dispose] it renders nothing.
  Future<FrameBatch<K>> render(List<FrameRequest<K>> requests) {
    if (_disposed) {
      return Future.value((
        rendered: <FrameHandle<K>>[],
        failed: <FrameHandle<K>>[],
      ));
    }
    final seen = <K>{};
    for (final request in requests) {
      if (request.handle.isReleased) {
        throw StateError('${request.handle.key} was released.');
      }
      if (!seen.add(request.handle.key)) {
        throw ArgumentError.value(
          request.handle.key,
          'requests',
          'is named twice in one batch',
        );
      }
    }
    // Pinned from now, not from when the batch starts: it may wait behind
    // another, and the handle can be released in between.
    final pins = [
      for (final request in requests)
        _pool.acquire(
          request.handle.key,
          request.handle.width,
          request.handle.height,
        )!,
    ];
    final run = _chain.then((_) => _renderOnce(requests, pins));
    _chain = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  /// Evicts every idle entry now, as memory pressure asks.
  void releaseUnpinned() => _pool.releaseUnpinned();

  /// Disposes the images and ignores later work. Idempotent.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _memoryPressure?.removeListener(releaseUnpinned);
    _images.dispose();
    _states.clear();
  }

  Future<FrameBatch<K>> _renderOnce(
    List<FrameRequest<K>> requests,
    List<FrameLease> pins,
  ) async {
    try {
      final rendered = <FrameHandle<K>>[];
      final failed = <FrameHandle<K>>[];
      if (_disposed || requests.isEmpty) {
        return (rendered: rendered, failed: failed);
      }
      final jobs = [
        for (final request in requests)
          FrameJob(
            slot: request.handle._lease.slot,
            frame: request.frame,
            width: request.handle.width,
            height: request.handle.height,
            source: request.handle.source,
          ),
      ];
      final done = (await renderer.render(jobs, _memory)).toSet();
      if (_disposed) return (rendered: rendered, failed: failed);
      for (var i = 0; i < jobs.length; i++) {
        final handle = requests[i].handle;
        if (done.contains(i)) {
          handle._state.frame = jobs[i].frame;
          _images.markDirty(jobs[i].slot.pageIndex);
          rendered.add(handle);
        } else {
          failed.add(handle);
        }
      }
      await _images.flush();
      return (rendered: rendered, failed: failed);
    } finally {
      pins.forEach(_release);
    }
  }

  static void _release(FrameLease pin) => pin.release();
}
