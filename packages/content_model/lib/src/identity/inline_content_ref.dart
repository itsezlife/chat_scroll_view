import 'package:content_model/src/identity/content_key.dart';
import 'package:meta/meta.dart';

/// A reference to content embedded in running text.
///
/// A [key] says which content, and the mandatory [alternativeText] says what
/// the text reads as without it. The alternative is what copying, selecting
/// and assistive technology use, so a reference without one would vanish from
/// all three; it is therefore required, not optional.
///
/// Where the reference sits in a text, its span and the formatting around it
/// belong to the rich-text value and the body model that hold it, not here.
@immutable
final class InlineContentRef {
  /// Creates a reference to [key] that reads as [alternativeText], which must
  /// not be empty.
  const InlineContentRef({required this.key, required this.alternativeText})
    : assert(
        alternativeText != '',
        'An InlineContentRef needs a plain-text alternative.',
      );

  /// The embedded content.
  final ContentKey key;

  /// The plain text this reference stands for.
  final String alternativeText;

  @override
  bool operator ==(Object other) =>
      other is InlineContentRef &&
      other.key == key &&
      other.alternativeText == alternativeText;

  @override
  int get hashCode => Object.hash(key, alternativeText);

  @override
  String toString() => 'InlineContentRef($key, $alternativeText)';
}
