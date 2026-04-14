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
    return chunk.messages[messageId - chunk.firstId];
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

  /// Check visible chunk range and fetch missing/dirty data.
  /// Called from the viewport's periodic poll timer.
  @internal
  void requestChunks(int layoutMinChunk, int layoutMaxChunk) {
    // Find the actual range that needs fetching.
    var needsMin = -1;
    var needsMax = -1;
    for (var ci = layoutMinChunk; ci <= layoutMaxChunk; ci++) {
      final chunk = _chunks[ci];
      if (chunk == null || chunk.status.isDirty) {
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
    _fetchToken = null;
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  void _executeFetch() {
    final token = Object();
    _fetchToken = token;

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
        for (var ci = _fetchingMinChunk; ci <= _fetchingMaxChunk; ci++) {
          _chunks[ci]?.status = ChatMessageStatus.valid;
        }
        notifyDataChanged();
      },
      onError: (Object _) {
        if (_fetchToken != token) return; // cancelled or replaced
        _fetchToken = null;

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
    final interval = _rnd.nextInt(val.toInt());
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
  @protected
  void notifyDataChanged() {
    for (final cb in _dataListeners) {
      cb();
    }
  }
}
