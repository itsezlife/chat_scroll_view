import 'package:chrome_foundation/src/strings/chrome_strings.dart';

/// A flat view of a [ChromeStrings], for completeness checks in tests.
abstract final class ChromeStringsSnapshot {
  /// Every string of [strings], keyed by `group.member`, with function members
  /// evaluated on representative arguments (`group.member[argument]`).
  ///
  /// For completeness checks: a host can assert that none of its own values is
  /// empty, and two languages can assert they define the same keys. Plural
  /// functions are sampled across the counts where languages differ
  /// (0, 1, 2, 5, 11, 21).
  static Map<String, String> of(ChromeStrings strings) {
    final panel = strings.panel;
    final composer = strings.composer;
    final formatting = strings.formatting;
    final semantics = strings.semantics;
    return {
      for (final id in _knownPageIds) 'panel.tabLabel[$id]': panel.tabLabel(id),
      for (final id in _knownCategoryIds)
        'panel.categoryTitle[$id]': panel.categoryTitle(id),
      'panel.recentlyUsedTitle': panel.recentlyUsedTitle,
      'panel.searchResultsTitle': panel.searchResultsTitle,
      'panel.searchHint': panel.searchHint,
      'panel.searchEmpty': panel.searchEmpty,
      'panel.clearRecentsTitle': panel.clearRecentsTitle,
      'panel.clearRecentsMessage': panel.clearRecentsMessage,
      'panel.clearAction': panel.clearAction,
      'panel.cancelAction': panel.cancelAction,
      'panel.copyAction': panel.copyAction,
      'panel.removeRecentAction': panel.removeRecentAction,
      'panel.clearRecentAction': panel.clearRecentAction,
      'panel.colorAllTitle': panel.colorAllTitle,
      'composer.messageHint': composer.messageHint,
      'composer.sendAction': composer.sendAction,
      'composer.confirmEditAction': composer.confirmEditAction,
      'composer.recordVoiceAction': composer.recordVoiceAction,
      'composer.attachAction': composer.attachAction,
      'composer.showPanelAction': composer.showPanelAction,
      'composer.showKeyboardAction': composer.showKeyboardAction,
      'composer.dismissHeaderAction': composer.dismissHeaderAction,
      'composer.pastePlainAction': composer.pastePlainAction,
      'composer.replyTo[name]': composer.replyTo('name'),
      'composer.editingMessage': composer.editingMessage,
      'formatting.quoteAction': formatting.quoteAction,
      'formatting.spoilerAction': formatting.spoilerAction,
      'formatting.boldAction': formatting.boldAction,
      'formatting.italicAction': formatting.italicAction,
      'formatting.monoAction': formatting.monoAction,
      'formatting.strikethroughAction': formatting.strikethroughAction,
      'formatting.underlineAction': formatting.underlineAction,
      'formatting.createLinkAction': formatting.createLinkAction,
      'formatting.editLinkAction': formatting.editLinkAction,
      'formatting.removeLinkAction': formatting.removeLinkAction,
      'formatting.codeBlockAction': formatting.codeBlockAction,
      'formatting.bulletListAction': formatting.bulletListAction,
      'formatting.numberedListAction': formatting.numberedListAction,
      'formatting.clearFormattingAction': formatting.clearFormattingAction,
      'formatting.moreAction': formatting.moreAction,
      'formatting.backAction': formatting.backAction,
      'formatting.bulletListItem': formatting.bulletListItem,
      'formatting.numberedListItem[3]': formatting.numberedListItem(3),
      'semantics.panelOpened': semantics.panelOpened,
      'semantics.panelClosed': semantics.panelClosed,
      'semantics.pageSelected[label]': semantics.pageSelected('label'),
      'semantics.searchFieldLabel': semantics.searchFieldLabel,
      for (final count in _pluralSamples)
        'semantics.searchResultCount[$count]': semantics.searchResultCount(
          count,
        ),
      'semantics.backspaceAction': semantics.backspaceAction,
      'semantics.variantsAction': semantics.variantsAction,
      'semantics.categoryStripLabel': semantics.categoryStripLabel,
    };
  }
}

const _knownPageIds = ['emoji', 'stickers', 'gif'];
const _knownCategoryIds = [
  'people',
  'nature',
  'food',
  'activity',
  'travel',
  'objects',
  'symbols',
];
const _pluralSamples = [0, 1, 2, 5, 11, 21];
