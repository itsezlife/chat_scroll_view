import 'package:content_model/src/rich_text/entity.dart';
import 'package:content_model/src/rich_text/entity_kind.dart';
import 'package:content_model/src/rich_text/rich_text.dart';

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
  String toString() => switch (entity) {
    final entity? => '$entity: $message',
    null => message,
  };
}

/// The rules that shape the entities of a [RichText] into the one list it
/// keeps, and the whitespace those rules trim.
abstract final class CanonicalEntities {
  /// The canonical entity list for [plain], or an [EntityFitException] when
  /// [input] cannot describe it.
  ///
  /// Canonical means one list per meaning, so equal texts compare equal:
  ///
  /// 1. Each entity is checked against the text (range, surrogate pairs,
  ///    payload, line breaks in atomic spans).
  /// 2. A quote or a code block widens to whole lines; every other non-atomic
  ///    entity splits at line breaks, because markup cannot carry a span
  ///    across one.
  /// 3. A text style (bold, italic, underline, strike, spoiler) gives up the
  ///    whitespace at its edges, because markup cannot open or close next to
  ///    whitespace; one over whitespace only disappears.
  /// 4. Equal kinds that touch or overlap merge into one entity. A list item
  ///    is the exception: items are never merged.
  /// 5. What yields is dropped, never reported: a detected username or
  ///    hashtag where it overlaps a link, a mention, inline content, code, a
  ///    code block or an earlier username or hashtag; a list item where it
  ///    shares a line with a quote, a code block or an item written before it.
  /// 6. The list is ordered by offset, longer first, then by kind.
  /// 7. The combination is checked: see [RichText] for the exclusivity rules.
  static List<Entity> of(String plain, Iterable<Entity> input) {
    final shaped = <Entity>[];
    final textStyles = <Entity>[];
    final items = <Entity>[];
    for (final entity in input) {
      _check(plain, entity);
      if (_isTextStyle(entity.kind)) {
        textStyles.add(entity);
      } else if (entity.kind is EntityKind$List) {
        items.add(entity);
      } else {
        _shape(plain, entity, shaped);
      }
    }
    // Trimming must leave the whitespace that sits inside code or an atomic
    // entity, or the style would end inside it.
    final guarded = _Guarded([
      for (final entity in shaped)
        if (entity.kind.isAtomic || entity.kind == EntityKind.code) entity,
    ]);
    for (final entity in textStyles) {
      _splitAtLineBreaks(plain, entity, shaped, guarded: guarded);
    }
    final merged = _withoutYieldingDetected(_merge(shaped));
    final result = [...merged, ..._listItems(plain, items, merged)]
      ..sort(_compare);
    _checkCombinations(result);
    return result;
  }

  /// Whether [unit] is a Unicode whitespace code unit as markup flanking rules
  /// see it: ASCII whitespace plus the space separators (Zs).
  static bool isWhitespaceUnit(int unit) =>
      unit == 0x20 ||
      (unit >= 0x09 && unit <= 0x0D) ||
      unit == 0xA0 ||
      unit == 0x1680 ||
      (unit >= 0x2000 && unit <= 0x200A) ||
      unit == 0x202F ||
      unit == 0x205F ||
      unit == 0x3000;
}

const int _newline = 0x0A;

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
  if (RichText.splitsSurrogatePair(plain, entity.offset) ||
      RichText.splitsSurrogatePair(plain, entity.end)) {
    throw EntityFitException('Starts or ends inside a surrogate pair.', entity);
  }
  switch (entity.kind) {
    case EntityKind$Style():
      break;
    case EntityKind$Link(:final url):
      if (url.isEmpty ||
          _hasLineBreak(url) ||
          _kindSchemes.any(url.startsWith)) {
        throw EntityFitException(
          'A link needs a url without line breaks that is not a mention, '
          'username or hashtag.',
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
    case EntityKind$Username(:final name):
      if (name.isEmpty || _hasLineBreak(name)) {
        throw EntityFitException(
          'A username needs a name without line breaks.',
          entity,
        );
      }
    case EntityKind$Hashtag(:final tag):
      if (tag.isEmpty || _hasLineBreak(tag)) {
        throw EntityFitException(
          'A hashtag needs a tag without line breaks.',
          entity,
        );
      }
    case EntityKind$List(:final depth)
        when depth < 0 || depth > EntityKind$List.maxDepth:
      throw EntityFitException(
        'A list item is nested 0 to ${EntityKind$List.maxDepth} levels.',
        entity,
      );
    case EntityKind$List():
      break;
    case EntityKind$InlineContent(:final key):
      if (_hasLineBreak(key.encoded)) {
        throw EntityFitException(
          'The content key contains a line break.',
          entity,
        );
      }
    case EntityKind$CodeBlock(:final language?)
        when !_language.hasMatch(language):
      throw EntityFitException(
        'A code block language is letters, digits and + # . _ -.',
        entity,
      );
    case EntityKind$CodeBlock():
      break;
  }
  if (entity.kind.isAtomic &&
      plain.substring(entity.offset, entity.end).contains('\n')) {
    throw EntityFitException(
      'An atomic entity cannot span a line break.',
      entity,
    );
  }
}

/// What a code block's language may be: a name a fence's info string holds.
final RegExp _language = RegExp(r'^[A-Za-z0-9+#._-]+$');

/// The schemes [EntityKind.mention], [EntityKind.username] and
/// [EntityKind.hashtag] use in markup and links may not: markup that read
/// them back would make the other kind.
const List<String> _kindSchemes = ['mention:', 'username:', 'hashtag:'];

void _shape(String plain, Entity entity, List<Entity> out) {
  final kind = entity.kind;
  switch (kind) {
    case EntityKind$Mention() || EntityKind$InlineContent():
      out.add(entity);
    case EntityKind$Style(style: EntityStyle.quote) || EntityKind$CodeBlock():
      out.add(_widenToLines(plain, entity));
    case EntityKind$Style(style: EntityStyle.code) ||
        EntityKind$Link() ||
        EntityKind$Username() ||
        EntityKind$Hashtag():
      _splitAtLineBreaks(plain, entity, out);
    case EntityKind$Style() || EntityKind$List():
      throw StateError('Shaped separately: $entity');
  }
}

bool _isTextStyle(EntityKind kind) => switch (kind) {
  EntityKind$Style(:final style) =>
    style != EntityStyle.code && style != EntityStyle.quote,
  EntityKind$Link() ||
  EntityKind$Mention() ||
  EntityKind$InlineContent() ||
  EntityKind$CodeBlock() ||
  EntityKind$Username() ||
  EntityKind$Hashtag() ||
  EntityKind$List() => false,
};

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
  _Guarded? guarded,
}) {
  var start = entity.offset;
  while (true) {
    // Looked for within the entity only: the text may be long, and hold many
    // entities.
    var lineBreak = start;
    while (lineBreak < entity.end && plain.codeUnitAt(lineBreak) != _newline) {
      lineBreak++;
    }
    final last = lineBreak >= entity.end;
    var end = last ? entity.end : lineBreak;
    var from = start;
    if (guarded != null) {
      bool trimmable(int index) =>
          CanonicalEntities.isWhitespaceUnit(plain.codeUnitAt(index)) &&
          !guarded.contains(index);
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

/// Code and atomic entities, whose whitespace a text style keeps. They do not
/// overlap one another (a list where they do fails its combination check
/// after trimming), so whether an index is inside one is a binary search.
final class _Guarded {
  _Guarded(List<Entity> entities)
    : _sorted = entities..sort((a, b) => a.offset.compareTo(b.offset));

  final List<Entity> _sorted;

  bool contains(int index) {
    // The last entity that starts at or before [index].
    var low = 0;
    var high = _sorted.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_sorted[middle].offset <= index) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    // Only the nearest can hold [index], as they do not overlap.
    return low > 0 && index < _sorted[low - 1].end;
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
  EntityKind$List(:final listKind, :final depth) =>
    1 + listKind.index * (EntityKind$List.maxDepth + 1) + depth,
  EntityKind$Link() => 10,
  EntityKind$Username() => 11,
  EntityKind$Hashtag() => 12,
  EntityKind$Mention() => 13,
  EntityKind$InlineContent() => 14,
  EntityKind$CodeBlock() => 15,
  EntityKind$Style(:final style) => 20 + style.index,
};

/// The entities of [merged] without the detected usernames and hashtags that
/// overlap something that outranks them.
///
/// A username or hashtag is a guess a detector made over text; a link, a
/// mention, inline content, code and a code block are not. Where they
/// overlap, keeping the guess would make the value unrepresentable (markup
/// cannot put a link inside a mention) or silently change what the author
/// wrote, so the guess goes. Of two overlapping guesses the earlier stays: a
/// longer one at the same start wins, so a re-detection is stable.
List<Entity> _withoutYieldingDetected(List<Entity> merged) {
  final detected = <Entity>[];
  final others = <Entity>[];
  for (final entity in merged) {
    (_isDetected(entity.kind) ? detected : others).add(entity);
  }
  if (detected.isEmpty) return merged;
  final outranking = _Spans([
    for (final entity in others)
      if (_outranksDetected(entity.kind)) entity,
  ]);
  detected.sort(_compare);
  var keptEnd = -1;
  for (final entity in detected) {
    if (entity.offset < keptEnd ||
        outranking.overlaps(entity.offset, entity.end)) {
      continue;
    }
    others.add(entity);
    keptEnd = entity.end;
  }
  return others;
}

bool _isDetected(EntityKind kind) =>
    kind is EntityKind$Username || kind is EntityKind$Hashtag;

bool _outranksDetected(EntityKind kind) => switch (kind) {
  EntityKind$Link() ||
  EntityKind$Mention() ||
  EntityKind$InlineContent() ||
  EntityKind$CodeBlock() => true,
  EntityKind$Style(:final style) => style == EntityStyle.code,
  EntityKind$Username() || EntityKind$Hashtag() || EntityKind$List() => false,
};

/// The list [items] widened to whole lines, minus those that yield: first the
/// ones that share a line with a quote or a code block in [others], then the
/// ones that share a line with an item before them.
///
/// Items are whole lines, so two share a line exactly when their ranges
/// overlap or touch (the empty last line of one is where the next starts).
/// "Before" is the order the items were written in, not the order of their
/// widened ranges: two items that a deleted line break joined onto one line
/// are one range, and the first of them is the one whose kind the line keeps.
List<Entity> _listItems(String plain, List<Entity> items, List<Entity> others) {
  if (items.isEmpty) return const [];
  final blocks = _Spans([
    for (final entity in others)
      if (entity.kind == EntityKind.quote ||
          entity.kind is EntityKind$CodeBlock)
        entity,
  ], touching: true);
  final ordered =
      [
        for (final item in items)
          (written: item, widened: _widenToLines(plain, item)),
      ]..sort((a, b) {
        final byStart = a.written.offset.compareTo(b.written.offset);
        return byStart != 0 ? byStart : _compare(a.widened, b.widened);
      });
  final kept = <Entity>[];
  var keptEnd = -1;
  for (final (:widened, written: _) in ordered) {
    if (widened.offset <= keptEnd ||
        blocks.overlaps(widened.offset, widened.end)) {
      continue;
    }
    kept.add(widened);
    keptEnd = widened.end;
  }
  return kept;
}

/// A set of spans that answers whether a range overlaps any of them, in
/// logarithmic time. The spans may overlap one another.
final class _Spans {
  /// [touching]: ranges that share only an edge count as overlapping.
  _Spans(List<Entity> entities, {bool touching = false})
    : _pad = touching ? 1 : 0,
      _sorted = [...entities]..sort((a, b) => a.offset.compareTo(b.offset)) {
    var furthest = 0;
    for (final entity in _sorted) {
      if (entity.end + _pad > furthest) furthest = entity.end + _pad;
      _furthestEnd.add(furthest);
    }
  }

  final int _pad;
  final List<Entity> _sorted;

  // For each span, the furthest end of it and every span before it.
  final List<int> _furthestEnd = [];

  bool overlaps(int from, int to) {
    // The last span that starts before the range ends.
    var low = 0;
    var high = _sorted.length;
    while (low < high) {
      final middle = (low + high) >> 1;
      if (_sorted[middle].offset < to + _pad) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low > 0 && _furthestEnd[low - 1] > from;
  }
}

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
  if ((aKind, bKind)
      case (EntityKind$CodeBlock(), _) || (_, EntityKind$CodeBlock())) {
    throw EntityFitException('A code block holds nothing else: $a and $b.');
  }
  if (aKind.isAtomic || bKind.isAtomic) {
    if (aKind.isAtomic && bKind.isAtomic) {
      throw EntityFitException('Atomic entities cannot overlap: $a and $b.');
    }
    final (atom, other) = aKind.isAtomic ? (a, b) : (b, a);
    if ((other.kind, atom.kind) case (
      EntityKind$Link(),
      EntityKind$Mention(),
    )) {
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
    if (other.kind case EntityKind$Link()) {
      throw EntityFitException('A link cannot overlap code: $a and $b.');
    }
    if (!_covers(other, code)) {
      throw EntityFitException('$other cuts into the code $code.');
    }
  }
  if ((aKind, bKind) case (EntityKind$Link(), EntityKind$Link())) {
    throw EntityFitException('Links cannot overlap: $a and $b.');
  }
}
