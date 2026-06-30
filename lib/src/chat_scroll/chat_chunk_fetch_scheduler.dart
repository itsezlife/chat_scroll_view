import 'dart:async';

import 'package:chatscrollview/src/chat_scroll/chat_data_source.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_chunk.dart';
import 'package:flutter/scheduler.dart';

/// Schedules lazy chunk fetching, scroll-debounced polling, jump-fetch
/// dispatch, and LRU chunk eviction for [RenderChatScrollView].
///
/// The render object measures the laid-out chunk range from built children
/// and calls [onLayoutComplete] / [onLayoutCleared] at the end of
/// `performLayout`. Scroll activity timestamps and jump navigation are fed
/// through [markScrollActive] and [onJump]. Attach / detach guard deferred
/// dispatches so a detaching viewport does not touch a stale data source.
class ChatChunkFetchScheduler {
  /// Creates a chunk fetch scheduler bound to [dataSource].
  ///
  /// [requestRange] is typically `dataSource.requestChunks`. [anchorChunkIndex]
  /// supplies the chunk index of the controller anchor for LRU eviction
  /// (the anchor chunk is never evicted).
  ChatChunkFetchScheduler({
    required ChatDataSource dataSource,
    required void Function(int minChunk, int maxChunk) requestRange,
    required int Function() anchorChunkIndex,
    Duration pollInterval = const Duration(milliseconds: 150),
  }) : _dataSource = dataSource,
       _requestRange = requestRange,
       _anchorChunkIndex = anchorChunkIndex,
       _pollInterval = pollInterval;

  final ChatDataSource _dataSource;
  final void Function(int minChunk, int maxChunk) _requestRange;
  final int Function() _anchorChunkIndex;
  final Duration _pollInterval;

  int _layoutMinChunk = 0;
  int _layoutMaxChunk = -1;

  Timer? _pollTimer;
  int _lastScrollTs = 0;

  /// Set by [onJump] / [queueJumpFetch]; cleared at the end of the layout
  /// that dispatches [maybeDispatchJumpFetch].
  bool _jumpFetchPending = false;

  /// Cleared on [onAttach], set on [onDetach] — guards deferred
  /// post-layout dispatch from touching a stale data source.
  bool _dispatchDetached = false;

  /// Inclusive minimum chunk index of the last normal-mode layout pass.
  int get layoutMinChunk => _layoutMinChunk;

  /// Inclusive maximum chunk index of the last normal-mode layout pass.
  int get layoutMaxChunk => _layoutMaxChunk;

  /// Whether a jump navigation is waiting for the next layout to dispatch a
  /// direct fetch. Read by the render object to drop stale tiles before fan-out.
  bool get jumpFetchPending => _jumpFetchPending;

  /// Re-enable deferred dispatch after the viewport re-attaches.
  void onAttach() => _dispatchDetached = false;

  /// Cancel the poll timer and block deferred jump-fetch dispatch.
  void onDetach() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _dispatchDetached = true;
  }

  /// Cancel the poll timer. Called from render-object [dispose].
  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  /// Reset the laid-out chunk range when the data source is swapped.
  void resetLayoutRange() {
    _layoutMinChunk = 0;
    _layoutMaxChunk = -1;
  }

  /// Bump the scroll-activity timestamp used by the poll debounce.
  void markScrollActive() {
    _lastScrollTs = DateTime.now().millisecondsSinceEpoch;
  }

  /// Called from `_onJump` after a discrete navigation.
  ///
  /// Clears [_lastScrollTs] so the poll's same-window debounce passes.
  /// Crucially we do **not** cancel [_pollTimer] here even though it
  /// may be armed for the previous range: a continuous scrollbar drag
  /// fires `_onJump` once per `PointerMove`, and cancelling the
  /// newly-armed `Duration.zero` poll on every move guarantees the
  /// timer is never given a chance to drain before the next move
  /// arrives, so chunks at the new anchor never get fetched until the
  /// user lets go. Letting the timer keep ticking is fine: each
  /// [_onPollTick] reads the live [_layoutMinChunk]/[_layoutMaxChunk],
  /// so a poll armed during an old drag still requests the *current*
  /// range when it eventually fires.
  ///
  /// Also queues a direct fetch dispatch out of the next layout — see
  /// [maybeDispatchJumpFetch]. The poll timer path is still the primary
  /// mechanism; this is the safety net for animation-driven repaint
  /// cadences (selection-mode chrome, highlight fade, etc.) that would
  /// otherwise race with the timer.
  void onJump() {
    _lastScrollTs = 0;
    _jumpFetchPending = true;
  }

  /// Queue jump-fetch without clearing scroll timestamp (pre-mount tail seed).
  void queueJumpFetch() => _jumpFetchPending = true;

  /// End of a normal-mode layout: publish range, evict, poll, jump-fetch.
  void onLayoutComplete(int minChunk, int maxChunk) {
    _layoutMinChunk = minChunk;
    _layoutMaxChunk = maxChunk;
    evictChunks();
    scheduleFetchPoll();
    maybeDispatchJumpFetch();
  }

  /// End of overlay / empty layout — no visible chunks.
  ///
  /// Resets the laid-out range to empty (`min=0`, `max=-1`) before eviction.
  /// With `maxChunk == -1`, every chunk index ≥ 0 satisfies `index > maxChunk`,
  /// so all cached chunks are already classified as outside layout — pass 2
  /// cannot evict distinct in-range victims. No separate outside-only API is
  /// needed; behaviour matches the pre-extraction overlay path.
  void onLayoutCleared() {
    _layoutMinChunk = 0;
    _layoutMaxChunk = -1;
    evictChunks();
    scheduleFetchPoll();
  }

  /// LRU-evict data chunks until at most [ChatDataSource.maxChunks] remain.
  ///
  /// Pass 1 drops outside-layout chunks when already at the budget — a
  /// `jumpTo` can leave `length == maxChunks` with every entry outside the
  /// new range. While under budget, off-screen chunks are kept so a later
  /// `jumpTo` / scroll back can reuse cached data without a refetch. Pass 2
  /// drops the coldest in-range chunk when still over budget, never the
  /// anchor's chunk.
  void evictChunks() {
    final chunks = _dataSource.chunks;
    final maxChunks = _dataSource.maxChunks;
    final anchorChunk = _anchorChunkIndex();

    ChatScrollChunk? coldest({required bool outsideLayoutOnly}) {
      ChatScrollChunk? victim;
      for (final chunk in chunks.values) {
        if (chunk.index == anchorChunk) continue;
        final outside =
            chunk.index < _layoutMinChunk || chunk.index > _layoutMaxChunk;
        if (outsideLayoutOnly && !outside) continue;
        if (victim == null || chunk.lastAccessTick < victim.lastAccessTick) {
          victim = chunk;
        }
      }
      return victim;
    }

    if (chunks.length >= maxChunks) {
      while (true) {
        final victim = coldest(outsideLayoutOnly: true);
        if (victim == null) break;
        chunks.remove(victim.index);
      }
    }

    while (chunks.length > maxChunks) {
      final victim = coldest(outsideLayoutOnly: false);
      if (victim == null) break;
      chunks.remove(victim.index);
    }
  }

  /// Arms a one-shot timer when the laid-out range has chunks that still need
  /// fetching. The timer goes idle once every chunk in range is valid or
  /// in-flight, so there are no periodic wake-ups.
  ///
  /// Outside an active scroll the timer fires on the next microtask instead
  /// of waiting a full [_pollInterval] — initial load, jumpTo settle, and
  /// "new chunk arrived" don't need the scroll-debounce. The interval still
  /// applies while the user is actively scrolling, so a fast fling doesn't
  /// spam the network with every chunk that briefly enters the viewport.
  void scheduleFetchPoll() {
    if (_pollTimer != null || !_rangeHasPendingChunks()) return;
    final sinceScroll = DateTime.now().millisecondsSinceEpoch - _lastScrollTs;
    final delay = sinceScroll >= _pollInterval.inMilliseconds
        ? Duration.zero
        : _pollInterval;
    _pollTimer = Timer(delay, _onPollTick);
  }

  void _onPollTick() {
    _pollTimer = null;
    final now = DateTime.now().millisecondsSinceEpoch;
    // Skip the fetch while a scroll is still in flight (light debounce); the
    // re-arm below keeps re-checking until it settles.
    if (now - _lastScrollTs >= _pollInterval.inMilliseconds &&
        _layoutMaxChunk >= _layoutMinChunk) {
      _requestRange(_layoutMinChunk, _layoutMaxChunk);
    }
    // Keep polling until everything in range has loaded, then go idle.
    scheduleFetchPoll();
  }

  /// Whether the laid-out chunk range has any missing or dirty chunk that is
  /// not already being fetched.
  ///
  /// Errored chunks are excluded — they are retried by [ChatDataSource]'s
  /// backoff timer and [ChatDataSource.retryChunk], not by this poll loop.
  /// Treating `error` as pending with [Duration.zero] poll delays spins
  /// forever once layout becomes cheap (a single chunk-error tile).
  bool _rangeHasPendingChunks() {
    if (_layoutMaxChunk < _layoutMinChunk) return false;
    for (var ci = _layoutMinChunk; ci <= _layoutMaxChunk; ci++) {
      final chunk = _dataSource.chunks[ci];
      if (chunk == null) return true;
      final status = chunk.status;
      if (status.isFetching) continue;
      if (status.isDirty) return true;
    }
    return false;
  }

  /// Dispatched from [onLayoutComplete] when [_jumpFetchPending] is set.
  ///
  /// The call into [_requestRange] cannot be made synchronously from within
  /// `performLayout`: it transitively fires `notifyDataChanged` →
  /// `markNeedsLayout`, which throws the "RenderObject mutated in its own
  /// performLayout" assert. Deferring to the next frame boundary is enough.
  ///
  /// **Post-frame-only dispatch:** Previously used both
  /// `scheduleMicrotask` and `addPostFrameCallback` under heavy frame churn.
  /// This extraction consolidates to a single `addPostFrameCallback` that
  /// reads the freshest [_layoutMinChunk]/[_layoutMaxChunk]. Reinstate a
  /// microtask belt only if a documented race reproduces.
  void maybeDispatchJumpFetch() {
    if (!_jumpFetchPending) return;
    _jumpFetchPending = false;
    if (_layoutMaxChunk < _layoutMinChunk) return;
    if (_dispatchDetached) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_dispatchDetached) return;
      if (_layoutMaxChunk < _layoutMinChunk) return;
      _requestRange(_layoutMinChunk, _layoutMaxChunk);
    });
  }
}
