/// The chat's bulletins: what each says, what
/// leads it and how long it stays.
///
/// **Seam:** [ChatBulletins], read as values: a library edit applied to a
/// `FakeContentLibrary` in, the `Bulletin` out. The English strings keep the
/// expected texts of their own.
library;

import 'package:bulletins/bulletins.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_bulletins.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_copy_feedback.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const strings = ChatBulletinStrings.english;
  const a = ContentKey.document('a');
  const b = ContentKey.document('b');
  const c = ContentKey.document('c');

  late FakeContentLibrary library;
  setUp(() {
    library = FakeContentLibrary(
      limits: const LibraryLimits(favouriteStickers: 2, savedGifs: 2),
    );
  });

  Bulletin? of(LibraryEdit edit) => ChatBulletins.ofLibraryEdit(
    library.apply(edit),
    limits: library.limits,
    strings: strings,
  );

  group('a sticker', () {
    test('added to favourites shows the sticker, short', () {
      final bulletin = of(const LibraryEdit.favouriteSticker(a))!;

      expect(bulletin.message, 'Sticker was added to Favorites');
      expect(bulletin.title, isNull);
      expect(
        bulletin.leading,
        isA<BulletinLeading$Thumbnail>().having((l) => l.source, 'source', a),
      );
      expect(bulletin.effectiveDuration, BulletinDuration.short);
    });

    test('added past the limit says an older one was replaced, 3.5 s', () {
      of(const LibraryEdit.favouriteSticker(a));
      of(const LibraryEdit.favouriteSticker(b));
      final bulletin = of(const LibraryEdit.favouriteSticker(c))!;

      expect(bulletin.title, 'Limit of 2 Stickers Reached');
      expect(bulletin.message, 'An older sticker was replaced with this one.');
      expect(
        bulletin.leading,
        isA<BulletinLeading$Thumbnail>().having((l) => l.source, 'source', c),
      );
      expect(
        bulletin.effectiveDuration,
        const BulletinDuration.exactly(Duration(milliseconds: 3500)),
      );
    });

    test('removed from favourites, short', () {
      of(const LibraryEdit.favouriteSticker(a));
      final bulletin = of(const LibraryEdit.unfavouriteSticker(a))!;

      expect(bulletin.message, 'Sticker was removed from Favorites');
      expect(bulletin.effectiveDuration, BulletinDuration.short);
    });

    test('removed from recents, short', () {
      library.apply(const LibraryEdit.addRecentSticker(a));
      final bulletin = of(const LibraryEdit.removeRecentSticker(a))!;

      expect(bulletin.message, 'Sticker was removed from Recent');
      expect(
        bulletin.leading,
        isA<BulletinLeading$Thumbnail>().having((l) => l.source, 'source', a),
      );
      expect(bulletin.effectiveDuration, BulletinDuration.short);
    });
  });

  group('a GIF', () {
    test('saved, with the saved-GIF icon, short', () {
      final bulletin = of(const LibraryEdit.saveGif(a))!;

      expect(bulletin.message, 'Added to saved GIFs');
      expect(
        bulletin.leading,
        isA<BulletinLeading$Icon>().having(
          (l) => l.icon,
          'icon',
          ChatBulletins.savedGifIcon,
        ),
      );
      expect(bulletin.effectiveDuration, BulletinDuration.short);
    });

    test('saved past the limit says an older one was replaced', () {
      of(const LibraryEdit.saveGif(a));
      of(const LibraryEdit.saveGif(b));
      final bulletin = of(const LibraryEdit.saveGif(c))!;

      expect(bulletin.title, 'Limit of 2 GIFs Reached');
      expect(bulletin.message, 'An older GIF was replaced with this one.');
      expect(
        bulletin.effectiveDuration,
        const BulletinDuration.exactly(Duration(milliseconds: 3500)),
      );
    });

    test('unsaved shows nothing', () {
      of(const LibraryEdit.saveGif(a));

      expect(of(const LibraryEdit.unsaveGif(a)), isNull);
    });
  });

  test('a pack edit is the pack sheet host\'s, not this', () {
    expect(
      of(const LibraryEdit.removePack(PackId('p'), PackKind.stickers)),
      isNull,
    );
  });

  group('a copy', () {
    test('of a link says so with the link icon', () {
      final bulletin = ChatBulletins.copied(ChatCopyKind.link, strings);

      expect(bulletin.message, 'Link copied to clipboard');
      expect(
        bulletin.leading,
        isA<BulletinLeading$Icon>().having(
          (l) => l.icon,
          'icon',
          ChatBulletins.linkIcon,
        ),
      );
      expect(bulletin.effectiveDuration, BulletinDuration.short);
    });

    test('of messages, text and code, each in its words', () {
      expect(
        ChatBulletins.copied(ChatCopyKind.messages, strings).message,
        'Message copied to clipboard.',
      );
      expect(
        ChatBulletins.copied(ChatCopyKind.textSelection, strings).message,
        'Text copied to clipboard',
      );
      final code = ChatBulletins.copied(ChatCopyKind.code, strings);
      expect(code.message, 'Code copied to clipboard');
      expect(
        code.leading,
        isA<BulletinLeading$Icon>().having(
          (l) => l.icon,
          'icon',
          ChatBulletins.copyIcon,
        ),
      );
      expect(code.effectiveDuration, BulletinDuration.short);
    });
  });

  test('an error leads with the info icon, short', () {
    final bulletin = ChatBulletins.error('No connection to the server');

    expect(bulletin.message, 'No connection to the server');
    expect(
      bulletin.leading,
      isA<BulletinLeading$Icon>().having(
        (l) => l.icon,
        'icon',
        ChatBulletins.infoIcon,
      ),
    );
    expect(bulletin.effectiveDuration, BulletinDuration.short);
  });

  test('the Russian set says the same', () {
    const ru = ChatBulletinStrings.russian;
    expect(ru.favouritesLimit(2), 'Достигнут лимит в 2 стикера');
    expect(ru.favouritesLimit(5), 'Достигнут лимит в 5 стикеров');
    expect(ru.favouritesLimit(21), 'Достигнут лимит в 21 стикер');
  });
}
