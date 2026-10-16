import 'package:chat_composer/src/text/composer_entity_styles.dart';
import 'package:chat_composer/src/text/inline_content_span_builder.dart';
import 'package:chat_composer/src/text/text_replacement.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart' hide RichText;

/// A [TextEditingController] whose text carries entities: it keeps the plain
/// text and the [Entity] spans of a [RichText] in step with every edit.
///
/// The platform text input only knows plain text and reports an edit as a
/// whole new value. This controller recovers the replacement behind each
/// value, applies it to the rich text (see [RichText.replaceRange] for how
/// entities follow an edit) and exposes the result as [richText], the value a
/// host stores as a draft, sends, or loads back for editing.
///
/// ## Inline content
///
/// An inline content reference ([insertContent]) is plain text, its
/// alternative text, with an atomic entity over it. It behaves as one unit
/// for the user: the caret never rests inside it, a range selection widens to
/// cover it whole, and a deletion that touches it removes all of it. How it
/// looks in the field is the [inlineContentBuilder]'s business.
///
/// ## IME composition
///
/// While the input method composes (the composing range is non-empty) the
/// text changes with every key, in ways that are not edits yet: a candidate
/// replaces another, a word is rebuilt. The entities are therefore left
/// alone until the composition finishes, and the whole composition is then
/// applied as one replacement against the text before it started. Until then
/// [richText] is derived from the current text and does not change what the
/// controller keeps, and no selection snapping or atom widening happens.
///
/// ## Not here
///
/// Formatting commands and the selection menu, link and mention detection
/// (the host makes those entities), and the content painting.
class ComposerTextController extends TextEditingController {
  /// Creates a controller holding [initial], or empty text.
  ///
  /// [inlineContentBuilder] shows inline content references; the default shows
  /// their alternative text. [entityStyles] paints the other entities.
  ComposerTextController({
    RichText? initial,
    InlineContentSpanBuilder inlineContentBuilder = alternativeTextSpan,
    ComposerEntityStyles entityStyles = const ComposerEntityStyles(),
  }) : _rich = initial ?? RichText.empty,
       _inlineContentBuilder = inlineContentBuilder,
       _entityStyles = entityStyles,
       super(text: initial?.plain);

  /// The default [InlineContentSpanBuilder]: the alternative text in [style].
  static InlineSpan alternativeTextSpan(
    BuildContext context,
    InlineContentRef reference,
    TextStyle style,
  ) => TextSpan(text: reference.alternativeText, style: style);

  RichText _rich;
  RichText? _derived;
  bool _composing = false;
  InlineContentSpanBuilder _inlineContentBuilder;
  ComposerEntityStyles _entityStyles;

  /// The text with its entities, always consistent with [text].
  RichText get richText {
    if (!_composing) return _rich;
    return _derived ??= _deriveDuringComposition();
  }

  /// Whether the input method is composing, so entity edits are pending.
  bool get isComposing => _composing;

  /// How the field shows an inline content reference.
  InlineContentSpanBuilder get inlineContentBuilder => _inlineContentBuilder;

  set inlineContentBuilder(InlineContentSpanBuilder builder) {
    if (identical(builder, _inlineContentBuilder)) return;
    _inlineContentBuilder = builder;
    notifyListeners();
  }

  /// How the field paints entities other than inline content.
  ComposerEntityStyles get entityStyles => _entityStyles;

  set entityStyles(ComposerEntityStyles styles) {
    if (styles == _entityStyles) return;
    _entityStyles = styles;
    notifyListeners();
  }

  // --- Platform edits ---

  @override
  set value(TextEditingValue newValue) {
    final composing =
        newValue.composing.isValid && !newValue.composing.isCollapsed;
    if (composing) {
      _composing = true;
      _derived = null;
      super.value = newValue;
      return;
    }
    final base = _rich;
    final previous = super.value;
    if (newValue.text == base.plain) {
      _composing = false;
      _derived = null;
      final textUnchanged = previous.text == newValue.text;
      super.value = newValue.copyWith(
        selection: _snap(
          newValue.selection,
          base,
          textUnchanged
              ? previous.selection
              : const TextSelection.collapsed(offset: -1),
        ),
      );
      return;
    }
    final replacement = TextReplacement.between(
      base.plain,
      newValue.text,
      caret: _caretOf(newValue.selection),
    );
    final (from, to) = _widenOverAtoms(
      base,
      replacement.start,
      replacement.oldEnd,
    );
    final widened = from != replacement.start || to != replacement.oldEnd;
    final next = replacement.widenedTo(from, to).applyTo(base);
    _commit(
      next,
      TextEditingValue(
        text: next.plain,
        selection: widened
            ? TextSelection.collapsed(
                offset: from + replacement.inserted.length,
              )
            : _snap(
                newValue.selection,
                next,
                const TextSelection.collapsed(offset: -1),
              ),
      ),
    );
  }

  RichText _deriveDuringComposition() {
    final replacement = TextReplacement.between(
      _rich.plain,
      value.text,
      caret: _caretOf(value.selection),
    );
    return replacement.applyTo(_rich);
  }

  int _caretOf(TextSelection selection) =>
      selection.isValid && selection.isCollapsed ? selection.baseOffset : -1;

  void _commit(RichText next, TextEditingValue newValue) {
    final entitiesChanged = next != _rich;
    final before = super.value;
    _rich = next;
    _composing = false;
    _derived = null;
    super.value = newValue;
    // An edit of the entities alone leaves the value equal, and a value
    // notifier stays silent for an equal value.
    if (entitiesChanged && before == newValue) notifyListeners();
  }

  // --- Commands ---

  /// Replaces the whole content with [text] and puts the caret at [selection],
  /// the end by default.
  ///
  /// Ends any composition. Use it to restore a draft or load a message for
  /// editing.
  void restore(RichText text, {TextSelection? selection}) {
    assert(
      selection == null ||
          !selection.isValid ||
          (selection.start >= 0 && selection.end <= text.length),
      'The selection must lie inside the restored text.',
    );
    _commit(
      text,
      TextEditingValue(
        text: text.plain,
        selection: selection ?? TextSelection.collapsed(offset: text.length),
      ),
    );
  }

  /// Replaces the selection (the end of the text when there is none) with
  /// [inserted] and puts the caret after it.
  ///
  /// Entities of [inserted] that cannot coexist with the ones around the
  /// insertion point (a mention inside code, for example) are dropped; the
  /// text still goes in. Ends any composition.
  void insert(RichText inserted) {
    final selection = value.selection;
    final end = value.text.length;
    final start = selection.isValid ? selection.start : end;
    replaceRange(start, selection.isValid ? selection.end : end, inserted);
  }

  /// Replaces the selection with the plain [text]; see [insert].
  void insertText(String text) => insert(RichText.plain(text));

  /// Replaces the selection with [reference]: its alternative text under an
  /// atomic inline content entity; see [insert].
  void insertContent(InlineContentRef reference) {
    final alternative = reference.alternativeText;
    insert(
      RichText(alternative, [
        Entity(0, alternative.length, EntityKind.inlineContent(reference.key)),
      ]),
    );
  }

  /// Deletes the selection, or when it is collapsed, the unit behind the
  /// caret: a whole atomic entity that ends there, else one grapheme cluster.
  /// Does nothing at the start of the text.
  void deleteBackward() {
    final selection = value.selection;
    if (selection.isValid && !selection.isCollapsed) {
      replaceRange(selection.start, selection.end, RichText.empty);
      return;
    }
    final caret = selection.isValid ? selection.baseOffset : text.length;
    if (caret <= 0) return;
    final before = text.substring(0, caret);
    replaceRange(caret - before.characters.last.length, caret, RichText.empty);
  }

  /// Replaces [start]..[end] of the text with [inserted] and puts the caret
  /// after it.
  ///
  /// The range widens to hold any atomic entity it touches whole. Entities of
  /// [inserted] that cannot coexist with the ones around it are dropped; the
  /// text still goes in. Ends any composition.
  void replaceRange(int start, int end, RichText inserted) {
    final current = richText;
    final (from, to) = _widenOverAtoms(current, start, end);
    RichText next;
    try {
      next = current.replaceRange(from, to, inserted);
      // RichText reports entities that cannot coexist as an ArgumentError and
      // offers no way to ask first.
      // ignore: avoid_catching_errors
    } on ArgumentError {
      next = TextReplacement(
        start: from,
        oldEnd: to,
        inserted: inserted.plain,
      ).applyTo(current);
    }
    _commit(
      next,
      TextEditingValue(
        text: next.plain,
        selection: TextSelection.collapsed(offset: from + inserted.length),
      ),
    );
  }

  // --- Atomic entities ---

  /// [start]..[end] widened outwards until it holds every atomic entity it
  /// touches whole, and does not cut a surrogate pair.
  (int, int) _widenOverAtoms(RichText rich, int start, int end) {
    var from = start;
    var to = end;
    for (final entity in rich.entities) {
      if (!entity.kind.isAtomic) continue;
      final touches = from == to
          ? entity.offset < from && from < entity.end
          : entity.offset < to && entity.end > from;
      if (touches) {
        if (entity.offset < from) from = entity.offset;
        if (entity.end > to) to = entity.end;
      }
    }
    final plain = rich.plain;
    while (RichText.splitsSurrogatePair(plain, from)) {
      from--;
    }
    while (RichText.splitsSurrogatePair(plain, to)) {
      to++;
    }
    return (from, to);
  }

  /// [selection] moved off the inside of any atomic entity of [rich].
  ///
  /// A caret that moved forward lands after the entity and one that moved back
  /// lands before it. With no previous position to compare (the text just
  /// changed) the nearer edge wins. A range widens to hold the entities at its
  /// ends whole.
  TextSelection _snap(
    TextSelection selection,
    RichText rich,
    TextSelection previous,
  ) {
    if (!selection.isValid) return selection;
    for (final entity in rich.entities) {
      if (!entity.kind.isAtomic) continue;
      if (selection.isCollapsed) {
        final offset = selection.baseOffset;
        if (offset <= entity.offset || offset >= entity.end) continue;
        final forward = previous.isValid && previous.isCollapsed
            ? offset > previous.baseOffset
            : offset - entity.offset >= entity.end - offset;
        return TextSelection.collapsed(
          offset: forward ? entity.end : entity.offset,
          affinity: selection.affinity,
        );
      }
    }
    if (selection.isCollapsed) return selection;
    var start = selection.start;
    var end = selection.end;
    for (final entity in rich.entities) {
      if (!entity.kind.isAtomic) continue;
      if (entity.offset < start && start < entity.end) start = entity.offset;
      if (entity.offset < end && end < entity.end) end = entity.end;
    }
    if (start == selection.start && end == selection.end) return selection;
    return selection.baseOffset <= selection.extentOffset
        ? selection.copyWith(baseOffset: start, extentOffset: end)
        : selection.copyWith(baseOffset: end, extentOffset: start);
  }

  // --- Painting ---

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    required bool withComposing,
    TextStyle? style,
  }) {
    final rich = richText;
    final text = value.text;
    assert(rich.plain == text, 'The entities must describe the shown text.');
    final base = style ?? const TextStyle();
    final composing =
        withComposing &&
            value.isComposingRangeValid &&
            !value.composing.isCollapsed
        ? value.composing
        : null;
    final cuts = <int>{0, text.length};
    for (final entity in rich.entities) {
      cuts
        ..add(entity.offset)
        ..add(entity.end);
    }
    if (composing != null) {
      cuts
        ..add(composing.start)
        ..add(composing.end);
    }
    final sorted = cuts.toList()..sort();
    final children = <InlineSpan>[];
    for (var i = 0; i + 1 < sorted.length; i++) {
      final from = sorted[i];
      final to = sorted[i + 1];
      if (from == to) continue;
      final active = [
        for (final entity in rich.entities)
          if (entity.offset <= from && entity.end >= to) entity,
      ];
      var segmentStyle = _styleOf(active, base);
      if (composing != null && composing.start <= from && composing.end >= to) {
        segmentStyle = segmentStyle.merge(
          const TextStyle(decoration: TextDecoration.underline),
        );
      }
      final content = active.where(
        (e) => switch (e.kind) {
          EntityKind$InlineContent() => e.offset == from && e.end == to,
          _ => false,
        },
      );
      if (content.isNotEmpty) {
        final reference = rich.inlineContentOf(content.first)!;
        final span = _inlineContentBuilder(context, reference, segmentStyle);
        assert(
          span.toPlainText(includeSemanticsLabels: false).length ==
              reference.alternativeText.length,
          'An inline content span must lay out as exactly the '
          '${reference.alternativeText.length} code units of its alternative '
          'text.',
        );
        children.add(span);
      } else {
        children.add(
          TextSpan(text: text.substring(from, to), style: segmentStyle),
        );
      }
    }
    return TextSpan(style: style, children: children);
  }

  TextStyle _styleOf(List<Entity> active, TextStyle base) {
    if (active.isEmpty) return base;
    final decorations = <TextDecoration>[];
    var result = base;
    for (final entity in active) {
      switch (entity.kind) {
        case EntityKind$Style(:final style):
          switch (style) {
            case EntityStyle.bold:
              result = result.merge(
                const TextStyle(fontWeight: FontWeight.bold),
              );
            case EntityStyle.italic:
              result = result.merge(
                const TextStyle(fontStyle: FontStyle.italic),
              );
            case EntityStyle.underline:
              decorations.add(TextDecoration.underline);
            case EntityStyle.strike:
              decorations.add(TextDecoration.lineThrough);
            case EntityStyle.code:
              result = result.merge(
                TextStyle(
                  fontFamily: 'monospace',
                  backgroundColor: _entityStyles.codeBackground,
                ),
              );
            case EntityStyle.spoiler:
              result = result.merge(
                TextStyle(backgroundColor: _entityStyles.spoilerBackground),
              );
            case EntityStyle.quote:
              result = result.merge(
                TextStyle(backgroundColor: _entityStyles.quoteBackground),
              );
          }
        case EntityKind$Link():
          decorations.add(TextDecoration.underline);
          result = result.merge(TextStyle(color: _entityStyles.link));
        case EntityKind$Mention():
          result = result.merge(TextStyle(color: _entityStyles.mention));
        case EntityKind$InlineContent():
          break;
      }
    }
    if (decorations.isEmpty) return result;
    return result.merge(
      TextStyle(decoration: TextDecoration.combine(decorations)),
    );
  }
}
