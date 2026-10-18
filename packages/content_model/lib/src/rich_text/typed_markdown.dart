import 'package:content_model/src/rich_text/entity.dart';
import 'package:content_model/src/rich_text/entity_kind.dart';
import 'package:content_model/src/rich_text/rich_text.dart';

/// Turns the markers a user typed into entities, with the reference client's
/// rules (Telegram Android's `MediaDataController.getEntities`).
///
/// A user who types `` `x` `` or `**x**` instead of choosing the style from
/// the menu gets the style, and the markers go. Like [EntityDetection] it is
/// one pure function, **host-invoked** at the moment a message is made, never
/// on paint and never per keystroke; run it before [EntityDetection.apply], so
/// a URL inside the new code is seen as code.
///
/// ## What becomes what
///
/// | Typed | Entity |
/// | --- | --- |
/// | `` `a` `` | [EntityKind.code] |
/// | ```` ```a``` ```` or ```` ```lang\na\n``` ```` | [EntityKind.codeBlock], with the language when the first line is one |
/// | `**a**` | [EntityKind.bold] |
/// | `__a__` | [EntityKind.italic] |
/// | `~~a~~` | [EntityKind.strike] |
/// | `||a||` | [EntityKind.spoiler] |
///
/// The markers are read in that order, so a marker inside code is text. A pair
/// holds at least one character and never crosses a line break, except for a
/// code block.
///
/// ## What it leaves alone
///
/// A pair that touches code, a code block, a link, a mention, a username, a
/// hashtag or inline content stays text: nothing is converted inside them, and
/// a pair is not made across one. Code and a code block also stay text where
/// they would hold an entity the text already has (they hold none).
///
/// Underline and quote have no typed form in the reference client, and none
/// here.
///
/// Returns the text itself when there is nothing to convert. Running it again
/// changes nothing.
abstract final class TypedMarkdown {
  /// [text] with its typed markers made into entities.
  static RichText apply(RichText text) {
    var result = text;
    for (final pass in _passes) {
      result = pass(result);
    }
    return result;
  }

  static final List<RichText Function(RichText)> _passes = [
    _codeBlocks,
    (text) => _pairs(text, _code, EntityKind.code, holdsNothing: true),
    (text) => _pairs(text, _bold, EntityKind.bold),
    (text) => _pairs(text, _italic, EntityKind.italic),
    (text) => _pairs(text, _spoiler, EntityKind.spoiler),
    (text) => _pairs(text, _strike, EntityKind.strike),
  ];

  static final RegExp _fence = RegExp(r'```([\s\S]+?)```');
  static final RegExp _languageName = RegExp(r'^[A-Za-z0-9+#._-]+$');
  // Not next to another backtick: an unconverted fence is not code.
  static final RegExp _code = RegExp(r'(?<!`)`([^`\n]+)`(?!`)');
  static final RegExp _bold = RegExp(r'\*\*(.+?)\*\*');
  static final RegExp _italic = RegExp('__(.+?)__');
  static final RegExp _spoiler = RegExp(r'\|\|(.+?)\|\|');
  static final RegExp _strike = RegExp('~~(.+?)~~');

  // Converts each ``` fence into a code block on lines of its own. Android's
  // reading: the fence swallows one space or line break outside it and the
  // block takes a line break in its place, a first line that names a language
  // (a first line that is code is code), one line break after the opener and
  // one before the closer are not content. A block with nothing to show, or
  // over any entity, stays text.
  static RichText _codeBlocks(RichText text) {
    final plain = StringBuffer();
    final blocks = <(int, int, String?)>[];
    final shifts = <(int, int, int)>[];
    var from = 0;
    var delta = 0;
    for (final match in _fence.allMatches(text.plain)) {
      final (:content, :language) = _fenceParts(match[1]!);
      if (content.trim().isEmpty) continue;
      final source = text.plain;
      final swallowsBefore =
          match.start > 0 &&
          (source[match.start - 1] == ' ' || source[match.start - 1] == '\n');
      final regionStart = match.start - (swallowsBefore ? 1 : 0);
      final after = match.end < source.length ? source[match.end] : '';
      final swallowsAfter = after == ' ' || after == '\n';
      final regionEnd = match.end + (swallowsAfter ? 1 : 0);
      if (regionStart < from ||
          _touchesAny(text.entities, regionStart, regionEnd)) {
        continue;
      }
      final breakBefore = regionStart > 0;
      final next = regionEnd < source.length ? source[regionEnd] : '';
      final breakAfter = regionEnd < source.length && next != '\n';
      plain
        ..write(source.substring(from, regionStart))
        ..write(breakBefore ? '\n' : '')
        ..write(content)
        ..write(breakAfter ? '\n' : '');
      final replacement =
          (breakBefore ? 1 : 0) + content.length + (breakAfter ? 1 : 0);
      blocks.add((
        regionStart + delta + (breakBefore ? 1 : 0),
        content.length,
        language,
      ));
      shifts.add((
        regionStart,
        regionEnd,
        replacement - (regionEnd - regionStart),
      ));
      delta += replacement - (regionEnd - regionStart);
      from = regionEnd;
    }
    if (blocks.isEmpty) return text;
    plain.write(text.plain.substring(from));
    int moved(int position) {
      var shift = 0;
      for (final (_, end, change) in shifts) {
        if (end <= position) shift += change;
      }
      return position + shift;
    }

    return RichText(plain.toString(), [
      for (final e in text.entities) Entity(moved(e.offset), e.length, e.kind),
      for (final (offset, length, language) in blocks)
        Entity(offset, length, EntityKind.codeBlock(language: language)),
    ]);
  }

  // The content and language of what lies between a fence's backticks.
  static ({String content, String? language}) _fenceParts(String body) {
    var content = body;
    String? language;
    final newline = body.indexOf('\n');
    if (newline >= 0) {
      final first = body.substring(0, newline);
      if (first.trim().isEmpty) {
        content = body.substring(newline + 1);
      } else if (_languageName.hasMatch(first)) {
        language = first;
        content = body.substring(newline + 1);
      }
    }
    if (content.endsWith('\n')) {
      content = content.substring(0, content.length - 1);
    }
    return (content: content, language: language);
  }

  // Converts each match of [pattern] (marker, inner group, marker) into an
  // entity of [kind] over the inner text, dropping the two markers.
  static RichText _pairs(
    RichText text,
    RegExp pattern,
    EntityKind kind, {
    bool holdsNothing = false,
  }) {
    final blocked = [
      for (final entity in text.entities)
        if (_blocks(entity.kind)) entity,
    ];
    final removals = <(int, int)>[];
    final made = <(int, int)>[];
    var removed = 0;
    for (final match in pattern.allMatches(text.plain)) {
      if (_touchesAny(blocked, match.start, match.end)) continue;
      final markerLength = (match.end - match.start - match[1]!.length) ~/ 2;
      if (holdsNothing &&
          _holdsEntity(text.entities, match.start, match.end, markerLength)) {
        continue;
      }
      removals
        ..add((match.start, markerLength))
        ..add((match.end - markerLength, markerLength));
      made.add((match.start - removed, match[1]!.length));
      removed += 2 * markerLength;
    }
    if (made.isEmpty) return text;
    final plain = StringBuffer();
    var from = 0;
    for (final (start, length) in removals) {
      plain.write(text.plain.substring(from, start));
      from = start + length;
    }
    plain.write(text.plain.substring(from));
    return RichText(plain.toString(), [
      for (final entity in text.entities) ?_remap(entity, removals),
      for (final (offset, length) in made) Entity(offset, length, kind),
    ]);
  }

  // Kinds a typed marker is never read inside or across.
  static bool _blocks(EntityKind kind) => switch (kind) {
    EntityKind$Link() ||
    EntityKind$CodeBlock() ||
    EntityKind$Mention() ||
    EntityKind$InlineContent() ||
    EntityKind$Username() ||
    EntityKind$Hashtag() => true,
    EntityKind$Style() => kind == EntityKind.code,
    EntityKind$List() => false,
  };

  static bool _touchesAny(List<Entity> entities, int start, int end) =>
      entities.any((e) => e.offset < end && e.end > start);

  // Whether an entity other than one covering the whole match lies within the
  // inner text of a match that starts at [start] and ends at [end].
  static bool _holdsEntity(
    List<Entity> entities,
    int start,
    int end,
    int markerLength,
  ) => entities.any(
    (e) =>
        e.offset < end - markerLength &&
        e.end > start + markerLength &&
        !(e.offset <= start && e.end >= end),
  );

  // [entity] in the text left after the [removals] (start, length pairs in
  // order), or null when nothing of it is left.
  static Entity? _remap(Entity entity, List<(int, int)> removals) {
    final start = _mapped(entity.offset, removals);
    final end = _mapped(entity.end, removals);
    return end > start ? Entity(start, end - start, entity.kind) : null;
  }

  static int _mapped(int position, List<(int, int)> removals) {
    var shift = 0;
    for (final (start, length) in removals) {
      if (position <= start) break;
      shift += position < start + length ? position - start : length;
    }
    return position - shift;
  }
}
