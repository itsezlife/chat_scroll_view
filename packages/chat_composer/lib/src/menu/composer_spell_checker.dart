import 'package:meta/meta.dart';

/// What a spell checker says about one word.
@immutable
final class ComposerWordSpelling {
  /// A verdict: [isCorrect], the [suggestions] for a wrong word, and whether
  /// the word is in the user's own dictionary.
  const ComposerWordSpelling({
    required this.isCorrect,
    this.suggestions = const [],
    this.inUserDictionary = false,
  });

  /// Whether the word is spelled right.
  final bool isCorrect;

  /// Replacements for a wrong word, best first.
  final List<String> suggestions;

  /// Whether the user added the word to their dictionary.
  final bool inUserDictionary;
}

/// The host's spell checker, which the composer's pointer menu asks about the
/// word under the pointer.
///
/// **A seam, with no implementation here.** The platforms' checkers (the
/// system checker on macOS, Windows and Linux) are the host's to wrap: this
/// package ships none, and the composer draws no squiggles. Given a checker,
/// the pointer menu shows the reference client's Spelling submenu for the
/// word the pointer is over; without one it shows no Spelling row.
///
/// Every call may be slow (a system checker is asynchronous on some
/// platforms): the menu waits for [check] before it opens, as the reference
/// menu waits for its own checker. A call that throws is reported and the menu
/// opens without the Spelling row.
abstract interface class ComposerSpellChecker {
  /// What is known about [word].
  Future<ComposerWordSpelling> check(String word);

  /// Adds [word] to the user's dictionary.
  Future<void> addToDictionary(String word);

  /// Stops flagging [word] in this session.
  Future<void> ignore(String word);

  /// Takes [word] out of the user's dictionary.
  Future<void> removeFromDictionary(String word);
}
