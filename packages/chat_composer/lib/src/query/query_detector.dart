import 'package:chat_composer/src/query/composer_input_query.dart';
import 'package:chat_composer/src/query/composer_query_kind.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/painting.dart' show TextRange;

/// Finds the input query the caret is in, among the [ComposerQueryKind]s a
/// host registered.
abstract final class QueryDetector {
  /// The query of the first of [kinds] whose token ends at [caret] in [text],
  /// or null.
  ///
  /// The scan walks back from the caret over the characters the kind's rule
  /// accepts, then wants the kind's trigger right before them, at a position
  /// the rule allows to open. A token never reaches into an atomic entity of
  /// [entities]: its text is a unit the user did not type.
  static ComposerInputQuery? detect(
    Iterable<ComposerQueryKind> kinds,
    String text,
    int caret,
    List<Entity> entities,
  ) {
    if (caret < 0 || caret > text.length) return null;
    for (final kind in kinds) {
      final start = _tokenStart(kind, text, caret);
      if (start == null) continue;
      if (_touchesAtom(entities, start, caret)) continue;
      return ComposerInputQuery(
        kind: kind,
        text: text.substring(start + kind.trigger.length, caret),
        range: TextRange(start: start, end: caret),
      );
    }
    return null;
  }
}

int? _tokenStart(ComposerQueryKind kind, String text, int caret) {
  var index = caret;
  while (index > 0 && caret - index < kind.maxLength) {
    final unit = text.codeUnitAt(index - 1);
    final isLow = (unit & 0xFC00) == 0xDC00 && index > 1;
    final width = isLow && (text.codeUnitAt(index - 2) & 0xFC00) == 0xD800
        ? 2
        : 1;
    final codePoint = width == 2
        ? 0x10000 +
              ((text.codeUnitAt(index - 2) & 0x3FF) << 10) +
              (unit & 0x3FF)
        : unit;
    if (!kind.rule.continues(codePoint)) break;
    index -= width;
  }
  if (caret - index > kind.maxLength) return null;
  final start = index - kind.trigger.length;
  if (start < 0 || !text.startsWith(kind.trigger, start)) return null;
  return kind.rule.opensAt(text, start) ? start : null;
}

bool _touchesAtom(List<Entity> entities, int start, int end) => entities.any(
  (entity) => entity.kind.isAtomic && entity.offset < end && entity.end > start,
);
