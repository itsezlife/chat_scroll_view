import 'dart:typed_data';

import 'package:catalog_assets/frame_pool.dart';
import 'package:lottie_decoder/src/cache/frame_cache.dart';
import 'package:lottie_decoder/src/cache/frame_cache_key.dart';
import 'package:lottie_decoder/src/engine/lottie_slot_engine.dart';
import 'package:lottie_decoder/src/memory/native_frame_page_memory.dart';
import 'package:lottie_decoder/src/renderer/lottie_source.dart';
import 'package:lottie_native/lottie_native.dart';

/// A [FrameRenderer] that draws through a [LottieSlotEngine] into one
/// [NativeFramePageMemory], replaying frames from a [FrameCache] when it has
/// them.
///
/// A job's `source` is the [LottieSource] of a loaded file. A batch is a few
/// engine calls at most; an engine error propagates as itself.
///
/// ## With a cache
///
/// A job whose source has a [FrameCacheKey] that the cache admits, and whose
/// frame is inside the animation, is **cacheable**. The batch asks the cache
/// to `open` each key the first time the renderer sees it, and again once its
/// frames have left RAM (that is what makes the frames of an earlier launch,
/// or of an eviction, resident). Only the batch that starts an open waits for
/// it; a batch that meets one still reading treats the key as a miss and
/// renders. A cache that cannot open a key is not used for that batch. Then:
///
/// - a cacheable job whose frame is resident is **restored**: the engine
///   decompresses the cached bytes into the slot;
/// - every other job renders, and a cacheable one also hands its compressed
///   pixels back, which go into the cache;
/// - a restore that fails (the entry is corrupt, or of another size) is
///   rendered after all in the same batch, and its animation is invalidated:
///   one damaged frame says nothing of how many others are, and a file left
///   in place would fail again on every launch.
///
/// The answer lists the jobs that now hold their frame, restored or rendered,
/// in job order. A cache that was disposed meanwhile is skipped, not an error.
/// Without a cache, or for a job that is not cacheable, the behaviour is that
/// of an engine alone.
final class LottieFrameRenderer implements FrameRenderer {
  /// Creates a renderer of [engine] that writes into [memory] only, and
  /// remembers frames in [cache] when there is one.
  LottieFrameRenderer({
    required LottieSlotEngine engine,
    required NativeFramePageMemory memory,
    FrameCache? cache,
  }) : _engine = engine,
       _memory = memory,
       _cache = cache;

  final LottieSlotEngine _engine;
  final NativeFramePageMemory _memory;
  final FrameCache? _cache;

  // The open of each key last started. A key stays for the life of the
  // renderer, one small value per animation and size shown.
  final Map<FrameCacheKey, _Open> _opened = {};

  @override
  Future<List<int>> render(List<FrameJob> jobs, FramePageMemory memory) async {
    if (!identical(memory, _memory)) {
      throw StateError('This renderer was built for another page memory.');
    }
    if (jobs.isEmpty) return const <int>[];
    final entries = [
      for (var i = 0; i < jobs.length; i++) _Entry.of(i, jobs[i], _memory),
    ];
    final cache = _cache;
    if (cache == null ||
        cache.isDisposed ||
        entries.every((entry) => entry.key == null)) {
      return _renderPlain(entries);
    }
    return _renderCached(cache, entries);
  }

  // --- No cache: today's path ---

  Future<List<int>> _renderPlain(List<_Entry> entries) async {
    final statuses = await _engine.renderBatch([
      for (final entry in entries) entry.job,
    ]);
    return [
      for (var i = 0; i < statuses.length; i++)
        if (statuses[i] == LottieRenderStatus.ok) i,
    ];
  }

  // --- With a cache ---

  Future<List<int>> _renderCached(
    FrameCache cache,
    List<_Entry> entries,
  ) async {
    final keys = {for (final entry in entries) ?entry.key};
    // Only a batch that starts an open waits for it. A done open is started
    // again once RAM has let the animation go, so that its file refills RAM
    // instead of the frames being rendered over; a pending one is a miss.
    final starts = <Future<bool>>[];
    for (final key in keys) {
      final open = _opened[key];
      if (open == null || (open.done && !cache.has(key, 0))) {
        starts.add(_open(cache, key));
      }
    }
    if (!(await Future.wait(starts)).every((opened) => opened)) {
      return _renderPlain(entries);
    }
    // The cache may have been disposed while the disk was read.
    if (cache.isDisposed) return _renderPlain(entries);

    final restores = <_Entry>[];
    final captures = <_Entry>[];
    final plain = <_Entry>[];
    for (final entry in entries) {
      final key = entry.key;
      final bytes = key == null ? null : cache.frame(key, entry.frame);
      if (bytes != null) {
        restores.add(entry.withCached(bytes));
      } else if (key != null) {
        captures.add(entry);
      } else {
        plain.add(entry);
      }
    }

    // Sent together, so the engine overlaps them; awaited one by one, so that
    // its error arrives as itself and not wrapped in a ParallelWaitError.
    final restoredAsk = _restore(restores)..ignore();
    final capturedAsk = _capture(captures)..ignore();
    final drawnAsk =
        (plain.isEmpty
              ? Future.value(const <LottieRenderStatus>[])
              : _engine.renderBatch([for (final entry in plain) entry.job]))
          ..ignore();
    final restored = await restoredAsk;
    final captured = await capturedAsk;
    final drawn = await drawnAsk;

    final held = <int>[];
    final damaged = <_Entry>[];
    for (var i = 0; i < restores.length; i++) {
      if (restored[i] == LottieRenderStatus.ok) {
        held.add(restores[i].index);
      } else {
        damaged.add(restores[i]);
      }
    }
    for (var i = 0; i < plain.length; i++) {
      if (drawn[i] == LottieRenderStatus.ok) held.add(plain[i].index);
    }
    held.addAll(_store(cache, captures, captured));

    if (damaged.isNotEmpty) {
      for (final key in {for (final entry in damaged) entry.key!}) {
        // Not awaited: the RAM entry goes at once, and the file's removal
        // reports its own failure, so this render waits for neither.
        cache.invalidate(key).ignore();
      }
      held.addAll(_store(cache, damaged, await _capture(damaged)));
    }
    return held..sort();
  }

  /// Starts the open of [key] and records it; true when the cache opened it.
  /// A failed open is a miss and leaves no record, so the next batch tries
  /// again.
  Future<bool> _open(FrameCache cache, FrameCacheKey key) async {
    final open = _opened[key] = _Open();
    try {
      await cache.open(key);
      open.done = true;
      return true;
    } on Object {
      // The cache is not fit to serve this batch (it was disposed meanwhile);
      // the batch renders without it, and its own reporting is not repeated.
      if (identical(_opened[key], open)) _opened.remove(key);
      return false;
    }
  }

  Future<List<LottieRenderStatus>> _restore(List<_Entry> entries) {
    if (entries.isEmpty) return Future.value(const <LottieRenderStatus>[]);
    return _engine.restore([
      for (final entry in entries)
        LottieRestoreJob(
          compressed: entry.cached!,
          width: entry.job.width,
          height: entry.job.height,
          address: entry.job.address,
          strideBytes: entry.job.strideBytes,
        ),
    ]);
  }

  Future<List<LottieCapture>> _capture(List<_Entry> entries) {
    if (entries.isEmpty) return Future.value(const <LottieCapture>[]);
    return _engine.renderCapturing([for (final entry in entries) entry.job]);
  }

  /// Puts the compressed frames of [captures] into [cache] and returns the
  /// indices of the jobs that rendered.
  List<int> _store(
    FrameCache cache,
    List<_Entry> entries,
    List<LottieCapture> captures,
  ) {
    final held = <int>[];
    for (var i = 0; i < entries.length; i++) {
      if (captures[i].status != LottieRenderStatus.ok) continue;
      held.add(entries[i].index);
      final bytes = captures[i].compressed;
      // An engine without a codec renders and has nothing to store; a cache
      // disposed during the render (shutdown) takes nothing more.
      if (bytes == null || cache.isDisposed) continue;
      cache.put(
        entries[i].key!,
        entries[i].frame,
        bytes,
        frameCount: entries[i].frameCount,
      );
    }
    return held;
  }
}

/// The open of one key: done once the cache has answered.
final class _Open {
  bool done = false;
}

/// One job of a batch, read once: where it sits, what it draws, where it is
/// cached.
final class _Entry {
  _Entry._(
    this.index,
    this.frame,
    this.frameCount,
    this.key,
    this.job, [
    this.cached,
  ]);

  factory _Entry.of(int index, FrameJob job, NativeFramePageMemory memory) {
    final source = switch (job.source) {
      final LottieSource source => source,
      final other => throw ArgumentError.value(
        other,
        'job.source',
        'must be a LottieSource',
      ),
    };
    final side = job.slot.pageSide;
    final left = job.slot.rect.left.toInt();
    final top = job.slot.rect.top.toInt();
    final candidate = source.cacheKey;
    final cacheable =
        candidate != null &&
        candidate.admitted() &&
        job.frame >= 0 &&
        job.frame < source.frameCount;
    return _Entry._(
      index,
      job.frame,
      source.frameCount,
      cacheable ? candidate : null,
      LottieEngineJob(
        handle: source.handle,
        frame: job.frame.toDouble(),
        width: job.width,
        height: job.height,
        address:
            memory.addressOf(job.slot.pageIndex, side: side) +
            (top * side + left) * FramePageMemory.bytesPerPixel,
        strideBytes: side * FramePageMemory.bytesPerPixel,
      ),
    );
  }

  final int index;
  final int frame;
  final int frameCount;

  /// The cache key when this job is cacheable, else null.
  final FrameCacheKey? key;
  final LottieEngineJob job;

  /// The cached bytes, once the cache has them.
  final Uint8List? cached;

  _Entry withCached(Uint8List bytes) =>
      _Entry._(index, frame, frameCount, key, job, bytes);
}
