import 'dart:async';
import 'dart:developer' as dev;
import 'dart:math' as math;

import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_chunk.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:flutter/foundation.dart';

/// Range-fetch state machine for [ChatDataSource].
///
/// Owns in-flight token, exponential-backoff retry timer, and the subset of
/// chunk indices marked `fetching`. [ChatDataSource] delegates
/// `requestChunks`, `cancelFetch`, and the fetch half of `retryChunk` /
/// `invalidate` here so backoff and token invalidation can be unit-tested
/// without subclassing the data source.
class ChatRangeFetch {
  /// Creates a fetch coordinator bound to [chunks] and [fetchRange].
  ChatRangeFetch({
    required Map<int, ChatScrollChunk> Function() chunks,
    required Future<List<IChatMessage>> Function({
      required int fromId,
      required int toId,
    })
    fetchRange,
    required VoidCallback notifyDataChanged,
    required bool Function() isDisposed,
    int? Function()? unconfirmedTailThroughId,
    void Function(int? maxReturnedId)? onFetchSuccess,
    bool Function(int id)? skipFetchUpsert,
  }) : _chunks = chunks,
       _fetchRange = fetchRange,
       _notifyDataChanged = notifyDataChanged,
       _isDisposed = isDisposed,
       _unconfirmedTailThroughId = unconfirmedTailThroughId,
       _onFetchSuccess = onFetchSuccess,
       _skipFetchUpsert = skipFetchUpsert;

  static final math.Random _rnd = math.Random();

  final Map<int, ChatScrollChunk> Function() _chunks;
  final Future<List<IChatMessage>> Function({
    required int fromId,
    required int toId,
  })
  _fetchRange;
  final VoidCallback _notifyDataChanged;
  final bool Function() _isDisposed;
  final int? Function()? _unconfirmedTailThroughId;
  final void Function(int? maxReturnedId)? _onFetchSuccess;
  final bool Function(int id)? _skipFetchUpsert;

  Object? _fetchToken;
  int _fetchRetryStep = 0;
  Timer? _retryTimer;
  int _fetchingMinChunk = 0;
  int _fetchingMaxChunk = -1;

  /// Chunk indices touched by the in-flight fetch — the subset of
  /// `[_fetchingMinChunk, _fetchingMaxChunk]` that actually needed loading.
  /// On resolution / cancellation only these chunks have their status
  /// updated; already-valid neighbours inside the bounding range are left
  /// alone so a transient failure on one chunk does not flicker a sibling
  /// from valid → error.
  final Set<int> fetchingChunks = <int>{};

  /// Whether [chunkIndex] lies inside the bounding range of an in-flight
  /// fetch (token armed, not merely a pending retry timer).
  bool coversChunkInFlight(int chunkIndex) =>
      _fetchToken != null &&
      chunkIndex >= _fetchingMinChunk &&
      chunkIndex <= _fetchingMaxChunk;

  /// Reset source-wide backoff — called from [ChatDataSource.invalidate].
  void resetRetryStep() => _fetchRetryStep = 0;

  /// Cancel retry timer. Called from [ChatDataSource.dispose].
  void dispose() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  /// Whether [chunk] should be (re-)fetched. Missing, dirty, or errored
  /// chunks are eligible; already-fetching and clean chunks are not. Without
  /// the `error` branch a chunk that failed while neighbouring a valid one
  /// would stay errored forever — `requestChunks` would not see it as dirty.
  @visibleForTesting
  static bool needsFetch(ChatScrollChunk? chunk) {
    if (chunk == null) return true;
    final status = chunk.status;
    if (status.isFetching) return false;
    return status.isDirty || status.isError;
  }

  /// Check visible chunk range and fetch missing/dirty data.
  void requestChunks(int layoutMinChunk, int layoutMaxChunk) {
    if (_isDisposed()) return;
    final chunks = _chunks();
    // Find the actual range that needs fetching.
    var needsMin = -1;
    for (var ci = layoutMinChunk; ci <= layoutMaxChunk; ci++) {
      if (needsFetch(chunks[ci])) {
        if (needsMin < 0) needsMin = ci;
      }
    }
    if (needsMin < 0) return; // all chunks valid

    // Bound the network request to the *laid-out* span, not the dirty subset.
    // Using needsMin..needsMax alone caused a scrollbar cancel storm:
    //   request 96..97 → both fetching → next poll "needs" only the still-dirty
    //   edge → cancel wider flight (dirtying the sibling) → flip forever under
    //   Duration.zero poll. Valid siblings inside the layout span are skipped
    //   when marking `fetching` in [_executeFetch].
    final fetchMin = layoutMinChunk;
    final fetchMax = layoutMaxChunk;

    // An in-flight (or retry-armed) fetch that overlaps the layout span must
    // not be cancelled for a shrink. Treat a pending retry timer as in-flight
    // too so poll does not defeat exponential backoff.
    final live = _fetchToken != null || _retryTimer != null;
    if (live) {
      final overlaps =
          fetchMin <= _fetchingMaxChunk && fetchMax >= _fetchingMinChunk;
      if (overlaps) {
        if (fetchMin < _fetchingMinChunk || fetchMax > _fetchingMaxChunk) {
          // Layout grew past the live span — widen once to the union.
          final unionMin = math.min(fetchMin, _fetchingMinChunk);
          final unionMax = math.max(fetchMax, _fetchingMaxChunk);
          cancelFetch();
          _fetchingMinChunk = unionMin;
          _fetchingMaxChunk = unionMax;
          _fetchRetryStep = 0;
          _executeFetch();
          return;
        }
        // Equal or subset — wait for the live request / retry.
        if (_fetchToken != null) {
          _rematerializeInFlightChunks(_fetchingMinChunk, _fetchingMaxChunk);
        }
        return;
      }
    }

    // Disjoint (or idle) — cancel any old request and start fresh.
    cancelFetch();
    _fetchingMinChunk = fetchMin;
    _fetchingMaxChunk = fetchMax;
    _fetchRetryStep = 0;
    _executeFetch();
  }

  /// Restore chunk map entries covered by the live token after mid-flight
  /// eviction so callers observing [needsFetch]/pending stay consistent.
  void _rematerializeInFlightChunks(int needsMin, int needsMax) {
    final chunks = _chunks();
    var changed = false;
    for (var ci = needsMin; ci <= needsMax; ci++) {
      final existing = chunks[ci];
      if (existing != null && !needsFetch(existing)) continue;
      final chunk = existing ?? (chunks[ci] = ChatScrollChunk(index: ci));
      if (chunk.status.isFetching) {
        fetchingChunks.add(ci);
        continue;
      }
      chunk.status = chunk.status
          .remove(ChatMessageStatus.error)
          .add(ChatMessageStatus.fetching);
      fetchingChunks.add(ci);
      changed = true;
    }
    if (changed) _notifyDataChanged();
  }

  /// Start a fetch for the inclusive chunk range [minChunk..maxChunk].
  void startFetchRange(int minChunk, int maxChunk) {
    if (_isDisposed()) return;
    cancelFetch();
    _fetchRetryStep = 0;
    _fetchingMinChunk = minChunk;
    _fetchingMaxChunk = maxChunk;
    _executeFetch();
  }

  /// Cancel any in-flight fetch and retry timer; notify listeners when chunk
  /// status flags change.
  void cancelFetch() {
    if (_isDisposed()) return;
    final changed = cancelFetchSilent();
    // Listeners (the viewport, debug overlays) need to know the fetching
    // flag dropped — a chunk stuck in `fetching` after detach / source-swap
    // would render an indefinite shimmer.
    if (changed) _notifyDataChanged();
  }

  /// Like [cancelFetch] but does not notify — returns whether any chunk
  /// status flag changed so the caller can fold the notification into its
  /// own pass (the `invalidate` path coalesces it with subsequent dirty
  /// marks).
  bool cancelFetchSilent() {
    final chunks = _chunks();
    var changed = false;
    if (fetchingChunks.isNotEmpty) {
      for (final ci in fetchingChunks) {
        final chunk = chunks[ci];
        if (chunk == null) continue;
        // Re-mark as dirty: a cancelled fetch leaves us without valid data
        // for this chunk. Without `dirty`, an `error`-only chunk that we
        // were retrying would land back on status `0` (= valid) while
        // `lastError`/`failedAttempts` still describe the prior failure —
        // any consumer reading `status.isValid && lastError != null` would
        // render a stale error on a "healthy" chunk.
        chunk.status = chunk.status
            .remove(ChatMessageStatus.fetching)
            .add(ChatMessageStatus.dirty);
        changed = true;
      }
      fetchingChunks.clear();
    }
    _fetchToken = null;
    _fetchingMinChunk = 0;
    _fetchingMaxChunk = -1;
    _retryTimer?.cancel();
    _retryTimer = null;
    return changed;
  }

  void _executeFetch() {
    if (_isDisposed()) return;
    // Sentinel guard: if the caller dispatched without having set the range
    // (or a reentrant cancel zeroed it), bail rather than emit a bogus
    // `fetchRange(0, -1+kSize-1)` to the subclass.
    if (_fetchingMaxChunk < _fetchingMinChunk) return;

    final chunks = _chunks();
    final token = Object();
    _fetchToken = token;
    // Compute the network range before notifying listeners — a synchronous
    // listener that calls `cancelFetch()` / `invalidate()` resets the range,
    // and we must not dispatch a request derived from the post-cancel state.
    final fromId = ChatScrollChunk.firstIdOf(_fetchingMinChunk);
    final toId =
        ChatScrollChunk.firstIdOf(_fetchingMaxChunk) +
        ChatScrollChunk.kSize -
        1;

    // Pre-create only the chunks that actually need loading and mark them
    // `fetching`. Valid chunks in the middle of the bounding range stay
    // valid — they piggyback on the request but their status is not touched
    // by success or failure of the fetch.
    fetchingChunks.clear();
    for (var ci = _fetchingMinChunk; ci <= _fetchingMaxChunk; ci++) {
      final existing = chunks[ci];
      if (existing != null && !needsFetch(existing)) continue;
      final chunk = existing ?? (chunks[ci] = ChatScrollChunk(index: ci));
      chunk.status = chunk.status
          .remove(ChatMessageStatus.error)
          .add(ChatMessageStatus.fetching);
      fetchingChunks.add(ci);
    }
    _notifyDataChanged();
    // Listener may have cancelled us reentrantly. Bail before dispatching to
    // the subclass — the cancel already cleared `fetchingChunks` and reset
    // `_fetchToken` to null.
    if (_fetchToken != token) return;

    // Subclasses are expected to return a Future, but a misbehaving
    // implementation that throws synchronously before producing one would
    // otherwise bubble the throw up into the viewport's layout poll. Wrap
    // it into a rejected Future so the normal error path runs.
    Future<List<IChatMessage>> request;
    try {
      request = _fetchRange(fromId: fromId, toId: toId);
    } catch (error) {
      request = Future<List<IChatMessage>>.error(error);
    }

    assert(
      ChatScrollChunk.isFullChunkRange(fromId, toId),
      'fetchRange boundary invariant violated for range [$fromId, $toId]. '
      'fromId must equal ChatScrollChunk.firstIdOf(chunkOf(fromId)) and toId '
      'must equal the last id of chunkOf(toId). Partial-range fetches corrupt '
      'absent-slot marking. See fetchRange doc and ChatScrollChunk.isFullChunkRange.',
    );

    request.then(
      (messages) {
        if (_fetchToken != token) return; // cancelled or replaced
        _fetchToken = null;

        final chunks = _chunks();
        // Upsert returned messages into their slots. Skip ids the integrator
        // removed locally — static/refetch sources may still return them.
        for (final msg in messages) {
          assert(
            msg.id >= fromId && msg.id <= toId,
            'fetchRange returned message id ${msg.id} outside the requested '
            'range [$fromId, $toId]. Subclasses must only return messages '
            'whose ids fall within the requested chunk-aligned range.',
          );
          if (_skipFetchUpsert?.call(msg.id) ?? false) continue;
          final ci = ChatScrollChunk.chunkOf(msg.id);
          final chunk = chunks.putIfAbsent(
            ci,
            () => ChatScrollChunk(index: ci),
          );
          chunk.messages[msg.id - chunk.firstId] = msg;
        }

        // Absent-marking pass: for every fetched chunk, mark null slots that
        // the server had a chance to fill as permanently absent.
        //
        // The full-chunk boundary invariant (fromId aligned to a chunk
        // boundary) guarantees the server was given the opportunity to return
        // every ID in [fromId, toId]. Any null slot was not returned and
        // therefore does not exist — except for the unconfirmed live tail
        // past the highest returned id (recent inserts whose refetch may still
        // be stale). Those stay unloaded so scroll-to-newest can refill.
        //
        // `upsertMessage` / `upsertMessages` call `clearAbsentSlot` when
        // writing a slot, so a realtime insert at a previously-absent ID
        // surfaces immediately without requiring `invalidate()`.
        final maxReturned = messages.isEmpty
            ? null
            : messages.map((m) => m.id).reduce(math.max);
        final unconfirmedThrough = _unconfirmedTailThroughId?.call();
        for (final ci in fetchingChunks) {
          final chunk = chunks[ci];
          if (chunk == null) continue;
          for (var slot = 0; slot < ChatScrollChunk.kSize; slot++) {
            if (chunk.messages[slot] != null) continue;
            final id = chunk.firstId + slot;
            if (id < fromId || id > toId) continue;
            if (unconfirmedThrough != null &&
                maxReturned != null &&
                id > maxReturned &&
                id <= unconfirmedThrough) {
              continue;
            }
            if (unconfirmedThrough != null &&
                maxReturned == null &&
                id <= unconfirmedThrough) {
              continue;
            }
            chunk.markAbsentSlot(slot);
          }
        }
        _onFetchSuccess?.call(maxReturned);

        for (final ci in fetchingChunks) {
          final chunk = chunks[ci];
          if (chunk == null) continue;
          chunk
            ..status = ChatMessageStatus.valid
            ..lastError = null
            ..failedAttempts = 0;
        }
        fetchingChunks.clear();
        _notifyDataChanged();
      },
      onError: (Object error, StackTrace stackTrace) {
        dev.log(
          'fetchRange error, range: (fromId: $fromId, toId: $toId)',
          error: error,
          stackTrace: stackTrace,
        );
        if (_fetchToken != token) return; // cancelled or replaced
        _fetchToken = null;

        final chunks = _chunks();
        // Clear fetching, mark error so UI can react. Touch only the chunks
        // we actually requested — neighbouring valid chunks must not flip
        // to error.
        for (final ci in fetchingChunks) {
          final chunk = chunks[ci];
          if (chunk == null) continue;
          chunk
            ..lastError = error
            ..failedAttempts += 1
            ..status = chunk.status
                .remove(ChatMessageStatus.fetching)
                .add(ChatMessageStatus.error);
        }
        fetchingChunks.clear();
        _notifyDataChanged();

        // Retry with backoff.
        final delay = nextRetryDelay(_fetchRetryStep);
        _fetchRetryStep++;
        _retryTimer = Timer(delay, _executeFetch);
      },
    );
  }

  /// Exponential backoff with jitter for fetch retries.
  @visibleForTesting
  static Duration nextRetryDelay(
    int step, {
    int minDelay = 500,
    int maxDelay = 30000,
    math.Random? random,
  }) {
    if (minDelay >= maxDelay) return Duration(milliseconds: maxDelay);
    final val = math.min(maxDelay, minDelay * math.pow(2, step.clamp(0, 31)));
    // `nextInt(0)` would throw; clamp the jitter window to at least 1ms so a
    // misconfigured `minDelay=0` stays well-defined.
    final window = math.max(1, val.toInt());
    final rnd = random ?? _rnd;
    final interval = rnd.nextInt(window);
    return Duration(milliseconds: (minDelay + interval).clamp(0, maxDelay));
  }
}
