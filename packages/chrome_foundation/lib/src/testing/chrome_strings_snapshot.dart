import 'package:chrome_foundation/src/strings/chrome_strings.dart';

/// Every string of [strings], keyed by `group.member`, with function members
/// evaluated on representative arguments (`group.member[argument]`).
///
/// For completeness checks: a host can assert that none of its own values is
/// empty, and two languages can assert they define the same keys. Plural
/// functions are sampled across the counts where languages differ
/// (0, 1, 2, 5, 11, 21).
Map<String, String> describeChromeStrings(ChromeStrings strings) {
  final panel = strings.panel;
  final composer = strings.composer;
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
    'composer.messageHint': composer.messageHint,
    'composer.sendAction': composer.sendAction,
    'composer.confirmEditAction': composer.confirmEditAction,
    'composer.recordVoiceAction': composer.recordVoiceAction,
    'composer.attachAction': composer.attachAction,
    'composer.showPanelAction': composer.showPanelAction,
    'composer.showKeyboardAction': composer.showKeyboardAction,
    'composer.dismissHeaderAction': composer.dismissHeaderAction,
    'composer.replyTo[name]': composer.replyTo('name'),
    'composer.editingMessage': composer.editingMessage,
    'semantics.panelOpened': semantics.panelOpened,
    'semantics.panelClosed': semantics.panelClosed,
    'semantics.pageSelected[label]': semantics.pageSelected('label'),
    'semantics.searchFieldLabel': semantics.searchFieldLabel,
    for (final count in _pluralSamples)
      'semantics.searchResultCount[$count]': semantics.searchResultCount(count),
    'semantics.backspaceAction': semantics.backspaceAction,
    'semantics.variantsAction': semantics.variantsAction,
    'semantics.categoryStripLabel': semantics.categoryStripLabel,
  };
}

const _knownPageIds = ['emoji', 'stickers', 'gif'];
const _knownCategoryIds = [
  'smileys-emotion',
  'people-body',
  'animals-nature',
  'food-drink',
  'travel-places',
  'activities',
  'objects',
  'symbols',
  'flags',
];
const _pluralSamples = [0, 1, 2, 5, 11, 21];
