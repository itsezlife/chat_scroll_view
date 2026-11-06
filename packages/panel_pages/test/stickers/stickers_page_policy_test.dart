/// What makes the stickers policy the stickers policy, without a widget.
///
/// **Seam:** [StickersPagePolicy] called the way the scaffold calls it, with
/// plain collections, hits and panel strings.
library;

import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/panel_pages.dart';
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

  test('declares a top strip and nothing else: no search, no actions', () {
    expect(policy.capabilities.topStrip, isTrue);
    expect(policy.capabilities.search, isFalse);
    expect(policy.capabilities.actions, isEmpty);
    expect(policy.stripExtent, StickerPackStrip.height);
    expect(policy.stripAtBottom(PanelArrangement.touch), isFalse);
  });

  group('geometry', () {
    // `StickersGridAdapter`: stickersPerRow = width / dp(72); the cell is
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

    test('are titled by the pack, and the recents by the panel strings', () {
      expect(policy.titleOf(_pack('a', title: 'Cats'), _strings), 'Cats');
      expect(policy.titleOf(_recents(), _strings), _strings.recentlyUsedTitle);
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
}
