import 'dart:async';

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chat_chrome/chat_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';

/// A ready emoji source with one category.
class _Data extends EmojiDataSource with EmojiDataListenerMixin {
  @override
  final List<EmojiCategorySpec> categories = const [
    EmojiCategorySpec(
      id: 'faces',
      title: 'Faces',
      items: [
        EmojiItem.unicode(glyph: '😀'),
        EmojiItem.unicode(glyph: '😁'),
      ],
    ),
  ];

  @override
  bool get isReady => true;
  @override
  int skinToneFor(String base) => 0;
  @override
  List<String> get recentGlyphs => const [];
  @override
  Future<void> load() async {}
  @override
  FutureOr<List<EmojiItem>> search(String query) => const [];
  @override
  Future<void> recordPick(EmojiItem item, {required EmojiPickSource source}) =>
      Future.value();
  @override
  Future<void> clearRecents() => Future.value();
  @override
  Future<void> setSkinTone(String base, int toneIndex) => Future.value();
  @override
  void dispose() => disposeDataListeners();
}

void main() {
  late _Data data;
  late FakeBakeFrameSource frames;
  late ValueNotifier<bool> visible;
  late ValueNotifier<bool> opening;

  setUp(() {
    data = _Data();
    frames = FakeBakeFrameSource();
    visible = ValueNotifier<bool>(true);
    opening = ValueNotifier<bool>(false);
  });
  tearDown(() {
    data.dispose();
    visible.dispose();
    opening.dispose();
  });

  GlyphAtlas atlas() {
    final atlas = GlyphAtlas(
      index: GlyphAtlasIndex(['😀', '😁']),
      rasteriser: FakeGlyphRasteriser(),
      store: FakeGlyphPageStore(),
      frames: frames,
      clock: ManualBakeClock().read,
      panelVisible: visible,
      panelOpening: opening,
    );
    addTearDown(atlas.dispose);
    return atlas;
  }

  Widget page(GlyphAtlas? glyphAtlas) => MaterialApp(
    home: Scaffold(
      body: EmojiPage(
        dataSource: data,
        recents: const [],
        recentlyUsedLabel: 'Recent',
        onEmojiSelected: (_, {source = EmojiPickSource.grid}) {},
        glyphAtlas: glyphAtlas,
      ),
    ),
  );

  GlyphAtlas? drawnFrom(WidgetTester tester) =>
      tester
              .widget<PanelCatalogViewport>(find.byType(PanelCatalogViewport))
              .assets
              .glyphSource
          as GlyphAtlas?;

  testWidgets('a page without an atlas draws text', (tester) async {
    await tester.pumpWidget(page(null));

    expect(drawnFrom(tester), isNull);
  });

  testWidgets('a page draws from the atlas it is given', (tester) async {
    final first = atlas();
    await tester.pumpWidget(page(first));

    expect(drawnFrom(tester), same(first));
  });

  testWidgets('a new atlas replaces the old one in the grid', (tester) async {
    final first = atlas();
    final second = atlas();
    await tester.pumpWidget(page(first));

    await tester.pumpWidget(page(second));
    expect(drawnFrom(tester), same(second));

    await tester.pumpWidget(page(null));
    expect(drawnFrom(tester), isNull);
  });
}
