import 'package:chatscrollview/src/chat_scroll/chat_scroll_common.dart';
import 'package:meta/meta.dart';

/// Chunk of chat messages used for pagination and eviction.
///
/// Holds message data in a fixed-size array. The chunk index is the message id
/// shifted right by [kBits].
@internal
class ChatScrollChunk {

  ChatScrollChunk({required this.index})
    : messages = List<IChatMessage?>.filled(kSize, null, growable: false),
      firstId = firstIdOf(index);
  static const int kBits = 6;
  static const int kSize = 64; // 1 << kBits

  /// Get the chunk index for a given message id.
  /// Dart's `>>` is arithmetic shift — works correctly for negative IDs.
  static int chunkOf(int messageId) => messageId >> kBits;

  /// Get the first message id for a given chunk index.
  static int firstIdOf(int chunkIndex) => chunkIndex << kBits;

  /// The chunk index, calculated as messageId >> kBits.
  /// Can be negative for messages with negative IDs.
  final int index;

  /// The first message id in this chunk (inclusive).
  final int firstId;

  /// The last message id in this chunk (inclusive).
  int get lastId => firstId + kSize - 1;

  /// Message data — populated from fetch results.
  final List<IChatMessage?> messages;

  /// Data status (dirty, fetching, error, valid).
  ChatMessageStatus status = ChatMessageStatus.dirty;

  /// Monotonic access tick — bumped on layout to track LRU order.
  int lastAccessTick = 0;

  /// Last error thrown by a fetch of this chunk, or `null` when the chunk
  /// has never failed (or recovered to `valid`). Cleared on success.
  Object? lastError;

  /// Count of failed fetches for this chunk since the last success. Reset to
  /// 0 on a successful fetch. Includes both auto-retries (backoff timer)
  /// and user-driven retries — what the UI typically wants to show.
  int failedAttempts = 0;

  // ---------------------------------------------------------------------------
  // Absent-slot bitmask
  //
  // Each bit N tracks whether slot N (= `firstId + N`) is permanently absent —
  // i.e. the server confirmed that message ID does not exist in this
  // conversation (e.g. batch-deleted messages, or an empty fetch for IDs in a
  // deletion gap).
  //
  // Invariants:
  //   - Bit N is set iff `messages[N] == null` AND server confirmed absent.
  //   - Absent and present are disjoint: a non-null slot MUST NOT have its bit
  //     set (asserted in `markAbsentSlot`).
  //   - `clearAbsentSlot` MUST be called by `upsertMessage` / `upsertMessages`
  //     when writing a slot, so a realtime insert at an absent slot surfaces
  //     immediately without `invalidate()`.
  //   - `clearAbsentMask()` MUST be called when the chunk is invalidated so
  //     a re-fetch always starts with a clean slate.
  //
  // Implementation note: Dart `int` is 64-bit signed on 64-bit platforms, so
  // bits 0–63 are all usable. `isFullyAbsent` checks `_absentMask == -1`
  // (all 64 bits set in two's complement). Unsigned right-shift (`>>>`) is
  // used for bit probing to avoid sign-extension on bit 63.
  // ---------------------------------------------------------------------------

  int _absentMask = 0;

  /// Whether slot [slot] (0-based within this chunk) is confirmed absent.
  ///
  /// A confirmed-absent slot will never return a message from `fetchRange`.
  /// Returns `false` for slots that are simply not yet loaded.
  bool isAbsentSlot(int slot) {
    assert(slot >= 0 && slot < kSize, 'slot $slot out of [0, $kSize)');
    return _absentMask >>> slot & 1 != 0;
  }

  /// Mark slot [slot] as confirmed absent.
  ///
  /// The slot MUST be null (not currently holding a message). Attempting to
  /// mark a present slot absent is a logic error and throws in debug mode.
  void markAbsentSlot(int slot) {
    assert(slot >= 0 && slot < kSize, 'slot $slot out of [0, $kSize)');
    assert(
      messages[slot] == null,
      'Cannot mark slot $slot absent: messages[$slot] is non-null',
    );
    _absentMask |= 1 << slot;
  }

  /// Clear the absent bit for slot [slot].
  ///
  /// The symmetric inverse of [markAbsentSlot]. Idempotent — a no-op when
  /// the bit is already zero. MUST be called by `upsertMessage` /
  /// `upsertMessages` before or when writing a message into this slot so that
  /// a realtime insert at a previously-absent slot surfaces immediately without
  /// requiring `invalidate()`.
  void clearAbsentSlot(int slot) {
    assert(slot >= 0 && slot < kSize, 'slot $slot out of [0, $kSize)');
    _absentMask &= ~(1 << slot);
  }

  /// Reset the absent bitmask to zero.
  ///
  /// Call this when the chunk is invalidated so a subsequent `fetchRange` call
  /// can re-confirm (or refute) the absent status of each slot.
  void clearAbsentMask() => _absentMask = 0;

  /// Whether all 64 slots in this chunk are confirmed absent.
  ///
  /// When `true`, fan-out can skip the entire chunk in O(1) without
  /// inspecting individual slots.
  bool get isFullyAbsent => _absentMask == -1;
}
