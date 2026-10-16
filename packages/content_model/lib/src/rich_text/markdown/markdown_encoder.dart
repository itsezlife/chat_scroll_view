import 'package:content_model/src/rich_text/entity.dart';
import 'package:content_model/src/rich_text/entity_kind.dart';
import 'package:content_model/src/rich_text/markdown/markdown_syntax.dart';
import 'package:content_model/src/rich_text/normalization.dart';
import 'package:content_model/src/rich_text/rich_text.dart';

/// The markdown form of [text]; see `RichTextMarkdown.encode`.
String encodeMarkdown(RichText text) {
  final plain = text.plain;
  final quotes = <Entity>[];
  final inline = <Entity>[];
  for (final entity in text.entities) {
    (entity.kind == EntityKind.quote ? quotes : inline).add(entity);
  }
  final escapes = _Escapes(plain, inline);
  final out = _Out();

  var start = 0;
  Entity? previousQuote;
  var first = true;
  while (true) {
    final lineBreak = plain.indexOf('\n', start);
    final end = lineBreak == -1 ? plain.length : lineBreak;
    final quote = _quoteOfLine(quotes, start);
    if (!first) {
      out.raw('\n');
      // A blank line is what ends a quote; without it the next line would
      // read as part of the quote.
      if (previousQuote != null && previousQuote != quote) out.raw('\n');
    }
    if (quote != null) out.raw(start == end ? '>' : '> ');
    _writeLine(out, plain, start, end, inline, escapes);
    previousQuote = quote;
    first = false;
    if (lineBreak == -1) break;
    start = lineBreak + 1;
  }
  return out.finish();
}

/// A quote covers the lines that start within its span, its end included, so
/// that the empty line a quote ends on belongs to it.
Entity? _quoteOfLine(List<Entity> quotes, int lineStart) {
  for (final quote in quotes) {
    if (quote.offset <= lineStart && lineStart <= quote.end) return quote;
  }
  return null;
}

// --- Inline content of one line ---

// Styles are written as toggles, the way the viewport's markdown library reads
// them: a marker switches its style on or off, and the order and nesting of
// different styles do not matter. A style that ends inside another therefore
// needs no splitting. The one thing written around a style boundary is a
// link: a link cannot hold markers, so it is cut into pieces at every style
// boundary, and the pieces merge back into one link when read.
void _writeLine(
  _Out out,
  String plain,
  int start,
  int end,
  List<Entity> entities,
  _Escapes escapes,
) {
  final inLine = [
    for (final entity in entities)
      if (entity.offset < end && entity.end > start) entity,
  ];
  final cuts = <int>{start, end};
  for (final entity in inLine) {
    cuts
      ..add(entity.offset)
      ..add(entity.end);
  }
  final sorted = cuts.toList()..sort();
  for (var i = 0; i < sorted.length; i++) {
    final from = sorted[i];
    _writeToggles(out, inLine, from);
    if (i + 1 == sorted.length) break;
    final to = sorted[i + 1];
    Entity? atom;
    EntityKind$Link? link;
    var isCode = false;
    for (final entity in inLine) {
      if (entity.offset > from || entity.end < to) continue;
      switch (entity.kind) {
        case EntityKind$Mention() || EntityKind$InlineContent():
          atom = entity;
        case EntityKind$Style(style: EntityStyle.code):
          isCode = true;
        case final EntityKind$Link kind:
          link = kind;
        case EntityKind$Style():
          break;
      }
    }
    if (atom != null) {
      final markup = _atomMarkup(plain, atom, escapes);
      out.structural(link == null ? markup : _linkPiece(markup, link.url));
    } else if (isCode) {
      out.structural(_codeSpan(plain.substring(from, to)));
    } else if (link != null) {
      out.structural(_linkPiece(escapes.apply(plain, from, to), link.url));
    } else {
      out.text(escapes.apply(plain, from, to));
    }
  }
}

/// The markers of the styles that end or begin at [position], endings first.
void _writeToggles(_Out out, List<Entity> entities, int position) {
  final closing = <EntityStyle>[];
  final opening = <EntityStyle>[];
  for (final entity in entities) {
    final kind = entity.kind;
    if (kind is! EntityKind$Style || kind.style == EntityStyle.code) continue;
    if (entity.end == position) closing.add(kind.style);
    if (entity.offset == position) opening.add(kind.style);
  }
  // Last opened, first closed, so `***x***` reads the way it is written.
  for (final style in closing.reversed.toList()..sort(_byMarkerOrder)) {
    out.structural(_marker(style));
  }
  for (final style in opening..sort(_byMarkerOrder)) {
    out.structural(_marker(style));
  }
}

int _byMarkerOrder(EntityStyle a, EntityStyle b) => a.index.compareTo(b.index);

String _linkPiece(String label, String url) => '[$label](${_destination(url)})';

String _marker(EntityStyle style) => switch (style) {
  EntityStyle.bold => '**',
  EntityStyle.italic => '*',
  EntityStyle.underline => '__',
  EntityStyle.strike => '~~',
  EntityStyle.spoiler => '||',
  EntityStyle.code => '`',
  EntityStyle.quote => '',
};

String _atomMarkup(String plain, Entity atom, _Escapes escapes) {
  final label = escapes.apply(plain, atom.offset, atom.end);
  return switch (atom.kind) {
    EntityKind$InlineContent(:final key) =>
      '![$label](${_destination(key.encoded)})',
    EntityKind$Mention(:final id) =>
      '[$label](${_destination('$mentionScheme$id')})',
    _ => throw StateError('Not an atomic entity: $atom'),
  };
}

/// A link target: bare when it can be, between angle brackets when it holds
/// whitespace or angle brackets.
String _destination(String target) {
  final needsBrackets = target.codeUnits.any(
    (unit) =>
        isWhitespaceUnit(unit) || unit < 0x20 || unit == 0x3C || unit == 0x3E,
  );
  return needsBrackets
      ? '<${_backslash(target, _inBrackets)}>'
      : _backslash(target, _bare);
}

// Code units that need a backslash in a bare target (parentheses, backslash)
// and between angle brackets (the brackets, backslash).
const Set<int> _bare = {0x28, 0x29, 0x5C};
const Set<int> _inBrackets = {0x3C, 0x3E, 0x5C};

String _backslash(String text, Set<int> units) {
  final out = StringBuffer();
  for (final unit in text.codeUnits) {
    if (units.contains(unit)) out.write(r'\');
    out.writeCharCode(unit);
  }
  return out.toString();
}

/// A code span for [content]: the shortest fence no backtick run inside can
/// be mistaken for, padded where the padding is the only way to read the
/// content back unchanged.
String _codeSpan(String content) {
  final runs = <int>{};
  var run = 0;
  for (final unit in content.codeUnits) {
    if (unit == 0x60) {
      run++;
    } else {
      if (run > 0) runs.add(run);
      run = 0;
    }
  }
  if (run > 0) runs.add(run);
  var length = 1;
  while (runs.contains(length)) {
    length++;
  }
  final fence = '`' * length;
  final padded =
      content.startsWith('`') ||
      content.endsWith('`') ||
      (content.startsWith(' ') &&
          content.endsWith(' ') &&
          content.codeUnits.any((unit) => unit != 0x20));
  return padded ? '$fence $content $fence' : '$fence$content$fence';
}

// --- Escaping ---

/// Which code units of a text need a backslash to be read back as text.
final class _Escapes {
  _Escapes(String plain, List<Entity> entities)
    : _flags = List<bool>.filled(plain.length, false) {
    final boundaries = <int>{};
    for (final entity in entities) {
      boundaries
        ..add(entity.offset)
        ..add(entity.end);
    }
    _flagLineStarts(plain);
    _flagMarkers(plain, boundaries);
  }

  final List<bool> _flags;

  /// [plain] from [from] to [to] with a backslash before each flagged unit.
  String apply(String plain, int from, int to) {
    final out = StringBuffer();
    var chunk = from;
    for (var i = from; i < to; i++) {
      if (_flags[i]) {
        out
          ..write(plain.substring(chunk, i))
          ..write(r'\');
        chunk = i;
      }
    }
    return (out..write(plain.substring(chunk, to))).toString();
  }

  // A block marker only means something as the first thing on a line.
  void _flagLineStarts(String plain) {
    var lineStart = 0;
    while (lineStart <= plain.length) {
      final lineBreak = plain.indexOf('\n', lineStart);
      final end = lineBreak == -1 ? plain.length : lineBreak;
      _flagLineStart(plain, lineStart, end);
      if (lineBreak == -1) break;
      lineStart = lineBreak + 1;
    }
  }

  void _flagLineStart(String plain, int start, int end) {
    var first = start;
    while (first < end &&
        (plain.codeUnitAt(first) == 0x20 || plain.codeUnitAt(first) == 0x09)) {
      first++;
    }
    if (first >= end) return;
    final unit = plain.codeUnitAt(first);
    if (_isBlockMarker(unit)) {
      _flags[first] = true;
    } else if (unit >= 0x30 && unit <= 0x39) {
      var digits = first;
      while (digits < end &&
          plain.codeUnitAt(digits) >= 0x30 &&
          plain.codeUnitAt(digits) <= 0x39) {
        digits++;
      }
      if (digits < end &&
          (plain.codeUnitAt(digits) == 0x2E ||
              plain.codeUnitAt(digits) == 0x29)) {
        _flags[digits] = true;
      }
    } else if (unit == 0x7E || unit == 0x3D) {
      var run = first;
      while (run < end && plain.codeUnitAt(run) == unit) {
        run++;
      }
      if (run - first >= 3) {
        for (var i = first; i < run; i++) {
          _flags[i] = true;
        }
      }
    }
  }

  bool _isBlockMarker(int unit) =>
      unit == 0x23 || // #
      unit == 0x3E || // >
      unit == 0x2D || // -
      unit == 0x2B || // +
      unit == 0x7C; // |

  void _flagMarkers(String plain, Set<int> boundaries) {
    final length = plain.length;
    for (var i = 0; i < length; i++) {
      final unit = plain.codeUnitAt(i);
      switch (unit) {
        case 0x5C || 0x2A || 0x60 || 0x5B || 0x5D: // \ * ` [ ]
          _flags[i] = true;
        case 0x5F: // _
          if (!_isSafeIntraword(plain, i, boundaries)) _flags[i] = true;
        case 0x7E || 0x7C || 0x3D: // ~ | =
          var end = i;
          while (end < length && plain.codeUnitAt(end) == unit) {
            end++;
          }
          if (_runNeedsEscape(plain, i, end, boundaries, unit)) {
            for (var j = i; j < end; j++) {
              _flags[j] = true;
            }
          }
          i = end - 1;
      }
    }
  }

  // An underscore between two word characters is never emphasis, unless a
  // marker is written right next to it.
  bool _isSafeIntraword(String plain, int index, Set<int> boundaries) =>
      index > 0 &&
      index + 1 < plain.length &&
      isWordUnit(plain.codeUnitAt(index - 1)) &&
      isWordUnit(plain.codeUnitAt(index + 1)) &&
      !boundaries.contains(index) &&
      !boundaries.contains(index + 1);

  // A pair marker needs two or more of a character and something to open or
  // close against. A run walled in by whitespace can do neither. A single ~
  // or | next to a written marker would join it, so it is escaped too.
  bool _runNeedsEscape(
    String plain,
    int start,
    int end,
    Set<int> boundaries,
    int unit,
  ) {
    final touchesMarker =
        unit != 0x3D &&
        boundaries.any((boundary) => boundary >= start && boundary <= end);
    if (touchesMarker) return true;
    if (end - start < 2) return false;
    final wallBefore =
        start == 0 || isWhitespaceUnit(plain.codeUnitAt(start - 1));
    final wallAfter =
        end == plain.length || isWhitespaceUnit(plain.codeUnitAt(end));
    return !(wallBefore && wallAfter);
  }
}

// --- Output ---

/// The output buffer, holding back a trailing `!` until it is known whether a
/// `[` follows, in which case the `!` is escaped so it cannot turn a link
/// into an image.
final class _Out {
  final StringBuffer _buffer = StringBuffer();
  bool _bangPending = false;

  void text(String text) {
    if (text.isEmpty) return;
    _flush();
    if (text.endsWith('!')) {
      _buffer.write(text.substring(0, text.length - 1));
      _bangPending = true;
    } else {
      _buffer.write(text);
    }
  }

  void structural(String markup) {
    if (markup.isEmpty) return;
    if (_bangPending) {
      _buffer.write(markup.startsWith('[') ? r'\!' : '!');
      _bangPending = false;
    }
    _buffer.write(markup);
  }

  void raw(String text) {
    _flush();
    _buffer.write(text);
  }

  String finish() {
    _flush();
    return _buffer.toString();
  }

  void _flush() {
    if (_bangPending) _buffer.write('!');
    _bangPending = false;
  }
}
