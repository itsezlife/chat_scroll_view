import 'package:content_model/src/rich_text/detection/code_point.dart';
import 'package:content_model/src/rich_text/entity.dart';
import 'package:content_model/src/rich_text/entity_kind.dart';
import 'package:content_model/src/rich_text/normalization.dart';

/// Finds `@name` and `#tag` in plain text.
///
/// Internal to [EntityDetection]: it reports candidates, and the caller
/// decides which survive (exclusions, overlaps, the budget).
///
/// - **Username** (Android `MessageObject.urlPattern`): `@` after the start of
///   the text, whitespace or `(`, then 1 to 32 characters of `[A-Za-z0-9_]`.
///   The pattern would take the first 32 characters of a longer name; a name
///   is a whole word here, so a longer one is not a username.
/// - **Hashtag** (the pattern, with iOS's Unicode letters): `#` after the same
///   boundary, then a letter or `_` and at least one more letter, mark, digit,
///   `_` or `.`. A sentence's closing dots are not part of the tag, and the
///   `#tag@name` form does not exist: the tag ends at the `@`.
abstract final class TagScanner {
  /// The longest username, in characters.
  static const int maxUsernameLength = 32;

  /// The candidates in [text], in text order.
  static List<Entity> scan(
    String text, {
    required bool usernames,
    required bool hashtags,
  }) {
    final found = <Entity>[];
    var i = 0;
    while (i < text.length) {
      final unit = text.codeUnitAt(i);
      if (unit == _at && usernames && _atBoundary(text, i)) {
        i = _username(text, i, found);
      } else if (unit == _hash && hashtags && _atBoundary(text, i)) {
        i = _hashtag(text, i, found);
      } else {
        i++;
      }
    }
    return found;
  }

  static const int _at = 0x40;
  static const int _hash = 0x23;
  static const int _dot = 0x2E;
  static const int _underscore = 0x5F;
  static const int _openParen = 0x28;

  static bool _atBoundary(String text, int i) =>
      i == 0 ||
      CanonicalEntities.isWhitespaceUnit(text.codeUnitAt(i - 1)) ||
      text.codeUnitAt(i - 1) == _openParen;

  /// Adds the username at [i] when there is one; returns where to go on.
  static int _username(String text, int i, List<Entity> found) {
    var end = i + 1;
    while (end < text.length && _isNameUnit(text.codeUnitAt(end))) {
      end++;
    }
    final length = end - i - 1;
    if (length >= 1 && length <= maxUsernameLength) {
      found.add(
        Entity(i, length + 1, EntityKind.username(text.substring(i + 1, end))),
      );
    }
    return end;
  }

  /// Adds the hashtag at [i] when there is one; returns where to go on.
  static int _hashtag(String text, int i, List<Entity> found) {
    var end = i + 1;
    var characters = 0;
    var contentEnd = end;
    var contentCharacters = 0;
    while (end < text.length) {
      final cp = CodePoint.at(text, end);
      final isFirst = characters == 0;
      final accepted = isFirst ? _isTagStart(cp) : _isTagWord(cp) || cp == _dot;
      if (!accepted) break;
      end += CodePoint.width(cp);
      characters++;
      if (cp != _dot) {
        contentEnd = end;
        contentCharacters = characters;
      }
    }
    if (contentCharacters >= 2) {
      found.add(
        Entity(
          i,
          contentEnd - i,
          EntityKind.hashtag(text.substring(i + 1, contentEnd)),
        ),
      );
    }
    return end > i + 1 ? end : i + 1;
  }

  static bool _isNameUnit(int unit) =>
      (unit >= 0x30 && unit <= 0x39) ||
      (unit >= 0x41 && unit <= 0x5A) ||
      (unit >= 0x61 && unit <= 0x7A) ||
      unit == _underscore;

  static final RegExp _letter = RegExp(r'^\p{L}$', unicode: true);
  static final RegExp _word = RegExp(r'^[\p{L}\p{M}\p{N}]$', unicode: true);

  static bool _isTagStart(int cp) =>
      cp == _underscore ||
      (cp < 0x80
          ? (cp >= 0x41 && cp <= 0x5A) || (cp >= 0x61 && cp <= 0x7A)
          : _letter.hasMatch(String.fromCharCode(cp)));

  static bool _isTagWord(int cp) =>
      cp < 0x80 ? _isNameUnit(cp) : _word.hasMatch(String.fromCharCode(cp));
}
