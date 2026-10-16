import 'package:content_model/src/identity/inline_content_ref.dart';
import 'package:content_model/src/rich_text/entity.dart';
import 'package:content_model/src/rich_text/entity_kind.dart';
import 'package:content_model/src/rich_text/normalization.dart';
import 'package:content_model/src/value_equality.dart';
import 'package:meta/meta.dart';

/// Plain text plus the [Entity] spans that format and annotate it.
///
/// This is the neutral value a composer produces and a host stores, sends and
/// loads back for editing; it is not a widget. **It shares its name with
/// Flutter's `RichText` widget**, so a host file that imports both must hide
/// one: `import 'package:flutter/widgets.dart' hide RichText;`, or import this
/// package `as model`. The glossary term is _rich text_, and the name stays so
/// the value and the term read the same.
///
/// ## Invariants
///
/// A value is always canonical, so two texts that mean the same compare equal:
///
/// - Entities sit inside the text and never cut a surrogate pair. They may cut
///   a grapheme cluster (a ZWJ sequence), which is the host's concern.
/// - A quote covers whole lines. Every other non-atomic entity lies within one
///   line, and a text style (bold, italic, underline, strike, spoiler) starts
///   and ends on a non-whitespace character. Construction splits, trims and
///   widens to get there; an entity left with nothing to cover disappears.
/// - Entities of an equal kind that touch or overlap are one entity.
/// - Mentions and inline content are atomic: no other entity starts or ends
///   inside one, and two atomic entities never overlap.
/// - Code holds no other entity; it may sit inside bold, a link, a quote.
/// - Links never overlap each other or a mention.
/// - Entities are ordered by offset, longer first, then by kind.
///
/// Construction throws an [ArgumentError] when the entities cannot describe
/// the text under these rules, rather than guess what was meant.
///
/// ## Not here
///
/// How an entity looks, how a host maps a link target or mention id, and the
/// markdown form (`package:content_model/markdown.dart`) are outside this
/// value. It carries no body-level state: bodies stay markdown.
@immutable
final class RichText {
  /// Creates the text [plain] with [entities], canonicalised as described on
  /// [RichText]; throws an [ArgumentError] when they do not fit.
  factory RichText(String plain, [List<Entity> entities = const []]) {
    try {
      return RichText._canonical(plain, entities);
    } on EntityFitException catch (failure) {
      throw ArgumentError.value(entities, 'entities', failure.toString());
    }
  }

  /// Creates the text [plain] with no entities.
  const RichText.plain(this.plain) : entities = const [];

  const RichText._(this.plain, this.entities);

  factory RichText._canonical(String plain, List<Entity> entities) =>
      entities.isEmpty
      ? RichText._(plain, const [])
      : RichText._(
          plain,
          List.unmodifiable(canonicalEntities(plain, entities)),
        );

  /// The text [json] describes, as written by [toJson].
  ///
  /// Meant for drafts and other stored values, so it is strict about the shape
  /// but forgiving about the future: an entity of a kind this version does not
  /// know is skipped and the text loads without that formatting.
  ///
  /// Throws a [FormatException] when [json] is not the output of [toJson], or
  /// when its entities do not fit its text. Use [tryFromJson] for data that
  /// may be damaged.
  factory RichText.fromJson(Object? json) {
    if (json is! Map<Object?, Object?>) {
      throw FormatException('Rich text must be a JSON object.', json);
    }
    final text = json['text'];
    if (text is! String) {
      throw FormatException('Rich text needs a string "text".', json);
    }
    final items = switch (json['entities']) {
      null => const <Object?>[],
      final List<Object?> list => list,
      final other => throw FormatException('"entities" must be a list.', other),
    };
    final entities = <Entity>[for (final item in items) ?Entity.fromJson(item)];
    try {
      return RichText._canonical(text, entities);
    } on EntityFitException catch (failure) {
      throw FormatException('The entities do not fit the text: $failure', json);
    }
  }

  /// The empty text.
  static const RichText empty = RichText.plain('');

  /// The text [json] describes, or null when [fromJson] would throw.
  static RichText? tryFromJson(Object? json) {
    try {
      return RichText.fromJson(json);
    } on FormatException {
      return null;
    }
  }

  /// The text without markup.
  final String plain;

  /// The canonical, unmodifiable entities; see the invariants on [RichText].
  final List<Entity> entities;

  /// The number of UTF-16 code units in [plain].
  int get length => plain.length;

  /// Whether [plain] is empty.
  bool get isEmpty => plain.isEmpty;

  /// The part of [plain] [entity] covers.
  ///
  /// [entity] must come from this text.
  String textOf(Entity entity) => plain.substring(entity.offset, entity.end);

  /// The content reference [entity] stands for, or null when it is not inline
  /// content. The span is the reference's plain-text alternative.
  InlineContentRef? inlineContentOf(Entity entity) => switch (entity.kind) {
    EntityKind$InlineContent(:final key) => InlineContentRef(
      key: key,
      alternativeText: textOf(entity),
    ),
    _ => null,
  };

  /// This text as JSON-encodable data: `text`, and `entities` (see
  /// [Entity.toJson]) when there are any. [RichText.fromJson] reads it back.
  Map<String, Object?> toJson() => {
    'text': plain,
    if (entities.isNotEmpty)
      'entities': [for (final entity in entities) entity.toJson()],
  };

  // --- Editing ---

  /// The part of this text from [start] to [end], with the entities clipped to
  /// it.
  ///
  /// An atomic entity survives only when the range holds all of it. Throws a
  /// [RangeError] for a range outside the text and an [ArgumentError] for an
  /// end that falls inside a surrogate pair.
  RichText slice(int start, int end) {
    _checkRange(start, end);
    return RichText(plain.substring(start, end), [
      for (final entity in entities)
        if (entity.end > start && entity.offset < end)
          if (!entity.kind.isAtomic ||
              (entity.offset >= start && entity.end <= end))
            Entity(
              entity.offset > start ? entity.offset - start : 0,
              (entity.end < end ? entity.end : end) -
                  (entity.offset > start ? entity.offset : start),
              entity.kind,
            ),
    ]);
  }

  /// This text with the range from [start] to [end] replaced by
  /// [replacement], keeping the entities consistent with the edit.
  ///
  /// How an existing entity follows the edit:
  ///
  /// - Entirely before the range: unchanged. Entirely after: shifted.
  /// - Around the range: it grows or shrinks with the text inside it. An
  ///   insertion strictly inside grows it; an insertion at its edge does not
  ///   extend it, so typing next to a styled run starts unstyled text. A host
  ///   that wants the style to continue passes a [replacement] carrying it:
  ///   equal kinds that touch merge.
  /// - Overlapping one end of the range: it keeps the part outside the range.
  /// - Inside the range: it is removed.
  /// - Atomic (mention, inline content) and touched by the range in any way
  ///   other than at its edge: it is removed, because the text no longer
  ///   says what it did. The remaining text stays.
  ///
  /// The entities of [replacement] are added at [start]; the result is then
  /// canonicalised, so it throws an [ArgumentError] if they cannot coexist
  /// with the surrounding entities (for example a style inside code). Throws a
  /// [RangeError] for a range outside the text and an [ArgumentError] for an
  /// edge inside a surrogate pair.
  RichText replaceRange(int start, int end, RichText replacement) {
    _checkRange(start, end);
    final inserted = replacement.length;
    final delta = inserted - (end - start);
    final next = <Entity>[];
    for (final entity in entities) {
      if (entity.end <= start) {
        next.add(entity);
      } else if (entity.offset >= end) {
        next.add(Entity(entity.offset + delta, entity.length, entity.kind));
      } else if (!entity.kind.isAtomic) {
        final keepsLeft = entity.offset < start;
        final keepsRight = entity.end > end;
        if (keepsLeft && keepsRight) {
          next.add(Entity(entity.offset, entity.length + delta, entity.kind));
        } else if (keepsLeft) {
          next.add(Entity(entity.offset, start - entity.offset, entity.kind));
        } else if (keepsRight) {
          next.add(Entity(start + inserted, entity.end - end, entity.kind));
        }
      }
    }
    for (final entity in replacement.entities) {
      next.add(Entity(entity.offset + start, entity.length, entity.kind));
    }
    return RichText(plain.replaceRange(start, end, replacement.plain), next);
  }

  /// This text with [inserted] added at [offset]; see [replaceRange].
  RichText insert(int offset, RichText inserted) =>
      replaceRange(offset, offset, inserted);

  /// This text without the range from [start] to [end]; see [replaceRange].
  RichText delete(int start, int end) =>
      replaceRange(start, end, RichText.empty);

  void _checkRange(int start, int end) {
    RangeError.checkValidRange(start, end, plain.length);
    if (splitsSurrogatePair(plain, start) || splitsSurrogatePair(plain, end)) {
      throw ArgumentError(
        'The range $start..$end cuts a surrogate pair in "$plain".',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is RichText &&
      other.plain == plain &&
      ValueEquality.lists(other.entities, entities);

  @override
  int get hashCode => Object.hash(plain, Object.hashAll(entities));

  @override
  String toString() => 'RichText($plain, $entities)';
}
