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
    final edit = strings.editMenu;
    final semantics = strings.semantics;
    final pack = strings.packSheet;
    return {
      for (final id in _knownPageIds) 'panel.tabLabel[$id]': panel.tabLabel(id),
      for (final id in _knownCategoryIds)
        'panel.categoryTitle[$id]': panel.categoryTitle(id),
      'panel.recentlyUsedTitle': panel.recentlyUsedTitle,
      'panel.favouriteStickersTitle': panel.favouriteStickersTitle,
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
      'panel.gifsEmpty': panel.gifsEmpty,
      'panel.stickersEmpty': panel.stickersEmpty,
      'panel.gifsFailed': panel.gifsFailed,
      'panel.retryAction': panel.retryAction,
      'panel.clearRecentStickersTitle': panel.clearRecentStickersTitle,
      'panel.clearRecentStickersMessage': panel.clearRecentStickersMessage,
      'panel.sendStickerAction': panel.sendStickerAction,
      'panel.sendEmojiAction': panel.sendEmojiAction,
      'panel.sendGifAction': panel.sendGifAction,
      'panel.sendWithoutSoundAction': panel.sendWithoutSoundAction,
      'panel.addToFavouritesAction': panel.addToFavouritesAction,
      'panel.removeFromFavouritesAction': panel.removeFromFavouritesAction,
      'panel.viewPackAction': panel.viewPackAction,
      'panel.deleteFromRecentAction': panel.deleteFromRecentAction,
      'panel.copyEmojiAction': panel.copyEmojiAction,
      'panel.saveGifAction': panel.saveGifAction,
      'panel.deleteGifAction': panel.deleteGifAction,
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
      'editMenu.undoAction': edit.undoAction,
      'editMenu.redoAction': edit.redoAction,
      'editMenu.cutAction': edit.cutAction,
      'editMenu.copyAction': edit.copyAction,
      'editMenu.pasteAction': edit.pasteAction,
      'editMenu.deleteAction': edit.deleteAction,
      'editMenu.selectAllAction': edit.selectAllAction,
      'editMenu.formattingMenu': edit.formattingMenu,
      'editMenu.boldAction': edit.boldAction,
      'editMenu.italicAction': edit.italicAction,
      'editMenu.underlineAction': edit.underlineAction,
      'editMenu.strikethroughAction': edit.strikethroughAction,
      'editMenu.quoteAction': edit.quoteAction,
      'editMenu.monospaceAction': edit.monospaceAction,
      'editMenu.spoilerAction': edit.spoilerAction,
      'editMenu.createLinkAction': edit.createLinkAction,
      'editMenu.editLinkAction': edit.editLinkAction,
      'editMenu.clearFormattingAction': edit.clearFormattingAction,
      'editMenu.pastePlainAction': edit.pastePlainAction,
      'editMenu.codeBlockAction': edit.codeBlockAction,
      'editMenu.removeLinkAction': edit.removeLinkAction,
      'editMenu.bulletListAction': edit.bulletListAction,
      'editMenu.numberedListAction': edit.numberedListAction,
      'editMenu.spellingMenu': edit.spellingMenu,
      'editMenu.addToDictionaryAction': edit.addToDictionaryAction,
      'editMenu.ignoreWordAction': edit.ignoreWordAction,
      'editMenu.removeFromDictionaryAction': edit.removeFromDictionaryAction,
      for (final count in _pluralSamples)
        'packSheet.addStickers[$count]': pack.addStickers(count),
      for (final count in _pluralSamples)
        'packSheet.removeStickers[$count]': pack.removeStickers(count),
      for (final count in _pluralSamples)
        'packSheet.addMasks[$count]': pack.addMasks(count),
      for (final count in _pluralSamples)
        'packSheet.removeMasks[$count]': pack.removeMasks(count),
      for (final count in _pluralSamples)
        'packSheet.addEmoji[$count]': pack.addEmoji(count),
      for (final count in _pluralSamples)
        'packSheet.removeEmoji[$count]': pack.removeEmoji(count),
      for (final count in _pluralSamples)
        'packSheet.addEmojiPacks[$count]': pack.addEmojiPacks(count),
      for (final count in _pluralSamples)
        'packSheet.removeEmojiPacks[$count]': pack.removeEmojiPacks(count),
      for (final count in _pluralSamples)
        'packSheet.emojiCount[$count]': pack.emojiCount(count),
      for (final count in _pluralSamples)
        'packSheet.emojiPacksAddedInfo[$count]': pack.emojiPacksAddedInfo(
          count,
        ),
      for (final count in _pluralSamples)
        'packSheet.emojiPacksRemovedInfo[$count]': pack.emojiPacksRemovedInfo(
          count,
        ),
      'packSheet.stickersAddedInfo[title]': pack.stickersAddedInfo('title'),
      'packSheet.masksAddedInfo[title]': pack.masksAddedInfo('title'),
      'packSheet.emojiAddedInfo[title]': pack.emojiAddedInfo('title'),
      'packSheet.stickersRemovedInfo[title]': pack.stickersRemovedInfo('title'),
      'packSheet.masksRemovedInfo[title]': pack.masksRemovedInfo('title'),
      'packSheet.emojiRemovedInfo[title]': pack.emojiRemovedInfo('title'),
      'packSheet.stickersArchivedInfo[title]': pack.stickersArchivedInfo(
        'title',
      ),
      'packSheet.masksArchivedInfo[title]': pack.masksArchivedInfo('title'),
      'packSheet.emojiArchivedInfo[title]': pack.emojiArchivedInfo('title'),
      'packSheet.addPackAction': pack.addPackAction,
      'packSheet.removePackAction': pack.removePackAction,
      'packSheet.closeAction': pack.closeAction,
      'packSheet.shareAction': pack.shareAction,
      'packSheet.copyLinkAction': pack.copyLinkAction,
      'packSheet.moreOptionsLabel': pack.moreOptionsLabel,
      'packSheet.linkCopied': pack.linkCopied,
      'packSheet.stickersNotFound': pack.stickersNotFound,
      'packSheet.emojiNotFound': pack.emojiNotFound,
      'packSheet.stickersAdded': pack.stickersAdded,
      'packSheet.masksAdded': pack.masksAdded,
      'packSheet.emojiAdded': pack.emojiAdded,
      'packSheet.stickersRemoved': pack.stickersRemoved,
      'packSheet.masksRemoved': pack.masksRemoved,
      'packSheet.emojiRemoved': pack.emojiRemoved,
      'packSheet.stickersArchived': pack.stickersArchived,
      'packSheet.masksArchived': pack.masksArchived,
      'packSheet.emojiArchived': pack.emojiArchived,
      'packSheet.undoAction': pack.undoAction,
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
      'semantics.stickerPackStripLabel': semantics.stickerPackStripLabel,
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
