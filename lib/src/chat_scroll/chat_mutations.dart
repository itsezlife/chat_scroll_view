import 'package:meta/meta.dart';

/// Integrator intent delivered to [ChatDataSource.addMutationListener].
///
/// Fetch, prefetch, invalidate, and silent [ChatDataSource.upsertMessage] /
/// [ChatDataSource.upsertMessages] **never** produce a [ChatMutation].
@immutable
sealed class ChatMutation {
  /// Shared optional debug label (`demo`, `local-edit`, …).
  const ChatMutation({required this.operationId, this.reason});

  /// Records a tail or in-span insert via [ChatDataSource.insertMessage].
  factory ChatMutation.insert(int messageId, {Object? reason}) =>
      InsertMutation(messageId: messageId, reason: reason);

  /// Records a bulk insert via [ChatDataSource.insertMessages].
  factory ChatMutation.insertBatch({
    required List<int> ids,
    required int operationId,
    Object? reason,
  }) => InsertBatchMutation(ids: ids, operationId: operationId, reason: reason);

  /// Records a content replace via [ChatDataSource.updateMessage].
  factory ChatMutation.update(int messageId, {Object? reason}) =>
      UpdateMutation(messageId: messageId, reason: reason);

  /// Records a bulk content replace via [ChatDataSource.updateMessages].
  factory ChatMutation.updateBatch({
    required List<int> ids,
    required int operationId,
    Object? reason,
  }) => UpdateBatchMutation(ids: ids, operationId: operationId, reason: reason);

  /// Records a staged batch remove via [ChatDataSource.removeMessages].
  factory ChatMutation.removeBatch({
    required List<int> ids,
    required int operationId,
    Object? reason,
  }) => RemoveBatchMutation(ids: ids, operationId: operationId, reason: reason);

  /// Records a move of the provisional tail via [ChatDataSource.rebaseTail].
  factory ChatMutation.rebaseTail({
    required List<int> insertedIds,
    required Map<int, int> moved,
    required List<int> removedIds,
    required int operationId,
    Object? reason,
  }) => RebaseTailMutation(
    insertedIds: insertedIds,
    moved: moved,
    removedIds: removedIds,
    operationId: operationId,
    reason: reason,
  );

  /// Optional debug label for tracing integrator paths.
  final Object? reason;

  /// Monotonic operation id grouping this batch remove.
  final int operationId;
}

/// A new message was added via [ChatDataSource.insertMessage].
@immutable
final class InsertMutation extends ChatMutation {
  /// Creates an insert intent for [messageId].
  const InsertMutation({required this.messageId, super.reason})
    : super(operationId: messageId);

  /// Id of the inserted message.
  final int messageId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is InsertMutation &&
        other.messageId == messageId &&
        other.operationId == operationId &&
        other.reason == reason;
  }

  @override
  int get hashCode => Object.hash(messageId, operationId, reason);

  @override
  String toString() =>
      'InsertMutation(messageId: $messageId, operationId: $operationId, reason: $reason)';
}

/// One or more messages were added via [ChatDataSource.insertMessages].
@immutable
final class InsertBatchMutation extends ChatMutation {
  /// Creates a batch insert intent.
  ///
  /// [ids] MUST be strictly unique and sorted **ascending** (lowest id first).
  /// [operationId] is shared by every id in one `insertMessages` call.
  const InsertBatchMutation({
    required this.ids,
    required super.operationId,
    super.reason,
  });

  /// Affected ids in ascending order (oldest / lowest id first).
  final List<int> ids;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is InsertBatchMutation &&
        other.ids == ids &&
        other.operationId == operationId &&
        other.reason == reason;
  }

  @override
  int get hashCode => Object.hash(ids, operationId, reason);

  @override
  String toString() =>
      'InsertBatchMutation(ids: $ids, operationId: $operationId, reason: $reason)';
}

/// An existing message was replaced via [ChatDataSource.updateMessage].
@immutable
final class UpdateMutation extends ChatMutation {
  /// Creates an update intent for [messageId].
  const UpdateMutation({required this.messageId, super.reason})
    : super(operationId: messageId);

  /// Id of the updated message.
  final int messageId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UpdateMutation &&
        other.messageId == messageId &&
        other.operationId == operationId &&
        other.reason == reason;
  }

  @override
  int get hashCode => Object.hash(messageId, operationId, reason);

  @override
  String toString() =>
      'UpdateMutation(messageId: $messageId, operationId: $operationId, reason: $reason)';
}

/// One or more messages were replaced via [ChatDataSource.updateMessages].
@immutable
final class UpdateBatchMutation extends ChatMutation {
  /// Creates a batch update intent.
  ///
  /// [ids] MUST be strictly unique and sorted **ascending** (lowest id first).
  /// [operationId] is shared by every id in one `updateMessages` call.
  const UpdateBatchMutation({
    required this.ids,
    required super.operationId,
    super.reason,
  });

  /// Affected ids in ascending order (oldest / lowest id first).
  final List<int> ids;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UpdateBatchMutation &&
        other.ids == ids &&
        other.operationId == operationId &&
        other.reason == reason;
  }

  @override
  int get hashCode => Object.hash(ids, operationId, reason);

  @override
  String toString() =>
      'UpdateBatchMutation(ids: $ids, operationId: $operationId, reason: $reason)';
}

/// One or more ids staged for removal via [ChatDataSource.removeMessages].
@immutable
final class RemoveBatchMutation extends ChatMutation {
  /// Creates a batch remove intent.
  ///
  /// [ids] MUST be strictly unique and sorted **descending** (highest id first).
  /// [operationId] is shared by every id in one `removeMessages` call.
  const RemoveBatchMutation({
    required this.ids,
    required super.operationId,
    super.reason,
  });

  /// Affected ids in descending order (newest / highest id first).
  final List<int> ids;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RemoveBatchMutation &&
        other.ids == ids &&
        other.operationId == operationId &&
        other.reason == reason;
  }

  @override
  int get hashCode => Object.hash(ids, operationId, reason);

  @override
  String toString() =>
      'RemoveBatchMutation(ids: $ids, operationId: $operationId, reason: $reason)';
}

/// The provisional tail moved via [ChatDataSource.rebaseTail]: its rows took
/// new positions, confirmed messages were inserted before them, and rows left
/// out of the new order left the tail.
///
/// Neither an insert nor a removal: the viewport does not pull a reader
/// scrolled into history to the tail for it (the self-insert follow) and does
/// not cancel a navigation animation that holds a moved position. Delivered
/// after the write, so a listener reads the new rows.
@immutable
final class RebaseTailMutation extends ChatMutation {
  /// Creates a tail move.
  ///
  /// [insertedIds] MUST be strictly unique and sorted **ascending**.
  /// [removedIds] are the positions the left-out rows held before the move,
  /// ascending.
  const RebaseTailMutation({
    required this.insertedIds,
    required this.moved,
    required this.removedIds,
    required super.operationId,
    super.reason,
  });

  /// Ids of the confirmed messages inserted before the tail, ascending.
  final List<int> insertedIds;

  /// Old position to new position of every provisional row whose position
  /// changed. A row that kept its position is not listed.
  final Map<int, int> moved;

  /// Positions held before the move by the rows left out of the new order,
  /// ascending.
  final List<int> removedIds;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RebaseTailMutation &&
        other.insertedIds == insertedIds &&
        other.moved == moved &&
        other.removedIds == removedIds &&
        other.operationId == operationId &&
        other.reason == reason;
  }

  @override
  int get hashCode =>
      Object.hash(insertedIds, moved, removedIds, operationId, reason);

  @override
  String toString() =>
      'RebaseTailMutation(insertedIds: $insertedIds, moved: $moved, '
      'removedIds: $removedIds, operationId: $operationId, reason: $reason)';
}
