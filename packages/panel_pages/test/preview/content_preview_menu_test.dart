/// The content preview's menu: which items it holds for what is shown, where
/// it was opened and what the opener can do, and what choosing one asks.
///
/// **Seam:** [ContentPreviewMenu] as pure functions over a
/// [ContentPreviewItem], [ContentPreviewActions] recording what they are asked
/// and a [FakeContentLibrary].
library;

import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/panel_pages.dart';

const _sticker = ContentKey.document('s1');
const _gif = ContentKey.document('g1');
const _emoji = ContentKey.document('e1');
const _cats = PackId('cats');

ContentPreviewItem _stickerItem({
  PackId? pack = _cats,
  bool inRecents = false,
}) => ContentPreviewItem(
  key: _sticker,
  semanticKind: SemanticKind.sticker,
  pack: pack,
  inRecents: inRecents,
);

const _gifItem = ContentPreviewItem(key: _gif, semanticKind: SemanticKind.gif);

void main() {
  late FakeContentLibrary library;
  late List<String> asked;
  late ContentPreviewActions all;

  setUp(() {
    library = FakeContentLibrary(
      limits: const LibraryLimits(favouriteStickers: 5, savedGifs: 200),
    );
    addTearDown(library.dispose);
    asked = [];
    all = ContentPreviewActions(
      send: (item) => asked.add('send ${item.key}'),
      sendWithoutSound: (item) => asked.add('silent ${item.key}'),
      copy: (item) => asked.add('copy ${item.key}'),
      removeRecent: (item) => asked.add('forget ${item.key}'),
      editLibrary: (edit) => asked.add('$edit'),
      viewPack: (id) => asked.add('pack ${id.value}'),
    );
  });

  group('kinds', () {
    test('stickers, masks, GIFs and custom emoji are previewed; unicode '
        'emoji never', () {
      expect(
        ContentPreviewKind.of(SemanticKind.sticker),
        ContentPreviewKind.sticker,
      );
      expect(
        ContentPreviewKind.of(SemanticKind.mask),
        ContentPreviewKind.sticker,
      );
      expect(ContentPreviewKind.of(SemanticKind.gif), ContentPreviewKind.gif);
      expect(
        ContentPreviewKind.of(SemanticKind.customEmoji),
        ContentPreviewKind.customEmoji,
      );
      expect(ContentPreviewKind.of(SemanticKind.unicodeEmoji), isNull);
      expect(ContentPreviewKind.of(SemanticKind.unknown), isNull);
      expect(ContentPreviewItem.ofLeaf(CatalogLeaf.unicode('😀')), isNull);
    });

    test('an item of a cell carries what the cell knows', () {
      final leaf = CatalogLeaf.fromDescriptor(
        const ContentDescriptor(
          key: _sticker,
          semanticKind: SemanticKind.sticker,
          mediaForm: MediaForm.still,
          size: ContentSize(512, 256),
          shortcode: '😺',
          spokenName: 'cat',
        ),
      );

      final item = ContentPreviewItem.ofLeaf(
        leaf,
        pack: _cats,
        inRecents: true,
      )!;

      expect(item.key, _sticker);
      expect(item.kind, ContentPreviewKind.sticker);
      expect(item.pack, _cats);
      expect(item.inRecents, isTrue);
      expect(item.emoji, '😺');
      expect(item.size, const ContentSize(512, 256));
    });
  });

  group('a sticker', () {
    test('in the reference order: send, send without sound, favourite, view '
        'pack, delete from recent', () {
      expect(
        ContentPreviewMenu.of(
          _stickerItem(inRecents: true),
          all,
          library: library,
        ),
        [
          ContentPreviewAction.send,
          ContentPreviewAction.sendWithoutSound,
          ContentPreviewAction.favourite,
          ContentPreviewAction.viewPack,
          ContentPreviewAction.removeRecent,
        ],
      );
    });

    test('a favourite offers to come out of the favourites', () {
      library.apply(const LibraryEdit.favouriteSticker(_sticker));

      expect(
        ContentPreviewMenu.of(_stickerItem(), all, library: library),
        contains(ContentPreviewAction.unfavourite),
      );
    });

    test('without a pack: no favourite to add and no pack to view; a '
        'favourite can still come out', () {
      final menu = ContentPreviewMenu.of(
        _stickerItem(pack: null),
        all,
        library: library,
      );
      expect(menu, [
        ContentPreviewAction.send,
        ContentPreviewAction.sendWithoutSound,
      ]);

      library.apply(const LibraryEdit.favouriteSticker(_sticker));
      expect(
        ContentPreviewMenu.of(_stickerItem(pack: null), all, library: library),
        contains(ContentPreviewAction.unfavourite),
      );
    });

    test('a mask is never a favourite', () {
      const mask = ContentPreviewItem(
        key: _sticker,
        semanticKind: SemanticKind.mask,
        pack: _cats,
      );
      expect(
        ContentPreviewMenu.of(mask, all, library: library),
        isNot(contains(ContentPreviewAction.favourite)),
      );
    });

    test('offers only what the opener can do', () {
      expect(
        ContentPreviewMenu.of(
          _stickerItem(inRecents: true),
          const ContentPreviewActions(),
          library: library,
        ),
        isEmpty,
      );
      expect(
        ContentPreviewMenu.of(
          _stickerItem(),
          ContentPreviewActions(viewPack: (_) {}),
          library: library,
        ),
        [ContentPreviewAction.viewPack],
      );
      expect(
        ContentPreviewMenu.of(_stickerItem(), all),
        isNot(contains(ContentPreviewAction.favourite)),
        reason: 'no library to read whether it is one',
      );
    });

    test('the library items ask for library edits', () {
      final item = _stickerItem(inRecents: true);
      ContentPreviewMenu.perform(ContentPreviewAction.favourite, item, all);
      ContentPreviewMenu.perform(ContentPreviewAction.unfavourite, item, all);
      ContentPreviewMenu.perform(ContentPreviewAction.removeRecent, item, all);
      ContentPreviewMenu.perform(ContentPreviewAction.viewPack, item, all);
      ContentPreviewMenu.perform(ContentPreviewAction.send, item, all);

      expect(asked, [
        '${const LibraryEdit.favouriteSticker(_sticker)}',
        '${const LibraryEdit.unfavouriteSticker(_sticker)}',
        '${const LibraryEdit.removeRecentSticker(_sticker)}',
        'pack cats',
        'send $_sticker',
      ]);
    });
  });

  group('a GIF', () {
    test('send, send without sound, then save', () {
      expect(ContentPreviewMenu.of(_gifItem, all, library: library), [
        ContentPreviewAction.send,
        ContentPreviewAction.sendWithoutSound,
        ContentPreviewAction.saveGif,
      ]);
    });

    test('a saved one offers delete, in the attention style', () {
      library.apply(const LibraryEdit.saveGif(_gif));

      final menu = ContentPreviewMenu.of(_gifItem, all, library: library);
      expect(menu.last, ContentPreviewAction.unsaveGif);
      expect(
        ContentPreviewMenu.isAttention(
          ContentPreviewAction.unsaveGif,
          _gifItem,
        ),
        isTrue,
      );

      ContentPreviewMenu.perform(ContentPreviewAction.unsaveGif, _gifItem, all);
      ContentPreviewMenu.perform(ContentPreviewAction.saveGif, _gifItem, all);
      expect(asked, [
        '${const LibraryEdit.unsaveGif(_gif)}',
        '${const LibraryEdit.saveGif(_gif)}',
      ]);
    });
  });

  group('a custom emoji', () {
    test('send, copy and, in the recents, remove: never a favourite or a '
        'pack', () {
      const item = ContentPreviewItem(
        key: _emoji,
        semanticKind: SemanticKind.customEmoji,
        pack: _cats,
        inRecents: true,
      );

      expect(ContentPreviewMenu.of(item, all, library: library), [
        ContentPreviewAction.send,
        ContentPreviewAction.copy,
        ContentPreviewAction.removeRecent,
      ]);
      expect(
        ContentPreviewMenu.isAttention(ContentPreviewAction.removeRecent, item),
        isTrue,
      );

      ContentPreviewMenu.perform(ContentPreviewAction.removeRecent, item, all);
      ContentPreviewMenu.perform(ContentPreviewAction.copy, item, all);
      expect(asked, ['forget $_emoji', 'copy $_emoji']);
    });
  });

  group('labels', () {
    final strings = ChromeStringsPresets.english.panel;

    test('are the reference texts, per kind for send', () {
      String label(ContentPreviewAction action, ContentPreviewItem item) =>
          ContentPreviewMenu.labelOf(action, item, strings);
      const emoji = ContentPreviewItem(
        key: _emoji,
        semanticKind: SemanticKind.customEmoji,
      );

      expect(label(ContentPreviewAction.send, _stickerItem()), 'Send Sticker');
      expect(label(ContentPreviewAction.send, _gifItem), 'Send GIF');
      expect(label(ContentPreviewAction.send, emoji), 'Send Emoji');
      expect(label(ContentPreviewAction.copy, emoji), 'Copy Emoji');
      expect(
        label(ContentPreviewAction.removeRecent, _stickerItem()),
        'Delete from Recent',
      );
      expect(
        label(ContentPreviewAction.removeRecent, emoji),
        strings.removeRecentAction,
      );
      expect(
        label(ContentPreviewAction.favourite, _stickerItem()),
        'Add to Favorites',
      );
      expect(
        label(ContentPreviewAction.unfavourite, _stickerItem()),
        'Delete from Favorites',
      );
      expect(label(ContentPreviewAction.viewPack, _stickerItem()), 'View Pack');
      expect(label(ContentPreviewAction.saveGif, _gifItem), 'Save to GIFs');
      expect(label(ContentPreviewAction.unsaveGif, _gifItem), 'Delete');
    });

    test('a context menu holds the same items under their ids', () {
      final entries = ContentPreviewMenu.entriesOf(
        _stickerItem(),
        all,
        strings,
        library: library,
      );

      expect(
        [for (final entry in entries.cast<CatalogMenuItem>()) entry.id],
        [
          for (final action in ContentPreviewMenu.of(
            _stickerItem(),
            all,
            library: library,
          ))
            action.id,
        ],
      );
      expect(
        ContentPreviewAction.byId('favourite'),
        ContentPreviewAction.favourite,
      );
      expect(ContentPreviewAction.byId('nonsense'), isNull);
    });
  });
}
