import 'package:content_model/src/identity/content_key.dart';
import 'package:content_model/src/rich_text/entity.dart';
import 'package:content_model/src/rich_text/entity_kind.dart';
import 'package:content_model/src/rich_text/markdown/markdown_syntax.dart';
import 'package:content_model/src/rich_text/normalization.dart';
import 'package:content_model/src/rich_text/rich_text.dart';

/// The reading half of `RichTextMarkdown`: markdown to rich text.
abstract final class MarkdownDecoder {
  /// The rich text [markdown] describes; see `RichTextMarkdown.decode`.
  static RichText decode(String markdown) {
    final lines = markdown.split('\n');
    final plain = StringBuffer();
    final entities = <Entity>[];
    var first = true;

    void startUnit() {
      if (!first) plain.write('\n');
      first = false;
    }

    void writeInline(String line) {
      final parsed = _InlineParser(line).parse();
      final offset = plain.length;
      plain.write(parsed.text);
      for (final entity in parsed.entities) {
        entities.add(
          Entity(entity.offset + offset, entity.length, entity.kind),
        );
      }
    }

    var i = 0;
    while (i < lines.length) {
      if (_fenceOpen.firstMatch(lines[i]) case final open?) {
        final ticks = open.group(1)!.length;
        final language = open.group(2)!;
        final code = <String>[];
        // An unclosed fence runs to the end, as CommonMark reads it.
        for (i++; i < lines.length && !_closes(lines[i], ticks); i++) {
          code.add(lines[i]);
        }
        i++;
        startUnit();
        final offset = plain.length;
        plain.write(code.join('\n'));
        if (plain.length > offset) {
          entities.add(
            Entity(
              offset,
              plain.length - offset,
              EntityKind.codeBlock(
                language: _languageName.hasMatch(language) ? language : null,
              ),
            ),
          );
        }
        continue;
      }
      if (_listLine(lines[i]) case final marker?) {
        startUnit();
        final itemStart = plain.length;
        // The line with the marker, then each line the item goes on in.
        for (var inItem = 0; ; inItem++) {
          final goesOn = _goesOn(lines, i);
          final line = goesOn
              ? lines[i].substring(
                  0,
                  lines[i].length - MarkdownSyntax.softBreak.length,
                )
              : _withoutLineEndEscape(lines[i]);
          if (inItem > 0) plain.write('\n');
          writeInline(inItem == 0 ? _listLine(line)!.text : line);
          i++;
          if (!goesOn) break;
        }
        // An item with no text holds nothing to mark: it is an empty line.
        if (plain.length > itemStart) {
          entities.add(
            Entity(
              itemStart,
              plain.length - itemStart,
              EntityKind.list(listKind: marker.kind, depth: marker.depth),
            ),
          );
        }
        continue;
      }
      if (!lines[i].startsWith('>')) {
        startUnit();
        writeInline(lines[i]);
        i++;
        continue;
      }
      startUnit();
      final quoteStart = plain.length;
      var quoteLine = 0;
      for (; i < lines.length && lines[i].startsWith('>'); i++, quoteLine++) {
        if (quoteLine > 0) plain.write('\n');
        writeInline(_withoutQuoteMarker(lines[i]));
      }
      if (plain.length > quoteStart) {
        entities.add(
          Entity(quoteStart, plain.length - quoteStart, EntityKind.quote),
        );
      }
      // The blank line that ends a quote is not part of the text.
      if (i < lines.length && lines[i].isEmpty) i++;
    }
    return RichText(plain.toString(), entities);
  }
}

// A backtick fence and the first word of its info string.
final RegExp _fenceOpen = RegExp(r'^(`{3,})\s*([^`\s]*)[^`]*$');

final RegExp _languageName = RegExp(r'^[A-Za-z0-9+#._-]+$');

bool _closes(String line, int ticks) {
  final trimmed = line.trimRight();
  return trimmed.length >= ticks &&
      trimmed.codeUnits.every((unit) => unit == 0x60);
}

// --- Lists ---

/// A line that opens a list item, read the way the viewport's markdown library
/// reads one: up to eight columns of indent (two a level, a tab two), a bullet
/// (`-`, `*`, `+`) or a number of up to nine digits with `.` or `)`, then
/// whitespace or the end of the line. The number is not kept. [text] is what
/// follows the one whitespace character after the marker.
({EntityListKind kind, int depth, String text})? _listLine(String line) {
  var i = 0;
  var columns = 0;
  while (i < line.length &&
      (line.codeUnitAt(i) == 0x20 || line.codeUnitAt(i) == 0x09)) {
    columns += line.codeUnitAt(i) == 0x09 ? 2 : 1;
    i++;
  }
  if (columns > MarkdownSyntax.maxListIndent || i >= line.length) return null;
  final unit = line.codeUnitAt(i);
  final EntityListKind kind;
  var after = i + 1;
  if (unit == 0x2D || unit == 0x2A || unit == 0x2B) {
    kind = EntityListKind.bullet;
  } else if (unit >= 0x30 && unit <= 0x39) {
    while (after < line.length &&
        after - i < 9 &&
        line.codeUnitAt(after) >= 0x30 &&
        line.codeUnitAt(after) <= 0x39) {
      after++;
    }
    if (after >= line.length ||
        (line.codeUnitAt(after) != 0x2E && line.codeUnitAt(after) != 0x29)) {
      return null;
    }
    after++;
    kind = EntityListKind.ordered;
  } else {
    return null;
  }
  if (after < line.length &&
      line.codeUnitAt(after) != 0x20 &&
      line.codeUnitAt(after) != 0x09) {
    return null;
  }
  return (
    kind: kind,
    depth: (columns ~/ 2).clamp(0, EntityKind$List.maxDepth),
    text: after < line.length ? line.substring(after + 1) : '',
  );
}

/// Whether the item whose line is `lines[index]` goes on in the next line: it
/// ends with a soft break, and the next line is not the start of another
/// block, which ends the item as CommonMark ends one.
bool _goesOn(List<String> lines, int index) =>
    index + 1 < lines.length &&
    lines[index].endsWith(MarkdownSyntax.softBreak) &&
    _listLine(lines[index + 1]) == null &&
    !lines[index + 1].startsWith('>') &&
    !_fenceOpen.hasMatch(lines[index + 1]);

/// [line], the last of an item, without the backslash that keeps its final
/// space from reading as half of a soft break.
String _withoutLineEndEscape(String line) {
  if (!line.endsWith(r'\ ')) return line;
  var backslashes = 0;
  for (var i = line.length - 2; i >= 0 && line.codeUnitAt(i) == 0x5C; i--) {
    backslashes++;
  }
  // An escaped backslash before the space is text, not an escape of it.
  return backslashes.isOdd ? '${line.substring(0, line.length - 2)} ' : line;
}

String _withoutQuoteMarker(String line) =>
    line.startsWith('> ') ? line.substring(2) : line.substring(1);

// --- Inline syntax of one line ---

/// Something read to its end in the source: a code span, a link, a mention or
/// an image. Its entities are relative to its own [text].
final class _SourceAtom {
  _SourceAtom(this.start, this.end, this.text, this.entities);

  final int start;
  final int end;
  final String text;
  final List<Entity> entities;
}

sealed class _Segment {}

final class _Chunk extends _Segment {
  _Chunk(this.text);
  final String text;
}

final class _AtomSegment extends _Segment {
  _AtomSegment(this.atom);
  final _SourceAtom atom;
}

/// A style marker that switched its style on or off.
final class _Marker extends _Segment {
  _Marker(this.style, this.unit, this.length, {required this.opens});

  final EntityStyle style;
  final int unit;
  final int length;
  final bool opens;

  /// For an opening marker, the marker that closes it, or null if it never
  /// closed.
  _Marker? closer;

  /// For a closing marker, the marker it closes.
  _Marker? opener;
}

final class _Parsed {
  _Parsed(this.text, this.entities);
  final String text;
  final List<Entity> entities;
}

/// Reads the inline syntax of one line the way the viewport's markdown library
/// does: a style marker toggles its style, so styles may overlap in any
/// order; it must have non-whitespace on its inner side and, to open, a closer
/// later on the line; a single underscore never opens or closes inside a word.
/// A marker that fails these stays text. Two things are more lenient than the
/// library, so that everything the encoder writes reads back: a doubled
/// underscore (underline) may touch a word, which the library cannot render,
/// and an escaped character is text even when it repeats the marker's
/// character. Links, code and images are read first
/// and are opaque to the markers.
///
/// A line is read on its own: styles, links and code never cross a line break.
final class _InlineParser {
  _InlineParser(this._source, {this.inLink = false});

  final String _source;

  /// Whether this is the label of a link, where another link cannot start.
  final bool inLink;

  late final List<_SourceAtom> _atoms = _findAtoms();

  _Parsed parse() => _build(_scan());

  // --- Atoms ---

  List<_SourceAtom> _findAtoms() {
    final s = _source;
    final atoms = <_SourceAtom>[];
    var i = 0;
    while (i < s.length) {
      final unit = s.codeUnitAt(i);
      _SourceAtom? atom;
      if (unit == 0x5C && i + 1 < s.length) {
        i += 2;
        continue;
      } else if (unit == 0x60) {
        atom = _readCode(i);
        if (atom == null) {
          i = _runEnd(i);
          continue;
        }
      } else if (unit == 0x21 &&
          i + 1 < s.length &&
          s.codeUnitAt(i + 1) == 0x5B) {
        atom = _readImage(i);
      } else if (unit == 0x5B && !inLink) {
        atom = _readLink(i);
      }
      if (atom == null) {
        i++;
      } else {
        atoms.add(atom);
        i = atom.end;
      }
    }
    return atoms;
  }

  int _runEnd(int start) {
    final unit = _source.codeUnitAt(start);
    var end = start;
    while (end < _source.length && _source.codeUnitAt(end) == unit) {
      end++;
    }
    return end;
  }

  /// The index just after the backtick run that closes the one at [start], or
  /// null when there is none; the run that closes must be as long as the one
  /// that opens.
  ({int contentEnd, int end})? _codeClose(int start) {
    final s = _source;
    final opening = _runEnd(start) - start;
    var search = start + opening;
    while (true) {
      final next = s.indexOf('`', search);
      if (next == -1) return null;
      final runEnd = _runEnd(next);
      if (runEnd - next == opening) return (contentEnd: next, end: runEnd);
      search = runEnd;
    }
  }

  _SourceAtom? _readCode(int start) {
    final close = _codeClose(start);
    if (close == null) return null;
    var content = _source.substring(_runEnd(start), close.contentEnd);
    if (content.length >= 2 &&
        content.startsWith(' ') &&
        content.endsWith(' ') &&
        content.codeUnits.any((unit) => unit != 0x20)) {
      content = content.substring(1, content.length - 1);
    }
    return _SourceAtom(start, close.end, content, [
      if (content.isNotEmpty) Entity(0, content.length, EntityKind.code),
    ]);
  }

  /// Reads `[label](target)` at [start]: a mention for the mention scheme, a
  /// username or a hashtag for theirs, a link otherwise.
  _SourceAtom? _readLink(int start) {
    final reference = _readReference(start);
    if (reference == null) return null;
    final (:label, :target, :end) = reference;
    if (target.startsWith(MarkdownSyntax.mentionScheme)) {
      final id = target.substring(MarkdownSyntax.mentionScheme.length);
      final text = _unescape(label);
      if (id.isEmpty || text.isEmpty) return null;
      return _SourceAtom(start, end, text, [
        Entity(0, text.length, EntityKind.mention(id)),
      ]);
    }
    final named =
        target.startsWith(MarkdownSyntax.usernameScheme) ||
        target.startsWith(MarkdownSyntax.hashtagScheme);
    final kind = named ? _namedKind(target) : EntityKind.link(target);
    // A username or hashtag with no name is not one: it stays text.
    if (kind == null) return null;
    final inner = _InlineParser(label, inLink: true).parse();
    if (inner.text.isEmpty) return null;
    return _SourceAtom(start, end, inner.text, [
      Entity(0, inner.text.length, kind),
      // A link and code never overlap in a RichText. Written as `[`a`](u)` the
      // target is what the writer meant to keep, so the label's code reads as
      // text; dropping the link instead would lose the target.
      for (final entity in inner.entities)
        if (kind is! EntityKind$Link || entity.kind != EntityKind.code) entity,
    ]);
  }

  EntityKind? _namedKind(String target) {
    if (target.startsWith(MarkdownSyntax.usernameScheme)) {
      final name = target.substring(MarkdownSyntax.usernameScheme.length);
      return name.isEmpty ? null : EntityKind.username(name);
    }
    final tag = target.substring(MarkdownSyntax.hashtagScheme.length);
    return tag.isEmpty ? null : EntityKind.hashtag(tag);
  }

  /// Reads `![alt](target)` at [start]. An image whose target is not a content
  /// key keeps only its alt text.
  _SourceAtom? _readImage(int start) {
    final reference = _readReference(start + 1);
    if (reference == null) return null;
    final (:label, :target, :end) = reference;
    final alt = _unescape(label);
    final key = ContentKey.tryParse(target);
    return _SourceAtom(start, end, alt, [
      if (key != null && alt.isNotEmpty)
        Entity(0, alt.length, EntityKind.inlineContent(key)),
    ]);
  }

  ({String label, String target, int end})? _readReference(int open) {
    final s = _source;
    final close = _labelEnd(open);
    if (close == null ||
        close + 1 >= s.length ||
        s.codeUnitAt(close + 1) != 0x28) {
      return null;
    }
    final target = _readTarget(close + 2);
    if (target == null) return null;
    return (
      label: s.substring(open + 1, close),
      target: target.$1,
      end: target.$2,
    );
  }

  // The index of the bracket closing the one at [open]: nesting counts, an
  // escaped bracket does not, and a bracket inside a code span is code.
  int? _labelEnd(int open) {
    final s = _source;
    var depth = 0;
    var i = open;
    while (i < s.length) {
      final unit = s.codeUnitAt(i);
      if (unit == 0x5C) {
        i += 2;
      } else if (unit == 0x60) {
        i = _codeClose(i)?.end ?? _runEnd(i);
      } else {
        if (unit == 0x5B) depth++;
        if (unit == 0x5D && --depth == 0) return i;
        i++;
      }
    }
    return null;
  }

  // The link target starting at [start] (just after the opening parenthesis)
  // and the index after the closing one; null when there is none.
  (String, int)? _readTarget(int start) {
    final s = _source;
    var i = _skipSpaces(start);
    final target = StringBuffer();
    if (i < s.length && s.codeUnitAt(i) == 0x3C) {
      i++;
      while (true) {
        if (i >= s.length) return null;
        final unit = s.codeUnitAt(i);
        if (unit == 0x3E) {
          i++;
          break;
        }
        if (unit == 0x3C) return null;
        if (unit == 0x5C &&
            i + 1 < s.length &&
            MarkdownSyntax.isAsciiPunctuation(s.codeUnitAt(i + 1))) {
          i++;
        }
        target.writeCharCode(s.codeUnitAt(i));
        i++;
      }
    } else {
      var depth = 0;
      while (i < s.length) {
        final unit = s.codeUnitAt(i);
        if (CanonicalEntities.isWhitespaceUnit(unit)) break;
        if (unit == 0x28) depth++;
        if (unit == 0x29) {
          if (depth == 0) break;
          depth--;
        }
        if (unit == 0x5C &&
            i + 1 < s.length &&
            MarkdownSyntax.isAsciiPunctuation(s.codeUnitAt(i + 1))) {
          i++;
        }
        target.writeCharCode(s.codeUnitAt(i));
        i++;
      }
    }
    i = _skipSpaces(i);
    if (i >= s.length || s.codeUnitAt(i) != 0x29) return null;
    final text = target.toString();
    if (text.isEmpty || text.contains('\r')) return null;
    return (text, i + 1);
  }

  int _skipSpaces(int from) {
    var i = from;
    while (i < _source.length &&
        (_source.codeUnitAt(i) == 0x20 || _source.codeUnitAt(i) == 0x09)) {
      i++;
    }
    return i;
  }

  /// [text] with each backslash before punctuation dropped.
  String _unescape(String text) {
    final out = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit == 0x5C &&
          i + 1 < text.length &&
          MarkdownSyntax.isAsciiPunctuation(text.codeUnitAt(i + 1))) {
        i++;
      }
      out.writeCharCode(text.codeUnitAt(i));
    }
    return out.toString();
  }

  // --- Style markers ---

  List<_Segment> _scan() {
    final s = _source;
    final segments = <_Segment>[];
    final text = StringBuffer();
    final open = <EntityStyle, _Marker>{};
    var atomIndex = 0;

    void flush() {
      if (text.isEmpty) return;
      segments.add(_Chunk(text.toString()));
      text.clear();
    }

    var i = 0;
    while (i < s.length) {
      if (atomIndex < _atoms.length && _atoms[atomIndex].start == i) {
        flush();
        segments.add(_AtomSegment(_atoms[atomIndex]));
        i = _atoms[atomIndex].end;
        atomIndex++;
        continue;
      }
      final unit = s.codeUnitAt(i);
      if (unit == 0x5C &&
          i + 1 < s.length &&
          MarkdownSyntax.isAsciiPunctuation(s.codeUnitAt(i + 1))) {
        text.writeCharCode(s.codeUnitAt(i + 1));
        i += 2;
        continue;
      }
      final marker = _markerAt(i, unit);
      if (marker == null) {
        text.writeCharCode(unit);
        i++;
        continue;
      }
      final (style, length) = marker;
      final opens = !open.containsKey(style);
      final valid = opens
          ? _canOpen(i, unit, length)
          : _canClose(i, unit, length);
      if (!valid) {
        text.writeCharCode(unit);
        i++;
        continue;
      }
      flush();
      final segment = _Marker(style, unit, length, opens: opens);
      segments.add(segment);
      if (opens) {
        open[style] = segment;
      } else {
        final opening = open.remove(style)!;
        opening.closer = segment;
        segment.opener = opening;
      }
      i += length;
    }
    flush();
    return segments;
  }

  // The style a marker at [i] switches and how many characters it takes: a
  // doubled character is the long form; a single `~` or `|` is text.
  (EntityStyle, int)? _markerAt(int i, int unit) {
    final doubled = i + 1 < _source.length && _source.codeUnitAt(i + 1) == unit;
    return switch (unit) {
      0x2A => doubled ? (EntityStyle.bold, 2) : (EntityStyle.italic, 1),
      0x5F => doubled ? (EntityStyle.underline, 2) : (EntityStyle.italic, 1),
      0x7E when doubled => (EntityStyle.strike, 2),
      0x7C when doubled => (EntityStyle.spoiler, 2),
      _ => null,
    };
  }

  bool _canOpen(int i, int unit, int length) {
    final s = _source;
    final after = i + length;
    if (after >= s.length ||
        CanonicalEntities.isWhitespaceUnit(s.codeUnitAt(after))) {
      return false;
    }
    if (unit == 0x5F &&
        length == 1 &&
        i > 0 &&
        MarkdownSyntax.isWordUnit(s.codeUnitAt(i - 1))) {
      return false;
    }
    return _hasCloser(after, unit, length);
  }

  bool _canClose(int i, int unit, int length) {
    final s = _source;
    if (i == 0 || CanonicalEntities.isWhitespaceUnit(s.codeUnitAt(i - 1)))
      return false;
    final after = i + length;
    return !(unit == 0x5F &&
        length == 1 &&
        after < s.length &&
        MarkdownSyntax.isWordUnit(s.codeUnitAt(after)));
  }

  // Whether a marker that could close a style opened by [length] characters of
  // [unit] follows [from]. A closer comes right after a non-space that is not
  // the same character, so the run `**` in `a **b ** c` closes nothing.
  bool _hasCloser(int from, int unit, int length) {
    final s = _source;
    var atomIndex = 0;
    // Whether the code unit before [j] was a backslash-escaped character,
    // which is text and never half of a marker.
    var afterEscape = false;
    for (var j = from; j < s.length; j++) {
      while (atomIndex < _atoms.length && _atoms[atomIndex].end <= j) {
        atomIndex++;
      }
      if (atomIndex < _atoms.length && _atoms[atomIndex].start <= j) {
        j = _atoms[atomIndex].end - 1;
        afterEscape = false;
        continue;
      }
      final here = s.codeUnitAt(j);
      if (here == 0x5C) {
        j++;
        afterEscape = true;
        continue;
      }
      final wasEscaped = afterEscape;
      afterEscape = false;
      if (here != unit) continue;
      final doubled = j + 1 < s.length && s.codeUnitAt(j + 1) == unit;
      final follows =
          j > 0 &&
          !CanonicalEntities.isWhitespaceUnit(s.codeUnitAt(j - 1)) &&
          (s.codeUnitAt(j - 1) != unit || wasEscaped);
      if (length == 2) {
        if (doubled) {
          if (follows) return true;
          j++;
        }
      } else if (follows) {
        if (unit != 0x5F) return true;
        final after = j + 1;
        if (after >= s.length ||
            !MarkdownSyntax.isWordUnit(s.codeUnitAt(after)))
          return true;
      }
    }
    return false;
  }

  // --- Result ---

  _Parsed _build(List<_Segment> segments) {
    final out = StringBuffer();
    final entities = <Entity>[];
    final openedAt = <_Marker, int>{};
    var position = 0;
    for (final segment in segments) {
      switch (segment) {
        case _Chunk(:final text):
          out.write(text);
          position += text.length;
        case _AtomSegment(:final atom):
          for (final entity in atom.entities) {
            entities.add(
              Entity(entity.offset + position, entity.length, entity.kind),
            );
          }
          out.write(atom.text);
          position += atom.text.length;
        case _Marker(opens: true, closer: null):
          // Never closed: it was text after all.
          final literal = String.fromCharCode(segment.unit) * segment.length;
          out.write(literal);
          position += literal.length;
        case _Marker(opens: true):
          openedAt[segment] = position;
        case _Marker(:final style, :final opener?):
          final start = openedAt[opener]!;
          if (position > start) {
            entities.add(
              Entity(start, position - start, EntityKind.style(style)),
            );
          }
        case _Marker():
          break;
      }
    }
    return _Parsed(out.toString(), entities);
  }
}
