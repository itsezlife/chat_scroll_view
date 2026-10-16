import 'package:meta/meta.dart';

/// The decision half of a [ComposerQueryKind]: where a token may start and
/// which characters it is made of.
///
/// A rule is two pure functions, so it is cheap to evaluate on every
/// keystroke and trivial to test.
@immutable
final class ComposerQueryRule {
  /// Creates a rule from [opensAt] and [continues].
  const ComposerQueryRule({required this.opensAt, required this.continues});

  /// Opens after the start of the text or whitespace, and continues over
  /// letters, digits and underscores: the shape of a mention or a hashtag.
  static const ComposerQueryRule word = ComposerQueryRule(
    opensAt: _afterWhitespace,
    continues: isWordCodePoint,
  );

  /// Opens only at the very start of the text, and continues like [word]: the
  /// shape of a bot command.
  static const ComposerQueryRule startOfText = ComposerQueryRule(
    opensAt: _atStart,
    continues: isWordCodePoint,
  );

  /// Whether a trigger found at [triggerIndex] of the text may open a token.
  final bool Function(String text, int triggerIndex) opensAt;

  /// Whether [codePoint] may be part of the token text that follows the
  /// trigger.
  ///
  /// Must reject the trigger itself, or a scan from the caret would run past
  /// it.
  final bool Function(int codePoint) continues;

  /// Whether [codePoint] is a letter, a digit or an underscore.
  static bool isWordCodePoint(int codePoint) =>
      codePoint == 0x5F ||
      _wordCharacter.hasMatch(String.fromCharCode(codePoint));

  static final RegExp _wordCharacter = RegExp(r'[\p{L}\p{N}]', unicode: true);

  static bool _atStart(String text, int triggerIndex) => triggerIndex == 0;

  static bool _afterWhitespace(String text, int triggerIndex) =>
      triggerIndex == 0 || _isWhitespace(text.codeUnitAt(triggerIndex - 1));

  static bool _isWhitespace(int unit) =>
      unit == 0x20 || (unit >= 0x09 && unit <= 0x0D) || unit == 0xA0;
}

/// A kind of token the host wants the composer to watch for at the caret: a
/// mention, a hashtag, a command, an inline-emoji shortcode.
///
/// The set of kinds is open: the host registers its own with
/// `ComposerController.registerQueryKind`, and builds the suggestion panel for
/// each. The composer knows no kind by itself.
@immutable
final class ComposerQueryKind {
  /// Creates a kind with the opaque [id] that opens at [trigger].
  const ComposerQueryKind({
    required this.id,
    required this.trigger,
    this.rule = ComposerQueryRule.word,
    this.maxLength = 64,
  }) : assert(id != '', 'A query kind needs an id.'),
       assert(trigger != '', 'A query kind needs a trigger.'),
       assert(maxLength > 0, 'A query token must be allowed some length.');

  /// What the host calls this kind; unique among the registered kinds.
  final String id;

  /// The text that opens a token of this kind, usually one character.
  final String trigger;

  /// Where a token may open and what it is made of.
  final ComposerQueryRule rule;

  /// The most UTF-16 code units a token may have after its trigger. Longer
  /// words are not queries, and the scan back from the caret stops here.
  final int maxLength;

  @override
  bool operator ==(Object other) =>
      other is ComposerQueryKind &&
      other.id == id &&
      other.trigger == trigger &&
      other.rule == rule &&
      other.maxLength == maxLength;

  @override
  int get hashCode => Object.hash(id, trigger, rule, maxLength);

  @override
  String toString() => 'ComposerQueryKind($id, "$trigger")';
}
