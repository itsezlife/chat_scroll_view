import 'dart:async';

import 'package:chat_composer/src/input/composer_controller.dart';
import 'package:chat_composer/src/menu/composer_formatting_option.dart';
import 'package:chat_composer/src/menu/composer_menu_hints.dart';
import 'package:chat_composer/src/menu/composer_pointer_menu_items.dart';
import 'package:chat_composer/src/menu/composer_spell_checker.dart';
import 'package:chat_composer/src/spec/composer_spec.dart';
import 'package:chat_composer/src/text/composer_link_edit.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:composer_editable/composer_editable.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart' hide RichText;

/// Opens the pointer menu over the composer's field: gathers what the rows
/// depend on (history, clipboard, the link and the word under the pointer),
/// builds the entries, and shows them at the pointer.
///
/// One menu at a time per field: a click while one is opening or open does
/// nothing (an open menu is modal, so only a click racing the clipboard probe
/// can get here).
final class ComposerPointerMenu {
  /// A presenter for the field of [controller].
  ComposerPointerMenu({
    required this.controller,
    required this.editable,
    required this.isAlive,
  });

  /// The input state.
  final ComposerController controller;

  /// The field's editable, or null while it is not built.
  final ExtendedEditableTextState? Function() editable;

  /// Whether the field is still in the tree.
  final bool Function() isAlive;

  PointerMenuHandle? _handle;
  var _opening = false;

  /// Whether a menu is opening or open.
  bool get isBusy => _opening || (_handle?.isOpen ?? false);

  /// Closes the menu if one is up.
  void close() => _handle?.close();

  /// Opens the menu at [globalPosition] over [context]'s field.
  ///
  /// [textPosition] is the text position under the pointer, which picks the
  /// link and the word the rows act on when nothing is selected; null for a
  /// keyboard-opened menu, which has no pointer to ask about.
  Future<void> open(
    BuildContext context, {
    required Offset globalPosition,
    required TextPosition? textPosition,
    required ComposerMenuHints hints,
    required Set<ComposerFormattingOption> options,
    required ComposerLinkPrompt? linkPrompt,
    required ComposerSpellChecker? spellChecker,
    required EditMenuStrings strings,
    required PointerMenuTokens tokens,
    required ChromeMotionData motion,
  }) async {
    if (isBusy) return;
    _opening = true;
    try {
      final pasteProbe = controller.canPaste();
      final spellProbe = _spellingAt(textPosition, spellChecker);
      final canPaste = await pasteProbe;
      final spelling = await spellProbe;
      if (!isAlive() || !context.mounted) return;
      final text = controller.text;
      final state = ComposerMenuState(
        canUndo: controller.canUndo,
        canRedo: controller.canRedo,
        canPaste: canPaste,
        hasRichClipboard: controller.clipboard != null,
        pointerLink: _linkAt(globalPosition, textPosition),
        spelling: spelling,
      );
      List<PointerMenuEntry> entries({required bool spellingOnTop}) =>
          ComposerPointerMenuItems.of(
            text: text,
            state: state,
            commands: _commands(context, linkPrompt),
            options: options,
            strings: strings,
            hints: hints,
            canLink: linkPrompt != null,
            spellingOnTop: spellingOnTop,
          );
      final top = entries(spellingOnTop: true);
      final onTop = _fitsBelow(context, globalPosition, top);
      _handle = PointerMenu.show(
        context,
        globalPosition: globalPosition,
        entries: onTop ? top : entries(spellingOnTop: false),
        tokens: tokens,
        motion: motion,
        focusParent: controller.focusNode,
        returnFocusTo: controller.focusNode,
      );
    } finally {
      _opening = false;
    }
  }

  // Whether a menu of [entries] opened at [pointer] fits under it: the
  // Spelling row goes on top only then, so it stays nearest the pointer when
  // the menu flips upward (the reference predicts it the same way, from the
  // heights of the rows).
  static bool _fitsBelow(
    BuildContext context,
    Offset pointer,
    List<PointerMenuEntry> entries,
  ) {
    var height = 2 * PointerMenuMetrics.verticalPadding;
    for (final entry in entries) {
      height += entry is PointerMenuSeparator
          ? PointerMenuMetrics.separatorHeight
          : PointerMenuMetrics.rowHeight;
    }
    final view = View.of(context);
    final screen = view.physicalSize.height / view.devicePixelRatio;
    return pointer.dy + height <= screen;
  }

  // --- What is under the pointer ---

  // The character the pointer is over, found from the glyph boxes around the
  // caret position nearest to it (that position is on the edge of two
  // characters, and the pointer is over one of them).
  int? _characterAt(Offset global, TextPosition position) {
    final render = editable()?.renderEditable;
    if (render == null) return null;
    final local = render.globalToLocal(global);
    final length = controller.text.text.length;
    for (final index in [position.offset - 1, position.offset]) {
      if (index < 0 || index >= length) continue;
      final boxes = render.getBoxesForSelection(
        TextSelection(baseOffset: index, extentOffset: index + 1),
      );
      if (boxes.any((box) => box.toRect().contains(local))) return index;
    }
    return null;
  }

  ComposerMenuLink? _linkAt(Offset? global, TextPosition? position) {
    if (global == null || position == null) return null;
    final index = _characterAt(global, position);
    if (index == null) return null;
    final link = controller.text.linkAt(index);
    return link == null
        ? null
        : ComposerMenuLink(range: link.range, url: link.url);
  }

  static final _hasLetter = RegExp(r'\p{L}', unicode: true);

  Future<ComposerMenuSpelling?> _spellingAt(
    TextPosition? position,
    ComposerSpellChecker? checker,
  ) async {
    final render = editable()?.renderEditable;
    if (checker == null || position == null || render == null) return null;
    final range = render.getWordBoundary(position);
    final plain = controller.text.text;
    if (!range.isValid ||
        range.isCollapsed ||
        range.end > plain.length ||
        _coveredByEntity(range)) {
      return null;
    }
    final word = plain.substring(range.start, range.end);
    // Numbers and punctuation are not words to check.
    if (!_hasLetter.hasMatch(word)) return null;
    try {
      return ComposerMenuSpelling(
        range: range,
        word: word,
        result: await checker.check(word),
        checker: checker,
      );
    } on Object catch (error, stack) {
      // The menu opens without its Spelling row.
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'chat_composer',
          context: ErrorDescription('while asking the spell checker'),
        ),
      );
      return null;
    }
  }

  // Links, mentions, inline content, code, usernames and hashtags are not
  // text to spell.
  bool _coveredByEntity(TextRange range) {
    for (final entity in controller.text.richText.entities) {
      if (entity.offset >= range.end || entity.end <= range.start) continue;
      switch (entity.kind) {
        case EntityKind$Link() ||
            EntityKind$Mention() ||
            EntityKind$InlineContent() ||
            EntityKind$CodeBlock() ||
            EntityKind$Username() ||
            EntityKind$Hashtag():
          return true;
        case EntityKind$Style(:final style) when style == EntityStyle.code:
          return true;
        case _:
          break;
      }
    }
    return false;
  }

  // --- What the rows do ---

  ComposerPointerMenuCommands _commands(
    BuildContext context,
    ComposerLinkPrompt? linkPrompt,
  ) {
    final rich = controller.clipboard != null;
    final state = editable();
    return ComposerPointerMenuCommands(
      undo: controller.undo,
      redo: controller.redo,
      cut: rich
          ? controller.cutSelection
          : () => state?.cutSelection(SelectionChangedCause.toolbar),
      copy: rich
          ? controller.copySelection
          : () => state?.copySelection(SelectionChangedCause.toolbar),
      paste: rich
          ? controller.paste
          : () => state?.pasteText(SelectionChangedCause.toolbar),
      pastePlain: () => controller.paste(plain: true),
      delete: controller.deleteSelection,
      selectAll: controller.selectAll,
      editLink: (pointerLink) {
        final prompt = linkPrompt;
        if (prompt == null) return;
        unawaited(
          ComposerLinkEdit(
            text: controller.text,
            prompt: prompt,
            context: context,
            isAlive: () => isAlive() && context.mounted,
            target: pointerLink?.range,
          ).ask(),
        );
      },
      toggleList: (kind) =>
          controller.text.lists ? () => controller.text.toggleList(kind) : null,
    );
  }
}
