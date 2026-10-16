import 'package:content_model/content_model.dart' show RichText;
import 'package:meta/meta.dart';

/// The single replacement that turns one text into another: the range
/// [start]..[oldEnd] of the old text became [inserted], which occupies
/// [start]..[newEnd] of the new one.
@immutable
final class TextReplacement {
  /// Creates the replacement of [start]..[oldEnd] with [inserted].
  const TextReplacement({
    required this.start,
    required this.oldEnd,
    required this.inserted,
  });

  /// The first code unit that differs.
  final int start;

  /// The end of the replaced range in the old text.
  final int oldEnd;

  /// What took the place of the range.
  final String inserted;

  /// The end of [inserted] in the new text.
  int get newEnd => start + inserted.length;

  /// Whether nothing changed.
  bool get isEmpty => start == oldEnd && inserted.isEmpty;

  /// The same replacement widened to cover [from]..[to] of the old text
  /// (which must contain the current range).
  TextReplacement widenedTo(int from, int to) =>
      TextReplacement(start: from, oldEnd: to, inserted: inserted);

  @override
  bool operator ==(Object other) =>
      other is TextReplacement &&
      other.start == start &&
      other.oldEnd == oldEnd &&
      other.inserted == inserted;

  @override
  int get hashCode => Object.hash(start, oldEnd, inserted);

  @override
  String toString() => 'TextReplacement($start..$oldEnd -> "$inserted")';
}

/// The one replacement that turns [old] into [next].
///
/// A text field reports an edit as a whole new value, so the edit has to be
/// recovered. Common prefix and suffix alone are ambiguous when characters
/// repeat (deleting either "a" of "aab" gives "ab"), and the entities depend
/// on which one went. [caret], the collapsed selection of the new value (or
/// -1), settles it: after typing, pasting and deleting in either direction
/// the caret sits where the edit ended on the new text, so the text after the
/// caret is the unchanged suffix. When that does not hold (a programmatic
/// write with an arbitrary selection) the edit is the greedy one.
///
/// The range never starts or ends between the two halves of a surrogate
/// pair, because an entity cannot.
TextReplacement diffText(String old, String next, {int caret = -1}) {
  final suffix =
      _suffixAfterCaret(old, next, caret) ?? _greedySuffix(old, next);
  // The old range is old[start .. oldEnd], the new one next[start .. newEnd].
  var oldEnd = old.length - suffix;
  var newEnd = next.length - suffix;
  final prefixLimit = oldEnd < newEnd ? oldEnd : newEnd;
  var start = 0;
  while (start < prefixLimit &&
      old.codeUnitAt(start) == next.codeUnitAt(start)) {
    start++;
  }
  while (start > 0 &&
      (splitsSurrogatePair(old, start) || splitsSurrogatePair(next, start))) {
    start--;
  }
  while (oldEnd < old.length &&
      (splitsSurrogatePair(old, oldEnd) || splitsSurrogatePair(next, newEnd))) {
    oldEnd++;
    newEnd++;
  }
  return TextReplacement(
    start: start,
    oldEnd: oldEnd,
    inserted: next.substring(start, newEnd),
  );
}

int? _suffixAfterCaret(String old, String next, int caret) {
  if (caret < 0 || caret > next.length) return null;
  final tail = next.length - caret;
  if (tail > old.length) return null;
  if (!old.endsWith(next.substring(caret))) return null;
  return tail;
}

int _greedySuffix(String old, String next) {
  final prefix = _commonPrefix(old, next);
  var suffix = 0;
  final limit = (old.length < next.length ? old.length : next.length) - prefix;
  while (suffix < limit &&
      old.codeUnitAt(old.length - 1 - suffix) ==
          next.codeUnitAt(next.length - 1 - suffix)) {
    suffix++;
  }
  return suffix;
}

int _commonPrefix(String a, String b) {
  final limit = a.length < b.length ? a.length : b.length;
  var i = 0;
  while (i < limit && a.codeUnitAt(i) == b.codeUnitAt(i)) {
    i++;
  }
  return i;
}

/// Whether [index] falls between the two halves of a surrogate pair in
/// [text].
bool splitsSurrogatePair(String text, int index) =>
    index > 0 &&
    index < text.length &&
    (text.codeUnitAt(index - 1) & 0xFC00) == 0xD800 &&
    (text.codeUnitAt(index) & 0xFC00) == 0xDC00;

/// Applies [replacement] to [rich], leaving the entities consistent with it;
/// falls back to plain text when the result cannot hold the entities.
RichText applyReplacement(RichText rich, TextReplacement replacement) {
  try {
    return rich.replaceRange(
      replacement.start,
      replacement.oldEnd,
      RichText.plain(replacement.inserted),
    );
    // RichText reports entities that cannot coexist as an ArgumentError and
    // offers no way to ask first.
    // ignore: avoid_catching_errors
  } on ArgumentError {
    return RichText.plain(
      rich.plain.replaceRange(
        replacement.start,
        replacement.oldEnd,
        replacement.inserted,
      ),
    );
  }
}
