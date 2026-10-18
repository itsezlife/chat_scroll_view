import 'dart:async';

import 'package:chat_composer/src/menu/composer_formatting_option.dart';
import 'package:chat_composer/src/text/composer_text_controller.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart' hide RichText;

/// What an item does, which is also its identity in a test and a semantics
/// tree.
enum SelectionMenuItemKind {
  /// Cut the selection to the clipboard.
  cut,

  /// Copy the selection to the clipboard.
  copy,

  /// Paste the clipboard.
  paste,

  /// Paste the clipboard's plain text.
  pastePlain,

  /// Select the whole text.
  selectAll,

  /// Quote the selected lines.
  quote,

  /// Spoiler.
  spoiler,

  /// Bold.
  bold,

  /// Italic.
  italic,

  /// Monospace.
  mono,

  /// Strikethrough.
  strikethrough,

  /// Underline.
  underline,

  /// Fenced code block.
  codeBlock,

  /// Bullet list.
  bulletList,

  /// Numbered list.
  numberedList,

  /// Create a link.
  createLink,

  /// Edit the link the selection touches.
  editLink,

  /// Remove the links the selection touches.
  removeLink,

  /// Clear formatting ("Regular").
  clearFormatting,
}

/// How an item's label shows its own effect: "Italic" in italic, "Mono" in a
/// monospaced face, as the reference client sets its labels.
enum SelectionMenuLabelStyle {
  /// The shared item style.
  plain,

  /// Slanted.
  italic,

  /// Monospaced.
  mono,

  /// Struck through.
  strike,

  /// Underlined.
  underline,
}

/// What the menu does once an item has run.
enum SelectionMenuAfter {
  /// Close the menu, hiding the handles and leaving the selection a caret at
  /// its end: the platform action mode's `finish`, which the reference runs
  /// after every item.
  dismiss,

  /// Close the menu and leave the selection and its handles as they are,
  /// because the action still needs the selection (a link prompt) or the
  /// platform keeps it (a copy on iOS and desktop).
  dismissKeepingSelection,

  /// Leave the menu open: select all grows the selection under the same menu.
  stay,
}

/// One entry of the selection menu.
@immutable
final class SelectionMenuItem {
  /// An entry of [kind] labelled [label] that runs [onSelected].
  const SelectionMenuItem({
    required this.kind,
    required this.label,
    required this.onSelected,
    this.after = SelectionMenuAfter.dismiss,
    this.selected = false,
    this.labelStyle = SelectionMenuLabelStyle.plain,
  });

  /// What the item is.
  final SelectionMenuItemKind kind;

  /// The visible and spoken label.
  final String label;

  /// Runs the item. The menu waits for a returned future before it closes, so
  /// a copy that finishes after the clipboard answers closes the menu with the
  /// selection as the copy left it.
  final FutureOr<void> Function() onSelected;

  /// What happens to the menu afterwards.
  final SelectionMenuAfter after;

  /// Whether the selection is in what the item applies (bold over bold text):
  /// spoken as selected, not drawn differently, as in the reference.
  final bool selected;

  /// How the label is set.
  final SelectionMenuLabelStyle labelStyle;
}

/// A clipboard action the field offers, ready to run: the label and the
/// handler are the field's, because the field knows whether copy, cut and
/// paste go through the composer's rich clipboard.
@immutable
final class SelectionMenuClipboardItem {
  /// A clipboard action of [kind] labelled [label].
  const SelectionMenuClipboardItem({
    required this.kind,
    required this.label,
    required this.onSelected,
    this.after = SelectionMenuAfter.dismiss,
  });

  /// [SelectionMenuItemKind.cut], [SelectionMenuItemKind.copy],
  /// [SelectionMenuItemKind.paste], [SelectionMenuItemKind.pastePlain] or
  /// [SelectionMenuItemKind.selectAll].
  final SelectionMenuItemKind kind;

  /// The label.
  final String label;

  /// Runs the action; it neither hides the menu nor moves the selection past
  /// what the action itself does.
  final FutureOr<void> Function() onSelected;

  /// What the menu does afterwards.
  final SelectionMenuAfter after;
}

/// The menu's entries for one selection, in menu order: the clipboard actions,
/// then the formatting items.
///
/// An item whose command cannot apply is left out, as the reference's floating
/// toolbar lays out only items that are visible and enabled
/// (`getVisibleAndEnabledMenuItems`, :272); a collapsed caret gets no
/// formatting at all, as the reference extends its menu only over a selection
/// (`ChatActivity.extendActionMode`, :27406).
abstract final class SelectionMenuItems {
  /// The entries for the selection in [text].
  ///
  /// [options] is `ComposerSpec.formatting`. [onLink] asks for a link's URL
  /// (the menu owns the prompt); [toggleList] returns the command that turns
  /// the selected lines into [EntityListKind] items, or null while lists are
  /// off.
  static List<SelectionMenuItem> of({
    required ComposerTextController text,
    required Set<ComposerFormattingOption> options,
    required FormattingStrings strings,
    required List<SelectionMenuClipboardItem> clipboard,
    required VoidCallback onLink,
    required VoidCallback? Function(EntityListKind kind) toggleList,
    bool canLink = true,
  }) {
    final items = <SelectionMenuItem>[
      for (final item in clipboard)
        SelectionMenuItem(
          kind: item.kind,
          label: item.label,
          onSelected: item.onSelected,
          after: item.after,
        ),
    ];
    final selection = text.selection;
    if (!selection.isValid || selection.isCollapsed) return items;

    bool offered(ComposerFormattingOption option) => options.contains(option);

    SelectionMenuItem? style(
      ComposerFormattingOption option,
      SelectionMenuItemKind kind,
      EntityStyle style,
      String label, {
      SelectionMenuLabelStyle labelStyle = SelectionMenuLabelStyle.plain,
    }) {
      final entity = EntityKind.style(style);
      if (!offered(option) || !text.canApply(entity)) return null;
      return SelectionMenuItem(
        kind: kind,
        label: label,
        labelStyle: labelStyle,
        selected: text.isActive(entity),
        onSelected: () => text.toggleStyle(style),
      );
    }

    SelectionMenuItem? list(
      ComposerFormattingOption option,
      SelectionMenuItemKind kind,
      EntityListKind listKind,
      String label,
    ) {
      final toggle = toggleList(listKind);
      final entity = EntityKind.list(listKind: listKind);
      if (!offered(option) || toggle == null || !text.canApply(entity)) {
        return null;
      }
      return SelectionMenuItem(
        kind: kind,
        label: label,
        selected: text.isActive(entity),
        onSelected: toggle,
      );
    }

    final quoted = text.isActive(EntityKind.quote);
    final quote = style(
      ComposerFormattingOption.quote,
      SelectionMenuItemKind.quote,
      EntityStyle.quote,
      strings.quoteAction,
    );

    final link = offered(ComposerFormattingOption.link) && canLink
        ? _link(text, strings, onLink)
        : const <SelectionMenuItem>[];

    final clear =
        offered(ComposerFormattingOption.clearFormatting) &&
            text.canClearFormatting
        ? SelectionMenuItem(
            kind: SelectionMenuItemKind.clearFormatting,
            label: strings.clearFormattingAction,
            onSelected: text.clearFormatting,
          )
        : null;

    final code =
        offered(ComposerFormattingOption.codeBlock) &&
            text.canApply(const EntityKind.codeBlock())
        ? SelectionMenuItem(
            kind: SelectionMenuItemKind.codeBlock,
            label: strings.codeBlockAction,
            selected: text.isActive(const EntityKind.codeBlock()),
            onSelected: text.toggleCodeBlock,
          )
        : null;

    return [
      ...items,
      // The reference hides Quote over a selection that is quoted already, and
      // offers no way to unquote from the menu.
      if (!quoted && quote != null) quote,
      ?style(
        ComposerFormattingOption.spoiler,
        SelectionMenuItemKind.spoiler,
        EntityStyle.spoiler,
        strings.spoilerAction,
      ),
      ?style(
        ComposerFormattingOption.bold,
        SelectionMenuItemKind.bold,
        EntityStyle.bold,
        strings.boldAction,
      ),
      ?style(
        ComposerFormattingOption.italic,
        SelectionMenuItemKind.italic,
        EntityStyle.italic,
        strings.italicAction,
        labelStyle: SelectionMenuLabelStyle.italic,
      ),
      ?style(
        ComposerFormattingOption.mono,
        SelectionMenuItemKind.mono,
        EntityStyle.code,
        strings.monoAction,
        labelStyle: SelectionMenuLabelStyle.mono,
      ),
      ?style(
        ComposerFormattingOption.strikethrough,
        SelectionMenuItemKind.strikethrough,
        EntityStyle.strike,
        strings.strikethroughAction,
        labelStyle: SelectionMenuLabelStyle.strike,
      ),
      ?style(
        ComposerFormattingOption.underline,
        SelectionMenuItemKind.underline,
        EntityStyle.underline,
        strings.underlineAction,
        labelStyle: SelectionMenuLabelStyle.underline,
      ),
      // Our additions sit after Underline so that Link keeps its place before
      // Regular, as in the reference.
      ?code,
      ?list(
        ComposerFormattingOption.bulletList,
        SelectionMenuItemKind.bulletList,
        EntityListKind.bullet,
        strings.bulletListAction,
      ),
      ?list(
        ComposerFormattingOption.numberedList,
        SelectionMenuItemKind.numberedList,
        EntityListKind.ordered,
        strings.numberedListAction,
      ),
      ...link,
      ?clear,
    ];
  }

  // Create, or Edit and Remove while the selection touches a link.
  static List<SelectionMenuItem> _link(
    ComposerTextController text,
    FormattingStrings strings,
    VoidCallback onLink,
  ) {
    // `canApply` for a link wants a URL to judge it, and reports no change
    // when the URL is the one the selection is linked to already. The refusals
    // it is asked about (code, a mention, a composition) do not depend on which
    // URL, so a probe that differs from the current one asks exactly those.
    final current = text.selectedLinkUrl;
    final probe = EntityKind.link(
      current == null ? 'https://example.com' : '$current#',
    );
    final applicable = text.canApply(probe);
    final touched = current != null;
    return [
      if (applicable)
        SelectionMenuItem(
          kind: touched
              ? SelectionMenuItemKind.editLink
              : SelectionMenuItemKind.createLink,
          label: touched ? strings.editLinkAction : strings.createLinkAction,
          after: SelectionMenuAfter.dismissKeepingSelection,
          onSelected: onLink,
        ),
      if (touched)
        SelectionMenuItem(
          kind: SelectionMenuItemKind.removeLink,
          label: strings.removeLinkAction,
          onSelected: text.removeLink,
        ),
    ];
  }
}
