import 'package:chat_outbox/src/ids/outgoing_id_strategy.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';

/// A row of a [FakeOutgoingTail]: outgoing while [clientMessageId] is set,
/// confirmed when it is null.
final class FakeTailMessage implements IChatMessage {
  /// A row inserted at [id].
  FakeTailMessage(this.id, [this.clientMessageId]);

  @override
  final int id;

  /// The identity of an outgoing row; null for a confirmed message.
  final String? clientMessageId;

  @override
  String get sender => clientMessageId == null ? 'peer' : 'me';

  @override
  DateTime get createdAt => DateTime.utc(2026);

  @override
  DateTime get updatedAt => DateTime.utc(2026);

  @override
  String toString() => 'FakeTailMessage($id, $clientMessageId)';
}

/// One `rebaseTail` a [FakeOutgoingTail] took: the order and the inserted
/// messages' ids.
typedef FakeTailRebase = ({List<Object> order, List<int> inserted});

/// An in-memory [OutgoingTailTarget]: confirmed history up to a tip, then the
/// provisional rows, with the moves a strategy made.
///
/// It keeps the data source's rules that a strategy relies on: the
/// provisional tail is the run of rows down from the newest one whose
/// [FakeTailMessage.clientMessageId] is set; a move takes a new order of
/// exactly those identities (a left-out one leaves) and inserts confirmed
/// messages at or after the tail's first position, the rows following the
/// last insert. A move that breaks a rule throws a [StateError] and changes
/// nothing, so a contract test fails where a data source would refuse.
final class FakeOutgoingTail implements OutgoingTailTarget {
  /// A chat whose newest confirmed message is [tip].
  FakeOutgoingTail({int tip = 100}) : _$newest = tip {
    _$slots[tip] = FakeTailMessage(tip);
  }

  final Map<int, IChatMessage> _$slots = {};
  int _$newest;

  /// Every move taken, oldest first.
  final List<FakeTailRebase> rebases = [];

  /// Every row inserted, oldest first.
  final List<IChatMessage> inserted = [];

  /// The ids of the rows inserted with no self-insert follow (restored
  /// rows), oldest first.
  final List<int> insertedWithoutFollow = [];

  /// The id of the newest row.
  int get newest => _$newest;

  @override
  int get nextInsertId => _$newest + 1;

  /// The row at [id], or null.
  IChatMessage? at(int id) => _$slots[id];

  /// The identity of the row at [id]: its client message id, `confirmed` for
  /// a confirmed message, or null when there is none.
  String? identityAt(int id) => switch (_$slots[id]) {
    FakeTailMessage(:final clientMessageId?) => clientMessageId,
    null => null,
    _ => 'confirmed',
  };

  /// The provisional tail's identities in order, lowest position first.
  List<String> get provisional => [
    for (final id in _tailPositions()) identityAt(id)!,
  ];

  /// The provisional tail's first position, or the position after the
  /// newest row when there is none.
  int get tailStart => switch (_tailPositions()) {
    [final first, ...] => first,
    _ => _$newest + 1,
  };

  @override
  int? positionOf(Object identity) {
    for (final id in _tailPositions()) {
      if (identityAt(id) == identity) return id;
    }
    return null;
  }

  /// Replaces the row at its id, as a host's `updateMessage` does when it
  /// confirms an outgoing row.
  void update(IChatMessage message) {
    if (!_$slots.containsKey(message.id)) {
      throw StateError('update: no row at ${message.id}');
    }
    _$slots[message.id] = message;
  }

  /// Writes a confirmed message into an empty slot below the tail, as a
  /// range fetch or a host placing a message it learned of does.
  void place(IChatMessage message) {
    if (message.id >= tailStart || _$slots[message.id] != null) {
      throw StateError(
        'place: ${message.id} is not an empty slot below the tail',
      );
    }
    _$slots[message.id] = message;
  }

  /// Inserts a new row; [followSelf] false inserts it as a restored row,
  /// which a reader scrolled up is not pulled down to.
  @override
  void insertMessage(IChatMessage message, {bool followSelf = true}) {
    if (message.id <= _$newest) {
      throw StateError(
        'insertMessage: ${message.id} is not after the newest ${_$newest}',
      );
    }
    _$slots[message.id] = message;
    _$newest = message.id;
    inserted.add(message);
    if (!followSelf) insertedWithoutFollow.add(message.id);
  }

  @override
  void rebaseTail({
    required List<Object> order,
    List<IChatMessage> insert = const [],
  }) {
    final positions = _tailPositions();
    final start = tailStart;
    final byIdentity = {for (final id in positions) identityAt(id)!: id};
    if (order.toSet().length != order.length) {
      throw StateError('rebaseTail: a duplicate identity in $order');
    }
    for (final key in order) {
      if (!byIdentity.containsKey(key)) {
        throw StateError('rebaseTail: $key is not provisional');
      }
    }
    final inserts = [...insert]..sort((a, b) => a.id.compareTo(b.id));
    for (final message in inserts) {
      if (message case FakeTailMessage(clientMessageId: _?)) {
        throw StateError('rebaseTail: insert ${message.id} is provisional');
      }
      if (message.id < start) {
        throw StateError('rebaseTail: insert ${message.id} is below $start');
      }
    }

    final rows = [for (final key in order) _$slots[byIdentity[key]]!];
    positions.forEach(_$slots.remove);
    for (final message in inserts) {
      _$slots[message.id] = message;
    }
    final rowsStart = switch (inserts) {
      [..., final last] when last.id + 1 > start => last.id + 1,
      _ => start,
    };
    for (var i = 0; i < rows.length; i++) {
      _$slots[rowsStart + i] = rows[i];
    }
    _$newest = switch ((rows, inserts)) {
      ([_, ...], _) => rowsStart + rows.length - 1,
      ([], [..., final last]) => last.id,
      _ => start - 1,
    };
    rebases.add((
      order: List.unmodifiable(order),
      inserted: List.unmodifiable([for (final message in inserts) message.id]),
    ));
  }

  List<int> _tailPositions() {
    final positions = <int>[];
    for (var id = _$newest; ; id--) {
      if (_$slots[id] case FakeTailMessage(clientMessageId: _?)) {
        positions.add(id);
      } else {
        break;
      }
    }
    return positions.reversed.toList();
  }
}
