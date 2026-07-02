import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';

/// Kind of message mutation — distinct from bulk [ChatDataSource.notifyDataChanged].
enum ChatMutationKind {
  /// New message inserted into chunk storage.
  insert,

  /// Existing message content or layout changed.
  update,

  /// Message marked for animated removal (storage evicted at request time).
  remove,
}

/// Typed mutation event for viewport / integrator observers.
@immutable
class ChatMutation {
  /// Creates a mutation notification for message [id].
  const ChatMutation(this.kind, this.id, {this.reason});

  /// Insert, update, or remove.
  final ChatMutationKind kind;

  /// Affected message id.
  final int id;

  /// Debug label (`local-edit`, `stub`, …).
  final Object? reason;

  @override
  String toString() => 'ChatMutation($kind, id: $id, reason: $reason)';
}

/// Removal animation tracking and explicit update channel for [ChatDataSource].
///
/// * [requestRemoval] — evicts chunk storage immediately (via
///   [prepareRemovalStorage]) and marks [pendingRemovalIds] until the viewport
///   collapse animation finishes.
/// * [confirmRemoval] — clears [pendingRemovalIds] after animation completes.
mixin ChatMutationsMixin {
  /// Ids whose viewport collapse animation is still running.
  ///
  /// **Read-only for integrators** — observe for UI state (e.g. disable send)
  /// but do not subscribe for removal orchestration; the viewport handles
  /// collapse via [mutations] only.
  final ValueNotifier<Set<int>> pendingRemovalIds = ValueNotifier<Set<int>>(
    <int>{},
  );

  /// Evicts [id] from chunk storage and retains a snapshot for the collapsing
  /// child. Implemented by [ChatDataSource].
  void prepareRemovalStorage(int id);

  /// Clears [pendingRemovalIds] and drops the removal snapshot for [id].
  void clearRemovalPending(int id);

  /// Whether [id] is already absent from chunk storage.
  bool isMessageAbsent(int id);

  final StreamController<ChatMutation> _mutationsController =
      StreamController<ChatMutation>.broadcast();

  /// Broadcast stream of insert / update / remove intents.
  Stream<ChatMutation> get mutations => _mutationsController.stream;

  void _logMutation(String tag, ChatMutation mutation) {
    if (!kDebugMode) return;
    dev.log(
      '$tag | kind=${mutation.kind.name} id=${mutation.id} reason=${mutation.reason}',
      name: 'ChatScrollExtent',
    );
  }

  /// Marks [id] for animated removal and evicts it from chunk storage
  /// immediately so neighbor lookups skip absent slots during collapse.
  void requestRemoval(int id, {Object? reason = 'stub'}) {
    if (pendingRemovalIds.value.contains(id)) return;
    prepareRemovalStorage(id);
    pendingRemovalIds.value = {...pendingRemovalIds.value, id};
    final mutation = ChatMutation(ChatMutationKind.remove, id, reason: reason);
    _logMutation('requestRemoval', mutation);
    _mutationsController.add(mutation);
  }

  /// Clears [pendingRemovalIds] after the viewport collapse animation.
  ///
  /// Storage is evicted at [requestRemoval] time. [evictFromChunk] is kept
  /// for off-tree / legacy callers that skip the animation path.
  void confirmRemoval(int id, {required void Function(int id) evictFromChunk}) {
    if (!isMessageAbsent(id)) {
      evictFromChunk(id);
    }
    clearRemovalPending(id);
  }

  /// Notifies listeners that message [id] content changed and needs remeasure.
  void requestUpdate(int id, {Object? reason = 'stub'}) {
    final mutation = ChatMutation(ChatMutationKind.update, id, reason: reason);
    _logMutation('requestUpdate', mutation);
    _mutationsController.add(mutation);
  }

  /// Notifies listeners that message [id] was inserted and may animate in.
  void notifyInsert(int id, {Object? reason = 'stub'}) {
    final mutation = ChatMutation(ChatMutationKind.insert, id, reason: reason);
    _logMutation('notifyInsert', mutation);
    _mutationsController.add(mutation);
  }

  /// Release [pendingRemovalIds] and close [mutations]. Call from [dispose].
  void disposeMutations() {
    pendingRemovalIds.dispose();
    unawaited(_mutationsController.close());
  }
}
