import 'dart:async';

import 'package:catalog_assets/glyph_atlas.dart';
import 'package:chat_chrome/chat_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Data data;
  late KeyboardPanelStore store;
  late ChatBottomInsetController inset;
  late KeyboardPanelController panel;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = KeyboardPanelStore(defaultHeight: 200);
    await store.load();
    data = _Data();
    inset = ChatBottomInsetController(store: store);
    panel = KeyboardPanelController(inset: inset, store: store);
  });
  tearDown(() {
    panel.dispose();
    inset.dispose();
    data.dispose();
  });

  Widget harness() => MaterialApp(
    home: Scaffold(
      body: Column(
        children: <Widget>[
          const Expanded(child: SizedBox.expand()),
          ValueListenableBuilder<double>(
            valueListenable: inset.heightListenable,
            builder: (context, height, child) =>
                SizedBox(height: height < 0 ? 0 : height, child: child),
            child: KeyboardPanel(
              controller: panel,
              dataSource: data,
              allow: KeyboardPanelAllow.emojiOnly,
              onEmojiSelected: (_) {},
              onBackspace: () {},
            ),
          ),
        ],
      ),
    ),
  );

  int bakedGlyphSize(WidgetTester tester) =>
      (tester
                  .widget<PanelCatalogViewport>(
                    find.byType(PanelCatalogViewport),
                  )
                  .assets
                  .glyphSource!
              as GlyphAtlas)
          .index
          .layout
          .glyphSize;

  testWidgets('the baked glyph size follows the screen density mid-session', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(harness());
    panel.open(landscape: false);
    await tester.pumpAndSettle();
    final before = bakedGlyphSize(tester);

    tester.view.devicePixelRatio = 3;
    await tester.pumpAndSettle();

    expect(bakedGlyphSize(tester), greaterThan(before));
  });
}
