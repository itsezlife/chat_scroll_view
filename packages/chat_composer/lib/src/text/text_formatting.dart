import 'package:content_model/content_model.dart';

/// The edits of the formatting commands, as pure transforms of a [RichText].
///
/// Each takes the text and the selected range [from]..[to] (already widened
/// over atomic entities by the caller) and returns the new text. They add and
/// cut entities and leave every rule about what may coexist to [RichText]'s
/// canonical form: an edit it cannot hold comes back as null, a refusal, never
/// a half-applied result.
///
/// Why entity surgery and not [RichText.replaceRange] of the selection's slice:
/// that edit keeps an entity that surrounds the range whole, so it could never
/// turn bold off in the middle of a bold run.
abstract final class TextFormatting {
  /// Whether [kind] covers whole lines, so a command acts on every line the
  /// selection touches, caret included.
  static bool isLineKind(EntityKind kind) => switch (kind) {
    EntityKind$Style(style: EntityStyle.quote) ||
    EntityKind$CodeBlock() ||
    EntityKind$List() => true,
    _ => false,
  };

  /// Whether a command toggles [kind] over a selection: the styles, the code
  /// block and the list kinds. A link is applied, never toggled.
  static bool isToggled(EntityKind kind) => switch (kind) {
    EntityKind$Style() || EntityKind$CodeBlock() || EntityKind$List() => true,
    _ => false,
  };

  /// The start of the first and the end of the last line [from]..[to] touches.
  ///
  /// A range that ends right after a line break does not touch the next line.
  static (int, int) linesOf(String plain, int from, int to) {
    final last = to > from && plain.codeUnitAt(to - 1) == _newline
        ? to - 1
        : to;
    var start = from;
    while (start > 0 && plain.codeUnitAt(start - 1) != _newline) {
      start--;
    }
    var end = last;
    while (end < plain.length && plain.codeUnitAt(end) != _newline) {
      end++;
    }
    return (start, end);
  }

  /// Whether the range is entirely in [kind]; for a link, whether it touches
  /// one (the question a menu asks is whether there is a link to edit).
  ///
  /// A line kind is judged on every non-empty line the range touches, a text
  /// style on what applying it would change: nothing, when it is all there.
  static bool isActive(RichText text, int from, int to, EntityKind kind) {
    switch (kind) {
      case EntityKind$Link():
        return from < to &&
            text.entities.any(
              (entity) =>
                  entity.kind is EntityKind$Link &&
                  entity.offset < to &&
                  entity.end > from,
            );
      case EntityKind$Style(style: EntityStyle.quote) ||
          EntityKind$CodeBlock() ||
          EntityKind$List():
        return _coversLines(text, from, to, kind);
      case EntityKind$Style():
        return from < to &&
            applied(text, from, to, kind) == text &&
            text.entities.any(
              (entity) =>
                  entity.kind == kind &&
                  entity.offset < to &&
                  entity.end > from,
            );
      default:
        return false;
    }
  }

  /// The target of the first link the range touches, or null when it touches
  /// none.
  static String? linkUrl(RichText text, int from, int to) {
    if (from >= to) return null;
    for (final entity in text.entities) {
      if (entity.kind case EntityKind$Link(
        :final url,
      ) when entity.offset < to && entity.end > from) {
        return url;
      }
    }
    return null;
  }

  /// [text] with [kind] over the range, or null when it cannot hold it.
  ///
  /// - A text style is added as it is: [RichText] trims its edges and splits it
  ///   at line breaks. It is refused where it would cut into code.
  /// - Code first cuts the other styles and links out of the range (code holds
  ///   nothing else). It is refused over an atom or a code block.
  /// - A link replaces the links it overlaps. It is refused over code or a
  ///   mention.
  /// - A quote, a code block and a list item widen to the lines the range
  ///   touches. A quote is refused where it would drop a list item; a code
  ///   block takes the line away from every other entity but atoms, which it
  ///   refuses. A list item takes over the items the lines touch (their
  ///   extent and depth stay, the kind changes) and makes one item of every
  ///   other non-empty line.
  static RichText? applied(RichText text, int from, int to, EntityKind kind) {
    switch (kind) {
      case EntityKind$Style(style: EntityStyle.quote):
        final (start, end) = linesOf(text.plain, from, to);
        if (start == end || _overlapsItems(text, start, end)) return null;
        return _rebuild(text, [
          ...text.entities,
          Entity(start, end - start, kind),
        ]);
      case EntityKind$Style(style: EntityStyle.code):
        if (from == to) return null;
        return _rebuild(text, [
          for (final entity in text.entities)
            if (_isTextStyle(entity.kind) || entity.kind is EntityKind$Link)
              ..._cutInline(entity, from, to)
            else
              entity,
          Entity(from, to - from, kind),
        ]);
      case EntityKind$Style():
        if (from == to) return null;
        return _rebuild(text, [
          ...text.entities,
          Entity(from, to - from, kind),
        ]);
      case EntityKind$Link():
        if (from == to || kind.url.isEmpty) return null;
        return _rebuild(text, [
          for (final entity in text.entities)
            if (entity.kind is EntityKind$Link)
              ..._cutInline(entity, from, to)
            else
              entity,
          Entity(from, to - from, kind),
        ]);
      case EntityKind$CodeBlock():
        final (start, end) = linesOf(text.plain, from, to);
        if (start == end) return null;
        return _rebuild(text, [
          for (final entity in text.entities)
            if (entity.kind.isAtomic)
              entity
            else if (isLineKind(entity.kind))
              ..._cutLines(entity, start, end)
            else
              ..._cutInline(entity, start, end),
          Entity(start, end - start, kind),
        ]);
      case EntityKind$List(:final listKind):
        final (start, end) = linesOf(text.plain, from, to);
        if (start == end) return null;
        // An item the lines touch keeps its extent and depth and takes the
        // kind: a soft break inside it is not a reason to split it. A line
        // that is no item yet becomes one.
        bool inItem(int lineStart) => text.entities.any(
          (entity) =>
              entity.kind is EntityKind$List &&
              entity.offset <= lineStart &&
              lineStart <= entity.end,
        );
        return _rebuild(text, [
          for (final entity in text.entities)
            if (entity.kind case EntityKind$List(
              :final depth,
            ) when entity.offset <= end && entity.end >= start)
              Entity(
                entity.offset,
                entity.length,
                EntityKind.list(listKind: listKind, depth: depth),
              )
            else
              entity,
          for (final (lineStart, lineEnd) in _lines(text.plain, start, end))
            if (!inItem(lineStart))
              Entity(lineStart, lineEnd - lineStart, kind),
        ]);
      default:
        return null;
    }
  }

  /// [text] with [kind] taken off the range (the lines it touches, for a line
  /// kind).
  static RichText? removed(RichText text, int from, int to, EntityKind kind) {
    if (isLineKind(kind)) {
      final (start, end) = linesOf(text.plain, from, to);
      return _rebuild(text, [
        for (final entity in text.entities)
          if (_matches(entity.kind, kind))
            ..._cutLines(entity, start, end)
          else
            entity,
      ]);
    }
    return _rebuild(text, [
      for (final entity in text.entities)
        if (_matches(entity.kind, kind))
          ..._cutInline(entity, from, to)
        else
          entity,
    ]);
  }

  /// [text] without the links the range touches, the linked text kept.
  static RichText? unlinked(RichText text, int from, int to) => _rebuild(text, [
    for (final entity in text.entities)
      if (entity.kind is EntityKind$Link)
        ..._cutInline(entity, from, to)
      else
        entity,
  ]);

  /// [text] with the formatting the range holds taken off: styles and links in
  /// the range itself, quotes, code blocks and list items on the lines it
  /// touches. Atoms are content, and detected usernames and hashtags are not
  /// formatting, so both stay.
  static RichText? cleared(RichText text, int from, int to) {
    final (start, end) = linesOf(text.plain, from, to);
    return _rebuild(text, [
      for (final entity in text.entities)
        if (isLineKind(entity.kind))
          ..._cutLines(entity, start, end)
        else if (entity.kind is EntityKind$Style ||
            entity.kind is EntityKind$Link)
          ..._cutInline(entity, from, to)
        else
          entity,
    ]);
  }

  // [entity]'s kind answered by [kind]: a link matches any link, a code block
  // of no language any block, a list kind any depth.
  static bool _matches(EntityKind entity, EntityKind kind) =>
      switch ((kind, entity)) {
        (
          EntityKind$CodeBlock(:final language),
          EntityKind$CodeBlock(language: final actual),
        ) =>
          language == null || language == actual,
        (EntityKind$Link(), EntityKind$Link()) => true,
        (
          EntityKind$List(:final listKind),
          EntityKind$List(listKind: final actual),
        ) =>
          listKind == actual,
        (EntityKind$Style(), EntityKind$Style()) => kind == entity,
        _ => false,
      };

  static const int _newline = 0x0A;

  static bool _isTextStyle(EntityKind kind) => switch (kind) {
    EntityKind$Style(:final style) =>
      style != EntityStyle.code && style != EntityStyle.quote,
    _ => false,
  };

  static bool _overlapsItems(RichText text, int start, int end) =>
      text.entities.any(
        (entity) =>
            entity.kind is EntityKind$List &&
            entity.offset < end &&
            entity.end > start,
      );

  // The non-empty lines of start..end, as start..end pairs.
  static Iterable<(int, int)> _lines(String plain, int start, int end) sync* {
    var lineStart = start;
    while (lineStart <= end) {
      final lineBreak = plain.indexOf('\n', lineStart);
      final lineEnd = lineBreak < 0 || lineBreak > end ? end : lineBreak;
      if (lineEnd > lineStart) yield (lineStart, lineEnd);
      lineStart = lineEnd + 1;
    }
  }

  static bool _coversLines(RichText text, int from, int to, EntityKind kind) {
    final (start, end) = linesOf(text.plain, from, to);
    var any = false;
    for (final (lineStart, lineEnd) in _lines(text.plain, start, end)) {
      any = true;
      final covered = text.entities.any(
        (entity) =>
            _matches(entity.kind, kind) &&
            entity.offset <= lineStart &&
            entity.end >= lineEnd,
      );
      if (!covered) return false;
    }
    return any;
  }

  // The parts of [entity] outside from..to.
  static Iterable<Entity> _cutInline(Entity entity, int from, int to) sync* {
    if (entity.end <= from || entity.offset >= to) {
      yield entity;
      return;
    }
    if (entity.offset < from) {
      yield Entity(entity.offset, from - entity.offset, entity.kind);
    }
    if (entity.end > to) yield Entity(to, entity.end - to, entity.kind);
  }

  // The parts of the whole-line [entity] outside the lines start..end. A part
  // gives up the line break it shared with the cut lines: left in, it would
  // widen back over them.
  static Iterable<Entity> _cutLines(Entity entity, int start, int end) sync* {
    if (entity.end <= start || entity.offset >= end) {
      yield entity;
      return;
    }
    if (entity.offset < start - 1) {
      yield Entity(entity.offset, start - 1 - entity.offset, entity.kind);
    }
    if (entity.end > end + 1) {
      yield Entity(end + 1, entity.end - end - 1, entity.kind);
    }
  }

  static RichText? _rebuild(RichText text, List<Entity> entities) {
    try {
      return RichText(text.plain, entities);
      // RichText reports entities that cannot coexist as an ArgumentError and
      // offers no way to ask first.
      // ignore: avoid_catching_errors
    } on ArgumentError {
      return null;
    }
  }
}
