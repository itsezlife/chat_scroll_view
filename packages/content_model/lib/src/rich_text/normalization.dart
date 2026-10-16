import 'package:content_model/src/rich_text/entity.dart';
import 'package:content_model/src/rich_text/entity_kind.dart';

/// The reason a list of entities cannot describe a text.
///
/// Internal: [RichText] reports it as an [ArgumentError] when constructed in
/// code and as a [FormatException] when read from data.
final class EntityFitException implements Exception {
  /// Creates the failure with [message], about [entity] when one is to blame.
  EntityFitException(this.message, [this.entity]);

  /// What is wrong.
  final String message;

  /// The offending entity, when there is one.
  final Entity? entity;

  @override
  String toString() => entity == null ? message : '$entity: $message';
}

/// The canonical entity list for [plain], or an [EntityFitException] when
/// [input] cannot describe it.
///
/// Canonical means one list per meaning, so equal texts compare equal:
///
/// 1. Each entity is checked against the text (range, surrogate pairs,
///    payload, line breaks in atomic spans).
/// 2. A quote widens to whole lines; every other non-atomic entity splits at
///    line breaks, because markup cannot carry a span across one.
/// 3. A text style (bold, italic, underline, strike, spoiler) gives up the
///    whitespace at its edges, because markup cannot open or close next to
///    whitespace; one over whitespace only disappears.
/// 4. Equal kinds that touch or overlap merge into one entity.
/// 5. The list is ordered by offset, longer first, then by kind.
/// 6. The combination is checked: see [RichText] for the exclusivity rules.
List<Entity> canonicalEntities(String plain, Iterable<Entity> input) {
  final shaped = <Entity>[];
  final textStyles = <Entity>[];
  for (final entity in input) {
    _check(plain, entity);
    if (_isTextStyle(entity.kind)) {
      textStyles.add(entity);
    } else {
      _shape(plain, entity, shaped);
    }
  }
  // Trimming must leave the whitespace that sits inside code or an atomic
  // entity, or the style would end inside it.
  final guarded = [
    for (final entity in shaped)
      if (entity.kind.isAtomic || entity.kind == EntityKind.code) entity,
  ];
  for (final entity in textStyles) {
    _splitAtLineBreaks(plain, entity, shaped, guarded: guarded);
  }
  final merged = _merge(shaped)..sort(_compare);
  _checkCombinations(merged);
  return merged;
}

/// Whether [unit] is a Unicode whitespace code unit as markup flanking rules
/// see it: ASCII whitespace plus the space separators (Zs).
bool isWhitespaceUnit(int unit) =>
    unit == 0x20 ||
    (unit >= 0x09 && unit <= 0x0D) ||
    unit == 0xA0 ||
    unit == 0x1680 ||
    (unit >= 0x2000 && unit <= 0x200A) ||
    unit == 0x202F ||
    unit == 0x205F ||
    unit == 0x3000;

/// Whether [index] falls between the two halves of a surrogate pair in
/// [text].
bool splitsSurrogatePair(String text, int index) =>
    index > 0 &&
    index < text.length &&
    _isHighSurrogate(text.codeUnitAt(index - 1)) &&
    _isLowSurrogate(text.codeUnitAt(index));

const int _newline = 0x0A;

bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

bool _hasLineBreak(String text) => text.contains('\n') || text.contains('\r');

void _check(String plain, Entity entity) {
  if (entity.offset < 0 || entity.length <= 0) {
    throw EntityFitException('Needs a span of at least one', entity);
  }
  if (entity.end > plain.length) {
    throw EntityFitException(
      'Runs past the end of the ${plain.length}-unit text.',
      entity,
    );
  }
  if (splitsSurrogatePair(plain, entity.offset) ||
      splitsSurrogatePair(plain, entity.end)) {
    throw EntityFitException('Starts or ends inside a surrogate pair.', entity);
  }
  switch (entity.kind) {
    case EntityKind$Style():
      break;
    case EntityKind$Link(:final url):
      if (url.isEmpty || _hasLineBreak(url) || url.startsWith(_mentionScheme)) {
        throw EntityFitException(
          'A link needs a url without line breaks that is not a mention.',
          entity,
        );
      }
    case EntityKind$Mention(:final id):
      if (id.isEmpty || _hasLineBreak(id)) {
        throw EntityFitException(
          'A mention needs an id without line breaks.',
          entity,
        );
      }
    case EntityKind$InlineContent(:final key):
      if (_hasLineBreak(key.encoded)) {
        throw EntityFitException(
          'The content key contains a line break.',
          entity,
        );
      }
  }
  if (entity.kind.isAtomic &&
      plain.substring(entity.offset, entity.end).contains('\n')) {
    throw EntityFitException(
      'An atomic entity cannot span a line break.',
      entity,
    );
  }
}

/// The scheme [EntityKind.mention] uses in markup and links may not.
const String _mentionScheme = 'mention:';

void _shape(String plain, Entity entity, List<Entity> out) {
  final kind = entity.kind;
  switch (kind) {
    case EntityKind$Mention() || EntityKind$InlineContent():
      out.add(entity);
    case EntityKind$Style(style: EntityStyle.quote):
      out.add(_widenToLines(plain, entity));
    case EntityKind$Style(style: EntityStyle.code) || EntityKind$Link():
      _splitAtLineBreaks(plain, entity, out);
    case EntityKind$Style():
      throw StateError('Text styles are shaped separately: $entity');
  }
}

bool _isTextStyle(EntityKind kind) =>
    kind is EntityKind$Style &&
    kind.style != EntityStyle.code &&
    kind.style != EntityStyle.quote;

Entity _widenToLines(String plain, Entity entity) {
  var start = entity.offset;
  while (start > 0 && plain.codeUnitAt(start - 1) != _newline) {
    start--;
  }
  var end = entity.end;
  while (end < plain.length && plain.codeUnitAt(end) != _newline) {
    end++;
  }
  return Entity(start, end - start, entity.kind);
}

/// Adds [entity] to [out] cut at line breaks. With [guarded] given, each piece
/// also loses the whitespace at its edges, except whitespace inside a guarded
/// entity.
void _splitAtLineBreaks(
  String plain,
  Entity entity,
  List<Entity> out, {
  List<Entity>? guarded,
}) {
  var start = entity.offset;
  while (true) {
    final lineBreak = plain.indexOf('\n', start);
    final last = lineBreak == -1 || lineBreak >= entity.end;
    var end = last ? entity.end : lineBreak;
    var from = start;
    if (guarded != null) {
      bool trimmable(int index) =>
          isWhitespaceUnit(plain.codeUnitAt(index)) &&
          !guarded.any((g) => g.offset <= index && index < g.end);
      while (from < end && trimmable(from)) {
        from++;
      }
      while (end > from && trimmable(end - 1)) {
        end--;
      }
    }
    if (end > from) out.add(Entity(from, end - from, entity.kind));
    if (last) return;
    start = lineBreak + 1;
  }
}

List<Entity> _merge(List<Entity> entities) {
  final byKind = <EntityKind, List<Entity>>{};
  final atomic = <Entity>{};
  for (final entity in entities) {
    if (entity.kind.isAtomic) {
      atomic.add(entity);
    } else {
      (byKind[entity.kind] ??= []).add(entity);
    }
  }
  final merged = <Entity>[...atomic];
  for (final MapEntry(:key, :value) in byKind.entries) {
    value.sort((a, b) => a.offset.compareTo(b.offset));
    var current = value.first;
    for (final next in value.skip(1)) {
      if (next.offset <= current.end) {
        final end = next.end > current.end ? next.end : current.end;
        current = Entity(current.offset, end - current.offset, key);
      } else {
        merged.add(current);
        current = next;
      }
    }
    merged.add(current);
  }
  return merged;
}

int _compare(Entity a, Entity b) {
  final byOffset = a.offset.compareTo(b.offset);
  if (byOffset != 0) return byOffset;
  final byLength = b.length.compareTo(a.length);
  if (byLength != 0) return byLength;
  return _rank(a.kind).compareTo(_rank(b.kind));
}

int _rank(EntityKind kind) => switch (kind) {
  EntityKind$Style(style: EntityStyle.quote) => 0,
  EntityKind$Link() => 1,
  EntityKind$Mention() => 2,
  EntityKind$InlineContent() => 3,
  EntityKind$Style(:final style) => 10 + style.index,
};

bool _covers(Entity outer, Entity inner) =>
    outer.offset <= inner.offset && outer.end >= inner.end;

bool _isCode(Entity entity) => entity.kind == EntityKind.code;

void _checkCombinations(List<Entity> sorted) {
  for (var i = 0; i < sorted.length; i++) {
    final a = sorted[i];
    for (var j = i + 1; j < sorted.length; j++) {
      final b = sorted[j];
      if (b.offset >= a.end) break;
      _checkOverlap(a, b);
    }
  }
}

void _checkOverlap(Entity a, Entity b) {
  final aKind = a.kind;
  final bKind = b.kind;
  if (aKind.isAtomic || bKind.isAtomic) {
    if (aKind.isAtomic && bKind.isAtomic) {
      throw EntityFitException('Atomic entities cannot overlap: $a and $b.');
    }
    final (atom, other) = aKind.isAtomic ? (a, b) : (b, a);
    if (other.kind is EntityKind$Link && atom.kind is EntityKind$Mention) {
      throw EntityFitException('A link cannot overlap a mention: $a and $b.');
    }
    if (_isCode(other)) {
      throw EntityFitException('Code cannot hold $atom: $other.');
    }
    if (!_covers(other, atom)) {
      throw EntityFitException('$other cuts through the atomic $atom.');
    }
    return;
  }
  if (_isCode(a) || _isCode(b)) {
    final (code, other) = _isCode(a) ? (a, b) : (b, a);
    if (other.kind is EntityKind$Link) {
      throw EntityFitException('A link cannot overlap code: $a and $b.');
    }
    if (!_covers(other, code)) {
      throw EntityFitException('$other cuts into the code $code.');
    }
  }
  if (aKind is EntityKind$Link && bKind is EntityKind$Link) {
    throw EntityFitException('Links cannot overlap: $a and $b.');
  }
}
