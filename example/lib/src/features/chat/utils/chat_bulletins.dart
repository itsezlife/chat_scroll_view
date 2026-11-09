import 'package:bulletins/bulletins.dart';
import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_copy_feedback.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/widgets.dart';

/// The words of the chat's own bulletins (ADR 045: a bulletin's message is
/// the host's). A pack's texts are the chrome's `PackSheetStrings`, and the
/// Undo label `BulletinStrings`.
///
/// [english] holds the English texts; [russian] is the demo's language, as
/// `demoChromeStrings` is.
@immutable
final class ChatBulletinStrings {
  /// A set of every text.
  const ChatBulletinStrings({
    required this.favouriteAdded,
    required this.favouriteRemoved,
    required this.recentRemoved,
    required this.favouritesLimit,
    required this.favouriteReplaced,
    required this.gifsLimit,
    required this.gifReplaced,
    required this.gifSaved,
    required this.messageCopied,
    required this.textCopied,
    required this.codeCopied,
    required this.linkCopied,
    required this.formatOffer,
  });

  /// The English texts.
  static const ChatBulletinStrings english = ChatBulletinStrings(
    favouriteAdded: 'Sticker was added to Favorites',
    favouriteRemoved: 'Sticker was removed from Favorites',
    recentRemoved: 'Sticker was removed from Recent',
    favouritesLimit: _englishFavouritesLimit,
    favouriteReplaced: 'An older sticker was replaced with this one.',
    gifsLimit: _englishGifsLimit,
    gifReplaced: 'An older GIF was replaced with this one.',
    gifSaved: 'Added to saved GIFs',
    messageCopied: 'Message copied to clipboard.',
    textCopied: 'Text copied to clipboard',
    codeCopied: 'Code copied to clipboard',
    linkCopied: 'Link copied to clipboard',
    formatOffer: 'Apply formatting',
  );

  /// The demo's Russian.
  static const ChatBulletinStrings russian = ChatBulletinStrings(
    favouriteAdded: 'Стикер добавлен в Избранное',
    favouriteRemoved: 'Стикер удалён из Избранного',
    recentRemoved: 'Стикер удалён из Недавних',
    favouritesLimit: _russianFavouritesLimit,
    favouriteReplaced: 'Более старый стикер заменён этим.',
    gifsLimit: _russianGifsLimit,
    gifReplaced: 'Более старый GIF заменён этим.',
    gifSaved: 'GIF добавлен в сохранённые',
    messageCopied: 'Сообщение скопировано в буфер обмена.',
    textCopied: 'Текст скопирован в буфер обмена',
    codeCopied: 'Код скопирован в буфер обмена',
    linkCopied: 'Ссылка скопирована в буфер обмена',
    formatOffer: 'Применить форматирование',
  );

  /// The set the demo shows: [russian], the language of its chrome strings.
  static const ChatBulletinStrings demo = russian;

  /// A sticker became a favourite (`AddedToFavorites`).
  final String favouriteAdded;

  /// A sticker stopped being one (`RemovedFromFavorites`).
  final String favouriteRemoved;

  /// A sticker left the recents (`RemovedFromRecent`).
  final String recentRemoved;

  /// The favourites are full at this many (`LimitReachedFavoriteStickers`).
  final String Function(int limit) favouritesLimit;

  /// The oldest favourite made room
  /// (`LimitReachedFavoriteStickersSubtitlePremium`).
  final String favouriteReplaced;

  /// The saved GIFs are full at this many (`LimitReachedFavoriteGifs`).
  final String Function(int limit) gifsLimit;

  /// The oldest saved GIF made room
  /// (`LimitReachedFavoriteGifsSubtitlePremium`).
  final String gifReplaced;

  /// A GIF was saved (`GifSavedHint`).
  final String gifSaved;

  /// A message was copied (`MessageCopied`).
  final String messageCopied;

  /// Selected text or messages were copied (`TextCopied`).
  final String textCopied;

  /// Code was copied (`CodeCopied`).
  final String codeCopied;

  /// A link was copied (`LinkCopied`).
  final String linkCopied;

  /// The offer to apply the formatting of a plain paste.
  final String formatOffer;
}

String _englishFavouritesLimit(int limit) => 'Limit of $limit Stickers Reached';

String _englishGifsLimit(int limit) => 'Limit of $limit GIFs Reached';

String _russianFavouritesLimit(int limit) =>
    'Достигнут лимит в $limit ${_russianPlural(limit, 'стикер', 'стикера', 'стикеров')}';

String _russianGifsLimit(int limit) => 'Достигнут лимит в $limit GIF';

// The CLDR one / few / many word of [n] in Russian (as `demoChromeStrings`).
String _russianPlural(int n, String one, String few, String many) {
  final mod10 = n % 10;
  final mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return one;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return few;
  return many;
}

/// The chat's bulletins: what each says, what leads it, and how long it
/// stays. Values only; the chat screen shows them through its
/// `BulletinController`.
///
/// Animated bulletin icons are not bundled with the demo; the icons here are
/// chrome icons the host registers ([icons]) in their place.
abstract final class ChatBulletins {
  /// A copy.
  static const ChromeIconId copyIcon = ChromeIconId('bulletin.copy');

  /// A copied link (`voip_invite`).
  static const ChromeIconId linkIcon = ChromeIconId('bulletin.link');

  /// A saved GIF (`ic_save_to_gifs`).
  static const ChromeIconId savedGifIcon = ChromeIconId.gif;

  /// An error (`chats_infotip`).
  static const ChromeIconId infoIcon = ChromeIconId('bulletin.info');

  /// The painters of the ids above that the chrome does not have; the host
  /// registers them in a `ChromeIconScope` over its `BulletinHost`.
  static const Map<ChromeIconId, ChromeIconPainter> icons = {
    copyIcon: ChromeIconPainter.font(Icons.copy_rounded),
    linkIcon: ChromeIconPainter.font(Icons.link_rounded),
    infoIcon: ChromeIconPainter.font(Icons.info_outline_rounded),
  };

  /// How long a "limit reached, older one replaced" bulletin stays: 3500 ms.
  static const BulletinDuration replaced = BulletinDuration.exactly(
    Duration(milliseconds: 3500),
  );

  /// The bulletin after [applied], a sticker or GIF edit the user asked for,
  /// or null when none is shown (a GIF unsaved, a pack's edit:
  /// that is the pack sheet host's). [limits] names the full list.
  ///
  /// Each is `DURATION_SHORT`, written out: the factory's length rule would
  /// make these texts long.
  static Bulletin? ofLibraryEdit(
    AppliedEdit applied, {
    required LibraryLimits limits,
    required ChatBulletinStrings strings,
  }) {
    // A full list of recent stickers replaces its oldest; the same holds for
    // the saved GIFs.
    Bulletin limit(ContentKey key, String title, String message) => Bulletin(
      title: title,
      message: message,
      leading: BulletinLeading.thumbnail(key),
      duration: replaced,
    );
    Bulletin sticker(ContentKey key, String message) => Bulletin(
      message: message,
      leading: BulletinLeading.thumbnail(key),
      duration: BulletinDuration.short,
    );
    return switch ((applied.edit, applied.evicted)) {
      (LibraryEdit$FavouriteSticker(:final key), _?) => limit(
        key,
        strings.favouritesLimit(limits.favouriteStickers),
        strings.favouriteReplaced,
      ),
      (LibraryEdit$FavouriteSticker(:final key), null) => sticker(
        key,
        strings.favouriteAdded,
      ),
      (LibraryEdit$UnfavouriteSticker(:final key), _) => sticker(
        key,
        strings.favouriteRemoved,
      ),
      (LibraryEdit$RemoveRecentSticker(:final key), _) => sticker(
        key,
        strings.recentRemoved,
      ),
      (LibraryEdit$SaveGif(:final key), _?) => limit(
        key,
        strings.gifsLimit(limits.savedGifs),
        strings.gifReplaced,
      ),
      // `createDownloadBulletin(FileType.GIF)`.
      (LibraryEdit$SaveGif(), null) => Bulletin(
        message: strings.gifSaved,
        leading: const BulletinLeading.icon(savedGifIcon),
        duration: BulletinDuration.short,
      ),
      (
        LibraryEdit$AddRecentSticker() ||
            LibraryEdit$UnsaveGif() ||
            LibraryPackEdit() ||
            LibraryEdit$ReorderPacks(),
        _,
      ) =>
        null,
    };
  }

  /// The bulletin after a copy of [kind] (`createCopyBulletin`,
  /// `createCopyLinkBulletin`): short, with the copy or the link icon.
  /// Whether one shows at all is `ChatCopyFeedback`'s.
  static Bulletin copied(ChatCopyKind kind, ChatBulletinStrings strings) =>
      switch (kind) {
        ChatCopyKind.link => Bulletin(
          message: strings.linkCopied,
          leading: const BulletinLeading.icon(linkIcon),
          duration: BulletinDuration.short,
        ),
        ChatCopyKind.messages ||
        ChatCopyKind.textSelection ||
        ChatCopyKind.code => Bulletin(
          message: switch (kind) {
            ChatCopyKind.messages => strings.messageCopied,
            ChatCopyKind.code => strings.codeCopied,
            _ => strings.textCopied,
          },
          leading: const BulletinLeading.icon(copyIcon),
          duration: BulletinDuration.short,
        ),
      };

  /// An error (`createErrorBulletin`): short, with the info icon.
  static Bulletin error(String message) => Bulletin(
    message: message,
    leading: const BulletinLeading.icon(infoIcon),
    duration: BulletinDuration.short,
  );

  /// A plain notice; the factory's length rule picks its duration.
  static Bulletin notice(String message) => Bulletin(message: message);

  /// The offer to apply the formatting of a plain paste: up until the
  /// offer's owner ends it, and [onApply] on a tap.
  static Bulletin formatOffer(
    ChatBulletinStrings strings, {
    required VoidCallback onApply,
  }) => Bulletin(
    message: strings.formatOffer,
    duration: BulletinDuration.untilDismissed,
    onTap: onApply,
  );

  // --- Look ---

  /// The builders of [policy]'s platform family, with a thumbnail of a
  /// content key drawn through the asset cache (a sticker is its own
  /// thumbnail): the Android card as glass over the chat (the card turns to
  /// glass in a chat only), the iOS blurred card, the
  /// desktop toast.
  static BulletinBuilders buildersFor(BulletinPolicy policy) =>
      switch (policy) {
        BulletinPolicy$IOS() => BulletinIOS.builders(
          animation: _content,
          thumbnail: _content,
        ),
        BulletinPolicy$Desktop() => DesktopBulletinBuilders.create(
          animation: _content,
          thumbnail: _content,
        ),
        _ => BulletinBuilders$Android.create(
          glass: true,
          animation: _content,
          thumbnail: _content,
        ),
      };

  // A content key, drawn by the asset cache over the box the builder gives
  // its leading; any other source keeps the slot empty.
  static Widget _content(
    BuildContext context,
    Object source,
    BulletinView view,
  ) => switch (source) {
    final ContentKey key => LayoutBuilder(
      builder: (context, constraints) => ContentView(
        content: key,
        preset: AssetPresets.square(
          extent: constraints.biggest.shortestSide,
          devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
          profile: const AssetProfile(animate: true),
        ),
      ),
    ),
    _ => const SizedBox.shrink(),
  };
}
