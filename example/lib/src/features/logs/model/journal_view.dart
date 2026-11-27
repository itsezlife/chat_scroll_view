import 'package:chat_scroll_view_example/src/features/logs/model/journal_record.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';

/// One correlation id a filter can hold: the [ChatCorrelation] fields, by
/// name.
enum JournalIdKind {
  /// The chat.
  chatId,

  /// The engine's id of a message.
  scrollId,

  /// An outgoing message's client id.
  clientMessageId,

  /// A media item of a message.
  mediaItemId,

  /// The media key of an item's content.
  mediaKey,

  /// A publish or save job.
  jobId;

  /// The id of this kind in [correlation], or null.
  String? of(ChatCorrelation correlation) => switch (this) {
    chatId => correlation.chatId,
    scrollId => correlation.scrollId,
    clientMessageId => correlation.clientMessageId,
    mediaItemId => correlation.mediaItemId,
    mediaKey => correlation.mediaKey,
    jobId => correlation.jobId,
  };
}

/// Which records the journal shows: enabled [levels], the [categories] (every
/// one when null) and the correlation [ids] a record must carry, every one.
@immutable
final class JournalFilter {
  /// A filter.
  JournalFilter({
    required Set<ChatEventLevel> levels,
    Set<String>? categories,
    Map<JournalIdKind, String> ids = const {},
  }) : levels = Set.unmodifiable(levels),
       categories = switch (categories) {
         final categories? => Set.unmodifiable(categories),
         null => null,
       },
       ids = Map.unmodifiable(ids);

  /// Every level and category, no id.
  factory JournalFilter.all() =>
      JournalFilter(levels: ChatEventLevel.values.toSet());

  /// The records of the message with [scrollId], every level and category:
  /// "logs of this message".
  factory JournalFilter.ofMessage(String scrollId) => JournalFilter(
    levels: ChatEventLevel.values.toSet(),
    ids: {JournalIdKind.scrollId: scrollId},
  );

  /// Levels that pass.
  final Set<ChatEventLevel> levels;

  /// Categories that pass, by name; null passes every one.
  final Set<String>? categories;

  /// Ids a record must carry.
  final Map<JournalIdKind, String> ids;

  /// Whether [record] passes every part.
  bool accepts(JournalRecord record) =>
      levels.contains(record.level) && matchesBesidesLevel(record);

  /// Whether [record] passes the categories and the ids, whatever its level,
  /// so the level chips can count what each level would add.
  bool matchesBesidesLevel(JournalRecord record) =>
      (categories?.contains(record.category) ?? true) &&
      ids.entries.every(
        (entry) => entry.key.of(record.correlation) == entry.value,
      );

  /// [level] turned off when on, on when off.
  JournalFilter toggleLevel(ChatEventLevel level) => _with(
    levels: levels.contains(level)
        ? ({...levels}..remove(level))
        : {...levels, level},
  );

  /// Only [level]; every level again when it is already the only one.
  JournalFilter soloLevel(ChatEventLevel level) => _with(
    levels: levels.length == 1 && levels.contains(level)
        ? ChatEventLevel.values.toSet()
        : {level},
  );

  /// Only [category]; every category again when it is already the only one.
  JournalFilter soloCategory(String category) => JournalFilter(
    levels: levels,
    categories: switch (categories) {
      final only? when only.length == 1 && only.contains(category) => null,
      _ => {category},
    },
    ids: ids,
  );

  /// [kind] set to [id], or dropped when [id] is blank.
  JournalFilter withId(JournalIdKind kind, String id) => _with(
    ids: switch (id.trim()) {
      '' => {...ids}..remove(kind),
      final id => {...ids, kind: id},
    },
  );

  JournalFilter _with({
    Set<ChatEventLevel>? levels,
    Map<JournalIdKind, String>? ids,
  }) => JournalFilter(
    levels: levels ?? this.levels,
    categories: categories,
    ids: ids ?? this.ids,
  );

  /// The filter as plain values, for an export's header.
  Map<String, Object> toJson() => {
    'levels': [for (final level in levels) level.name],
    'categories': ?categories?.toList(),
    'ids': {for (final MapEntry(:key, :value) in ids.entries) key.name: value},
  };
}

/// The journal's view of its records under a [JournalFilter].
@immutable
final class JournalSnapshot {
  const JournalSnapshot._({
    required this.visible,
    required this.total,
    required this.categories,
    required Map<ChatEventLevel, int> countByLevel,
  }) : _countByLevel = countByLevel;

  /// Projects [records] (oldest first, as the journal holds them) through
  /// [filter].
  factory JournalSnapshot.of(
    Iterable<JournalRecord> records,
    JournalFilter filter,
  ) {
    final visible = <JournalRecord>[];
    final countByLevel = <ChatEventLevel, int>{};
    final categories = <String>{};
    var total = 0;
    for (final record in records) {
      total++;
      categories.add(record.category);
      if (!filter.matchesBesidesLevel(record)) continue;
      countByLevel.update(record.level, (n) => n + 1, ifAbsent: () => 1);
      if (filter.levels.contains(record.level)) visible.add(record);
    }
    return JournalSnapshot._(
      visible: List.unmodifiable(visible.reversed),
      total: total,
      categories: List.unmodifiable(categories.toList()..sort()),
      countByLevel: Map.unmodifiable(countByLevel),
    );
  }

  /// Records that pass the filter, newest first.
  final List<JournalRecord> visible;

  /// Records before filtering.
  final int total;

  /// The categories of every record, by name, sorted.
  final List<String> categories;

  final Map<ChatEventLevel, int> _countByLevel;

  /// Records of [level] that pass the rest of the filter, whether or not
  /// [level] is on.
  int countOf(ChatEventLevel level) => _countByLevel[level] ?? 0;
}
