import 'package:chat_composer/src/text/text_replacement.dart';
import 'package:content_model/content_model.dart';

/// How text typed against a styled run takes its style.
///
/// [RichText.replaceRange] grows an entity only for text inserted strictly
/// inside it. Typing goes further: the word typed against a run's edge
/// continues the run, until whitespace ends it.
///
/// - At a run's end, the inserted text up to its first whitespace joins the
///   run.
/// - At a run's start, with no run ending there, the inserted text from its
///   last whitespace on joins it. Where one run ends and another starts, the
///   one that ends wins.
/// - Inside a run it grows as before, whitespace included.
///
/// What continues: the inline styles (bold, italic, underline, strike,
/// spoiler, code) and links. Not quotes, code blocks and list items, which
/// follow lines, nor mentions and inline content, which are atoms, nor
/// usernames and hashtags, which a detector makes.
abstract final class StyleContinuation {
  /// [replacement] applied to [base], the inserted text continuing the runs
  /// it touches as above.
  ///
  /// Falls back to [TextReplacement.applyTo] when the continued runs cannot
  /// coexist with the rest.
  static RichText applied(RichText base, TextReplacement replacement) {
    final inserted = replacement.inserted;
    if (inserted.isEmpty) return replacement.applyTo(base);
    final RichText removed;
    try {
      removed = base.delete(replacement.start, replacement.oldEnd);
      // RichText reports a range it cannot cut as an ArgumentError.
      // ignore: avoid_catching_errors
    } on ArgumentError {
      return replacement.applyTo(base);
    }
    final at = replacement.start;
    final ending = [
      for (final entity in removed.entities)
        if (entity.end == at && _continues(entity.kind)) entity.kind,
    ];
    final List<Entity> carried;
    if (ending.isNotEmpty) {
      final length = _leadingWord(inserted);
      carried = [
        if (length > 0)
          for (final kind in ending) Entity(0, length, kind),
      ];
    } else {
      final length = _trailingWord(inserted);
      carried = [
        if (length > 0)
          for (final entity in removed.entities)
            if (entity.offset == at && _continues(entity.kind))
              Entity(inserted.length - length, length, entity.kind),
      ];
    }
    if (carried.isEmpty) return replacement.applyTo(base);
    try {
      return removed.insert(at, RichText(inserted, carried));
      // RichText reports entities that cannot coexist as an ArgumentError
      // and offers no way to ask first.
      // ignore: avoid_catching_errors
    } on ArgumentError {
      return replacement.applyTo(base);
    }
  }

  static bool _continues(EntityKind kind) => switch (kind) {
    EntityKind$Style() => kind != EntityKind.quote,
    EntityKind$Link() => true,
    _ => false,
  };

  // The length of [text] before its first whitespace.
  static int _leadingWord(String text) {
    var i = 0;
    while (i < text.length && !_isWhitespace(text.codeUnitAt(i))) {
      i++;
    }
    return i;
  }

  // The length of [text] after its last whitespace.
  static int _trailingWord(String text) {
    var i = text.length;
    while (i > 0 && !_isWhitespace(text.codeUnitAt(i - 1))) {
      i--;
    }
    return text.length - i;
  }

  static bool _isWhitespace(int unit) =>
      unit == 0x20 ||
      unit == 0x09 ||
      unit == 0x0A ||
      unit == 0x0D ||
      unit == 0xA0;
}
