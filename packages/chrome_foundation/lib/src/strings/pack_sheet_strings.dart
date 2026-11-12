/// Strings of the pack sheets (the sheet that shows one pack of stickers,
/// masks or custom emoji, or several packs of custom emoji) and of the
/// feedback a host shows when the user adds, removes or archives a pack.
///
/// Supplied by the host as part of `ChromeStrings`; this package ships no
/// translation. Counts and titles are functions so a host can apply its
/// language's plural rules. The feedback strings are here although the sheet
/// does not show them: the host's bulletin does, and one group keeps the
/// sheet's button and the bulletin after it in the same words.
final class PackSheetStrings {
  /// Pack sheet strings with every member given.
  const PackSheetStrings({
    required this.addStickers,
    required this.removeStickers,
    required this.addMasks,
    required this.removeMasks,
    required this.addEmoji,
    required this.removeEmoji,
    required this.addEmojiPacks,
    required this.removeEmojiPacks,
    required this.emojiCount,
    required this.addPackAction,
    required this.removePackAction,
    required this.addStickersLabel,
    required this.addEmojiLabel,
    required this.removeStickersLabel,
    required this.removeEmojiLabel,
    required this.closeAction,
    required this.shareAction,
    required this.copyLinkAction,
    required this.moreOptionsLabel,
    required this.linkCopied,
    required this.stickersNotFound,
    required this.emojiNotFound,
    required this.stickersAdded,
    required this.stickersAddedInfo,
    required this.masksAdded,
    required this.masksAddedInfo,
    required this.emojiAdded,
    required this.emojiAddedInfo,
    required this.emojiPacksAddedInfo,
    required this.stickersRemoved,
    required this.stickersRemovedInfo,
    required this.masksRemoved,
    required this.masksRemovedInfo,
    required this.emojiRemoved,
    required this.emojiRemovedInfo,
    required this.emojiPacksRemovedInfo,
    required this.stickersArchived,
    required this.stickersArchivedInfo,
    required this.masksArchived,
    required this.masksArchivedInfo,
    required this.emojiArchived,
    required this.emojiArchivedInfo,
    required this.undoAction,
  });

  // --- The sheet's button ---------------------------------------------------

  /// The button that adds a pack of [count] stickers.
  final String Function(int count) addStickers;

  /// The button that removes an installed pack of [count] stickers.
  final String Function(int count) removeStickers;

  /// The button that adds a pack of [count] masks.
  final String Function(int count) addMasks;

  /// The button that removes an installed pack of [count] masks.
  final String Function(int count) removeMasks;

  /// The button that adds a pack of [count] custom emoji.
  final String Function(int count) addEmoji;

  /// The button that removes an installed pack of [count] custom emoji.
  final String Function(int count) removeEmoji;

  /// The button of a sheet of several packs that adds the [count] packs not
  /// added yet.
  final String Function(int count) addEmojiPacks;

  /// The button of a sheet of several packs that removes its [count] packs.
  final String Function(int count) removeEmojiPacks;

  // --- Several packs --------------------------------------------------------

  /// How many emoji a pack holds, under its title in a sheet of several.
  final String Function(int count) emojiCount;

  /// The button beside one pack of several that adds it.
  final String addPackAction;

  /// The button beside one pack of several that removes it.
  final String removePackAction;

  /// The box's button that adds a sticker pack, its count drawn beside it in
  /// a badge (a pointer).
  final String addStickersLabel;

  /// The box's button that adds an emoji pack, with its count badge.
  final String addEmojiLabel;

  /// The box's button that removes a sticker pack, with its count badge.
  final String removeStickersLabel;

  /// The box's button that removes an emoji pack, with its count badge.
  final String removeEmojiLabel;

  // --- Header and menu ------------------------------------------------------

  /// The button that closes the sheet where it has one (a box under a
  /// pointer).
  final String closeAction;

  /// The menu item that shares the pack's link.
  final String shareAction;

  /// The menu item that copies the pack's link.
  final String copyLinkAction;

  /// What a screen reader says for the button that opens the menu.
  final String moreOptionsLabel;

  /// Said once the pack's link is on the clipboard.
  final String linkCopied;

  // --- A pack that cannot be shown ------------------------------------------

  /// Said when a pack of stickers or masks does not exist.
  final String stickersNotFound;

  /// Said when a pack of custom emoji does not exist.
  final String emojiNotFound;

  // --- Added ----------------------------------------------------------------

  /// Title of the feedback after a pack of stickers was added.
  final String stickersAdded;

  /// Line under [stickersAdded], naming the pack [title].
  final String Function(String title) stickersAddedInfo;

  /// Title of the feedback after a pack of masks was added.
  final String masksAdded;

  /// Line under [masksAdded], naming the pack [title].
  final String Function(String title) masksAddedInfo;

  /// Title of the feedback after packs of custom emoji were added.
  final String emojiAdded;

  /// Line under [emojiAdded] after one pack, named [title].
  final String Function(String title) emojiAddedInfo;

  /// Line under [emojiAdded] after [count] packs at once.
  final String Function(int count) emojiPacksAddedInfo;

  // --- Removed --------------------------------------------------------------

  /// Title of the feedback after a pack of stickers was removed.
  final String stickersRemoved;

  /// Line under [stickersRemoved], naming the pack [title].
  final String Function(String title) stickersRemovedInfo;

  /// Title of the feedback after a pack of masks was removed.
  final String masksRemoved;

  /// Line under [masksRemoved], naming the pack [title].
  final String Function(String title) masksRemovedInfo;

  /// Title of the feedback after packs of custom emoji were removed.
  final String emojiRemoved;

  /// Line under [emojiRemoved] after one pack, named [title].
  final String Function(String title) emojiRemovedInfo;

  /// Line under [emojiRemoved] after [count] packs at once.
  final String Function(int count) emojiPacksRemovedInfo;

  // --- Archived -------------------------------------------------------------

  /// Title of the feedback after a pack of stickers was archived.
  final String stickersArchived;

  /// Line under [stickersArchived], naming the pack [title].
  final String Function(String title) stickersArchivedInfo;

  /// Title of the feedback after a pack of masks was archived.
  final String masksArchived;

  /// Line under [masksArchived], naming the pack [title].
  final String Function(String title) masksArchivedInfo;

  /// Title of the feedback after a pack of custom emoji was archived.
  final String emojiArchived;

  /// Line under [emojiArchived], naming the pack [title].
  final String Function(String title) emojiArchivedInfo;

  /// The feedback's button that takes a removal or an archiving back.
  final String undoAction;
}
