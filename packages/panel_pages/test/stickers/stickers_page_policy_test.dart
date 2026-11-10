/// What makes the stickers policy the stickers policy, without a widget.
///
/// **Seam:** [StickersPagePolicy] called the way the scaffold calls it, with
/// plain collections, hits and panel strings.
library;

import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_pages/src/policy/pack_section_action.dart';
import 'package:panel_pages/testing.dart';
import 'package:panel_shell/panel_shell.dart';

final _strings = ChromeStringsPresets.english.panel;

ContentKey _key(String id) => ContentKey.document(id);

CollectionItem _item(String id) => CollectionItem.described(
  ContentDescriptor(
    key: _key(id),
    semanticKind: SemanticKind.sticker,
    mediaForm: MediaForm.still,
    size: const ContentSize(512, 512),
    spokenName: 'sticker $id',
  ),
);

Collection _pack(String id, {String? title, int items = 3}) => Collection(
  id: CollectionId.set(id),
  metadata: CollectionMetadata(title: title),
  contents: CollectionContents.loaded([
    for (var i = 0; i < items; i++) _item('$id-$i'),
  ]),
);

Collection _recents({int items = 2}) => Collection(
  id: CollectionId.recent,
  contents: CollectionContents.loaded([
    for (var i = 0; i < items; i++) _item('r-$i'),
  ]),
);

Collection _favourites({int items = 2}) => Collection(
  id: CollectionId.faved,
  contents: CollectionContents.loaded([
    for (var i = 0; i < items; i++) _item('f-$i'),
  ]),
);

CatalogLeafHit _hit(Collection collection, int index) {
  final item = (collection.contents as CollectionContents$Loaded).items[index];
  return CatalogLeafHit(
    sectionId: '${collection.id}',
    index: index,
    leaf: CatalogLeaf.fromDescriptor(item.descriptor!),
  );
}

void main() {
  const policy = StickersPagePolicy();

  test('declares a strip (at the bottom under a pointer) and nothing '
      'else: no search, no actions', () {
    expect(policy.capabilities.topStrip, isTrue);
    expect(policy.capabilities.search, isFalse);
    expect(policy.capabilities.actions, isEmpty);
    expect(policy.stripExtent, StickerPackStrip.height);
    expect(policy.stripAtBottom(PanelArrangement.touch), isFalse);
    expect(policy.stripAtBottom(PanelArrangement.pointer), isTrue);
  });

  group('geometry', () {
    // Columns are width / 72; the cell is
    // 82 tall; the sticker is drawn at most 66; the name cell is 27 tall and
    // its text begins 15 in.
    test('takes the columns from the width, 72 at least, rows 82 tall', () {
      final layout = policy.layoutOf(_pack('a')) as SectionLayout$Grid;

      expect(layout.desiredCellWidth, 72);
      expect(layout.spanCount, isNull);
      expect(layout.cellExtent, 82);
      expect(layout.headerExtent, 27);
    });

    test('draws a sticker at 66, not the whole cell', () {
      final layout = policy.layoutOf(_pack('a')) as SectionLayout$Grid;

      expect(policy.contentBoxOf(_pack('a')), CatalogContentBox.glyph);
      expect(layout.glyphExtent, 66);
    });

    test('is the same under the pointer arrangement', () {
      expect(
        policy.layoutOf(_pack('a'), arrangement: PanelArrangement.pointer),
        policy.layoutOf(_pack('a')),
      );
    });

    test('begins the section titles 15 in', () {
      expect(policy.headerStartInset, 15);
    });
  });

  group('sections', () {
    test('show every pack, and the recents only while there are some', () {
      final packs = [_pack('a'), _pack('b')];

      expect(policy.visibleCollections([_recents(items: 0), ...packs]), packs);
      expect(policy.visibleCollections([_recents(), ...packs]), [
        _recents(),
        ...packs,
      ]);
    });

    test('show the favourites only while there are some', () {
      final packs = [_pack('a')];

      expect(
        policy.visibleCollections([
          _favourites(items: 0),
          _recents(),
          ...packs,
        ]),
        [_recents(), ...packs],
      );
      expect(policy.visibleCollections([_favourites(), _recents(), ...packs]), [
        _favourites(),
        _recents(),
        ...packs,
      ]);
    });

    test('keep favourites still loading, as they may have some', () {
      const loading = Collection(id: CollectionId.faved);

      expect(policy.visibleCollections([loading]), [loading]);
    });

    test('are titled by the pack, and the recents by the panel strings', () {
      expect(policy.titleOf(_pack('a', title: 'Cats'), _strings), 'Cats');
      expect(policy.titleOf(_recents(), _strings), _strings.recentlyUsedTitle);
    });

    test('title the favourites by the panel strings', () {
      expect(
        policy.titleOf(_favourites(), _strings),
        _strings.favouriteStickersTitle,
      );
    });
  });

  group('picks', () {
    test('files a sticker under its own kind, as from a pack', () {
      final pack = _pack('a');

      expect(
        policy.pickOf(_hit(pack, 1), pack, searching: false),
        CatalogPick(
          key: _key('a-1'),
          kind: SemanticKind.sticker,
          source: PickSource.collection,
        ),
      );
    });

    test('says a pick from the recents is from the recents', () {
      final recents = _recents();

      expect(
        policy.pickOf(_hit(recents, 0), recents, searching: false)?.source,
        PickSource.recents,
      );
    });

    test('files a favourite under its own kind, as from a collection', () {
      final favourites = _favourites();

      expect(
        policy.pickOf(_hit(favourites, 1), favourites, searching: false),
        CatalogPick(
          key: _key('f-1'),
          kind: SemanticKind.sticker,
          source: PickSource.collection,
        ),
      );
    });
  });

  group('the recents header', () {
    test('carries a clear button, and no pack header does', () {
      expect(
        policy.actionOf(_recents(), _strings)?.id,
        StickersPagePolicy.clearRecentsActionId,
      );
      expect(
        policy.actionOf(_recents(), _strings)?.semanticLabel,
        _strings.clearRecentAction,
      );
      expect(policy.actionOf(_pack('a'), _strings), isNull);
    });

    test('paints its cross as one stroked path, so the crossing is not '
        'covered twice by a translucent colour', () {
      final canvas = TestRecordingCanvas();
      policy.actionOf(_recents(), _strings)!.painter!(
        canvas,
        const Rect.fromLTWH(0, 0, 24, 24),
        const Color(0x80FFFFFF),
      );
      final calls = canvas.invocations.map((i) => i.invocation.memberName);
      expect(calls, isNot(contains(#drawLine)));
      expect(calls.where((name) => name == #drawPath), hasLength(1));
    });

    test('is the only one: the favourites header has no button', () {
      expect(policy.actionOf(_favourites(), _strings), isNull);
    });

    test('asks the host to clear the recent stickers, which it confirms', () {
      final host = FakePanelPageHost();
      addTearDown(host.dispose);

      policy.onSectionAction(
        _recents(),
        StickersPagePolicy.clearRecentsActionId,
        host,
      );

      expect(host.clearRecentsRequests, [SemanticKind.sticker]);
    });

    test('ignores an action it does not know', () {
      final host = FakePanelPageHost();
      addTearDown(host.dispose);

      policy.onSectionAction(_recents(), 'other', host);

      expect(host.clearRecentsRequests, isEmpty);
    });
  });

  group('the remove badge', () {
    test('a recent or a favourite has one; a pack\'s sticker has none', () {
      expect(policy.leafRemovable(_hit(_recents(), 0), _recents()), isTrue);
      expect(
        policy.leafRemovable(_hit(_favourites(), 0), _favourites()),
        isTrue,
      );
      expect(policy.leafRemovable(_hit(_pack('a'), 0), _pack('a')), isFalse);
    });

    test('a recent leaves the recents, a favourite the favourites', () {
      final host = FakePanelPageHost();
      addTearDown(host.dispose);

      policy
        ..onLeafRemove(_hit(_recents(), 1), _recents(), host)
        ..onLeafRemove(_hit(_favourites(), 0), _favourites(), host);

      expect(host.removeRecentRequests, [
        (key: _key('r-1'), kind: SemanticKind.sticker),
      ]);
      expect(host.libraryEditRequests, [
        LibraryEdit.unfavouriteSticker(_key('f-0')),
      ]);
    });
  });

  group('the remove button of a pack\'s header', () {
    Collection installed(String id) => Collection(
      id: CollectionId.set(id),
      metadata: const CollectionMetadata(
        title: 'Cats',
        flags: CollectionFlags.installed,
      ),
      contents: CollectionContents.loaded(const []),
    );

    test('ends an installed pack\'s header under a pointer, as a cross', () {
      final action = policy.actionOf(
        installed('a'),
        _strings,
        arrangement: PanelArrangement.pointer,
      );
      expect(action?.id, PackSectionAction.removePackActionId);
      expect(action?.semanticLabel, _strings.removePackAction);
      expect(action?.painter, isNotNull);
    });

    test('is not there under touch, nor on a pack not installed', () {
      expect(policy.actionOf(installed('a'), _strings), isNull);
      expect(
        policy.actionOf(
          _pack('a'),
          _strings,
          arrangement: PanelArrangement.pointer,
        ),
        isNull,
      );
    });

    test('asks the host to remove the pack, which it confirms', () {
      final host = FakePanelPageHost();
      addTearDown(host.dispose);

      policy.onSectionAction(
        installed('a'),
        PackSectionAction.removePackActionId,
        host,
      );

      expect(host.libraryEditRequests, [
        const LibraryEdit.removePack(PackId('a'), PackKind.stickers),
      ]);
    });
  });
}
