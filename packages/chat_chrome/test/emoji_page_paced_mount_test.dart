import 'dart:async';

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
  late TextEditingController search;
  late FocusNode focus;
  late ValueNotifier<bool> searchOpen;
  late ValueNotifier<double> fieldTy;
  setUp(() {
    data = _Data();
    search = TextEditingController();
    focus = FocusNode();
    searchOpen = ValueNotifier<bool>(false);
    fieldTy = ValueNotifier<double>(EmojiPage.gridPadTop);
  });
  tearDown(() {
    data.dispose();
    search.dispose();
    focus.dispose();
    searchOpen.dispose();
    fieldTy.dispose();
  });

  Widget page({required bool deferChrome}) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 360,
        height: 480,
        child: EmojiPage(
          dataSource: data,
          recents: const [],
          recentlyUsedLabel: 'Recent',
          onEmojiSelected: (_, {source = EmojiPickSource.grid}) {},
          // The wiring the panel shell gives its page: sticky search + strip.
          searchController: search,
          searchModeListenable: searchOpen,
          searchFieldTranslationY: fieldTy,
          searchFocusNode: focus,
          onOpenSearch: () {},
          deferChrome: deferChrome,
        ),
      ),
    ),
  );

  testWidgets('a page mounts its chrome with the grid by default', (
    tester,
  ) async {
    await tester.pumpWidget(page(deferChrome: false));

    expect(find.byType(PanelCatalogViewport), findsOneWidget);
    expect(find.byType(EmojiSearchField), findsOneWidget);
    expect(find.byType(EmojiCategoryStripOverlay), findsOneWidget);
  });

  testWidgets('a page with deferred chrome mounts the grid, then the search '
      'field, then the strip, one frame each', (tester) async {
    await tester.pumpWidget(page(deferChrome: true));

    expect(find.byType(PanelCatalogViewport), findsOneWidget);
    expect(find.byType(EmojiSearchField), findsNothing);
    expect(find.byType(EmojiCategoryStripOverlay), findsNothing);

    await tester.pump();

    expect(find.byType(EmojiSearchField), findsOneWidget);
    expect(find.byType(EmojiCategoryStripOverlay), findsNothing);

    await tester.pump();

    expect(find.byType(EmojiSearchField), findsOneWidget);
    expect(find.byType(EmojiCategoryStripOverlay), findsOneWidget);
  });
}
