import 'dart:async';
import 'dart:math' as math;

import 'package:chat_scroll_view/src/chat_scroll/chat_data_source.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_chunk.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_dev_log.dart';
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

  /// Filter console by `ChatScrollFetchSched`.
  final ChatScrollDevLog log = ChatScrollDevLog(
    'ChatScrollFetchSched',
    enabled: false,
  );

  /// Dedupes identical diagnostic lines so a zero-delay poll storm stays readable.
  String? _lastLogSignature;
  int _logRepeatCount = 0;

  int _layoutMinChunk = 0;
  int _layoutMaxChunk = -1;

  Timer? _pollTimer;
  int _lastScrollTs = 0;

  /// Set by [onJump] / [queueJumpFetch]; cleared at the end of the layout
  /// that dispatches [maybeDispatchJumpFetch].
  bool _jumpFetchPending = false;

  /// While set, fetch prioritizes an around-target destination window for the
  /// navigation load-gate (not a contiguous gap fill from the laid-out range).
  int? _navigationDestChunk;

  /// Half-width of the load-gate destination window in chunks (target ± radius).
  static const int destinationWindowRadiusChunks = 1;

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

  /// Chunk index of the load-gate destination, if any.
  int? get navigationDestinationChunk => _navigationDestChunk;

  /// Pin fetch priority to an around-[messageId] destination window for the
  /// navigation load-gate. Pass `null` to clear.
  ///
  /// Requests only that window (target chunk ± [destinationWindowRadiusChunks])
  /// — never expands into a contiguous fill from the current layout range to
  /// the target.
  void setNavigationDestinationId(int? messageId) {
    final next = messageId == null ? null : ChatScrollChunk.chunkOf(messageId);
    if (_navigationDestChunk == next) {
      if (next != null) {
        log.event('dest.pin.reassert', {
          'dest': next,
          'id': messageId,
          'layout': '$_layoutMinChunk..$_layoutMaxChunk',
        });
        // Keep the pin; do not queue another dest fetch. Callers that used to
        // reassert every load-gate layout frame caused a cancel/restart storm.
      }
      return;
    }
    log.event('dest.pin', {
      'from': _navigationDestChunk,
      'to': next,
      'id': messageId,
      'layout': '$_layoutMinChunk..$_layoutMaxChunk',
    });
    _navigationDestChunk = next;
    if (next != null) {
      _lastScrollTs = 0;
      _queueDestinationWindowFetch();
      scheduleFetchPoll();
    }
  }

  /// Clears [setNavigationDestinationId].
  void clearNavigationDestination() => setNavigationDestinationId(null);

  /// Whether [messageId]'s chunk lies outside the pinned destination window.
  ///
  /// Used by jump handlers (scrollbar) to drop an orphan / abandoned load-gate
  /// pin so fetch returns to the laid-out band.
  bool isOutsideNavigationDestination(int messageId) {
    final dest = _navigationDestChunk;
    if (dest == null) return false;
    final range = _clampedDestinationWindow(dest);
    final chunk = ChatScrollChunk.chunkOf(messageId);
    return chunk < range.$1 || chunk > range.$2;
  }

  void _queueDestinationWindowFetch() {
    final dest = _navigationDestChunk;
    if (dest == null || _dispatchDetached) return;
    log.event('dest.queue', {
      'dest': dest,
      'layout': '$_layoutMinChunk..$_layoutMaxChunk',
    });
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_dispatchDetached || _navigationDestChunk != dest) {
        log.event('dest.queue.skip', {
          'dest': dest,
          'liveDest': _navigationDestChunk,
          'detached': _dispatchDetached,
        });
        return;
      }
      _requestDestinationWindow(dest);
    });
  }

  void _logRequest(String via, int minChunk, int maxChunk) {
    _schedEvent('request', {
      'via': via,
      'range': '$minChunk..$maxChunk',
      'dest': _navigationDestChunk,
      'layout': '$_layoutMinChunk..$_layoutMaxChunk',
      'pending': _chunkRangeHasPending(minChunk, maxChunk),
      'inFlight': _dataSource.coversChunkInFlight(minChunk),
      'jumpPending': _jumpFetchPending,
    });
  }

  void _schedEvent(String tag, Map<String, Object?> fields) {
    if (!log.enabled) return;
    final signature =
        '$tag|${fields.entries.map((e) => '${e.key}=${e.value}').join(' ')}';
    if (signature == _lastLogSignature) {
      _logRepeatCount++;
      // Emit a heartbeat every 64 identical lines so storms are visible
      // without flooding the console.
      if (_logRepeatCount % 64 != 0) return;
      log.event('$tag.repeat', {...fields, 'x': _logRepeatCount});
      return;
    }
    if (_logRepeatCount > 0) {
      log.event('log.collapsed', {
        'prev': _lastLogSignature,
        'x': _logRepeatCount,
      });
    }
    _lastLogSignature = signature;
    _logRepeatCount = 0;
    log.event(tag, fields);
  }

  /// Inclusive chunk range for the load-gate window, clamped to known ids.
  ///
  /// Without clamping, `dest ± radius` can include indexes that never exist
  /// (e.g. chunk `-1` when targeting chunk 0). Those stay `null` forever and
  /// would keep [scheduleFetchPoll] armed on a zero-delay loop.
  (int, int) _clampedDestinationWindow(int destChunk) {
    var min = destChunk - destinationWindowRadiusChunks;
    var max = destChunk + destinationWindowRadiusChunks;
    final oldest = _dataSource.oldestKnownId;
    final newest = _dataSource.newestKnownId;
    if (oldest != null) {
      min = math.max(min, ChatScrollChunk.chunkOf(oldest));
    }
    if (newest != null) {
      max = math.min(max, ChatScrollChunk.chunkOf(newest));
    }
    if (max < min) {
      return (destChunk, destChunk);
    }
    return (min, max);
  }

  void _requestDestinationWindow(int destChunk) {
    final range = _clampedDestinationWindow(destChunk);
    _logRequest('destWindow', range.$1, range.$2);
    _requestRange(range.$1, range.$2);
  }

  /// `true` when laid-out chunks look like a stitch dual-strip: they overlap
  /// the destination window and extend far beyond it (outgoing + incoming).
  ///
  /// Used so jump-fetch / poll can keep requesting the on-screen layout band
  /// under a live dest pin (scrollbar) without contiguous-filling the gap
  /// during stitch flight.
  bool _layoutSpansStitchGap(int destChunk) {
    if (_layoutMaxChunk < _layoutMinChunk) return false;
    final range = _clampedDestinationWindow(destChunk);
    final overlapsDest =
        _layoutMinChunk <= range.$2 && _layoutMaxChunk >= range.$1;
    if (!overlapsDest) return false;
    final windowWidth = range.$2 - range.$1 + 1;
    final layoutWidth = _layoutMaxChunk - _layoutMinChunk + 1;
    return layoutWidth > windowWidth + 2;
  }

  bool _chunkRangeHasPending(int minChunk, int maxChunk) {
    for (var ci = minChunk; ci <= maxChunk; ci++) {
      // In-flight cover wins even if the map entry was evicted — otherwise
      // poll sees perpetual null pending and spins with Duration.zero.
      if (_dataSource.coversChunkInFlight(ci)) continue;
      final chunk = _dataSource.chunks[ci];
      if (chunk == null) return true;
      final status = chunk.status;
      if (status.isFetching) continue;
      if (status.isDirty) return true;
      // Valid chunks can still need a refill (insert after eviction, or a
      // stale absent tombstone on the live tail). Treat those as pending so
      // poll does not go idle with `pending=false` while load-gate waits.
      if (!status.isError && _dataSource.hasKnownSpanHoles(ci)) return true;
    }
    return false;
  }

  /// Missing/dirty chunks only — excludes hole-only refill on already-valid
  /// chunks (those use [_pollInterval] so incomplete tails cannot busy-spin).
  bool _chunkRangeHasUrgentPending(int minChunk, int maxChunk) {
    for (var ci = minChunk; ci <= maxChunk; ci++) {
      if (_dataSource.coversChunkInFlight(ci)) continue;
      final chunk = _dataSource.chunks[ci];
      if (chunk == null) return true;
      final status = chunk.status;
      if (status.isFetching) continue;
      if (status.isDirty) return true;
    }
    return false;
  }

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
    log.event('onJump', {
      'dest': _navigationDestChunk,
      'layout': '$_layoutMinChunk..$_layoutMaxChunk',
      'outsideDest': _navigationDestChunk == null
          ? null
          : isOutsideNavigationDestination(
              ChatScrollChunk.firstIdOf(_layoutMinChunk),
            ),
    });
  }

  /// Queue jump-fetch without clearing scroll timestamp (pre-mount tail seed).
  void queueJumpFetch() {
    _jumpFetchPending = true;
    log.event('queueJumpFetch', {
      'dest': _navigationDestChunk,
      'layout': '$_layoutMinChunk..$_layoutMaxChunk',
    });
  }

  /// End of a normal-mode layout: publish range, evict, poll, jump-fetch.
  void onLayoutComplete(int minChunk, int maxChunk) {
    _layoutMinChunk = minChunk;
    _layoutMaxChunk = maxChunk;
    _schedEvent('layout', {
      'layout': '$minChunk..$maxChunk',
      'dest': _navigationDestChunk,
      'jumpPending': _jumpFetchPending,
      'pending': _rangeHasPendingChunks(),
      'frame': log.bumpLayoutFrame(),
    });
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
  /// anchor's chunk. Load-gate destination-window chunks are also protected.
  void evictChunks() {
    final chunks = _dataSource.chunks;
    final maxChunks = _dataSource.maxChunks;
    final anchorChunk = _anchorChunkIndex();
    final dest = _navigationDestChunk;

    bool isProtected(int index) {
      if (index == anchorChunk) return true;
      // Never drop an in-flight fetch victim — eviction + same-range early
      // return left the poll with null pending forever.
      if (_dataSource.coversChunkInFlight(index)) return true;
      final chunk = chunks[index];
      if (chunk != null && chunk.status.isFetching) return true;
      if (dest == null) return false;
      final range = _clampedDestinationWindow(dest);
      return index >= range.$1 && index <= range.$2;
    }

    ChatScrollChunk? coldest({required bool outsideLayoutOnly}) {
      ChatScrollChunk? victim;
      for (final chunk in chunks.values) {
        if (isProtected(chunk.index)) continue;
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
    final urgent = _rangeHasUrgentPendingChunks();
    // Hole-only refill (valid chunk, missing known-span payloads) must not
    // arm Duration.zero — a stale partial tail would otherwise busy-spin.
    final delay = !urgent
        ? _pollInterval
        : (sinceScroll >= _pollInterval.inMilliseconds
              ? Duration.zero
              : _pollInterval);
    _pollTimer = Timer(delay, _onPollTick);
  }

  void _onPollTick() {
    _pollTimer = null;
    final now = DateTime.now().millisecondsSinceEpoch;
    final sinceScroll = now - _lastScrollTs;
    final scrollSettled = sinceScroll >= _pollInterval.inMilliseconds;
    // Skip the fetch while a scroll is still in flight (light debounce); the
    // re-arm below keeps re-checking until it settles.
    if (scrollSettled) {
      final dest = _navigationDestChunk;
      if (dest != null) {
        // Load-gate / stitch: one range only. Do not also request layout in
        // the same tick — [requestChunks] cancels in-flight work on range
        // change, which left on-screen tiles permanently unloaded.
        // Scrollbar jumps clear this pin via
        // [isOutsideNavigationDestination] / animate cancel.
        log.event('poll.tick', {
          'branch': 'dest',
          'dest': dest,
          'layout': '$_layoutMinChunk..$_layoutMaxChunk',
          'sinceScrollMs': sinceScroll,
          'stitchGap': _layoutSpansStitchGap(dest),
        });
        _requestDestinationWindow(dest);
      } else if (_layoutMaxChunk >= _layoutMinChunk) {
        _schedEvent('poll.tick', {
          'branch': 'layout',
          'layout': '$_layoutMinChunk..$_layoutMaxChunk',
          'sinceScrollMs': sinceScroll > 60000 ? 'idle' : sinceScroll,
          'pending': _rangeHasPendingChunks(),
        });
        _logRequest('poll', _layoutMinChunk, _layoutMaxChunk);
        _requestRange(_layoutMinChunk, _layoutMaxChunk);
      } else {
        log.event('poll.tick', {
          'branch': 'empty',
          'layout': '$_layoutMinChunk..$_layoutMaxChunk',
        });
      }
    } else {
      log.event('poll.debounce', {
        'sinceScrollMs': sinceScroll,
        'dest': _navigationDestChunk,
        'layout': '$_layoutMinChunk..$_layoutMaxChunk',
      });
    }
    // Keep polling until everything in range has loaded, then go idle.
    // Sparse-valid chunks (insert after eviction) are healed inside
    // [ChatDataSource.requestChunks] before needsFetch runs.
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
    final dest = _navigationDestChunk;
    if (dest != null) {
      final range = _clampedDestinationWindow(dest);
      return _chunkRangeHasPending(range.$1, range.$2);
    }
    if (_layoutMaxChunk < _layoutMinChunk) return false;
    return _chunkRangeHasPending(_layoutMinChunk, _layoutMaxChunk);
  }

  bool _rangeHasUrgentPendingChunks() {
    final dest = _navigationDestChunk;
    if (dest != null) {
      final range = _clampedDestinationWindow(dest);
      return _chunkRangeHasUrgentPending(range.$1, range.$2);
    }
    if (_layoutMaxChunk < _layoutMinChunk) return false;
    return _chunkRangeHasUrgentPending(_layoutMinChunk, _layoutMaxChunk);
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
    if (_dispatchDetached) return;
    log.event('jumpFetch.arm', {
      'dest': _navigationDestChunk,
      'layout': '$_layoutMinChunk..$_layoutMaxChunk',
    });
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_dispatchDetached) {
        log.event('jumpFetch.skip', {'reason': 'detached'});
        return;
      }
      final dest = _navigationDestChunk;
      if (dest != null) {
        if (_layoutSpansStitchGap(dest)) {
          // Stitch dual-strip: outgoing…incoming would gap-storm if we used
          // layout min…max. Keep the destination window only.
          log.event('jumpFetch.dispatch', {
            'branch': 'stitchGap→dest',
            'dest': dest,
            'layout': '$_layoutMinChunk..$_layoutMaxChunk',
          });
          _requestDestinationWindow(dest);
          return;
        }
        final range = _clampedDestinationWindow(dest);
        final layoutOverlapsDest =
            _layoutMaxChunk >= _layoutMinChunk &&
            _layoutMinChunk <= range.$2 &&
            _layoutMaxChunk >= range.$1;
        if (!layoutOverlapsDest) {
          // Load-gate still at origin (or empty layout): warm dest only.
          // Requesting origin layout here would cancel the dest fetch every
          // frame while poll re-requests dest.
          log.event('jumpFetch.dispatch', {
            'branch': 'noOverlap→dest',
            'dest': dest,
            'destWin': '${range.$1}..${range.$2}',
            'layout': '$_layoutMinChunk..$_layoutMaxChunk',
          });
          _requestDestinationWindow(dest);
          return;
        }
        // Layout already overlaps the dest window — fetch the on-screen band.
        log.event('jumpFetch.dispatch', {
          'branch': 'overlap→layout',
          'dest': dest,
          'destWin': '${range.$1}..${range.$2}',
          'layout': '$_layoutMinChunk..$_layoutMaxChunk',
        });
      }
      if (_layoutMaxChunk < _layoutMinChunk) {
        if (dest != null) {
          log.event('jumpFetch.dispatch', {
            'branch': 'emptyLayout→dest',
            'dest': dest,
          });
          _requestDestinationWindow(dest);
        } else {
          log.event('jumpFetch.dispatch', {'branch': 'emptyLayout→noop'});
        }
        return;
      }
      // Scrollbar / normal jump (pin cleared on jump-away) — laid-out band.
      if (dest == null) {
        log.event('jumpFetch.dispatch', {
          'branch': 'layout',
          'layout': '$_layoutMinChunk..$_layoutMaxChunk',
        });
      }
      _logRequest('jumpFetch', _layoutMinChunk, _layoutMaxChunk);
      _requestRange(_layoutMinChunk, _layoutMaxChunk);
    });
  }
}
