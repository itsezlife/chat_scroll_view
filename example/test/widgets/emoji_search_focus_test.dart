import 'package:chat_chrome/chat_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Feedback loop for: search field loses focus when keyword results flip
/// between non-empty and empty (or empty → non-empty).
Future<DefaultEmojiDataSource> _createSource() async {
  final source = DefaultEmojiDataSource(
    catalog: LocaleEmojiCatalogProvider(filterUnsupported: false),
    recentsStore: MemoryEmojiRecentsStore(),
    skinTonePrefs: MemorySkinTonePrefs(),
  );
  await source.load();
  return source;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DefaultEmojiDataSource dataSource;
  late TextEditingController searchController;
  late FocusNode searchFocus;
  late ValueNotifier<bool> searchMode;
  late ValueNotifier<double> searchFieldTy;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    dataSource = await _createSource();
    searchController = TextEditingController();
    searchFocus = FocusNode(debugLabel: 'EmojiSearchFocusTest');
    searchMode = ValueNotifier<bool>(true);
    searchFieldTy = ValueNotifier<double>(0);
  });

  tearDown(() async {
    searchFocus.unfocus();
    await Future<void>.delayed(Duration.zero);
    searchController.dispose();
    searchFocus.dispose();
    searchMode.dispose();
    searchFieldTy.dispose();
    dataSource.dispose();
  });

  Widget harness() => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 360,
        height: 480,
        child: EmojiPage(
          dataSource: dataSource,
          recents: const <String>[],
          recentlyUsedLabel: 'Recently used',
          searchController: searchController,
          searchModeListenable: searchMode,
          searchFieldTranslationY: searchFieldTy,
          searchFocusNode: searchFocus,
          onOpenSearch: () => searchMode.value = true,
          onEmojiSelected: (_, {required source}) {},
        ),
      ),
    ),
  );

  Future<void> settleSearch(WidgetTester tester) async {
    // Debounce + async catalog search.
    await tester.pump(KeyboardPanelMotion.searchDebounce);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets(
    'keeps search focus across empty ↔ non-empty keyword results',
    (tester) async {
      await tester.pumpWidget(harness());
      await tester.pump();

      // Drive the real TextField path (not only controller listeners).
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(searchFocus.hasFocus, isTrue, reason: 'precondition: focused');

      final fieldState = tester.state(find.byType(EmojiSearchField));

      await tester.enterText(find.byType(TextField), 'cat');
      await settleSearch(tester);
      expect(find.text('No emoji found'), findsNothing);
      expect(
        searchFocus.hasFocus,
        isTrue,
        reason: 'focus after first non-empty results',
      );
      expect(
        identical(tester.state(find.byType(EmojiSearchField)), fieldState),
        isTrue,
        reason: 'EmojiSearchField State must survive first results',
      );

      await tester.enterText(find.byType(TextField), 'zzzznotanemoji');
      await settleSearch(tester);
      expect(find.text('No emoji found'), findsOneWidget);
      expect(
        searchFocus.hasFocus,
        isTrue,
        reason: 'focus after results → empty',
      );
      expect(
        identical(tester.state(find.byType(EmojiSearchField)), fieldState),
        isTrue,
        reason: 'EmojiSearchField State must survive results → empty',
      );

      await tester.enterText(find.byType(TextField), 'dog');
      await settleSearch(tester);
      expect(find.text('No emoji found'), findsNothing);
      expect(
        searchFocus.hasFocus,
        isTrue,
        reason: 'focus after empty → results',
      );
      expect(
        identical(tester.state(find.byType(EmojiSearchField)), fieldState),
        isTrue,
        reason: 'EmojiSearchField State must survive empty → results',
      );
    },
  );
}
