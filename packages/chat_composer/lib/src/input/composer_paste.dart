import 'package:flutter/widgets.dart';

/// A paste that put text into the field, as the host is told of it.
///
/// The host that offers to apply markdown formatting to a plain paste (the
/// reference desktop client's toast) reads it, and replaces [range] with
/// `ComposerTextController.replaceRange`. The offer is feedback UI and stays
/// the host's (ADR 032).
@immutable
final class ComposerPaste {
  /// A paste of [text] that landed in [range].
  const ComposerPaste({
    required this.range,
    required this.text,
    required this.wasRich,
  });

  /// Where [text] sits in the field's text now: the range the selection
  /// widened to (over an atomic entity it touched), not the one the user had.
  final TextRange range;

  /// The plain text that went in.
  final String text;

  /// Whether the paste came with formatting: the clipboard held a rich form
  /// and the paste was not one as plain text. Entities that could not sit where
  /// the text landed were dropped, and this is still true.
  final bool wasRich;

  @override
  bool operator ==(Object other) =>
      other is ComposerPaste &&
      other.range == range &&
      other.text == text &&
      other.wasRich == wasRich;

  @override
  int get hashCode => Object.hash(range, text, wasRich);

  @override
  String toString() => 'ComposerPaste($range, wasRich: $wasRich)';
}
