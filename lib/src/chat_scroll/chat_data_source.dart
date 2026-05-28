import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import 'package:chatscrollview/src/chat_scroll/chat_scroll_chunk.dart';
import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:meta/meta.dart';

/// Data source for [ChatScrollView].
///
/// Owns message data (chunks) and the fetch contract.
/// Uses typed listeners instead of [ChangeNotifier] —
/// subscribers know exactly what event occurred.
abstract class ChatDataSource {
  // --- Fetch contract (subclass implements) ---

  /// Fetch messages by ID range or timestamp.
  /// `from` and `to` are inclusive message IDs, where `from <= to`.
  /// `after` used for time-based pagination,
  /// fetching only updated messages after the given timestamp.
  /// If nothing is provided, fetch should return the most recent messages to
  /// determine the initial scroll position.
  Future<List<IChatMessage>> fetch({int? from, int? to, DateTime? after});

  /// Maximum number of chunks to keep in memory.
  /// Override to control the memory/re-fetch tradeoff.
  /// Default 16 ≈ 1024 messages.
  int get maxChunks => 16;

  // --- Chunk storage ---

  final Map<int, ChatScrollChunk> _chunks = HashMap<int, ChatScrollChunk>();

  /// Direct access to chunks for the viewport.
  @internal
  Map<int, ChatScrollChunk> get chunks => _chunks;

  /// Get a message by ID from the chunk cache.
  IChatMessage? getMessage(int messageId) {
    final chunkIndex = ChatScrollChunk.chunkOf(messageId);
    final chunk = _chunks[chunkIndex];
    if (chunk == null) return null;
    final slot = messageId - chunk.firstId;
    assert(
      slot >= 0 && slot < ChatScrollChunk.kSize,
      'Chunk $chunkIndex stored at the wrong index for id $messageId: '
      'firstId=${chunk.firstId} → slot=$slot out of [0..${ChatScrollChunk.kSize})',
    );
    return chunk.messages[slot];
  }

  /// Upsert a message into the chunk cache.
  /// Creates the chunk if it does not exist yet.
  void upsertMessage(IChatMessage message) {
    final chunkIndex = ChatScrollChunk.chunkOf(message.id);
    final chunk = _chunks.putIfAbsent(
      chunkIndex,
      () => ChatScrollChunk(index: chunkIndex),
    );
    chunk.messages[message.id - chunk.firstId] = message;
    notifyDataChanged();
  }

  /// Upsert multiple messages into the chunk cache.
  void upsertMessages(Iterable<IChatMessage> messages) {
    var changed = false;
    for (final message in messages) {
      final chunkIndex = ChatScrollChunk.chunkOf(message.id);
      final chunk = _chunks.putIfAbsent(
        chunkIndex,
        () => ChatScrollChunk(index: chunkIndex),
      );
      chunk.messages[message.id - chunk.firstId] = message;
      changed = true;
    }
    if (changed) notifyDataChanged();
  }

  // --- Range fetch orchestration ---

  static final math.Random _rnd = math.Random();
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
  final Set<int> _fetchingChunks = <int>{};

  /// Whether [chunk] should be (re-)fetched. Missing, dirty, or errored
  /// chunks are eligible; already-fetching and clean chunks are not. Without
  /// the `error` branch a chunk that failed while neighbouring a valid one
  /// would stay errored forever — `requestChunks` would not see it as dirty.
  static bool _needsFetch(ChatScrollChunk? chunk) {
    if (chunk == null) return true;
    final status = chunk.status;
    if (status.isFetching) return false;
    return status.isDirty || status.isError;
  }

  /// Check visible chunk range and fetch missing/dirty data.
  /// Called from the viewport's periodic poll timer.
  @internal
  void requestChunks(int layoutMinChunk, int layoutMaxChunk) {
    // Find the actual range that needs fetching.
    var needsMin = -1;
    var needsMax = -1;
    for (var ci = layoutMinChunk; ci <= layoutMaxChunk; ci++) {
      if (_needsFetch(_chunks[ci])) {
        if (needsMin < 0) needsMin = ci;
        needsMax = ci;
      }
    }
    if (needsMin < 0) return; // all chunks valid

    // Same range already fetching — wait for it.
    if (_fetchToken != null &&
        _fetchingMinChunk == needsMin &&
        _fetchingMaxChunk == needsMax) {
      return;
    }

    // New range — cancel old request and start fresh.
    _cancelFetch();
    _fetchingMinChunk = needsMin;
    _fetchingMaxChunk = needsMax;
    _fetchRetryStep = 0;
    _executeFetch();
  }

  /// Cancel any in-flight fetch and retry timer.
  @internal
  void cancelFetch() => _cancelFetch();

  void _cancelFetch() {
    // Clear the `fetching` flag from chunks that were part of the in-flight
    // range so they don't get stuck in an indeterminate state.
    var changed = false;
    if (_fetchingChunks.isNotEmpty) {
      for (final ci in _fetchingChunks) {
        final chunk = _chunks[ci];
        if (chunk == null) continue;
        chunk.status = chunk.status.remove(ChatMessageStatus.fetching);
        changed = true;
      }
      _fetchingChunks.clear();
    }
    _fetchToken = null;
    _fetchingMinChunk = 0;
    _fetchingMaxChunk = -1;
    _retryTimer?.cancel();
    _retryTimer = null;
    // Listeners (the viewport, debug overlays) need to know the fetching
    // flag dropped — a chunk stuck in `fetching` after detach / source-swap
    // would render an indefinite shimmer.
    if (changed) notifyDataChanged();
  }

  void _executeFetch() {
    final token = Object();
    _fetchToken = token;

    // Pre-create only the chunks that actually need loading and mark them
    // `fetching`. Valid chunks in the middle of the bounding range stay
    // valid — they piggyback on the request but their status is not touched
    // by success or failure of the fetch.
    _fetchingChunks.clear();
    for (var ci = _fetchingMinChunk; ci <= _fetchingMaxChunk; ci++) {
      final existing = _chunks[ci];
      if (existing != null && !_needsFetch(existing)) continue;
      final chunk = existing ??
          (_chunks[ci] = ChatScrollChunk(index: ci));
      chunk.status = chunk.status
          .remove(ChatMessageStatus.error)
          .add(ChatMessageStatus.fetching);
      _fetchingChunks.add(ci);
    }
    notifyDataChanged();

    final fromId = ChatScrollChunk.firstIdOf(_fetchingMinChunk);
    final toId =
        ChatScrollChunk.firstIdOf(_fetchingMaxChunk) +
        ChatScrollChunk.kSize -
        1;

    fetch(from: fromId, to: toId).then(
      (messages) {
        if (_fetchToken != token) return; // cancelled or replaced
        _fetchToken = null;

        // Upsert and mark chunks valid.
        for (final msg in messages) {
          final ci = ChatScrollChunk.chunkOf(msg.id);
          final chunk = _chunks.putIfAbsent(
            ci,
            () => ChatScrollChunk(index: ci),
          );
          chunk.messages[msg.id - chunk.firstId] = msg;
        }
        for (final ci in _fetchingChunks) {
          _chunks[ci]?.status = ChatMessageStatus.valid;
        }
        _fetchingChunks.clear();
        notifyDataChanged();
      },
      onError: (Object _) {
        if (_fetchToken != token) return; // cancelled or replaced
        _fetchToken = null;

        // Clear fetching, mark error so UI can react. Touch only the chunks
        // we actually requested — neighbouring valid chunks must not flip
        // to error.
        for (final ci in _fetchingChunks) {
          final chunk = _chunks[ci];
          if (chunk == null) continue;
          chunk.status = chunk.status
              .remove(ChatMessageStatus.fetching)
              .add(ChatMessageStatus.error);
        }
        _fetchingChunks.clear();
        notifyDataChanged();

        // Retry with backoff.
        final delay = _nextDelay(_fetchRetryStep, 500, 30000);
        _fetchRetryStep++;
        _retryTimer = Timer(delay, _executeFetch);
      },
    );
  }

  static Duration _nextDelay(int step, int minDelay, int maxDelay) {
    if (minDelay >= maxDelay) return Duration(milliseconds: maxDelay);
    final val = math.min(maxDelay, minDelay * math.pow(2, step.clamp(0, 31)));
    // `nextInt(0)` would throw; clamp the jitter window to at least 1ms so a
    // misconfigured `minDelay=0` stays well-defined.
    final window = math.max(1, val.toInt());
    final interval = _rnd.nextInt(window);
    return Duration(milliseconds: (minDelay + interval).clamp(0, maxDelay));
  }

  // --- Typed listener: data changed ---

  final _dataListeners = <VoidCallback>[];

  /// Subscribe to data changes.
  void addDataListener(VoidCallback callback) => _dataListeners.add(callback);

  /// Unsubscribe from data changes.
  void removeDataListener(VoidCallback callback) =>
      _dataListeners.remove(callback);

  /// Notify all listeners that message data has changed.
  ///
  /// Iterates over a snapshot to remain safe if a listener adds or removes
  /// listeners (including itself) during dispatch.
  @protected
  void notifyDataChanged() {
    for (final cb in List<VoidCallback>.of(_dataListeners, growable: false)) {
      cb();
    }
  }

  /// Cancel any in-flight fetch / retry timer and drop all listeners. Call
  /// from the owning widget's `dispose` so the retry timer cannot resurrect
  /// network work after the viewport is gone.
  void dispose() {
    _cancelFetch();
    _dataListeners.clear();
  }
}
