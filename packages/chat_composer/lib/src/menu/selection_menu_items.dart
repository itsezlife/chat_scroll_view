import 'dart:async';

import 'package:chat_composer/src/menu/composer_formatting_option.dart';
import 'package:chat_composer/src/menu/composer_menu_policy.dart';
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

  /// Bold.
  bold,

  /// Italic.
  italic,

  /// Underline.
  underline,

  /// Strikethrough.
  strikethrough,

  /// Monospace.
  mono,

  /// Spoiler.
  spoiler,

  /// Quote the selected lines.
  quote,

  /// Fenced code block.
  codeBlock,

  /// Create a link.
  createLink,

  /// Edit the link the selection touches.
  editLink,

  /// Remove the links the selection touches.
  removeLink,

  /// Bullet list.
  bulletList,

  /// Numbered list.
  numberedList,

  /// Clear formatting ("Regular").
  clearFormatting;

  /// Whether the item is a clipboard action: it goes on the main row, or at
  /// the top of the More page when the row has no room.
  bool get isClipboard => index <= selectAll.index;

  /// The marker a list item's row shows before its label, or null for any
  /// other item.
  String? get listMarker => switch (this) {
    bulletList => '\u2022',
    numberedList => '1.',
    _ => null,
  };
}

/// How an item's label shows its own effect: "Italic" in italic, "Monospace"
/// in a monospaced face.
enum SelectionMenuLabelStyle {
  /// The shared item style.
  plain,

  /// Bold.
  bold,

  /// Slanted.
  italic,

  /// Monospaced.
  mono,

  /// Struck through.
  strike,

  /// Underlined.
  underline;

  /// [base] with this effect applied.
  TextStyle apply(TextStyle base) => switch (this) {
    plain => base,
    bold => base.copyWith(fontWeight: FontWeight.bold),
    italic => base.copyWith(fontStyle: FontStyle.italic),
    mono => ChromeMonospace.style(base),
    strike => base.copyWith(decoration: TextDecoration.lineThrough),
    underline => base.copyWith(decoration: TextDecoration.underline),
  };
}

/// What the menu does once an item has run.
enum SelectionMenuAfter {
  /// Close the menu, hiding the handles and leaving the selection a caret at
  /// its extent.
  dismiss,

  /// Close the menu and leave the selection and its handles as they are,
  /// because the action still needs the selection (a link prompt).
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
    this.enabled = true,
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
  /// spoken as selected, not drawn differently.
  final bool selected;

  /// Whether the item can be chosen. An item whose command cannot apply to the
  /// selection stays in the menu, drawn at the disabled tile's 0.38 and
  /// without a tap.
  final bool enabled;

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
/// A formatting item whose command cannot apply to the selection is
/// [SelectionMenuItem.enabled] false and, by [ComposerUnavailableActions],
/// either stays in the list (`disable`, so the More page keeps its shape from
/// one selection to the next) or is left out (`hide`). Quote alone is always
/// left out over a selection that is quoted already. A collapsed caret gets
/// the same list: what acts on a caret (the line kinds, the link) is enabled,
/// the rest is not.
abstract final class SelectionMenuItems {
  /// The entries for the selection in [text].
  ///
  /// [options] is `ComposerSpec.formatting`. [onLink] asks for a link's URL
  /// (the menu owns the prompt); [toggleList] returns the command that turns
  /// the selected lines into [EntityListKind] items, or null while lists are
  /// off. [unavailableActions] is the menu policy's.
  static List<SelectionMenuItem> of({
    required ComposerTextController text,
    required Set<ComposerFormattingOption> options,
    required FormattingStrings strings,
    required List<SelectionMenuClipboardItem> clipboard,
    required VoidCallback onLink,
    required VoidCallback? Function(EntityListKind kind) toggleList,
    bool canLink = true,
    ComposerUnavailableActions unavailableActions =
        ComposerUnavailableActions.disable,
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
    if (!text.selection.isValid) return items;

    bool offered(ComposerFormattingOption option) => options.contains(option);

    SelectionMenuItem? style(
      ComposerFormattingOption option,
      SelectionMenuItemKind kind,
      EntityStyle style,
      String label, {
      SelectionMenuLabelStyle labelStyle = SelectionMenuLabelStyle.plain,
    }) {
      if (!offered(option)) return null;
      final entity = EntityKind.style(style);
      return SelectionMenuItem(
        kind: kind,
        label: label,
        labelStyle: labelStyle,
        selected: text.isActive(entity),
        enabled: text.canApply(entity),
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
      if (!offered(option) || toggle == null || !text.lists) return null;
      final entity = EntityKind.list(listKind: listKind);
      return SelectionMenuItem(
        kind: kind,
        label: label,
        selected: text.isActive(entity),
        enabled: text.canApply(entity),
        onSelected: toggle,
      );
    }

    // Quote has no way back from the menu, so over a quoted selection it has
    // nothing to offer.
    final quote = text.isActive(EntityKind.quote)
        ? null
        : style(
            ComposerFormattingOption.quote,
            SelectionMenuItemKind.quote,
            EntityStyle.quote,
            strings.quoteAction,
          );

    final code = offered(ComposerFormattingOption.codeBlock)
        ? SelectionMenuItem(
            kind: SelectionMenuItemKind.codeBlock,
            label: strings.codeBlockAction,
            selected: text.isActive(const EntityKind.codeBlock()),
            enabled: text.canApply(const EntityKind.codeBlock()),
            onSelected: text.toggleCodeBlock,
          )
        : null;

    final link = offered(ComposerFormattingOption.link) && canLink
        ? _link(text, strings, onLink)
        : const <SelectionMenuItem>[];

    final clear = offered(ComposerFormattingOption.clearFormatting)
        ? SelectionMenuItem(
            kind: SelectionMenuItemKind.clearFormatting,
            label: strings.clearFormattingAction,
            enabled: text.canClearFormatting,
            onSelected: text.clearFormatting,
          )
        : null;

    final all = [
      ...items,
      ?style(
        ComposerFormattingOption.bold,
        SelectionMenuItemKind.bold,
        EntityStyle.bold,
        strings.boldAction,
        labelStyle: SelectionMenuLabelStyle.bold,
      ),
      ?style(
        ComposerFormattingOption.italic,
        SelectionMenuItemKind.italic,
        EntityStyle.italic,
        strings.italicAction,
        labelStyle: SelectionMenuLabelStyle.italic,
      ),
      ?style(
        ComposerFormattingOption.underline,
        SelectionMenuItemKind.underline,
        EntityStyle.underline,
        strings.underlineAction,
        labelStyle: SelectionMenuLabelStyle.underline,
      ),
      ?style(
        ComposerFormattingOption.strikethrough,
        SelectionMenuItemKind.strikethrough,
        EntityStyle.strike,
        strings.strikethroughAction,
        labelStyle: SelectionMenuLabelStyle.strike,
      ),
      ?style(
        ComposerFormattingOption.mono,
        SelectionMenuItemKind.mono,
        EntityStyle.code,
        strings.monoAction,
        labelStyle: SelectionMenuLabelStyle.mono,
      ),
      ?style(
        ComposerFormattingOption.spoiler,
        SelectionMenuItemKind.spoiler,
        EntityStyle.spoiler,
        strings.spoilerAction,
      ),
      ?quote,
      ?code,
      ...link,
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
      ?clear,
    ];
    return switch (unavailableActions) {
      ComposerUnavailableActions.disable => all,
      ComposerUnavailableActions.hide => [
        for (final item in all)
          if (item.enabled) item,
      ],
    };
  }

  // One Link row, Create or Edit by whether the selection touches a link, and
  // Remove while it does.
  static List<SelectionMenuItem> _link(
    ComposerTextController text,
    FormattingStrings strings,
    VoidCallback onLink,
  ) {
    final touched = text.selectedLinkUrl != null;
    return [
      SelectionMenuItem(
        kind: touched
            ? SelectionMenuItemKind.editLink
            : SelectionMenuItemKind.createLink,
        label: touched ? strings.editLinkAction : strings.createLinkAction,
        after: SelectionMenuAfter.dismissKeepingSelection,
        enabled: text.canLink,
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
