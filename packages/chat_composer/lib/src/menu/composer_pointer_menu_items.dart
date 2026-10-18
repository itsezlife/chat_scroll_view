import 'dart:async';

import 'package:chat_composer/src/menu/composer_formatting_option.dart';
import 'package:chat_composer/src/menu/composer_menu_hints.dart';
import 'package:chat_composer/src/menu/composer_spell_checker.dart';
import 'package:chat_composer/src/text/composer_text_controller.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart' hide RichText;

/// The link the pointer is over while nothing is selected: the extent and the
/// target of the link, so Edit link and Remove link act on it.
@immutable
final class ComposerMenuLink {
  /// A link over [range] pointing at [url].
  const ComposerMenuLink({required this.range, required this.url});

  /// The link's extent in the text.
  final TextRange range;

  /// The link's target.
  final String url;
}

/// The word under the pointer and what the spell checker says about it.
@immutable
final class ComposerMenuSpelling {
  /// A verdict [result] on the [word] at [range], from [checker].
  const ComposerMenuSpelling({
    required this.range,
    required this.word,
    required this.result,
    required this.checker,
  });

  /// Where the word is in the text.
  final TextRange range;

  /// The word.
  final String word;

  /// The checker's verdict.
  final ComposerWordSpelling result;

  /// The checker, which the rows call.
  final ComposerSpellChecker checker;

  /// Whether the Spelling submenu has anything to show: a wrong word always
  /// does, a right one only to be taken out of the user dictionary.
  bool get hasRows => !result.isCorrect || result.inUserDictionary;
}

/// What a menu opening saw: everything the rows' enabled states depend on that
/// is not in the text controller.
@immutable
final class ComposerMenuState {
  /// The facts of one opening.
  const ComposerMenuState({
    required this.canUndo,
    required this.canRedo,
    required this.canPaste,
    required this.hasRichClipboard,
    this.pointerLink,
    this.spelling,
  });

  /// Whether the field's history has an edit to undo.
  final bool canUndo;

  /// Whether it has one to redo.
  final bool canRedo;

  /// Whether a paste would put anything in.
  final bool canPaste;

  /// Whether the composer has a rich clipboard, which Paste as plain text
  /// needs.
  final bool hasRichClipboard;

  /// The link under the pointer, used only while nothing is selected.
  final ComposerMenuLink? pointerLink;

  /// The word under the pointer, when a spell checker is given.
  final ComposerMenuSpelling? spelling;
}

/// What each row does. The menu closes before a command runs.
@immutable
final class ComposerPointerMenuCommands {
  /// The commands of one opening.
  const ComposerPointerMenuCommands({
    required this.undo,
    required this.redo,
    required this.cut,
    required this.copy,
    required this.paste,
    required this.pastePlain,
    required this.delete,
    required this.selectAll,
    required this.editLink,
    required this.toggleList,
  });

  /// Undo.
  final VoidCallback undo;

  /// Redo.
  final VoidCallback redo;

  /// Cut the selection.
  final FutureOr<void> Function() cut;

  /// Copy the selection.
  final FutureOr<void> Function() copy;

  /// Paste.
  final FutureOr<void> Function() paste;

  /// Paste as plain text.
  final FutureOr<void> Function() pastePlain;

  /// Delete the selection.
  final VoidCallback delete;

  /// Select all.
  final VoidCallback selectAll;

  /// Asks for a link's URL and applies it: to the selection, or to the link
  /// under the pointer when one is given.
  final void Function(ComposerMenuLink? pointerLink) editLink;

  /// The command that makes the selected lines items of a list kind, or null
  /// while lists are off.
  final VoidCallback? Function(EntityListKind kind) toggleList;
}

/// The entries of the composer's pointer menu: the reference desktop client's
/// context menu of its message field, as a pure function of the state.
///
/// Order, from the top: the Spelling submenu (when a checker has something to
/// say; at the bottom instead when the menu opens upward, so it stays nearest
/// the pointer), Undo, Redo, a separator, Cut, Copy, Paste (and Paste as plain
/// text, an addition), Delete, a separator, Formatting, a separator, Select
/// All. Rows that cannot be chosen stay and are greyed; none is hidden for
/// that.
///
/// The Formatting submenu: Bold, Italic, Underline, Strikethrough, Quote,
/// Monospace, Spoiler, then the additions Code block and the list rows, a
/// separator, Create link or Edit link (and Remove link, an addition), a
/// separator and Clear formatting. A row whose option the host did not offer is
/// absent; every style row is greyed without a selection, **including** the
/// line kinds (quote, code block, lists), which the commands accept at a caret:
/// the reference menu greys them, and the keys stay for a caret.
abstract final class ComposerPointerMenuItems {
  /// The entries for the selection in [text].
  ///
  /// [canLink] says whether the host has a link prompt; without one there are
  /// no link rows. [spellingOnTop] places the Spelling submenu at the top
  /// (the menu opens downward) or at the bottom (upward).
  static List<PointerMenuEntry> of({
    required ComposerTextController text,
    required ComposerMenuState state,
    required ComposerPointerMenuCommands commands,
    required Set<ComposerFormattingOption> options,
    required EditMenuStrings strings,
    required ComposerMenuHints hints,
    required bool canLink,
    bool spellingOnTop = true,
  }) {
    final selection = text.selection;
    final hasSelection = selection.isValid && !selection.isCollapsed;
    final isEmpty = text.text.isEmpty;

    PointerMenuItem item(
      ComposerMenuAction action,
      String label, {
      required bool enabled,
      FutureOr<void> Function()? run,
      List<PointerMenuEntry>? submenu,
    }) => PointerMenuItem(
      id: action,
      label: label,
      hint: hints.of(action),
      enabled: enabled,
      onSelected: run,
      submenu: submenu,
    );

    final formatting = _formatting(
      text: text,
      state: state,
      commands: commands,
      options: options,
      strings: strings,
      hints: hints,
      canLink: canLink,
      hasSelection: hasSelection,
    );

    final spelling = state.spelling;
    final spellingRow = spelling != null && spelling.hasRows
        ? item(
            ComposerMenuAction.spelling,
            strings.spellingMenu,
            enabled: true,
            submenu: _spelling(text, spelling, strings),
          )
        : null;

    return [
      if (spellingRow != null && spellingOnTop) ...[
        spellingRow,
        const PointerMenuSeparator(),
      ],
      item(
        ComposerMenuAction.undo,
        strings.undoAction,
        enabled: state.canUndo,
        run: commands.undo,
      ),
      item(
        ComposerMenuAction.redo,
        strings.redoAction,
        enabled: state.canRedo,
        run: commands.redo,
      ),
      const PointerMenuSeparator(),
      item(
        ComposerMenuAction.cut,
        strings.cutAction,
        enabled: hasSelection,
        run: commands.cut,
      ),
      item(
        ComposerMenuAction.copy,
        strings.copyAction,
        enabled: hasSelection,
        run: commands.copy,
      ),
      item(
        ComposerMenuAction.paste,
        strings.pasteAction,
        enabled: state.canPaste,
        run: commands.paste,
      ),
      if (state.hasRichClipboard)
        item(
          ComposerMenuAction.pastePlain,
          strings.pastePlainAction,
          enabled: state.canPaste,
          run: commands.pastePlain,
        ),
      item(
        ComposerMenuAction.delete,
        strings.deleteAction,
        enabled: hasSelection,
        run: commands.delete,
      ),
      const PointerMenuSeparator(),
      if (formatting.isNotEmpty) ...[
        item(
          ComposerMenuAction.formatting,
          strings.formattingMenu,
          enabled: true,
          submenu: formatting,
        ),
        const PointerMenuSeparator(),
      ],
      item(
        ComposerMenuAction.selectAll,
        strings.selectAllAction,
        enabled: !isEmpty,
        run: commands.selectAll,
      ),
      if (spellingRow != null && !spellingOnTop) ...[
        const PointerMenuSeparator(),
        spellingRow,
      ],
    ];
  }

  static List<PointerMenuEntry> _formatting({
    required ComposerTextController text,
    required ComposerMenuState state,
    required ComposerPointerMenuCommands commands,
    required Set<ComposerFormattingOption> options,
    required EditMenuStrings strings,
    required ComposerMenuHints hints,
    required bool canLink,
    required bool hasSelection,
  }) {
    bool offered(ComposerFormattingOption option) => options.contains(option);

    PointerMenuItem row(
      ComposerMenuAction action,
      String label, {
      required bool enabled,
      required VoidCallback run,
    }) => PointerMenuItem(
      id: action,
      label: label,
      hint: hints.of(action),
      enabled: enabled,
      onSelected: run,
    );

    PointerMenuItem? style(
      ComposerFormattingOption option,
      ComposerMenuAction action,
      EntityStyle style,
      String label,
    ) {
      if (!offered(option)) return null;
      return row(
        action,
        label,
        enabled: hasSelection && text.canApply(EntityKind.style(style)),
        run: () => text.toggleStyle(style),
      );
    }

    PointerMenuItem? list(
      ComposerFormattingOption option,
      ComposerMenuAction action,
      EntityListKind kind,
      String label,
    ) {
      final toggle = commands.toggleList(kind);
      if (!offered(option) || toggle == null || !text.lists) return null;
      return row(
        action,
        label,
        enabled: hasSelection && text.canApply(EntityKind.list(listKind: kind)),
        run: toggle,
      );
    }

    final styles = <PointerMenuItem>[
      ?style(
        ComposerFormattingOption.bold,
        ComposerMenuAction.bold,
        EntityStyle.bold,
        strings.boldAction,
      ),
      ?style(
        ComposerFormattingOption.italic,
        ComposerMenuAction.italic,
        EntityStyle.italic,
        strings.italicAction,
      ),
      ?style(
        ComposerFormattingOption.underline,
        ComposerMenuAction.underline,
        EntityStyle.underline,
        strings.underlineAction,
      ),
      ?style(
        ComposerFormattingOption.strikethrough,
        ComposerMenuAction.strikethrough,
        EntityStyle.strike,
        strings.strikethroughAction,
      ),
      ?style(
        ComposerFormattingOption.quote,
        ComposerMenuAction.quote,
        EntityStyle.quote,
        strings.quoteAction,
      ),
      ?style(
        ComposerFormattingOption.mono,
        ComposerMenuAction.monospace,
        EntityStyle.code,
        strings.monospaceAction,
      ),
      ?style(
        ComposerFormattingOption.spoiler,
        ComposerMenuAction.spoiler,
        EntityStyle.spoiler,
        strings.spoilerAction,
      ),
      if (offered(ComposerFormattingOption.codeBlock))
        row(
          ComposerMenuAction.codeBlock,
          strings.codeBlockAction,
          enabled: hasSelection && text.canApply(const EntityKind.codeBlock()),
          run: text.toggleCodeBlock,
        ),
      ?list(
        ComposerFormattingOption.bulletList,
        ComposerMenuAction.bulletList,
        EntityListKind.bullet,
        strings.bulletListAction,
      ),
      ?list(
        ComposerFormattingOption.numberedList,
        ComposerMenuAction.numberedList,
        EntityListKind.ordered,
        strings.numberedListAction,
      ),
    ];

    final links = <PointerMenuItem>[];
    if (offered(ComposerFormattingOption.link) && canLink) {
      // With a selection the link is the selection's; with a caret it is the
      // one under the pointer, if any.
      final pointerLink = hasSelection ? null : state.pointerLink;
      final touches = hasSelection
          ? text.selectedLinkUrl != null
          : pointerLink != null;
      links.add(
        row(
          touches ? ComposerMenuAction.editLink : ComposerMenuAction.createLink,
          touches ? strings.editLinkAction : strings.createLinkAction,
          enabled: touches || text.canLink,
          run: () => commands.editLink(pointerLink),
        ),
      );
      if (touches) {
        links.add(
          row(
            ComposerMenuAction.removeLink,
            strings.removeLinkAction,
            enabled: true,
            run: pointerLink == null
                ? text.removeLink
                : () => text.removeLinkFrom(pointerLink.range),
          ),
        );
      }
    }

    final clear = offered(ComposerFormattingOption.clearFormatting)
        ? row(
            ComposerMenuAction.clearFormatting,
            strings.clearFormattingAction,
            enabled: hasSelection && text.canClearFormatting,
            run: text.clearFormatting,
          )
        : null;

    final groups = <List<PointerMenuItem>>[
      styles,
      links,
      if (clear != null) [clear],
    ].where((group) => group.isNotEmpty);
    return [
      for (final (i, group) in groups.indexed) ...[
        if (i > 0) const PointerMenuSeparator(),
        ...group,
      ],
    ];
  }

  // Add to Dictionary and Ignore word, then the suggestions, for a wrong
  // word; Remove from Dictionary for a right one the user added.
  static List<PointerMenuEntry> _spelling(
    ComposerTextController text,
    ComposerMenuSpelling spelling,
    EditMenuStrings strings,
  ) {
    final checker = spelling.checker;
    final word = spelling.word;
    if (spelling.result.isCorrect) {
      return [
        PointerMenuItem(
          id: ComposerMenuAction.removeFromDictionary,
          label: strings.removeFromDictionaryAction,
          onSelected: () => checker.removeFromDictionary(word),
        ),
      ];
    }
    return [
      PointerMenuItem(
        id: ComposerMenuAction.addToDictionary,
        label: strings.addToDictionaryAction,
        onSelected: () => checker.addToDictionary(word),
      ),
      PointerMenuItem(
        id: ComposerMenuAction.ignoreWord,
        label: strings.ignoreWordAction,
        onSelected: () => checker.ignore(word),
      ),
      if (spelling.result.suggestions.isNotEmpty) const PointerMenuSeparator(),
      for (final suggestion in spelling.result.suggestions)
        PointerMenuItem(
          id: ComposerSuggestionId(suggestion),
          // A suggestion is text, not a label with a mnemonic mark.
          label: suggestion.replaceAll('&', '&&'),
          onSelected: () => text.replaceRange(
            spelling.range.start,
            spelling.range.end,
            RichText.plain(suggestion),
          ),
        ),
    ];
  }
}

/// The id of a spelling suggestion row: the suggested word.
@immutable
final class ComposerSuggestionId {
  /// The id of the row suggesting [word].
  const ComposerSuggestionId(this.word);

  /// The suggested replacement.
  final String word;

  @override
  bool operator ==(Object other) =>
      other is ComposerSuggestionId && other.word == word;

  @override
  int get hashCode => word.hashCode;

  @override
  String toString() => 'ComposerSuggestionId($word)';
}
