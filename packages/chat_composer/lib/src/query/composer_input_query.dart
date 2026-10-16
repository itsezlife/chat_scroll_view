import 'dart:ui' show Rect;

import 'package:chat_composer/src/query/composer_query_kind.dart';
import 'package:flutter/painting.dart' show TextRange;
import 'package:meta/meta.dart';

/// The token at the caret that a registered [ComposerQueryKind] recognised:
/// what the host builds a suggestion panel from.
///
/// A value is a snapshot; the composer publishes a new one when the token or
/// its anchor changes and `null` when there is no token.
@immutable
final class ComposerInputQuery {
  /// Creates a query.
  const ComposerInputQuery({
    required this.kind,
    required this.text,
    required this.range,
    this.caretAnchor,
  });

  /// The kind that recognised the token.
  final ComposerQueryKind kind;

  /// The token text after the trigger, without it. Empty right after the
  /// trigger.
  final String text;

  /// Where the token sits in the field text, trigger included: the range
  /// `ComposerController.replaceQuery` replaces.
  final TextRange range;

  /// The caret rectangle in the field's coordinate space, for anchoring a
  /// popup, or null before the field has laid out and reported it. It may lag
  /// the text by a frame.
  final Rect? caretAnchor;

  /// Whether [other] is the same token, whatever its anchor.
  bool isSameToken(ComposerInputQuery other) =>
      other.kind == kind && other.text == text && other.range == range;

  /// This query with [caretAnchor] replaced.
  ComposerInputQuery withAnchor(Rect? anchor) => ComposerInputQuery(
    kind: kind,
    text: text,
    range: range,
    caretAnchor: anchor,
  );

  @override
  bool operator ==(Object other) =>
      other is ComposerInputQuery &&
      isSameToken(other) &&
      other.caretAnchor == caretAnchor;

  @override
  int get hashCode => Object.hash(kind, text, range, caretAnchor);

  @override
  String toString() => 'ComposerInputQuery(${kind.id}, "$text", $range)';
}
