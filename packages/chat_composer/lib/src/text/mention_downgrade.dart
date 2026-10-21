import 'package:content_model/content_model.dart';

/// [text] with every mention whose id [isResolved] does not accept rewritten
/// to what it displays, for the send path before the text is encoded.
///
/// A mention is an id the host looked up; one the host did not resolve in
/// this draft (a paste from another page's HTML) must not reach the wire as a
/// claim about a person (ADR 034). A draft the host restores, or a message it
/// loads for editing, is its own earlier state, so `ComposerController`
/// counts its mentions as resolved; [isResolved] decides the rest. A mention
/// it rejects becomes an [EntityKind.username] over the same `@name` text,
/// which the server and the readers treat as text, so the message still says
/// what the user saw. A mention that displays no `@name` (a display name, say)
/// loses its entity and keeps its text: there is no name to carry, as ADR 034
/// has the server strip such a link to its label. Nothing is ever rejected,
/// and the styles around the mention stay.
///
/// Returns [text] itself when there is nothing to rewrite.
RichText downgradeUnresolvedMentions(
  RichText text,
  bool Function(String id) isResolved,
) {
  var changed = false;
  final entities = <Entity>[];
  for (final entity in text.entities) {
    final kind = entity.kind;
    if (kind is! EntityKind$Mention || isResolved(kind.id)) {
      entities.add(entity);
      continue;
    }
    changed = true;
    final shown = text.textOf(entity);
    if (_atName.hasMatch(shown)) {
      entities.add(
        Entity(
          entity.offset,
          entity.length,
          EntityKind.username(shown.substring(1)),
        ),
      );
    }
  }
  return changed ? RichText(text.plain, entities) : text;
}

// An `@` and at least one character, none of them white space.
final _atName = RegExp(r'^@\S+$');
