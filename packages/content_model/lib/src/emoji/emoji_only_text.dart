import 'package:content_model/src/identity/content_key.dart';
import 'package:content_model/src/rich_text/entity_kind.dart';
import 'package:content_model/src/rich_text/rich_text.dart';
import 'package:content_model/src/value_equality.dart';
import 'package:meta/meta.dart';

/// One emoji of an [EmojiOnly] text, with the line breaks before it.
@immutable
final class EmojiOnlyItem {
  /// Creates the item for [key] that follows [lineBreaksBefore] line breaks.
  const EmojiOnlyItem(this.key, {this.lineBreaksBefore = 0, this.alt = ''})
    : assert(lineBreaksBefore >= 0, 'A count of line breaks is not negative.');

  /// What the item is: a [ContentKey.unicode] with the exact sequence written
  /// (a ZWJ family, a toned hand, a flag, a keycap), or a [ContentKey.document]
  /// for the inline content of a custom emoji.
  final ContentKey key;

  /// How many `\n` stand between the previous item and this one; 0 for the
  /// first item, whatever came before it.
  final int lineBreaksBefore;

  /// The text the item stands for when it is copied: the characters under a
  /// custom emoji's entity (the emoji it replaces), empty for a unicode item,
  /// whose [key] is its text, and for a host that did not keep it.
  final String alt;

  @override
  bool operator ==(Object other) =>
      other is EmojiOnlyItem &&
      other.key == key &&
      other.lineBreaksBefore == lineBreaksBefore &&
      other.alt == alt;

  @override
  int get hashCode => Object.hash(key, lineBreaksBefore, alt);

  @override
  String toString() => lineBreaksBefore == 0
      ? 'EmojiOnlyItem($key)'
      : 'EmojiOnlyItem($key, lineBreaksBefore: $lineBreaksBefore)';
}

/// The emoji of a text that [EmojiOnlyText.of] found to be emoji-only, in
/// order.
///
/// Spaces and tabs between emoji are not kept, and neither are line breaks
/// before the first emoji or after the last one; the breaks between emoji are
/// on the item that follows them.
@immutable
final class EmojiOnly {
  /// Creates the value for [items], which must not be empty.
  EmojiOnly(List<EmojiOnlyItem> items)
    : assert(items.isNotEmpty, 'An emoji-only text has an emoji.'),
      items = List.unmodifiable(items);

  /// The emoji, in reading order; never empty.
  final List<EmojiOnlyItem> items;

  @override
  bool operator ==(Object other) =>
      other is EmojiOnly && ValueEquality.lists(other.items, items);

  @override
  int get hashCode => Object.hashAll(items);

  @override
  String toString() => 'EmojiOnly($items)';
}

/// The reference client's rule for a message that is nothing but emoji, over a
/// [RichText].
///
/// A host calls [of] when it materialises a message and passes the result on
/// as a body kind; the viewport never re-detects. The host adds the facts only
/// it has: that the message has no media, and whether the large-emoji setting
/// and the chat permit it. Sizes and layout are the viewport's.
///
/// ## The rule
///
/// This is the permissive superset of the reference client's emoji parse, with no
/// cap on the count:
///
/// - Every character belongs to an emoji sequence, or is a space, `\n`, `\t`
///   or a stray `U+FE0F`. Any other character, including a no-break space, a
///   carriage return and every other space, disqualifies; so does a sequence
///   left unfinished (a ZWJ with nothing after it, one regional indicator).
/// - A sequence is one item: a code point of `U+1F000` to `U+1FFFF`, a pair of
///   regional indicators (a flag), a keycap (`[0-9#*]`, an optional `U+FE0F`,
///   `U+20E3`), or a BMP emoji (`©`, `®`, and the symbols from `U+203C` to
///   `U+3299` that the emoji catalogue lists). After that base it absorbs
///   Fitzpatrick modifiers, variation selectors (`U+FE00` to `U+FE0F`), the
///   tag characters of a subdivision flag, `U+2640`, `U+2642` and `U+2695`, and
///   a ZWJ together with the base it joins.
/// - The only entities allowed are inline content with a **document** key,
///   each one item. A style, link, mention, username, hashtag, quote, code,
///   code block or list item disqualifies, and so does inline content of
///   another key.
///
/// ## Where it differs from the reference client
///
/// - The reference client gets the BMP set from its emoji table.
///   `content_model` depends on no workspace package, so the set is a constant
///   here, taken from the emoji catalogue; `emoji_data` has a test that fails
///   when the two disagree.
/// - A code point of `U+1F000` to `U+1FFFF` counts without a table lookup, as
///   it does there. So does a Fitzpatrick modifier with no emoji before
///   it. Whether a glyph exists for it is a drawing fact, not this rule's.
/// - The reference client lets a ZWJ followed by a non-emoji character through without
///   counting the character; here the character disqualifies, since it is not
///   part of a sequence.
abstract final class EmojiOnlyText {
  /// The emoji of [text] when it is emoji-only, or null when it is not, or when
  /// it holds no emoji at all.
  static EmojiOnly? of(RichText text) {
    final scan = _Scan(text.plain);
    var cursor = 0;
    for (final entity in text.entities) {
      if (entity.kind case EntityKind$InlineContent(
        :final key,
      ) when key is ContentKey$Document) {
        if (!scan.scan(cursor, entity.offset)) return null;
        scan.add(key, alt: text.plain.substring(entity.offset, entity.end));
        cursor = entity.end;
      } else {
        return null;
      }
    }
    if (!scan.scan(cursor, text.plain.length)) return null;
    return scan.items.isEmpty ? null : EmojiOnly(scan.items);
  }
}

/// Where the emoji are in a text that is not only emoji, for a renderer that
/// draws them larger than the letters around them.
///
/// The grammar is [EmojiOnlyText]'s, with one difference that comes from what
/// is drawn, not from what is meant. [EmojiOnlyText] counts every character the
/// catalogue lists as an emoji, because a message of them is shown as a row of
/// emoji whatever the font does. Here a run is a sequence the font draws as a
/// colour picture, because only that picture is enlarged: a heart, a copyright
/// sign or a digit with no presentation selector is a text glyph in the text's
/// font, and scaling it would make a letter of the sentence larger.
///
/// So a sequence is a run when it holds a code point of `U+1F000` or above (a
/// flag too), a keycap, a presentation selector (`U+FE0F`) or a ZWJ, or when its
/// base is one of the BMP code points the standard draws as an emoji by default
/// (`Emoji_Presentation`: a watch, a lightning bolt, a check mark, a star).
abstract final class EmojiRuns {
  /// The runs of [text] as `[start, end)` ranges of UTF-16 code units, in
  /// order and not overlapping; empty when [text] draws no colour emoji.
  static List<({int start, int end})> of(String text) {
    final scan = _Scan(text);
    final runs = <({int start, int end})>[];
    var index = 0;
    while (index < text.length) {
      final end = scan._sequenceEnd(index, text.length);
      if (end > index && scan._drawsInColour(index, end)) {
        runs.add((start: index, end: end));
        index = end;
      } else {
        index++;
      }
    }
    return runs;
  }
}

// --- Scanning ---

const int _zwj = 0x200D;
const int _variationSelector16 = 0xFE0F;
const int _keycapMark = 0x20E3;

/// Reads the emoji of a text a stretch at a time. A stretch ends where an
/// inline content entity starts, so a sequence never runs into one.
class _Scan {
  _Scan(this._text);

  final String _text;
  final List<EmojiOnlyItem> items = [];
  int _breaks = 0;

  void add(ContentKey key, {String alt = ''}) {
    items.add(
      EmojiOnlyItem(
        key,
        lineBreaksBefore: items.isEmpty ? 0 : _breaks,
        alt: alt,
      ),
    );
    _breaks = 0;
  }

  /// Reads `[start, end)`, adding each sequence to [items] and counting the
  /// line breaks between them; false when something in it is not emoji.
  bool scan(int start, int end) {
    var index = start;
    while (index < end) {
      switch (_text.codeUnitAt(index)) {
        case 0x20 || 0x09 || _variationSelector16:
          index++;
        case 0x0A:
          _breaks++;
          index++;
        case _:
          final sequenceEnd = _sequenceEnd(index, end);
          if (sequenceEnd < 0) return false;
          add(ContentKey.unicode(_text.substring(index, sequenceEnd)));
          index = sequenceEnd;
      }
    }
    return true;
  }

  /// Whether the sequence `[start, end)` is drawn as a colour picture: see
  /// [EmojiRuns].
  bool _drawsInColour(int start, int end) {
    final base = _codePointAt(start);
    if (base >= 0x1F000 || base < 0x80) return true; // a keycap is `< 0x80`
    for (var i = start; i < end; i++) {
      final unit = _text.codeUnitAt(i);
      if (unit == _variationSelector16 || unit == _zwj) return true;
    }
    return _isDefaultColour(base);
  }

  /// The end of the sequence that starts at [start], or -1 when none does.
  int _sequenceEnd(int start, int end) {
    var index = _baseEnd(start, end);
    if (index < 0) return -1;
    final startsWithBlackFlag = _codePointAt(start) == 0x1F3F4;
    while (index < end) {
      final codePoint = _codePointAt(index);
      if (codePoint == _zwj) {
        index = _baseEnd(index + 1, end);
        if (index < 0) return -1;
      } else if (_continuesSequence(codePoint, startsWithBlackFlag)) {
        index += codePoint > 0xFFFF ? 2 : 1;
      } else {
        break;
      }
    }
    return index;
  }

  /// The end of the single emoji that starts at [start], or -1 when none does.
  int _baseEnd(int start, int end) {
    if (start >= end) return -1;
    final codePoint = _codePointAt(start);
    if (codePoint == 0x23 ||
        codePoint == 0x2A ||
        (codePoint >= 0x30 && codePoint <= 0x39)) {
      var index = start + 1;
      if (index < end && _text.codeUnitAt(index) == _variationSelector16) {
        index++;
      }
      return index < end && _text.codeUnitAt(index) == _keycapMark
          ? index + 1
          : -1;
    }
    if (_isRegionalIndicator(codePoint)) {
      final second = start + 2;
      return second < end && _isRegionalIndicator(_codePointAt(second))
          ? second + 2
          : -1;
    }
    if (codePoint >= 0x1F000 && codePoint <= 0x1FFFF) return start + 2;
    return _isBmpEmoji(codePoint) ? start + 1 : -1;
  }

  /// The code point at [index], or the lone surrogate there when it is not
  /// half of a pair.
  int _codePointAt(int index) {
    final unit = _text.codeUnitAt(index);
    if (unit & 0xFC00 == 0xD800 && index + 1 < _text.length) {
      final next = _text.codeUnitAt(index + 1);
      if (next & 0xFC00 == 0xDC00) {
        return 0x10000 + ((unit & 0x3FF) << 10) + (next & 0x3FF);
      }
    }
    return unit;
  }

  static bool _isRegionalIndicator(int codePoint) =>
      codePoint >= 0x1F1E6 && codePoint <= 0x1F1FF;

  /// Whether [codePoint] extends the sequence before it: a Fitzpatrick
  /// modifier, a variation selector, a gender or medical sign, or, after a
  /// black flag, a tag character.
  static bool _continuesSequence(int codePoint, bool afterBlackFlag) =>
      (codePoint >= 0x1F3FB && codePoint <= 0x1F3FF) ||
      (codePoint >= 0xFE00 && codePoint <= 0xFE0F) ||
      codePoint == 0x2640 ||
      codePoint == 0x2642 ||
      codePoint == 0x2695 ||
      (afterBlackFlag && codePoint >= 0xE0020 && codePoint <= 0xE007F);
}

// --- The BMP emoji set ---

/// Whether [codePoint] is a BMP code point that starts an emoji of the
/// catalogue, found by binary search over [_bmpEmojiRanges].
bool _isBmpEmoji(int codePoint) {
  var low = 0;
  var high = _bmpEmojiRanges.length ~/ 2 - 1;
  while (low <= high) {
    final middle = (low + high) ~/ 2;
    if (codePoint < _bmpEmojiRanges[2 * middle]) {
      high = middle - 1;
    } else if (codePoint > _bmpEmojiRanges[2 * middle + 1]) {
      low = middle + 1;
    } else {
      return true;
    }
  }
  return false;
}

/// Whether [codePoint] is a BMP code point the standard draws as an emoji
/// without a presentation selector (`Emoji_Presentation`), found by binary
/// search over [_bmpColourRanges].
bool _isDefaultColour(int codePoint) {
  var low = 0;
  var high = _bmpColourRanges.length ~/ 2 - 1;
  while (low <= high) {
    final middle = (low + high) ~/ 2;
    if (codePoint < _bmpColourRanges[2 * middle]) {
      high = middle - 1;
    } else if (codePoint > _bmpColourRanges[2 * middle + 1]) {
      low = middle + 1;
    } else {
      return true;
    }
  }
  return false;
}

/// Inclusive `start, end` pairs, ascending: the BMP code points with the
/// `Emoji_Presentation` property (Unicode 15, unchanged since), which a font draws in colour
/// with no `U+FE0F`. Every other BMP emoji is a text glyph until a selector
/// asks for the picture.
const List<int> _bmpColourRanges = [
  0x231A, 0x231B, 0x23E9, 0x23EC, 0x23F0, 0x23F0, 0x23F3, 0x23F3, //
  0x25FD, 0x25FE, 0x2614, 0x2615, 0x2648, 0x2653, 0x267F, 0x267F, //
  0x2693, 0x2693, 0x26A1, 0x26A1, 0x26AA, 0x26AB, 0x26BD, 0x26BE, //
  0x26C4, 0x26C5, 0x26CE, 0x26CE, 0x26D4, 0x26D4, 0x26EA, 0x26EA, //
  0x26F2, 0x26F3, 0x26F5, 0x26F5, 0x26FA, 0x26FA, 0x26FD, 0x26FD, //
  0x2705, 0x2705, 0x270A, 0x270B, 0x2728, 0x2728, 0x274C, 0x274C, //
  0x274E, 0x274E, 0x2753, 0x2755, 0x2757, 0x2757, 0x2795, 0x2797, //
  0x27B0, 0x27B0, 0x27BF, 0x27BF, 0x2B1B, 0x2B1C, 0x2B50, 0x2B50, //
  0x2B55, 0x2B55, 0x3297, 0x3297, 0x3299, 0x3299, //
];

/// Inclusive `start, end` pairs, ascending: the first BMP code point of every
/// key of the emoji catalogue (Unicode Emoji 18.0) in the reference client's window, `©`,
/// `®` and `U+203C` to `U+3299`.
///
/// A digit, `#` and `*` are not here; they are emoji only inside a keycap.
/// `emoji_data` tests this set against its catalogue in both directions, so
/// a catalogue that gains a BMP emoji fails that test until the pair is added
/// here.
const List<int> _bmpEmojiRanges = [
  0x00A9, 0x00A9, 0x00AE, 0x00AE, 0x203C, 0x203C, 0x2049, 0x2049, //
  0x2122, 0x2122, 0x2139, 0x2139, 0x2194, 0x2199, 0x21A9, 0x21AA, //
  0x231A, 0x231B, 0x2328, 0x2328, 0x23CF, 0x23CF, 0x23E9, 0x23F3, //
  0x23F8, 0x23FA, 0x24C2, 0x24C2, 0x25AA, 0x25AB, 0x25B6, 0x25B6, //
  0x25C0, 0x25C0, 0x25FB, 0x25FE, 0x2600, 0x2604, 0x260E, 0x260E, //
  0x2611, 0x2611, 0x2614, 0x2615, 0x2618, 0x2618, 0x261D, 0x261D, //
  0x2620, 0x2620, 0x2622, 0x2623, 0x2626, 0x2626, 0x262A, 0x262A, //
  0x262E, 0x262F, 0x2638, 0x263A, 0x2640, 0x2640, 0x2642, 0x2642, //
  0x2648, 0x2653, 0x265F, 0x2660, 0x2663, 0x2663, 0x2665, 0x2666, //
  0x2668, 0x2668, 0x267B, 0x267B, 0x267E, 0x267F, 0x2692, 0x2697, //
  0x2699, 0x2699, 0x269B, 0x269C, 0x26A0, 0x26A1, 0x26A7, 0x26A7, //
  0x26AA, 0x26AB, 0x26B0, 0x26B1, 0x26BD, 0x26BE, 0x26C4, 0x26C5, //
  0x26C8, 0x26C8, 0x26CE, 0x26CF, 0x26D1, 0x26D1, 0x26D3, 0x26D4, //
  0x26E9, 0x26EA, 0x26F0, 0x26F5, 0x26F7, 0x26FA, 0x26FD, 0x26FD, //
  0x2702, 0x2702, 0x2705, 0x2705, 0x2708, 0x270D, 0x270F, 0x270F, //
  0x2712, 0x2712, 0x2714, 0x2714, 0x2716, 0x2716, 0x271D, 0x271D, //
  0x2721, 0x2721, 0x2728, 0x2728, 0x2733, 0x2734, 0x2744, 0x2744, //
  0x2747, 0x2747, 0x274C, 0x274C, 0x274E, 0x274E, 0x2753, 0x2755, //
  0x2757, 0x2757, 0x2763, 0x2764, 0x2795, 0x2797, 0x27A1, 0x27A1, //
  0x27B0, 0x27B0, 0x27BF, 0x27BF, 0x2934, 0x2935, 0x2B05, 0x2B07, //
  0x2B1B, 0x2B1C, 0x2B50, 0x2B50, 0x2B55, 0x2B55, 0x3030, 0x3030, //
  0x303D, 0x303D, 0x3297, 0x3297, 0x3299, 0x3299, //
];
