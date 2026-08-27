import 'package:message_media/src/grouped_message_position.dart';
import 'package:message_media/src/grouped_messages.dart';
import 'package:message_media/src/media_kind.dart';
import 'package:message_media/src/media_layout_metrics.dart';

/// One present message’s contribution to a [GroupedMessagesMap] entry.
///
/// Owns: Message ID, aspect, optional caption text / flags for calculate.
/// Does not own: bytes, image-receiver state, or chat-list presence.
///
/// [messageId] MUST be unique within the map. [aspectRatio] ≤ 0 is coerced to
/// `1.0` inside [GroupedMessages.calculate] like [GroupedMediaMember].
final class GroupedMapMember {
  /// Creates a map member keyed by [messageId].
  const GroupedMapMember({
    required this.messageId,
    required this.aspectRatio,
    this.kind = MediaKind.photo,
    this.hasCaption = false,
    this.invertMedia = false,
    this.captionText,
  });

  /// Present Message ID (ADR 001 `int`); immutable identity of this group row.
  final int messageId;

  /// Width / height of the thumb used for mosaic proportions.
  final double aspectRatio;

  /// Photo vs video — ignored for mosaic geometry (shared box).
  final MediaKind kind;

  /// When true, participates in caption-index selection during calculate.
  final bool hasCaption;

  /// When true, forces [GroupedMessages.captionAbove] for the group.
  final bool invertMedia;

  /// Plain caption string when this member owns the group caption.
  ///
  /// Entities / spoilers are out of scope. Empty or null text with
  /// [hasCaption] still affects calculate’s caption index rules.
  final String? captionText;

  /// Converts to the calculate input (drops Message ID / text).
  GroupedMediaMember toMediaMember() => GroupedMediaMember(
    aspectRatio: aspectRatio,
    kind: kind,
    hasCaption: hasCaption,
    invertMedia: invertMedia,
  );
}

/// Snapshot of one `groupId` after the latest recalculation.
///
/// Owns: ordered [messageIds], matching [messages] positions / caption
/// summary, and optional plain [captionText] for the sole caption owner.
/// Does not own: map lifecycle or pixel projection.
final class GroupedMessagesEntry {
  /// Creates an entry from ordered members and a calculate result.
  const GroupedMessagesEntry({
    required this.groupId,
    required this.messageIds,
    required this.messages,
    this.captionText,
  });

  /// Telegram `grouped_id` / host album key for this set.
  final int groupId;

  /// Message IDs in insertion / group order (same order as [messages.positions]).
  final List<int> messageIds;

  /// Latest [GroupedMessages.calculate] result for these members.
  final GroupedMessages messages;

  /// Plain text from the sole caption-owning member when
  /// [GroupedMessages.captionIndex] is non-null; otherwise `null`.
  final String? captionText;

  /// Message ID of the sole caption owner ([GroupedMessages.captionIndex]),
  /// mirroring Java `captionMessage` identity; `null` when there is no sole
  /// owner.
  int? get captionMessageId {
    if (messages.captionIndex case final index?
        when index >= 0 && index < messageIds.length) {
      return messageIds[index];
    }
    return null;
  }

  /// Position for [messageId], or `null` when that id is not in this entry.
  GroupedMessagePosition? positionFor(int messageId) {
    final index = messageIds.indexOf(messageId);
    if (index < 0 || index >= messages.positions.length) {
      return null;
    }
    return messages.positions[index];
  }
}

/// Per-chat (per-dialog) index of `groupId` → grouped messages + positions.
///
/// Mirrors Telegram `ChatActivity.groupedMessagesMap`: constructed and
/// [dispose]d with the chat surface. Not a process-wide singleton and not part
/// of `ChatDataSource` — the host feeds this map when messages with a
/// `groupId` enter, leave, or change aspect / caption flags.
///
/// ## Ownership
///
/// Owns: member lists per `groupId`, recalculated [GroupedMessages], Message ID
/// → `groupId` lookup. Does not own: chunk/presence, neighbor policy, pixel
/// mosaic projection, or inbox last-message group lists.
///
/// ## Recalculation
///
/// Every [put], [remove], or [update] that changes a group’s membership or a
/// member’s layout inputs re-runs [GroupedMessages.calculate] for that
/// `groupId`. Groups with fewer than two members have no calculate result
/// ([group] returns `null`); a lone remaining member is still indexed so a
/// later sibling can form a mosaic.
///
/// ## Dispose
///
/// [dispose] clears all entries. After dispose, [put] / [remove] / [update]
/// are silent no-ops; queries return `null`.
///
/// ## Edge modes
///
/// - Moving a Message ID to a different [groupId] via [put] removes it from
///   the previous group and recalculates both sides.
/// - [remove] of the last member drops the `groupId` entry entirely.
/// - Duplicate [put] for the same Message ID replaces that member in place
///   (order preserved) and recalculates.
final class GroupedMessagesMap {
  /// Creates an empty per-chat map.
  ///
  /// [isOut] / [needShare] / [displayMinSide] are forwarded to every
  /// [GroupedMessages.calculate] pass for groups in this chat.
  GroupedMessagesMap({
    this.isOut = false,
    this.needShare = false,
    this.displayMinSide = MediaLayoutMetrics.referenceDisplayMinSide,
  });

  /// Outgoing vs incoming edge / span finish for calculate.
  final bool isOut;

  /// Share-button gutter shrink for calculate.
  final bool needShare;

  /// Display min-side rescale for `minWidth` / paddings (default 360).
  final double displayMinSide;

  final Map<int, _GroupBucket> _byGroup = {};
  final Map<int, int> _groupIdByMessage = {};
  bool _disposed = false;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  /// Snapshot for [groupId], or `null` when unknown, disposed, or fewer than
  /// two members (no mosaic yet).
  GroupedMessagesEntry? group(int groupId) {
    if (_disposed) {
      return null;
    }
    final bucket = _byGroup[groupId];
    if (bucket == null || bucket.members.length < 2) {
      return null;
    }
    return bucket.toEntry(groupId);
  }

  /// `groupId` owning [messageId], or `null` when unknown / disposed.
  int? groupIdFor(int messageId) {
    if (_disposed) {
      return null;
    }
    return _groupIdByMessage[messageId];
  }

  /// Position for [messageId] when its group has a mosaic (≥2 members).
  GroupedMessagePosition? positionFor(int messageId) {
    final groupId = groupIdFor(messageId);
    if (groupId == null) {
      return null;
    }
    return group(groupId)?.positionFor(messageId);
  }

  /// Inserts or replaces [member] under [groupId] and recalculates.
  ///
  /// Silent no-op after [dispose]. If [member.messageId] was under another
  /// `groupId`, it is removed there first.
  void put({required int groupId, required GroupedMapMember member}) {
    if (_disposed) {
      return;
    }

    final previousGroupId = _groupIdByMessage[member.messageId];
    if (previousGroupId != null && previousGroupId != groupId) {
      _removeFromBucket(previousGroupId, member.messageId);
      _recalculate(previousGroupId);
    }

    final bucket = _byGroup.putIfAbsent(groupId, _GroupBucket.new);
    final existing = bucket.indexOf(member.messageId);
    if (existing >= 0) {
      bucket.members[existing] = member;
    } else {
      bucket.members.add(member);
    }
    _groupIdByMessage[member.messageId] = groupId;
    _recalculate(groupId);
  }

  /// Removes [messageId] from its group and recalculates (or drops the group).
  ///
  /// Silent no-op when unknown or after [dispose].
  void remove(int messageId) {
    if (_disposed) {
      return;
    }
    final groupId = _groupIdByMessage.remove(messageId);
    if (groupId == null) {
      return;
    }
    _removeFromBucket(groupId, messageId);
    _recalculate(groupId);
  }

  /// Patches layout inputs for an existing [messageId] and recalculates.
  ///
  /// Silent no-op when unknown or after [dispose]. Omitted fields keep their
  /// previous values. Passing [clearCaptionText] `true` sets caption text to
  /// `null` even when [captionText] is omitted.
  void update(
    int messageId, {
    double? aspectRatio,
    MediaKind? kind,
    bool? hasCaption,
    bool? invertMedia,
    String? captionText,
    bool clearCaptionText = false,
  }) {
    if (_disposed) {
      return;
    }
    final groupId = _groupIdByMessage[messageId];
    if (groupId == null) {
      return;
    }
    final bucket = _byGroup[groupId];
    if (bucket == null) {
      return;
    }
    final index = bucket.indexOf(messageId);
    if (index < 0) {
      return;
    }
    final old = bucket.members[index];
    bucket.members[index] = GroupedMapMember(
      messageId: messageId,
      aspectRatio: aspectRatio ?? old.aspectRatio,
      kind: kind ?? old.kind,
      hasCaption: hasCaption ?? old.hasCaption,
      invertMedia: invertMedia ?? old.invertMedia,
      captionText: clearCaptionText ? null : (captionText ?? old.captionText),
    );
    _recalculate(groupId);
  }

  /// Clears all entries. Further mutations are silent no-ops.
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _byGroup.clear();
    _groupIdByMessage.clear();
  }

  void _removeFromBucket(int groupId, int messageId) {
    final bucket = _byGroup[groupId];
    if (bucket == null) {
      return;
    }
    bucket.members.removeWhere((m) => m.messageId == messageId);
    if (bucket.members.isEmpty) {
      _byGroup.remove(groupId);
    }
  }

  void _recalculate(int groupId) {
    final bucket = _byGroup[groupId];
    if (bucket == null) {
      return;
    }
    if (bucket.members.length < 2) {
      bucket.messages = null;
      return;
    }
    bucket.messages = GroupedMessages.calculate(
      members: [for (final m in bucket.members) m.toMediaMember()],
      isOut: isOut,
      needShare: needShare,
      displayMinSide: displayMinSide,
    );
  }
}

/// Mutable member list + last calculate result for one `groupId`.
final class _GroupBucket {
  final List<GroupedMapMember> members = [];
  GroupedMessages? messages;

  int indexOf(int messageId) {
    for (var i = 0; i < members.length; i++) {
      if (members[i].messageId == messageId) {
        return i;
      }
    }
    return -1;
  }

  GroupedMessagesEntry toEntry(int groupId) {
    if (messages case final calculated?) {
      String? captionText;
      if (calculated.captionIndex case final index?
          when index >= 0 && index < members.length) {
        captionText = members[index].captionText;
      }
      return GroupedMessagesEntry(
        groupId: groupId,
        messageIds: [for (final m in members) m.messageId],
        messages: calculated,
        captionText: captionText,
      );
    }
    throw StateError('toEntry requires a calculated mosaic');
  }
}
