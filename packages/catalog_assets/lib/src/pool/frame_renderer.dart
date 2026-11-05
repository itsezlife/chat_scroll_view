import 'dart:typed_data';

import 'package:catalog_assets/src/pool/frame_slot_allocator.dart';
import 'package:meta/meta.dart';

/// The bytes of the dynamic pages, where a renderer writes frames.
///
/// Pixels are **premultiplied RGBA**, byte order `[R, G, B, A]`, four bytes a
/// pixel, rows `pageSide * 4` bytes apart, whatever engine wrote them. One
/// format everywhere is the point: an engine whose own output differs
/// (the WebAssembly build returns straight alpha) converts before it writes,
/// so no surface and no upload ever has to ask.
///
/// A page is addressed by the index of its slot's page; the memory makes it on
/// first use. Native adapters back it with memory the render isolate and the
/// UI isolate both see; [ListFramePageMemory] keeps it on the Dart heap.
abstract interface class FramePageMemory {
  /// Bytes of one pixel: premultiplied RGBA.
  static const int bytesPerPixel = 4;

  /// Page edge in pixels.
  int get pageSide;

  /// The bytes of page [pageIndex], zero (transparent) when first made.
  /// Valid until [drop]: read it when needed and never keep it.
  Uint8List page(int pageIndex);

  /// Forgets page [pageIndex]; a later [page] makes it again, blank.
  void drop(int pageIndex);
}

/// [FramePageMemory] on the Dart heap.
final class ListFramePageMemory implements FramePageMemory {
  /// Creates memory of [pageSide] x [pageSide] pixel pages.
  ListFramePageMemory({required this.pageSide})
    : assert(pageSide > 0, 'pageSide must be positive');

  @override
  final int pageSide;

  final Map<int, Uint8List> _pages = <int, Uint8List>{};

  @override
  Uint8List page(int pageIndex) => _pages[pageIndex] ??= Uint8List(
    pageSide * pageSide * FramePageMemory.bytesPerPixel,
  );

  @override
  void drop(int pageIndex) => _pages.remove(pageIndex);
}

/// One frame to render into one slot.
@immutable
final class FrameJob {
  /// Creates a job: frame [frame] of [source] at [width] x [height] pixels
  /// into [slot].
  const FrameJob({
    required this.slot,
    required this.frame,
    required this.width,
    required this.height,
    required this.source,
  });

  /// Where the frame goes. The renderer writes inside [FrameSlot.rect] only,
  /// from its top left corner.
  final FrameSlot slot;

  /// The frame index to render.
  final int frame;

  /// Pixels to render, at most the slot's size.
  final int width;

  /// Pixels to render, at most the slot's size.
  final int height;

  /// What to render, as the renderer that made it understands it (a handle to
  /// a parsed animation). The pool never looks inside.
  final Object source;
}

/// Renders frames into slots of a [FramePageMemory], a batch at a time.
///
/// The seam between the pool, which knows slots, pages and who may keep them,
/// and an engine adapter, which knows how to draw. A batch is one call, not
/// one per animation: an adapter on another isolate or native thread pays its
/// call overhead once per tick.
///
/// ## Contract
///
/// - [render] completes with the indices, into `jobs`, of the jobs that now
///   hold their frame. Indices, not the jobs: a renderer on another isolate or
///   thread need not hand back the same objects. A job whose index is left out
///   failed or was dropped; its slot keeps what it had and nothing else about
///   the batch changes. It never throws for one bad job.
/// - A job writes inside its slot, premultiplied, and touches no other byte.
/// - An empty batch completes with an empty list and writes nothing.
abstract interface class FrameRenderer {
  /// Renders every job of [jobs] into [memory].
  Future<List<int>> render(List<FrameJob> jobs, FramePageMemory memory);
}
