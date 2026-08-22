import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import 'package:chat_scroll_view/src/chat_scroll/chat_mutations.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_range_fetch.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_chunk.dart';
import 'package:chat_scroll_view/src/chat_scroll/chat_scroll_common.dart';
import 'package:meta/meta.dart';

/// Data source for [ChatScrollView].
///
/// Owns message data (chunks), the fetch contract, and the conversation
/// boundary state (`oldestKnownId`, `reachedNewest`, …). Boundary state used
/// to live on the controller but it describes the *data*, not the
/// navigation — keeping a single source of truth here means consumers don't
/// have to mirror page metadata onto two objects after every fetch.
///
/// **ID allocation (ADR 002)**: This engine treats raw message ids as scroll
/// positions (`id++` fan-out, per-slot absent marking). Backends MUST allocate
/// ids **per conversation, sequentially** (deletion gaps only). Global
/// auto-increment or random ids per chat are unsupported and cause incorrect
/// absent marking and navigation — a design constraint, not a runtime security
/// check. See `docs/adr/002-position-model.md`.
///
/// **Integrator CRUD** (emits [ChatMutation] + one [notifyDataChanged]):
/// [insertMessage], [insertMessages], [updateMessage], [updateMessages],
/// [removeMessages]. Subclasses may alias
/// these (`sendMessage`, `editMessage`, …) but MUST NOT expose a second
/// add/edit path through [upsertMessage].
///
/// **Silent storage** (fetch / CRUD internals — **never** emits [ChatMutation]):
/// [upsertMessage], [upsertMessages]. Pagination and prefetch use these only.
/// Subclasses MUST NOT call [notifyDataChanged] after delegating to
/// `super.upsertMessage` / `super.upsertMessages` — the base class notifies.
///
/// **Mutation delivery**: [addMutationListener] / [removeMutationListener]
/// invoke [ChatMutation] synchronously (same dedup-on-add pattern as
/// [addDataListener]). No `Stream`. Viewport and animation layers subscribe
/// here for explicit add/update/delete intent — not for fetch merges.
///
/// **Boundary deletes**: when a delete removes the message at [oldestKnownId]
/// or [newestKnownId], [removeMessages] auto-retracts via present-neighbor
/// walks and one atomic [seedBoundaries] — callers do not pass boundary ids.
///
/// **Removal staging**: [removeMessages] marks slots absent and retains
/// payloads in an internal staging map until [finalizeRemoval] (viewport /
/// tests). [pendingRemovalIds] is read-only observability derived from staging.
abstract class ChatDataSource {
  // --- Fetch contract (subclass implements) ---

  /// Load messages whose IDs fall in `[fromId, toId]` (both inclusive).
  ///
  /// The subclass returns a **sparse** list containing only messages that
  /// exist — not a dense array with `null` placeholders for absent IDs.
  /// The framework's post-fetch absent-marking pass walks every null slot in
  /// each fetched chunk and marks it permanently absent. Integrators MUST NOT
  /// embed absent slots in the returned list; omit missing IDs entirely.
  ///
  /// **Full-chunk boundary invariant** (caller's guarantee):
  /// `fromId` MUST equal `ChatScrollChunk.firstIdOf(chunkIndex)` and `toId`
  /// MUST equal `chunk.lastId` for every chunk in the requested span.
  /// Verify with [ChatScrollChunk.isFullChunkRange] before calling. Partial-range
  /// fetches within a chunk are not supported — the absent-marking pass that
  /// runs after a successful `fetchRange` relies on the entire chunk being
  /// covered by the request. Violating this invariant causes null slots inside
  /// the unfetched portion to be incorrectly marked absent (silent data loss).
  ///
  /// The subclass may return fewer messages than the ID range spans when the
  /// conversation boundary lies inside the range. IDs not returned are treated
  /// as permanently absent, except the unconfirmed live tail past the highest
  /// returned id (recent inserts) which stays unloaded for refill.
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  });

  /// Maximum number of chunks to keep in memory.
  /// Override to control the memory/re-fetch tradeoff.
  /// Default 16 ≈ 1024 messages.
  int get maxChunks => 16;

  // --- Boundary state -------------------------------------------------------

  int? _oldestKnownId;
  int? _newestKnownId;
  bool _reachedOldest = false;
  bool _reachedNewest = false;

  /// Highest id advanced by [insertMessage] / [insertMessages] that a later
  /// range fetch may still omit (stale backend / race). Absent-marking must
  /// not tombstone `(maxReturned, through]` while this is set.
  int? _unconfirmedTailThroughId;

  /// Lowest message id the data source has seen so far. `null` until the
  /// first page lands. Bumped down by subsequent fetches that reveal older
  /// pages.
  int? get oldestKnownId => _oldestKnownId;

  /// Highest message id the data source has seen so far. `null` while the
  /// conversation is empty.
  int? get newestKnownId => _newestKnownId;

  /// Whether [oldestKnownId] is the very first message of the conversation —
  /// no more older pages exist. The viewport pins content to the top edge
  /// when both this is `true` and the oldest is in view.
  bool get reachedOldest => _reachedOldest;

  /// Whether [newestKnownId] is the very last message of the conversation —
  /// no more newer pages exist. The viewport pins content to the bottom
  /// edge when both this is `true` and the newest is in view.
  bool get reachedNewest => _reachedNewest;

  /// Whether the conversation is known to contain no messages — both
  /// boundaries are reached and neither id was set. Distinct from "nothing
  /// loaded yet" ([isInitialLoading]): empty is a *confirmed* terminal state.
  /// The viewport switches to its empty overlay when this is `true` and a
  /// builder is provided.
  bool get isEmpty =>
      _reachedOldest &&
      _reachedNewest &&
      _oldestKnownId == null &&
      _newestKnownId == null;

  /// Whether the data source has not yet seen any messages or boundaries —
  /// the very first page is still being resolved. Distinct from [isEmpty]:
  /// initial-loading is *unknown* (either side may still produce ids). The
  /// viewport switches to its loading overlay when this is `true` and a
  /// builder is provided.
  bool get isInitialLoading {
    if (_oldestKnownId != null || _newestKnownId != null) return false;
    return !_reachedOldest && !_reachedNewest;
  }

  /// Sentinel for [seedBoundaries] optional ids — omit the parameter to leave
  /// that boundary unchanged; pass explicit `null` to clear it (empty chat).
  static const Object _boundaryUnset = Object();

  /// Atomically set the boundary state. Notifies listeners only if anything
  /// actually changed. Intended for subclasses to call after a fetch resolves
  /// — but also exposed publicly so consumers that pre-load their data can
  /// configure the viewport in one statement.
  ///
  /// Omitted [oldestKnownId] / [newestKnownId] leave the current value.
  /// Explicit `null` clears the id (e.g. after the last message is removed).
  @mustCallSuper
  void seedBoundaries({
    Object? oldestKnownId = _boundaryUnset,
    Object? newestKnownId = _boundaryUnset,
    bool? reachedOldest,
    bool? reachedNewest,
  }) {
    var changed = false;
    if (oldestKnownId != _boundaryUnset) {
      final next = oldestKnownId as int?;
      if (next != _oldestKnownId) {
        _oldestKnownId = next;
        changed = true;
      }
    }
    if (newestKnownId != _boundaryUnset) {
      final next = newestKnownId as int?;
      if (next != _newestKnownId) {
        _newestKnownId = next;
        changed = true;
      }
    }
    if (reachedOldest != null && reachedOldest != _reachedOldest) {
      _reachedOldest = reachedOldest;
      changed = true;
    }
    if (reachedNewest != null && reachedNewest != _reachedNewest) {
      _reachedNewest = reachedNewest;
      changed = true;
    }
    assert(
      _oldestKnownId == null ||
          _newestKnownId == null ||
          _oldestKnownId! <= _newestKnownId!,
      'oldestKnownId ($_oldestKnownId) must be ≤ newestKnownId '
      '($_newestKnownId)',
    );
    // An empty conversation is `reachedOldest && reachedNewest` with both ids
    // null — there are no messages, so no oldest/newest exists to point at.
    // The assert allows that, but still catches half-empty seeding.
    final empty = _reachedOldest && _reachedNewest;
    assert(
      !_reachedOldest || _oldestKnownId != null || empty,
      'reachedOldest=true requires oldestKnownId to be set '
      '(unless the conversation is empty: reachedNewest also true, '
      'newestKnownId also null)',
    );
    assert(
      !_reachedNewest || _newestKnownId != null || empty,
      'reachedNewest=true requires newestKnownId to be set '
      '(unless the conversation is empty: reachedOldest also true, '
      'oldestKnownId also null)',
    );
    if (changed) _notifyBoundary();
  }

  // --- Typed listener: boundary changed ---

  /// Plain `List` rather than `Set` so the field's runtime type stays
  /// stable across hot-reload. `addBoundaryListener` dedups explicitly so
  /// a double-registration with the same closure is a no-op (otherwise the
  /// listener fired twice per notification and the symmetric `remove` only
  /// stripped one registration). A `Set<>` field would change the typed
  /// schema mid-session and trip a `_Set is not List` runtime error in any
  /// hot-reloaded code path that still expected the old type.
  final _boundaryListeners = <VoidCallback>[];

  /// Subscribe to boundary state changes. Adding the same callback twice is
  /// a no-op — the registration is dedup'd.
  void addBoundaryListener(VoidCallback callback) {
    if (_boundaryListeners.contains(callback)) return;
    _boundaryListeners.add(callback);
  }

  /// Unsubscribe from boundary state changes.
  void removeBoundaryListener(VoidCallback callback) =>
      _boundaryListeners.remove(callback);

  void _notifyBoundary() {
    for (final cb in List<VoidCallback>.of(
      _boundaryListeners,
      growable: false,
    )) {
      cb();
    }
  }

  // --- Chunk storage ---

  final Map<int, ChatScrollChunk> _chunks = HashMap<int, ChatScrollChunk>();

  /// Direct access to chunks for the viewport.
  @internal
  Map<int, ChatScrollChunk> get chunks => _chunks;

  /// Get a message by ID from the chunk cache — **exact slot lookup**.
  ///
  /// Returns the instance at [messageId], or `null` if the chunk is missing or
  /// the slot is empty (absent **or** not yet loaded). Does **not** walk to a
  /// neighbor when [messageId] is absent; use [getPreviousPresentMessage] or
  /// [getNextPresentMessage] for directed neighbor lookup.
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

  /// Silent chunk write — no [notifyDataChanged], no [ChatMutation].
  ///
  /// Used by fetch [upsertMessage] / [upsertMessages] and by CRUD methods after
  /// intent is recorded. Clears absent flags before writing.
  @protected
  void writeMessageSilent(IChatMessage message) {
    if (_disposed) return;
    final chunkIndex = ChatScrollChunk.chunkOf(message.id);
    final existed = _chunks.containsKey(chunkIndex);
    final chunk = _chunks.putIfAbsent(
      chunkIndex,
      () =>
          ChatScrollChunk(index: chunkIndex)..status = ChatMessageStatus.valid,
    );
    final slot = message.id - chunk.firstId;
    chunk.clearAbsentSlot(slot);
    chunk.messages[slot] = message;
    if (!existed) chunk.status = ChatMessageStatus.valid;
  }

  /// Bulk silent write — no notification.
  @protected
  void writeMessagesSilent(Iterable<IChatMessage> messages) {
    if (_disposed) return;
    messages.forEach(writeMessageSilent);
  }

  /// Upsert a message into the chunk cache — **silent storage for fetch**.
  ///
  /// Does **not** emit [ChatMutation]. Integrators adding user content MUST
  /// use [insertMessage] / [updateMessage] instead.
  ///
  /// Creates the chunk if it does not exist yet. A freshly-created chunk is
  /// marked `valid` — the upsert is the consumer's source of truth, so a
  /// subsequent poll must not re-fetch this chunk and overwrite the local
  /// message with whatever (possibly empty) page the server returns. If a
  /// real refresh is wanted, call [invalidate] afterwards.
  ///
  /// **Eviction caveat:** [insertMessage] into a previously LRU-evicted chunk
  /// recreates that chunk with only the new row. That path marks the chunk
  /// dirty when known-span sibling slots are still empty so the viewport can
  /// refill them (see [_markDirtyIfKnownSpanHoles]).
  void upsertMessage(IChatMessage message) {
    if (_disposed) return;
    writeMessageSilent(message);
    notifyDataChanged();
  }

  /// Upsert multiple messages — **fetch / cache merge only** (no mutations).
  void upsertMessages(Iterable<IChatMessage> messages) {
    if (_disposed) return;
    var changed = false;
    for (final message in messages) {
      writeMessageSilent(message);
      changed = true;
    }
    if (changed) notifyDataChanged();
  }

  // --- CRUD (integrator intent — emits ChatMutation) ------------------------

  /// Records an insert intent, writes storage silently, extends boundaries,
  /// and notifies layout once.
  ///
  /// Does not block when *other* ids are in removal staging
  /// ([pendingRemovalIds]). Re-inserting an id that is still staged is a
  /// contract error — sequential allocators must use [nextInsertId], not
  /// `newestKnownId + 1`, after a tail delete (those ids stay staged until
  /// collapse finishes).
  ///
  /// Emits [InsertMutation] (not [InsertBatchMutation]). For bulk tail bursts
  /// use [insertMessages] — integrator explicit API choice vs silent
  /// [upsertMessages].
  void insertMessage(IChatMessage message, {Object? reason}) {
    if (_disposed) return;
    assert(
      !_removalStaging.containsKey(message.id),
      'insertMessage: id ${message.id} is pending removal',
    );
    _notifyMutation(ChatMutation.insert(message.id, reason: reason));
    writeMessageSilent(message);
    _extendBoundariesForInsert(message.id);
    // After eviction, writeMessageSilent recreates the chunk as `valid` with
    // only this row — sibling slots stay null and would shimmer forever
    // because needsFetch skips valid chunks. Mark dirty when the known span
    // still has holes so jump/poll refetch fills them.
    _markDirtyIfKnownSpanHoles(ChatScrollChunk.chunkOf(message.id));
    notifyDataChanged();
  }

  /// Records a batch insert intent, writes storage silently, extends boundaries,
  /// and notifies layout once.
  ///
  /// Normalizes [messages] to unique ids sorted **ascending**, skipping ids
  /// pending removal idempotently. Does not block when unrelated ids are staged.
  ///
  /// Integrators choose this over [upsertMessages] when batch insert intent /
  /// animation eligibility is desired (e.g. app-resume tail burst). Fetch and
  /// silent cache merge MUST use [upsertMessages] instead.
  void insertMessages(Iterable<IChatMessage> messages, {Object? reason}) {
    if (_disposed) return;
    final normalized = _normalizeInsertMessages(messages);
    if (normalized.isEmpty) return;

    final operationId = _nextOperationId++;
    final ids = normalized.map((m) => m.id).toList(growable: false);
    _notifyMutation(
      ChatMutation.insertBatch(
        ids: ids,
        operationId: operationId,
        reason: reason,
      ),
    );
    for (final message in normalized) {
      writeMessageSilent(message);
      _extendBoundariesForInsert(message.id);
      _markDirtyIfKnownSpanHoles(ChatScrollChunk.chunkOf(message.id));
    }
    notifyDataChanged();
  }

  /// Records an update intent, replaces the stored instance, notifies once.
  ///
  /// Integrator edits MUST use this or [updateMessages] — never [upsertMessage]
  /// for user-driven content changes. Emits [UpdateMutation] so hosts can run
  /// edit transitions; the viewport expects the message child to **lerp its
  /// reported height** during resize (see example `DemoMessageEditBody`) until
  /// a viewport-owned extent spring lands. No-op with debug assert when
  /// [message.id] is confirmed absent or staged.
  ///
  /// Emits [UpdateMutation] (not [UpdateBatchMutation]). For bulk edits use
  /// [updateMessages].
  void updateMessage(IChatMessage message, {Object? reason}) {
    if (_disposed) return;
    if (_removalStaging.containsKey(message.id) ||
        _isConfirmedAbsent(message.id)) {
      assert(
        false,
        'updateMessage: id ${message.id} is absent or pending removal',
      );
      return;
    }
    _notifyMutation(ChatMutation.update(message.id, reason: reason));
    writeMessageSilent(message);
    notifyDataChanged();
  }

  /// Records a batch update intent, replaces stored instances, notifies once.
  ///
  /// Normalizes [messages] to unique ids sorted **ascending**, skipping absent
  /// and pending-removal ids idempotently. There is **no** silent bulk-edit API
  /// (contrast with fetch [upsertMessages]).
  void updateMessages(Iterable<IChatMessage> messages, {Object? reason}) {
    if (_disposed) return;
    final normalized = _normalizeUpdateMessages(messages);
    if (normalized.isEmpty) return;

    final operationId = _nextOperationId++;
    final ids = normalized.map((m) => m.id).toList(growable: false);
    _notifyMutation(
      ChatMutation.updateBatch(
        ids: ids,
        operationId: operationId,
        reason: reason,
      ),
    );
    normalized.forEach(writeMessageSilent);
    notifyDataChanged();
  }

  /// Stages one or more ids for removal — one [RemoveBatchMutation]
  /// and one [notifyDataChanged] per call.
  ///
  /// Normalizes [ids] to unique descending order. Unknown ids outside the known
  /// span and already-staged ids are skipped idempotently. Boundaries retract
  /// atomically via present-neighbor walks.
  void removeMessages(Iterable<int> ids, {Object? reason}) {
    if (_disposed) return;
    final normalized = _normalizeRemoveIds(ids);
    if (normalized.isEmpty) return;

    final operationId = _nextOperationId++;
    normalized.forEach(_stageRemoval);
    _retractBoundariesAfterRemove();
    _notifyMutation(
      ChatMutation.removeBatch(
        ids: normalized,
        operationId: operationId,
        reason: reason,
      ),
    );
    notifyDataChanged();
  }

  /// Clears removal staging for [id]. Slot stays absent — no second mutation.
  ///
  /// Intended for the viewport after collapse completes, or tests. Integrators
  /// deleting messages use [removeMessages] instead.
  void finalizeRemoval(int id) {
    if (_disposed) return;
    if (_removalStaging.remove(id) != null) {
      notifyDataChanged();
    }
  }

  /// Payload retained while [id] is pending collapse — absent from [getMessage].
  IChatMessage? getStagedRemovalMessage(int id) => _removalStaging[id];

  /// Read-only view of ids awaiting [finalizeRemoval].
  Set<int> get pendingRemovalIds => Set.unmodifiable(_removalStaging.keys);

  /// Next tail id that is not live and not pending removal.
  ///
  /// After a tail delete, [newestKnownId] retracts to the last present
  /// message while the deleted ids remain in [pendingRemovalIds].
  /// `newestKnownId + 1` then collides with staging; this getter skips
  /// those ids.
  int get nextInsertId {
    var id = newestKnownId ?? -1;
    for (final staged in _removalStaging.keys) {
      if (staged > id) id = staged;
    }
    return id + 1;
  }

  /// Nearest loaded message **below** [id] in conversation order.
  ///
  /// Walks id downward from [id] - 1, skipping confirmed-absent slots
  /// (deleted, staging, absent flag) within `[oldestKnownId, id)`. Named
  /// `Present` — not `getPreviousMessage` — to distinguish from raw
  /// `getMessage(id - 1)` and to signal absent-skip semantics.
  ///
  /// Returns `null` when no probe id exists, or the probe is unloaded
  /// (`getMessage(probe)` null).
  IChatMessage? getPreviousPresentMessage(int id) {
    final probe = _previousPresentId(id);
    return probe == null ? null : getMessage(probe);
  }

  /// Nearest loaded message **above** [id] in conversation order.
  ///
  /// Walks id upward from [id] + 1, skipping confirmed-absent slots within
  /// `(id, newestKnownId]`. See [getPreviousPresentMessage] for naming rationale.
  IChatMessage? getNextPresentMessage(int id) {
    final probe = _nextPresentId(id);
    return probe == null ? null : getMessage(probe);
  }

  List<IChatMessage> _normalizeUpdateMessages(Iterable<IChatMessage> messages) {
    final byId = <int, IChatMessage>{};
    for (final message in messages) {
      if (_removalStaging.containsKey(message.id)) continue;
      if (_isConfirmedAbsent(message.id)) continue;
      byId[message.id] = message;
    }
    final sorted = byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    return sorted;
  }

  List<IChatMessage> _normalizeInsertMessages(Iterable<IChatMessage> messages) {
    final byId = <int, IChatMessage>{};
    for (final message in messages) {
      if (_removalStaging.containsKey(message.id)) continue;
      byId[message.id] = message;
    }
    final sorted = byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    return sorted;
  }

  List<int> _normalizeRemoveIds(Iterable<int> ids) {
    final unique = <int>{};
    for (final id in ids) {
      if (_shouldSkipRemoveId(id)) continue;
      unique.add(id);
    }
    final sorted = unique.toList()..sort((a, b) => b.compareTo(a));
    return sorted;
  }

  bool _shouldSkipRemoveId(int id) {
    if (_removalStaging.containsKey(id)) return true;
    final oldest = _oldestKnownId;
    final newest = _newestKnownId;
    if (oldest != null && id < oldest) return true;
    if (newest != null && id > newest) return true;
    if (oldest == null && newest == null && !isInitialLoading) return true;
    return false;
  }

  void _stageRemoval(int id) {
    final chunkIndex = ChatScrollChunk.chunkOf(id);
    final chunk = _chunks.putIfAbsent(
      chunkIndex,
      () =>
          ChatScrollChunk(index: chunkIndex)..status = ChatMessageStatus.valid,
    );
    final slot = id - chunk.firstId;
    final existing = chunk.messages[slot];
    // Always record the id so local deletes survive chunk LRU eviction and
    // block fetchRange merge from resurrecting rows the integrator removed.
    _removalStaging[id] = existing;
    chunk.messages[slot] = null;
    if (!chunk.isAbsentSlot(slot)) {
      chunk.markAbsentSlot(slot);
    }
  }

  void _retractBoundariesAfterRemove() {
    var oldest = _oldestKnownId;
    var newest = _newestKnownId;

    while (oldest != null && _isConfirmedAbsent(oldest)) {
      oldest = _nextPresentId(oldest);
    }
    while (newest != null && _isConfirmedAbsent(newest)) {
      newest = _previousPresentId(newest);
    }

    if (oldest == null && newest == null) {
      seedBoundaries(
        oldestKnownId: null,
        newestKnownId: null,
        reachedOldest: true,
        reachedNewest: true,
      );
    } else {
      seedBoundaries(oldestKnownId: oldest, newestKnownId: newest);
    }
  }

  void _extendBoundariesForInsert(int id) {
    if (_oldestKnownId == null && _newestKnownId == null) {
      seedBoundaries(
        oldestKnownId: id,
        newestKnownId: id,
        reachedOldest: _reachedOldest,
        reachedNewest: _reachedNewest,
      );
      _noteUnconfirmedTail(id);
      return;
    }
    if (_oldestKnownId == null || id < _oldestKnownId!) {
      seedBoundaries(oldestKnownId: id);
    }
    if (_newestKnownId == null || id > _newestKnownId!) {
      seedBoundaries(newestKnownId: id, reachedNewest: true);
      _noteUnconfirmedTail(id);
    } else if (id == _newestKnownId) {
      // Re-insert / replace at newest still needs fetch protection if LRU
      // drops the payload before a confirming range response.
      _noteUnconfirmedTail(id);
    }
  }

  void _noteUnconfirmedTail(int id) {
    final through = _unconfirmedTailThroughId;
    if (through == null || id > through) {
      _unconfirmedTailThroughId = id;
    }
  }

  void _onRangeFetchSuccess(int? maxReturnedId) {
    final through = _unconfirmedTailThroughId;
    if (through == null) return;
    if (maxReturnedId != null && maxReturnedId >= through) {
      _unconfirmedTailThroughId = null;
    }
  }

  bool _isConfirmedAbsent(int id) {
    if (_removalStaging.containsKey(id)) return true;
    final chunk = _chunks[ChatScrollChunk.chunkOf(id)];
    if (chunk == null) return false;
    return chunk.isAbsentSlot(id - chunk.firstId);
  }

  int? _previousPresentId(int id) {
    final bound = _oldestKnownId;
    if (bound == null) return null;
    for (var probe = id - 1; probe >= bound; probe--) {
      if (!_isConfirmedAbsent(probe)) return probe;
    }
    return null;
  }

  int? _nextPresentId(int id) {
    final bound = _newestKnownId;
    if (bound == null) return null;
    for (var probe = id + 1; probe <= bound; probe++) {
      if (!_isConfirmedAbsent(probe)) return probe;
    }
    return null;
  }

  // --- Removal staging ------------------------------------------------------

  final Map<int, IChatMessage?> _removalStaging = <int, IChatMessage?>{};
  int _nextOperationId = 1;

  // --- Typed listener: mutation intent --------------------------------------

  /// Plain `List` — see [_boundaryListeners]. Same dedup-on-add invariant.
  final _mutationListeners = <void Function(ChatMutation)>[];

  /// Subscribe to CRUD mutation events. Fetch and upsert never invoke this.
  void addMutationListener(void Function(ChatMutation) listener) {
    if (_mutationListeners.contains(listener)) return;
    _mutationListeners.add(listener);
  }

  /// Unsubscribe from mutation events.
  void removeMutationListener(void Function(ChatMutation) listener) =>
      _mutationListeners.remove(listener);

  void _notifyMutation(ChatMutation mutation) {
    for (final cb in List<void Function(ChatMutation)>.of(
      _mutationListeners,
      growable: false,
    )) {
      cb(mutation);
    }
  }

  // --- Range fetch orchestration ---

  late final ChatRangeFetch _rangeFetch = ChatRangeFetch(
    chunks: () => _chunks,
    fetchRange: fetchRange,
    notifyDataChanged: notifyDataChanged,
    isDisposed: () => _disposed,
    unconfirmedTailThroughId: () => _unconfirmedTailThroughId,
    onFetchSuccess: _onRangeFetchSuccess,
    skipFetchUpsert: _isConfirmedAbsent,
  );

  /// Check visible chunk range and fetch missing/dirty data.
  /// Called from the viewport's periodic poll timer.
  ///
  /// Before dispatching, any in-range `valid` chunk that still has empty
  /// known-span slots (typical after insert into an LRU-evicted chunk) is
  /// marked dirty so [ChatRangeFetch.needsFetch] will refill it.
  @internal
  void requestChunks(int layoutMinChunk, int layoutMaxChunk) {
    if (layoutMaxChunk >= layoutMinChunk) {
      for (var ci = layoutMinChunk; ci <= layoutMaxChunk; ci++) {
        _markDirtyIfKnownSpanHoles(ci);
      }
    }
    _rangeFetch.requestChunks(layoutMinChunk, layoutMaxChunk);
  }

  /// Marks [chunkIndex] dirty when it still has empty known-span slots.
  /// No-op while a fetch is in flight.
  void _markDirtyIfKnownSpanHoles(int chunkIndex) {
    final chunk = _chunks[chunkIndex];
    if (chunk == null) return;
    if (chunk.status.isFetching) return;
    if (!_chunkHasKnownSpanHoles(chunk)) return;
    _clearSuspectAbsentSlots(chunk);
    chunk.status = ChatMessageStatus.dirty;
  }

  /// `true` when any slot in the intersection of this chunk and the known
  /// conversation span is still missing a payload.
  ///
  /// Also treats absent marks on the unconfirmed live tail (past the last
  /// present payload, through [_unconfirmedTailThroughId]) as holes — stale
  /// fetches used to tombstone recent inserts and leave load-gate stuck.
  bool _chunkHasKnownSpanHoles(ChatScrollChunk chunk) {
    final oldest = _oldestKnownId;
    final newest = _newestKnownId;
    if (oldest == null || newest == null) return false;
    final from = math.max(chunk.firstId, oldest);
    final to = math.min(chunk.firstId + ChatScrollChunk.kSize - 1, newest);
    if (from > to) return false;
    final unconfirmedThrough = _unconfirmedTailThroughId;
    int? maxPresent;
    for (var id = from; id <= to; id++) {
      final slot = id - chunk.firstId;
      if (chunk.messages[slot] != null) maxPresent = id;
    }
    for (var id = from; id <= to; id++) {
      final slot = id - chunk.firstId;
      if (chunk.messages[slot] != null) continue;
      if (!chunk.isAbsentSlot(slot)) return true;
      if (unconfirmedThrough != null &&
          id <= unconfirmedThrough &&
          (maxPresent == null || id > maxPresent)) {
        return true;
      }
    }
    return false;
  }

  /// Clears absent flags on the unconfirmed live tail so a refetch can refill.
  void _clearSuspectAbsentSlots(ChatScrollChunk chunk) {
    final oldest = _oldestKnownId;
    final newest = _newestKnownId;
    final unconfirmedThrough = _unconfirmedTailThroughId;
    if (oldest == null || newest == null || unconfirmedThrough == null) {
      return;
    }
    final from = math.max(chunk.firstId, oldest);
    final to = math.min(chunk.firstId + ChatScrollChunk.kSize - 1, newest);
    if (from > to) return;
    int? maxPresent;
    for (var id = from; id <= to; id++) {
      final slot = id - chunk.firstId;
      if (chunk.messages[slot] != null) maxPresent = id;
    }
    for (var id = from; id <= to; id++) {
      final slot = id - chunk.firstId;
      if (chunk.messages[slot] != null) continue;
      if (!chunk.isAbsentSlot(slot)) continue;
      if (id > unconfirmedThrough) continue;
      if (maxPresent == null || id > maxPresent) {
        chunk.clearAbsentSlot(slot);
      }
    }
  }

  /// Clears absent/tombstone state for [messageId] and marks its chunk dirty
  /// so the next [requestChunks] refetches it.
  ///
  /// Used once when a navigation destination pin is newly established so a
  /// prior stale absent mark cannot leave load-gate idle at `pending=false`.
  @internal
  void reopenIdForFetch(int messageId) {
    if (_disposed) return;
    final chunkIndex = ChatScrollChunk.chunkOf(messageId);
    final chunk = _chunks.putIfAbsent(
      chunkIndex,
      () => ChatScrollChunk(index: chunkIndex),
    );
    if (chunk.status.isFetching) return;
    final slot = messageId - chunk.firstId;
    if (slot < 0 || slot >= ChatScrollChunk.kSize) return;
    if (chunk.messages[slot] != null) return;
    final wasAbsent = chunk.isAbsentSlot(slot);
    final wasDirty = chunk.status.isDirty;
    chunk
      ..clearAbsentSlot(slot)
      ..status = ChatMessageStatus.dirty
      ..lastError = null;
    _clearSuspectAbsentSlots(chunk);
    if (!wasDirty || wasAbsent) {
      notifyDataChanged();
    }
  }

  /// Whether [chunkIndex] still has missing payloads in the known conversation
  /// span (including suspect trailing absents). Used by the fetch scheduler
  /// so poll stays armed while a "valid" chunk needs refill.
  @internal
  bool hasKnownSpanHoles(int chunkIndex) {
    final chunk = _chunks[chunkIndex];
    if (chunk == null) return false;
    return _chunkHasKnownSpanHoles(chunk);
  }

  /// Cancel any in-flight fetch and retry timer.
  @internal
  void cancelFetch() => _rangeFetch.cancelFetch();

  /// Whether [chunkIndex] is covered by an in-flight range fetch token.
  ///
  /// True even if the chunk map entry was LRU-evicted mid-flight — the
  /// scheduler must not treat those indexes as "still need a fetch" or it
  /// will busy-loop on a zero-delay poll while the token is live.
  @internal
  bool coversChunkInFlight(int chunkIndex) =>
      _rangeFetch.coversChunkInFlight(chunkIndex);

  /// Mark every loaded chunk as stale so the viewport refetches them on the
  /// next pass — lazy: in-range chunks get a fresh fetch from the poll;
  /// off-range chunks stay dirty until visited.
  ///
  /// Use after a connection-state change that may have produced new data
  /// the source missed: SSE / WebSocket reconnect, `AppLifecycleState
  /// .resumed`, a pull-to-refresh affordance. The existing chunk data stays
  /// in place (no flicker) until the refetch lands; consumers that want a
  /// "loading" indicator can read `status.isDirty` from the chunk via
  /// `statusOf(id)`.
  ///
  /// Cancels any in-flight fetch and retry timer — the new dirty marks
  /// drive a fresh fetch cycle. Per-chunk `failedAttempts` and `lastError`
  /// are reset; an errored chunk reaches the user as `dirty` again rather
  /// than carrying the prior failure state into the new attempt.
  ///
  /// Absent masks are cleared so subsequent re-fetches start with a clean
  /// slate — a message that was absent may have been restored (e.g. un-delete
  /// or sync recovery) and must not be suppressed by a stale absent flag.
  void invalidate() {
    if (_disposed) return;
    // Coalesce the cancel-fetch notification into ours: otherwise listeners
    // see two `notifyDataChanged` calls (one from the running fetch's
    // status drop, one from the dirty-marking pass) for what is logically
    // a single state change.
    var changed = _rangeFetch.cancelFetchSilent();
    // Reset source-wide backoff step so the post-invalidate refetch starts
    // from the initial window rather than inheriting accumulated backoff
    // (the per-chunk `lastError`/`failedAttempts` reset below is not enough
    // — the retry step lives on [ChatRangeFetch]).
    _rangeFetch.resetRetryStep();
    for (final chunk in _chunks.values) {
      // Don't overwrite a chunk that is already dirty (or fetching after a
      // cancelFetch race) — the goal is "mark stale", not "reset to a
      // particular flag set".
      if (chunk.status.isValid || chunk.status.isError) {
        chunk.status = chunk.status
            .remove(ChatMessageStatus.error)
            .add(ChatMessageStatus.dirty);
        changed = true;
      }
      if (chunk.failedAttempts != 0 || chunk.lastError != null) {
        chunk
          ..failedAttempts = 0
          ..lastError = null;
        changed = true;
      }
      // Clear the absent mask so the re-fetch can re-confirm (or refute)
      // each slot's absent status. A restored message must not be suppressed
      // by a stale absent flag from a previous fetch cycle.
      // Unconditional: clearAbsentMask is O(1) and idempotent.
      chunk.clearAbsentMask();
    }
    if (changed) notifyDataChanged();
  }

  /// Force an immediate re-fetch of the chunk containing [messageId],
  /// bypassing the in-flight backoff.
  ///
  /// Intended for UI retry — the user taps "Retry" on a chunk that failed,
  /// and the viewport's poll alone would either wait out the backoff or skip
  /// the chunk if the user is no longer near it. Resets the backoff step and
  /// per-chunk `failedAttempts` / `lastError` so the next attempt is reported
  /// to the UI as a fresh first try, and fires a fresh fetch scoped to the
  /// single chunk.
  ///
  /// When the requested chunk is already covered by an in-flight fetch this
  /// is a no-op — the running request will resolve it. Otherwise any
  /// in-flight fetch is cancelled and replaced with the single-chunk
  /// request; that trade-off favours the visible chunk the user clicked on.
  ///
  /// No-op when the chunk is already loaded successfully. When the chunk
  /// does not exist yet, a fresh fetch is launched.
  void retryChunk(int messageId) {
    if (_disposed) return;
    final chunkIndex = ChatScrollChunk.chunkOf(messageId);
    final chunk = _chunks[chunkIndex];
    if (chunk != null && chunk.status.isValid) return;

    // If a fetch is already in flight that covers this chunk, let it
    // resolve — the user tap mustn't trash an in-progress network round-trip
    // that is about to satisfy the same request.
    if (_rangeFetch.coversChunkInFlight(chunkIndex)) return;

    // Reset per-chunk failure state so the UI sees the user-initiated retry
    // as a fresh attempt rather than continuing the previous counter.
    if (chunk != null) {
      chunk
        ..failedAttempts = 0
        ..lastError = null;
    }
    _rangeFetch.startFetchRange(chunkIndex, chunkIndex);
  }

  // --- Typed listener: data changed ---

  /// Plain `List` — see [_boundaryListeners]. Same dedup-on-add invariant.
  final _dataListeners = <VoidCallback>[];

  /// Subscribe to data changes. Adding the same callback twice is a no-op.
  void addDataListener(VoidCallback callback) {
    if (_dataListeners.contains(callback)) return;
    _dataListeners.add(callback);
  }

  /// Unsubscribe from data changes.
  void removeDataListener(VoidCallback callback) =>
      _dataListeners.remove(callback);

  /// Notify all listeners that message data has changed.
  ///
  /// Iterates over a snapshot to remain safe if a listener adds or removes
  /// listeners (including itself) during dispatch.
  ///
  /// Subclasses must not override this method or call it after
  /// `super.upsertMessage` / `super.upsertMessages` — the base class already
  /// notifies.
  @protected
  @nonVirtual
  void notifyDataChanged() {
    for (final cb in List<VoidCallback>.of(_dataListeners, growable: false)) {
      cb();
    }
  }

  /// Whether [dispose] has been called. After dispose every mutating entry
  /// point ([requestChunks], [retryChunk], [invalidate], CRUD methods,
  /// [upsertMessage], [upsertMessages], [cancelFetch]) becomes a silent no-op
  /// so a stale reference cannot resurrect network work or notify torn-down
  /// listeners.
  bool get isDisposed => _disposed;
  bool _disposed = false;

  /// Cancel any in-flight fetch / retry timer and drop all listeners. Call
  /// from the owning widget's `dispose` so the retry timer cannot resurrect
  /// network work after the viewport is gone. Idempotent — safe to call
  /// twice.
  @mustCallSuper
  void dispose() {
    if (_disposed) return;
    _rangeFetch.cancelFetch();
    _rangeFetch.dispose();
    _dataListeners.clear();
    _boundaryListeners.clear();
    _mutationListeners.clear();
    _removalStaging.clear();
    _chunks.clear();
    _disposed = true;
  }
}
