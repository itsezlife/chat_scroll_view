import 'package:chat_composer/src/text/composer_entity_styles.dart';
import 'package:chat_composer/src/text/inline_content_span_builder.dart';
import 'package:chat_composer/src/text/list_editing.dart';
import 'package:chat_composer/src/text/text_formatting.dart';
import 'package:chat_composer/src/text/text_replacement.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart' hide RichText;
import 'package:meta/meta.dart';

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
/// ## Formatting commands
///
/// [toggleStyle], [toggleCodeBlock], [applyLink], [removeLink] and
/// [clearFormatting] map one to one onto the [EntityKind]s, and [isActive] and
/// [canApply] tell a menu or a shortcut map which are on and which would do
/// anything. They act on the selection and change only the entities, never the
/// text, except that [applyLink] at a caret inserts the URL. What may coexist
/// (code excludes other styles, a quote widens to whole lines) is [RichText]'s
/// to decide; a command it would make impossible does nothing, and [canApply]
/// says so beforehand.
///
/// - A caret turns off every command but [applyLink] and the kinds that cover
///   whole lines (quote, code block), which act on the caret's line. There is
///   no typing style: text typed after a command is plain, because no
///   reference client has one and it makes entity edits on an IME commit
///   ambiguous.
/// - A selection edge inside an atomic entity widens to hold it whole, so a
///   command never splits one.
/// - A command that touches the IME composition does nothing; one that does not
///   leaves the composition alone.
///
/// ## Lists
///
/// Off unless [lists] is set, and then nothing about lists changes: a list
/// item that comes in with a restored or pasted text stays in it as it was,
/// unedited and without a gutter, and no key or command below does anything.
///
/// With [lists] on, an item is one [EntityKind.list] over its lines (see
/// there), and the editor behaves as a list editor does:
///
/// - Typing `- `, `* ` or `1. ` at the start of a line makes the line an item
///   and takes the marker out of the text. Elsewhere in a line it stays text.
/// - [toggleList] makes the lines under the selection items of a kind, or
///   takes them out when they all are.
/// - Enter continues the item with one of the same kind and depth, and an
///   empty item leaves the list (one level out first). Backspace at the start
///   of an item does the same instead of joining it to the line before.
///   [indentListItems] and [outdentListItems] move items between depths 0
///   and 3; [insertSoftBreak] goes on a new line inside the item.
///   Enter-to-send keys of the view stand aside while the caret is in an item
///   ([isInListItem]), as the Enter of any editor with lists does.
/// - Two or more marker lines in text inserted at once (a keyboard's paste,
///   autofill, [withPastedLists]) become items.
///
/// An item with no text yet is not representable in a [RichText]: the caret
/// rests on an empty line the controller remembers is an item (see
/// [PendingListItem]) until text lands on it or the caret leaves.
///
/// ## Not here
///
/// The selection menu and the shortcuts that call the commands, link and
/// mention detection (the host makes those entities), undo, and the content
/// painting.
class ComposerTextController extends TextEditingController {
  /// Creates a controller holding [initial], or empty text.
  ///
  /// [inlineContentBuilder] shows inline content references; the default shows
  /// their alternative text. [entityStyles] paints the other entities.
  /// [lists] turns on list editing; see "Lists" above.
  ComposerTextController({
    RichText? initial,
    InlineContentSpanBuilder inlineContentBuilder = alternativeTextSpan,
    ComposerEntityStyles entityStyles = const ComposerEntityStyles(),
    this.lists = false,
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

  /// Whether the field edits lists; see "Lists" above.
  final bool lists;

  RichText _rich;
  RichText? _derived;
  PendingListItem? _pending;
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
      final snapped = _snap(
        newValue.selection,
        base,
        textUnchanged
            ? previous.selection
            : const TextSelection.collapsed(offset: -1),
      );
      // The empty item is the caret's line: the caret leaving it ends it.
      if (_pending case final pending?
          when !(snapped.isValid &&
              snapped.isCollapsed &&
              snapped.baseOffset == pending.offset)) {
        _pending = null;
      }
      super.value = newValue.copyWith(selection: snapped);
      return;
    }
    if (lists) {
      final edit = _listKeystroke(previous, newValue, base);
      if (edit != null) {
        _commitListEdit(edit);
        return;
      }
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
    final absorbed = lists
        ? _absorbedInsertion(base, previous, replacement)
        : null;
    if (absorbed != null) {
      final next = _fitted(base, from, to, absorbed);
      if (next != null) {
        _commit(
          next,
          TextEditingValue(
            text: next.plain,
            selection: TextSelection.collapsed(offset: from + absorbed.length),
          ),
        );
        return;
      }
    }
    var next = replacement.widenedTo(from, to).applyTo(base);
    // Text landing on the empty item is what makes it an item.
    final pending = lists && !widened ? _pending : null;
    if (pending != null &&
        replacement.start == pending.offset &&
        replacement.oldEnd == pending.offset &&
        replacement.inserted.isNotEmpty &&
        !replacement.inserted.startsWith('\n')) {
      next =
          TextFormatting.applied(
            next,
            pending.offset,
            pending.offset,
            pending.entityKind,
          ) ??
          next;
    }
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

  // --- List keystrokes ---

  // The list edit the platform's [newValue] amounts to, or null when it is an
  // edit like any other. Only a single keystroke at a caret counts: a marker's
  // space, Enter, or Backspace over the line break before an item's start.
  ListEdit? _listKeystroke(
    TextEditingValue previous,
    TextEditingValue newValue,
    RichText base,
  ) {
    final selection = previous.selection;
    if (!selection.isValid ||
        !selection.isCollapsed ||
        previous.text != base.plain ||
        (previous.composing.isValid && !previous.composing.isCollapsed)) {
      return null;
    }
    final caret = selection.baseOffset;
    final old = previous.text;
    final text = newValue.text;
    if (text.length == old.length + 1 &&
        text.startsWith(old.substring(0, caret)) &&
        text.endsWith(old.substring(caret))) {
      return switch (text[caret]) {
        ' ' => ListEditing.typedMarker(base, caret),
        '\n' => ListEditing.enter(base, caret, _pending),
        _ => null,
      };
    }
    if (caret > 0 &&
        old.codeUnitAt(caret - 1) == 0x0A &&
        text == old.replaceRange(caret - 1, caret, '')) {
      return ListEditing.backspaceAtStart(base, caret, _pending);
    }
    return null;
  }

  // The items that text inserted in one go stands for, when it holds marker
  // lines (a keyboard's paste or autofill; the clipboard's own go through
  // [withPastedLists]).
  RichText? _absorbedInsertion(
    RichText base,
    TextEditingValue previous,
    TextReplacement replacement,
  ) {
    if (replacement.inserted.length < 2 ||
        previous.text != base.plain ||
        (previous.composing.isValid && !previous.composing.isCollapsed)) {
      return null;
    }
    return _itemsFrom(base, replacement.start, replacement.inserted);
  }

  RichText? _itemsFrom(RichText base, int at, String inserted) {
    if (ListEditing.holdsLine(base, at)) return null;
    return ListEditing.itemsFromPlain(
      inserted,
      atLineStart: at == 0 || base.plain.codeUnitAt(at - 1) == 0x0A,
    );
  }

  /// [pasted] with its marker lines made list items, when the field edits
  /// lists, [pasted] is plain text, it lands where an item may start, and two
  /// or more of its lines are markers (`- `, `* `, `+ `, `1. `); else
  /// [pasted] itself.
  ///
  /// A single marker line is likelier the text itself, so it stays text. A
  /// text that carries entities is the clipboard's own rich payload and keeps
  /// the items it has.
  RichText withPastedLists(RichText pasted) {
    if (!lists || pasted.entities.isNotEmpty || pasted.length < 2) {
      return pasted;
    }
    final selection = value.selection;
    final at = selection.isValid ? selection.start : richText.length;
    return _itemsFrom(richText, at, pasted.plain) ?? pasted;
  }

  void _commitListEdit(ListEdit edit) {
    final caret = edit.caret;
    _commit(
      edit.text,
      TextEditingValue(
        text: edit.text.plain,
        selection: caret == null
            ? super.value.selection
            : TextSelection.collapsed(offset: caret),
      ),
      pending: edit.pending,
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

  // [pending] is the empty item the caret rests on after the edit; an edit
  // that does not say so ends it.
  void _commit(
    RichText next,
    TextEditingValue newValue, {
    PendingListItem? pending,
  }) {
    final entitiesChanged = next != _rich || pending != _pending;
    final before = super.value;
    _rich = next;
    _pending = pending;
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
  /// [inserted] that cannot coexist with the ones around it are dropped, the
  /// broadest first, until the rest fit: code blocks and quotes (a code block
  /// in a quote is its text), then styles, then links; mentions and inline
  /// content go last, where nothing else fits (inside code). The text still
  /// goes in. Ends any composition.
  void replaceRange(int start, int end, RichText inserted) {
    final current = richText;
    final (from, to) = _widenOverAtoms(current, start, end);
    final next =
        _fitted(current, from, to, inserted) ??
        TextReplacement(
          start: from,
          oldEnd: to,
          inserted: inserted.plain,
        ).applyTo(current);
    _commit(
      next,
      TextEditingValue(
        text: next.plain,
        selection: TextSelection.collapsed(offset: from + inserted.length),
      ),
    );
  }

  // [current] with [inserted] over [from]..[to], keeping as many of the
  // inserted entities as fit; null when not even its plain text fits.
  static RichText? _fitted(
    RichText current,
    int from,
    int to,
    RichText inserted,
  ) {
    bool isBlock(Entity entity) =>
        entity.kind is EntityKind$CodeBlock ||
        entity.kind is EntityKind$List ||
        entity.kind == EntityKind.quote;
    int? tried;
    for (final keep in <bool Function(Entity)>[
      (_) => true,
      (entity) => !isBlock(entity),
      (entity) => !isBlock(entity) && entity.kind is! EntityKind$Style,
      (entity) => entity.kind.isAtomic,
      (_) => false,
    ]) {
      final kept = [
        for (final entity in inserted.entities)
          if (keep(entity)) entity,
      ];
      // A tier that drops nothing more than the last one fails as it did.
      if (kept.length == tried) continue;
      tried = kept.length;
      try {
        return current.replaceRange(from, to, RichText(inserted.plain, kept));
        // RichText reports entities that cannot coexist as an ArgumentError
        // and offers no way to ask first.
        // ignore: avoid_catching_errors
      } on ArgumentError {
        continue;
      }
    }
    return null;
  }

  // --- Formatting ---

  /// Turns [style] on over the selection, or off when it is all in [style]
  /// already.
  ///
  /// Bold, italic, underline, strike and spoiler give up the whitespace at the
  /// edges of the selection and each line break; code takes the other styles
  /// and links out of the selection and is refused over an atom; a quote
  /// widens to the lines the selection touches, a caret's line included.
  void toggleStyle(EntityStyle style) => _toggle(EntityKind.style(style));

  /// Turns a code block on over the lines the selection touches (a caret's
  /// line included), or off when they all are one already.
  ///
  /// A block of [language] over lines that are a block of another language
  /// changes the language; with no [language] it is off when they are any
  /// block. The block takes the lines away from every other style, link, quote
  /// and list item, and is refused over an atom. A [language] a fence could not
  /// carry (letters, digits and `+ # . _ -` only) is refused.
  void toggleCodeBlock({String? language}) =>
      _toggle(EntityKind.codeBlock(language: language));

  /// Links the selection to [url], replacing any link in it; at a caret,
  /// inserts [url] as linked text.
  ///
  /// Refused over code or a mention, for an empty [url] or one that has a line
  /// break or spells a mention, username or hashtag (`mention:`, `username:`,
  /// `hashtag:`).
  void applyLink(String url) {
    final edit = _linkEdit(url);
    if (edit == null) return;
    final (next, caret) = edit;
    if (caret == null) {
      _commitFormatted(next);
      return;
    }
    _commit(
      next,
      TextEditingValue(
        text: next.plain,
        selection: TextSelection.collapsed(offset: caret),
      ),
    );
  }

  /// Takes the links off the selection and keeps the text. Does nothing at a
  /// caret.
  void removeLink() {
    final target = _target();
    if (target == null || target.from == target.to) return;
    final next = TextFormatting.unlinked(target.rich, target.from, target.to);
    if (next != null && next != target.rich) _commitFormatted(next);
  }

  /// Takes every style, link, quote, code block and list item off the
  /// selection (off the lines it touches, for the last three). Mentions and
  /// inline content are content and stay, and so do detected usernames and
  /// hashtags. Does nothing at a caret.
  void clearFormatting() {
    final next = _cleared();
    if (next != null) _commitFormatted(next);
  }

  /// Whether the selection holds anything [clearFormatting] would take off.
  bool get canClearFormatting => _cleared() != null;

  /// Whether the selection is in [kind].
  ///
  /// - A style, a code block or a list kind: all of it is (a quote and the
  ///   other line kinds are judged on the lines the selection touches, and a
  ///   caret counts). A code block of no language is any block, a list kind
  ///   ignores depth, and the caret on an empty item is in that item's kind.
  /// - A link: the selection touches one, whatever its target (so a menu can
  ///   offer to edit or remove it rather than create it).
  /// - Any other kind is not formatting: false.
  bool isActive(EntityKind kind) {
    final (from, to) = _selectedRange(richText);
    final pending = _pending;
    if (kind is EntityKind$List &&
        pending != null &&
        from == to &&
        from == pending.offset) {
      return pending.kind == kind.listKind;
    }
    return TextFormatting.isActive(richText, from, to, kind);
  }

  /// Whether the command for [kind] would change anything now: toggling it
  /// either way, or for a link, applying it.
  ///
  /// False for a caret (except a link, whose URL then goes in as text, and the
  /// line kinds), for a selection [RichText] could not hold [kind] over (bold
  /// inside code, code over a mention), for a selection that touches the IME
  /// composition, for a list kind unless [lists] is on, and for the kinds
  /// that are not formatting.
  bool canApply(EntityKind kind) => switch (kind) {
    EntityKind$Link(:final url) => _linkEdit(url) != null,
    EntityKind$List(:final listKind) =>
      lists &&
          (_onEmptyLine
              ? _toggledEmpty(listKind) != null
              : _toggled(kind) != null),
    _ when TextFormatting.isToggled(kind) => _toggled(kind) != null,
    _ => false,
  };

  void _toggle(EntityKind kind) {
    final next = _toggled(kind);
    if (next != null) _commitFormatted(next);
  }

  // The text after toggling [kind] over the selection; null when that would
  // do nothing or cannot be done.
  RichText? _toggled(EntityKind kind) {
    final target = _target(lines: TextFormatting.isLineKind(kind));
    if (target == null) return null;
    final (:rich, :from, :to) = target;
    if (from == to && !TextFormatting.isLineKind(kind)) return null;
    final next = TextFormatting.isActive(rich, from, to, kind)
        ? TextFormatting.removed(rich, from, to, kind)
        : TextFormatting.applied(rich, from, to, kind);
    return next == null || next == rich ? null : next;
  }

  RichText? _cleared() {
    final target = _target(lines: true);
    if (target == null || target.from == target.to) return null;
    final next = TextFormatting.cleared(target.rich, target.from, target.to);
    return next == null || next == target.rich ? null : next;
  }

  // The text after linking the selection to [url] and, when the URL went in as
  // text, the caret after it; null when refused.
  (RichText, int?)? _linkEdit(String url) {
    if (url.isEmpty) return null;
    final target = _target();
    if (target == null) return null;
    final (:rich, :from, :to) = target;
    if (from != to) {
      final next = TextFormatting.applied(rich, from, to, EntityKind.link(url));
      return next == null || next == rich ? null : (next, null);
    }
    // The text changes, which an IME composition cannot take under it.
    if (_composing) return null;
    try {
      final linked = RichText(url, [
        Entity(0, url.length, EntityKind.link(url)),
      ]);
      return (rich.replaceRange(from, from, linked), from + url.length);
      // RichText reports entities that cannot coexist as an ArgumentError and
      // offers no way to ask first.
      // ignore: avoid_catching_errors
    } on ArgumentError {
      return null;
    }
  }

  // The selection and the text it is in, or null when a command there would
  // touch the IME composition. [lines]: the command acts on whole lines.
  ({RichText rich, int from, int to})? _target({bool lines = false}) {
    final rich = richText;
    final (from, to) = _selectedRange(rich);
    if (_composing && value.composing.isValid && !value.composing.isCollapsed) {
      final (start, end) = lines
          ? TextFormatting.linesOf(rich.plain, from, to)
          : (from, to);
      final composing = value.composing;
      if (composing.start < end && start < composing.end) return null;
    }
    return (rich: rich, from: from, to: to);
  }

  // The selection (a caret at the end when there is none), widened over the
  // atomic entities it cuts into; a caret is never widened.
  (int, int) _selectedRange(RichText rich) {
    final selection = value.selection;
    final end = rich.length;
    final from = selection.isValid ? selection.start : end;
    final to = selection.isValid ? selection.end : end;
    return from == to ? (from, to) : _widenOverAtoms(rich, from, to);
  }

  // Commits entities that describe the same text, the selection and the
  // composition left as they are.
  void _commitFormatted(RichText next) {
    if (_composing) {
      _rich = next;
      _derived = null;
      notifyListeners();
      return;
    }
    _commit(next, super.value, pending: _pending);
  }

  // --- Lists ---

  /// Turns the lines the selection touches into list items of [listKind], or
  /// back into plain lines when they all are items of it already.
  ///
  /// An item the lines touch keeps its extent and depth and takes the kind. At
  /// a caret on an empty line it makes (or ends) an empty item there. Does
  /// nothing unless [lists] is on, or where a quote or a code block holds a
  /// line.
  void toggleList(EntityListKind listKind) {
    if (!lists || _composing) return;
    if (_onEmptyLine) {
      if (_toggledEmpty(listKind) case final edit?) _commitListEdit(edit);
      return;
    }
    _toggle(EntityKind.list(listKind: listKind));
  }

  /// Whether [indentListItems] would move an item.
  bool get canIndentListItems => _shifted(1) != null;

  /// Moves the items the selection touches one level deeper, up to
  /// [EntityKind$List.maxDepth].
  void indentListItems() {
    if (_shifted(1) case final edit?) _commitListEdit(edit);
  }

  /// Whether [outdentListItems] would move an item.
  bool get canOutdentListItems => _shifted(-1) != null;

  /// Moves the items the selection touches one level out, down to depth 0
  /// (they stay items; Backspace at an item's start is what leaves the list).
  void outdentListItems() {
    if (_shifted(-1) case final edit?) _commitListEdit(edit);
  }

  /// Whether the caret is in a list item (an empty one included): Enter there
  /// continues or leaves the list, so a host's Enter-to-send leaves the key to
  /// the field.
  bool get isInListItem {
    final caret = _caret;
    if (!lists || caret == null) return false;
    return _pending?.offset == caret ||
        ListEditing.itemAt(_rich, caret) != null;
  }

  /// Whether the caret is in an item, so [insertSoftBreak] has one to go on.
  bool get canInsertSoftBreak => _softBreak() != null;

  /// Inserts a line break the item covers: the item goes on after it, instead
  /// of the break opening the next item. The markdown spells it `"  \n"`.
  void insertSoftBreak() {
    if (_softBreak() case final edit?) _commitListEdit(edit);
  }

  /// Whether the caret is at the start of an item, where
  /// [outdentOrExitListItem] acts.
  bool get canOutdentOrExitListItem => _atItemStart() != null;

  /// With the caret at the start of an item (or on an empty one), moves it
  /// one level out, and takes it out of the list when it has none left.
  void outdentOrExitListItem() {
    if (_atItemStart() case final edit?) _commitListEdit(edit);
  }

  /// The marker the gutter paints for each item, with the numbers derived.
  /// Empty unless [lists] is on. For the field.
  @internal
  List<ListMarker> get listMarkers {
    if (!lists) return const [];
    final rich = richText;
    final cached = _markers;
    if (cached != null &&
        identical(cached.rich, rich) &&
        cached.pending == _pending) {
      return cached.markers;
    }
    final markers = ListEditing.markers(rich, _pending);
    _markers = (rich: rich, pending: _pending, markers: markers);
    return markers;
  }

  ({RichText rich, PendingListItem? pending, List<ListMarker> markers})?
  _markers;

  // Whether the selection is a caret on an empty line.
  bool get _onEmptyLine {
    final rich = richText;
    final (from, to) = _selectedRange(rich);
    if (from != to) return false;
    final (start, end) = TextFormatting.linesOf(rich.plain, from, to);
    return start == end;
  }

  // The empty item a toggle of [kind] leaves on the caret's empty line; null
  // where the line cannot hold one.
  ListEdit? _toggledEmpty(EntityListKind kind) {
    if (!lists || _composing) return null;
    final rich = richText;
    final (caret, _) = _selectedRange(rich);
    final pending = _pending;
    if (pending != null && pending.offset == caret) {
      return (
        text: rich,
        caret: null,
        pending: pending.kind == kind ? null : pending.withKind(kind),
      );
    }
    final item = ListEditing.emptyItem(rich, caret, kind);
    return item == null ? null : (text: rich, caret: null, pending: item);
  }

  ListEdit? _shifted(int delta) {
    if (!lists || _composing) return null;
    final rich = richText;
    final (from, to) = _selectedRange(rich);
    return ListEditing.shifted(rich, from, to, _pending, delta);
  }

  // The collapsed caret, or null.
  int? get _caret {
    final selection = value.selection;
    return selection.isValid && selection.isCollapsed
        ? selection.baseOffset
        : null;
  }

  ListEdit? _softBreak() {
    final caret = _caret;
    if (!lists || _composing || caret == null) return null;
    return ListEditing.softBreak(_rich, caret);
  }

  ListEdit? _atItemStart() {
    final caret = _caret;
    if (!lists || _composing || caret == null) return null;
    return ListEditing.backspaceAtStart(_rich, caret, _pending);
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
        // A detected username or hashtag is painted as a mention is.
        case EntityKind$Mention() ||
            EntityKind$Username() ||
            EntityKind$Hashtag():
          result = result.merge(TextStyle(color: _entityStyles.mention));
        // A block of code reads as inline code does, line by line.
        case EntityKind$CodeBlock():
          result = result.merge(
            TextStyle(
              fontFamily: 'monospace',
              backgroundColor: _entityStyles.codeBackground,
            ),
          );
        // The marker of a list item is not text: the field's gutter paints it.
        case EntityKind$InlineContent() || EntityKind$List():
          break;
      }
    }
    if (decorations.isEmpty) return result;
    return result.merge(
      TextStyle(decoration: TextDecoration.combine(decorations)),
    );
  }
}
