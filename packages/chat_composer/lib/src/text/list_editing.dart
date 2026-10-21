import 'package:chat_composer/src/text/text_formatting.dart';
import 'package:content_model/content_model.dart';
import 'package:meta/meta.dart';

/// A list item with no text yet: the empty line the caret is on, which is
/// about to hold the item's text.
///
/// [RichText] cannot hold it: an entity spans at least one code unit, and the
/// canonical form of a document with an empty item reads it as an empty line
/// (the markdown `-` decodes to one). The editor still has to: Enter in an item
/// opens the next one, and a second Enter on it leaves the list. So the
/// composer keeps it beside the text, as a value that lives exactly as long as
/// the caret stays on that empty line, and turns it into an entity the moment
/// text lands there.
@immutable
final class PendingListItem {
  /// An empty item at [offset], the start of an empty line.
  const PendingListItem(this.offset, this.kind, this.depth);

  /// Where the empty line is.
  final int offset;

  /// Whether the item is a bullet or a numbered one.
  final EntityListKind kind;

  /// How many levels the item is nested.
  final int depth;

  /// The entity the item becomes once it holds text.
  EntityKind$List get entityKind =>
      EntityKind$List(listKind: kind, depth: depth);

  /// This item at another [depth].
  PendingListItem withDepth(int depth) => PendingListItem(offset, kind, depth);

  /// This item as another [kind].
  PendingListItem withKind(EntityListKind kind) =>
      PendingListItem(offset, kind, depth);

  @override
  bool operator ==(Object other) =>
      other is PendingListItem &&
      other.offset == offset &&
      other.kind == kind &&
      other.depth == depth;

  @override
  int get hashCode => Object.hash(offset, kind, depth);

  @override
  String toString() => 'PendingListItem($offset, ${kind.name}, depth: $depth)';
}

/// The result of a list edit: the new text, where the caret goes (null: the
/// selection stays), and the empty item the caret rests on, if any.
typedef ListEdit = ({RichText text, int? caret, PendingListItem? pending});

/// One marker the gutter paints: the item that starts at [offset].
@immutable
final class ListMarker {
  /// The marker of the item at [offset].
  const ListMarker(this.offset, this.kind, this.depth, this.number);

  /// Where the item's first line starts.
  final int offset;

  /// Whether the item is a bullet or a numbered one.
  final EntityListKind kind;

  /// How many levels the item is nested.
  final int depth;

  /// The derived number of a numbered item; zero for a bullet.
  final int number;

  /// What the gutter paints.
  ///
  /// A bullet changes shape with depth because the text itself cannot be
  /// indented: the field lays out one paragraph, and an indent per depth
  /// would move the plain lines with it.
  String get label => switch (kind) {
    EntityListKind.bullet => _bullets[depth.clamp(0, _bullets.length - 1)],
    EntityListKind.ordered => '$number.',
  };

  static const List<String> _bullets = ['•', '◦', '▪', '▫'];

  @override
  bool operator ==(Object other) =>
      other is ListMarker &&
      other.offset == offset &&
      other.kind == kind &&
      other.depth == depth &&
      other.number == number;

  @override
  int get hashCode => Object.hash(offset, kind, depth, number);

  @override
  String toString() => 'ListMarker($offset, $label)';
}

/// The edits of list editing, as pure transforms of a [RichText].
///
/// Like [TextFormatting] these return the new text or null when the key has
/// nothing to do, so the field's own handling goes on. Where an edit can leave
/// the caret on an empty item, it reports it as the [PendingListItem].
abstract final class ListEditing {
  /// The item whose lines hold the line [offset] is on, or null.
  ///
  /// An item holds the lines that start within its span, its end included
  /// (the empty last line a soft break leaves is the item's), as the markdown
  /// encoder reads it.
  static Entity? itemAt(RichText text, int offset) {
    final start = _lineStart(text.plain, offset);
    for (final entity in text.entities) {
      if (entity.kind is EntityKind$List &&
          entity.offset <= start &&
          start <= entity.end) {
        return entity;
      }
    }
    return null;
  }

  /// Whether the line [offset] is on is held by an item, a quote or a code
  /// block, none of which a new item can share a line with.
  static bool holdsLine(RichText text, int offset) {
    final start = _lineStart(text.plain, offset);
    return text.entities.any(
      (entity) =>
          (entity.kind is EntityKind$List ||
              entity.kind == EntityKind.quote ||
              entity.kind is EntityKind$CodeBlock) &&
          entity.offset <= start &&
          start <= entity.end,
    );
  }

  /// The list marker typed at the start of the caret's line, when the space
  /// just typed completes one (`-` or `*` for a bullet, `1.` for a numbered
  /// item): the marker goes and the line becomes an item.
  ///
  /// [caret] is where the space would go. Null when the text before it on the
  /// line is not exactly a marker, or the line already belongs to an item, a
  /// quote or a code block. A structural shortcut, not detection: it fires
  /// only on the keystroke that completes the marker.
  static ListEdit? typedMarker(RichText text, int caret) {
    final plain = text.plain;
    final start = _lineStart(plain, caret);
    final kind = switch (plain.substring(start, caret)) {
      '-' || '*' => EntityListKind.bullet,
      '1.' => EntityListKind.ordered,
      _ => null,
    };
    if (kind == null || holdsLine(text, start)) return null;
    final rest = _tryText(() => text.delete(start, caret));
    if (rest == null) return null;
    if (_lineEnd(rest.plain, start) == start) {
      return (
        text: rest,
        caret: start,
        pending: PendingListItem(start, kind, 0),
      );
    }
    final listed = TextFormatting.applied(
      rest,
      start,
      start,
      EntityKind.list(listKind: kind),
    );
    if (listed == null || listed == rest) return null;
    return (text: listed, caret: start, pending: null);
  }

  /// Enter at [caret]: opens the next item of the same kind and depth, or
  /// leaves the list from an empty one. Null when the caret is in no item (or
  /// at the very start of a non-empty one, where Enter pushes it down).
  static ListEdit? enter(RichText text, int caret, PendingListItem? pending) {
    if (pending != null && pending.offset == caret) {
      return (text: text, caret: caret, pending: _outdented(pending));
    }
    final item = itemAt(text, caret);
    if (item == null) return null;
    final kind = item.kind as EntityKind$List;
    final plain = text.plain;
    final lineStart = _lineStart(plain, caret);
    final lineEnd = _lineEnd(plain, caret);

    // A blank item on its own: Enter leaves it.
    if (plain.substring(lineStart, lineEnd).trim().isEmpty &&
        lineStart == item.offset &&
        lineEnd == item.end) {
      return (
        text: _withItem(text, item, _outdentedKind(kind)),
        caret: caret,
        pending: null,
      );
    }

    // The empty line a soft break left at the end: Enter takes it for the next
    // item, so a second Enter is how a soft break turns into a new item.
    if (caret == item.end &&
        item.end > item.offset &&
        plain[caret - 1] == '\n') {
      final trimmed = item.length - 1;
      final entities = [
        for (final entity in text.entities)
          if (entity != item) entity,
        if (trimmed > 0) Entity(item.offset, trimmed, kind),
      ];
      final next = _tryText(() => RichText(plain, entities));
      if (next == null) return null;
      return (
        text: next,
        caret: caret,
        pending: PendingListItem(caret, kind.listKind, kind.depth),
      );
    }

    if (caret == item.offset) return null;
    final inserted = _tryText(
      () => text.replaceRange(caret, caret, const RichText.plain('\n')),
    );
    if (inserted == null) return null;
    final rightLength = item.end - caret;
    final entities = [
      for (final entity in inserted.entities)
        if (!(entity.kind is EntityKind$List && entity.offset == item.offset))
          entity,
      Entity(item.offset, caret - item.offset, kind),
      if (rightLength > 0) Entity(caret + 1, rightLength, kind),
    ];
    final next = _tryText(() => RichText(inserted.plain, entities));
    if (next == null) return null;
    return (
      text: next,
      caret: caret + 1,
      pending: rightLength > 0
          ? null
          : PendingListItem(caret + 1, kind.listKind, kind.depth),
    );
  }

  /// Backspace with the caret at the start of an item: outdents it, and an
  /// item with no depth left stops being one. Null when the caret is not at
  /// the start of an item, so Backspace deletes as it does anywhere.
  static ListEdit? backspaceAtStart(
    RichText text,
    int caret,
    PendingListItem? pending,
  ) {
    if (pending != null && pending.offset == caret) {
      return (text: text, caret: caret, pending: _outdented(pending));
    }
    final item = itemAt(text, caret);
    if (item == null || item.offset != caret) return null;
    return (
      text: _withItem(text, item, _outdentedKind(item.kind as EntityKind$List)),
      caret: caret,
      pending: null,
    );
  }

  /// The items the lines [from]..[to] touch, [delta] levels deeper (or
  /// shallower, negative); null when none of them can move.
  static ListEdit? shifted(
    RichText text,
    int from,
    int to,
    PendingListItem? pending,
    int delta,
  ) {
    final (start, end) = TextFormatting.linesOf(text.plain, from, to);
    var changed = false;
    int shift(int depth) {
      final next = (depth + delta).clamp(0, EntityKind$List.maxDepth);
      if (next != depth) changed = true;
      return next;
    }

    final entities = [
      for (final entity in text.entities)
        if (entity.kind case EntityKind$List(
          :final listKind,
          :final depth,
        ) when entity.offset <= end && entity.end >= start)
          Entity(
            entity.offset,
            entity.length,
            EntityKind.list(listKind: listKind, depth: shift(depth)),
          )
        else
          entity,
    ];
    final movedPending =
        pending != null && pending.offset >= start && pending.offset <= end
        ? pending.withDepth(shift(pending.depth))
        : pending;
    if (!changed) return null;
    final next = _tryText(() => RichText(text.plain, entities));
    if (next == null) return null;
    return (text: next, caret: null, pending: movedPending);
  }

  /// A soft break at [caret] inside an item: a line break the item covers, so
  /// the item goes on. Null when the caret is in no item.
  static ListEdit? softBreak(RichText text, int caret) {
    final item = itemAt(text, caret);
    if (item == null) return null;
    final inserted = _tryText(
      () => text.replaceRange(caret, caret, const RichText.plain('\n')),
    );
    if (inserted == null) return null;
    // An insertion at the end of an entity does not extend it.
    final entities = [
      for (final entity in inserted.entities)
        if (!(entity.kind is EntityKind$List && entity.offset == item.offset))
          entity,
      Entity(item.offset, item.length + 1, item.kind),
    ];
    final next = _tryText(() => RichText(inserted.plain, entities));
    if (next == null) return null;
    return (text: next, caret: caret + 1, pending: null);
  }

  /// The empty item a toggle of [kind] makes at the empty line [offset] is on,
  /// or null where it is refused: the line is held by an item, a quote or a
  /// code block.
  static PendingListItem? emptyItem(
    RichText text,
    int offset,
    EntityListKind kind,
  ) {
    if (holdsLine(text, offset)) return null;
    return PendingListItem(_lineStart(text.plain, offset), kind, 0);
  }

  /// The markers of the items of [text], with the numbers a reader counts.
  ///
  /// The numbering is the markdown encoder's, so the gutter shows the numbers
  /// the encoded text will have: an ordered item continues the run of ordered
  /// items at its depth that the item before it left open, a shallower item
  /// ends the deeper runs, a bullet ends the ordered run at its depth, and a
  /// line that is not an item ends all of them. The [pending] item counts as
  /// one.
  static List<ListMarker> markers(RichText text, PendingListItem? pending) {
    final items = <({int offset, int end, EntityKind$List kind})>[
      for (final entity in text.entities)
        if (entity.kind case final EntityKind$List kind)
          (offset: entity.offset, end: entity.end, kind: kind),
    ];
    if (pending != null) {
      final at = items.indexWhere((item) => item.offset > pending.offset);
      items.insert(at < 0 ? items.length : at, (
        offset: pending.offset,
        end: pending.offset,
        kind: pending.entityKind,
      ));
    }
    final next = <int, int?>{};
    final markers = <ListMarker>[];
    int? previousEnd;
    for (final item in items) {
      // Items on consecutive lines belong to one list; anything between them
      // is a line that is not an item.
      if (previousEnd == null || item.offset != previousEnd + 1) next.clear();
      previousEnd = item.end;
      final depth = item.kind.depth;
      next.removeWhere((deeper, _) => deeper > depth);
      switch (item.kind.listKind) {
        case EntityListKind.bullet:
          next[depth] = null;
          markers.add(ListMarker(item.offset, EntityListKind.bullet, depth, 0));
        case EntityListKind.ordered:
          final number = next[depth] ?? 1;
          next[depth] = number + 1;
          markers.add(
            ListMarker(item.offset, EntityListKind.ordered, depth, number),
          );
      }
    }
    return markers;
  }

  /// [pasted], the plain text, with its marker lines made items; null when
  /// fewer than two lines are markers (`- `, `* `, `+ `, `1. `, `1) `),
  /// because one is likelier the text itself.
  ///
  /// The depth of a marker is its indentation relative to the markers before
  /// it, so two and four spaces both nest one level. [atLineStart] says the
  /// paste lands at the start of its line; a marker that lands mid-line
  /// continues that line.
  static RichText? itemsFromPlain(String pasted, {required bool atLineStart}) {
    final lines = pasted.replaceAll('\r\n', '\n').split('\n');
    final plain = StringBuffer();
    final entities = <Entity>[];
    final indents = <int>[];
    var items = 0;
    var offset = 0;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final match = i == 0 && !atLineStart ? null : _marker.firstMatch(line);
      if (i > 0) {
        plain.write('\n');
        offset++;
      }
      if (match == null) {
        indents.clear();
        plain.write(line);
        offset += line.length;
        continue;
      }
      items++;
      final indent = match.group(1)!.replaceAll('\t', '  ').length;
      while (indents.isNotEmpty && indents.last > indent) {
        indents.removeLast();
      }
      if (indents.isEmpty || indents.last < indent) indents.add(indent);
      final body = match.group(4)!;
      if (body.isNotEmpty) {
        entities.add(
          Entity(
            offset,
            body.length,
            EntityKind.list(
              listKind: match.group(2) != null
                  ? EntityListKind.bullet
                  : EntityListKind.ordered,
              depth: (indents.length - 1).clamp(0, EntityKind$List.maxDepth),
            ),
          ),
        );
      }
      plain.write(body);
      offset += body.length;
    }
    if (items < 2) return null;
    return _tryText(() => RichText(plain.toString(), entities));
  }

  // indent, bullet, number, body.
  static final RegExp _marker = RegExp(
    r'^([ \t]*)(?:([-*+])|([0-9]{1,9})[.)])[ \t]+(.*)$',
  );

  // --- Helpers ---

  static PendingListItem? _outdented(PendingListItem item) =>
      item.depth > 0 ? item.withDepth(item.depth - 1) : null;

  static EntityKind$List? _outdentedKind(EntityKind$List kind) => kind.depth > 0
      ? EntityKind$List(listKind: kind.listKind, depth: kind.depth - 1)
      : null;

  // [text] with [item] given [kind], or without it for null.
  static RichText _withItem(
    RichText text,
    Entity item,
    EntityKind$List? kind,
  ) => RichText(text.plain, [
    for (final entity in text.entities)
      if (entity != item) entity,
    if (kind != null) Entity(item.offset, item.length, kind),
  ]);

  static int _lineStart(String plain, int offset) =>
      offset <= 0 ? 0 : plain.lastIndexOf('\n', offset - 1) + 1;

  static int _lineEnd(String plain, int offset) {
    final lineBreak = plain.indexOf('\n', offset);
    return lineBreak < 0 ? plain.length : lineBreak;
  }

  // RichText reports entities that cannot coexist as an ArgumentError and
  // offers no way to ask first.
  static RichText? _tryText(RichText Function() build) {
    try {
      return build();
      // ignore: avoid_catching_errors
    } on ArgumentError {
      return null;
    }
  }
}
