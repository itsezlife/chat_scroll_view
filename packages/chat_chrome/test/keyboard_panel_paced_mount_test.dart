import 'dart:async';

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

  testWidgets('a cold open mounts the grid, then the search field, then the '
      'strip, before the panel starts to move', (tester) async {
    await tester.pumpWidget(harness());

    panel.open(landscape: false);
    await tester.pump();

    expect(find.byType(PanelCatalogViewport), findsOneWidget);
    expect(find.byType(EmojiSearchField), findsNothing);
    expect(find.byType(EmojiCategoryStripOverlay), findsNothing);
    expect(inset.height, 0, reason: 'nothing moves while the page mounts');

    await tester.pump();
    expect(find.byType(EmojiSearchField), findsOneWidget);
    await tester.pump();
    expect(find.byType(EmojiCategoryStripOverlay), findsOneWidget);
    expect(inset.height, 0, reason: 'the chrome is there before the slide');

    await tester.pumpAndSettle();
    expect(inset.height, closeTo(200, 1));
  });

  testWidgets('a panel that replaces the keyboard mounts everything at once', (
    tester,
  ) async {
    inset.onImeHeight(320, landscape: false);
    await tester.pumpWidget(harness());

    panel.open(landscape: false);
    await tester.pump();

    expect(find.byType(PanelCatalogViewport), findsOneWidget);
    expect(find.byType(EmojiSearchField), findsOneWidget);
    expect(find.byType(EmojiCategoryStripOverlay), findsOneWidget);
  });
}
