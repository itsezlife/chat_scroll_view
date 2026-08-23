import 'package:chat_chrome/chat_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<DefaultEmojiDataSource> createTestEmojiDataSource() async {
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

  late KeyboardHeightStore store;
  late DefaultEmojiDataSource dataSource;
  late GlobalKey<EmojiPageState> pageKey;
  final selected = <String>[];
  final sources = <EmojiPickSource>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    store = KeyboardHeightStore(defaultHeight: 200);
    await store.load();
    dataSource = await createTestEmojiDataSource();
    pageKey = GlobalKey<EmojiPageState>();
    selected.clear();
    sources.clear();
  });

  tearDown(() => dataSource.dispose());

  Widget harness({
    List<String> recents = const <String>[],
    String searchQuery = '',
    bool searchMode = false,
  }) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 360,
        height: 480,
        child: EmojiPage(
          key: pageKey,
          dataSource: dataSource,
          recents: recents,
          recentlyUsedLabel: 'Recently used',
          searchQuery: searchQuery,
          searchMode: searchMode,
          onEmojiSelected: (g, {required source}) {
            selected.add(g);
            sources.add(source);
          },
        ),
      ),
    ),
  );

  Future<void> pumpJump(WidgetTester tester, int index) async {
    final future = pageKey.currentState!.jumpToSection(index);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await future;
  }

  Future<void> revealGlyph(WidgetTester tester, String glyph) async {
    final finder = find.text(glyph);
    final scrollable = find
        .descendant(
          of: find.byType(EmojiPage),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(finder, 120, scrollable: scrollable);
    await tester.drag(scrollable, const Offset(0, 80));
    await tester.pump();
  }

  testWidgets('category strip jump scrolls to real section offsets', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final animalsIndex = dataSource.categories.indexWhere(
      (c) => c.id == 'animals',
    );
    expect(animalsIndex, greaterThanOrEqualTo(0));

    await pumpJump(tester, animalsIndex);
    expect(pageKey.currentState!.categoryIndex, animalsIndex);
    expect(find.text('Animals'), findsWidgets);

    final flagsIndex = dataSource.categories.indexWhere(
      (c) => c.id == 'flags',
    );
    await pumpJump(tester, flagsIndex);
    expect(pageKey.currentState!.categoryIndex, flagsIndex);
    expect(find.text('Flags'), findsWidgets);
  });

  testWidgets('jump updates category strip selection', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final flagsIndex = dataSource.categories.indexWhere(
      (c) => c.id == 'flags',
    );
    await pumpJump(tester, flagsIndex);
    expect(pageKey.currentState!.categoryIndex, flagsIndex);

    await pumpJump(tester, 0);
    expect(pageKey.currentState!.categoryIndex, 0);
  });

  testWidgets('tap skin-capable emoji inserts without opening picker', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await revealGlyph(tester, '👍');
    await tester.tap(find.text('👍'));
    await tester.pump();

    expect(selected, <String>['👍']);
    expect(find.byType(EmojiColorPicker), findsNothing);
  });

  testWidgets('tap uses persisted skin tone', (tester) async {
    await dataSource.setSkinTone('👍', 3);
    await tester.pumpWidget(harness());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final colored = EmojiSkinTone.apply('👍', 3);
    await revealGlyph(tester, colored);
    expect(find.text(colored), findsOneWidget);
    await tester.tap(find.text(colored));
    await tester.pump();

    expect(selected, <String>[colored]);
  });

  testWidgets('long-press opens color picker', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await revealGlyph(tester, '👍');
    final center = tester.getCenter(find.text('👍'));
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(EmojiColorPicker), findsOneWidget);
    await gesture.up();
    await tester.pump();
  });

  testWidgets('long-press recent requests clear (does not wipe alone)', (
    tester,
  ) async {
    var requested = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            height: 480,
            child: EmojiPage(
              dataSource: dataSource,
              recents: const <String>['😀', '🎉'],
              recentlyUsedLabel: 'Recently used',
              onEmojiSelected: (g, {required source}) => selected.add(g),
              onClearRecents: () => requested = true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final center = tester.getCenter(find.text('😀').first);
    final gesture = await tester.startGesture(center);
    await tester.pump(const Duration(seconds: 1));
    expect(requested, isTrue);
    expect(find.byType(EmojiColorPicker), findsNothing);
    await gesture.up();
    await tester.pump();
  });

  testWidgets('scroll hides category strip', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();
    expect(pageKey.currentState!.stripOffset, 0);

    final scrollable = find
        .descendant(
          of: find.byType(EmojiPage),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.drag(scrollable, const Offset(0, -120));
    await tester.pump();
    expect(pageKey.currentState!.stripOffset, lessThan(0));
  });

  testWidgets('jumpToSection resets strip offset', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    final scrollable = find
        .descendant(
          of: find.byType(EmojiPage),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.drag(scrollable, const Offset(0, -120));
    await tester.pump();
    expect(pageKey.currentState!.stripOffset, lessThan(0));

    await pumpJump(tester, 0);
    expect(pageKey.currentState!.stripOffset, 0);
  });

  testWidgets('searchMode empty query reports search pick source', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(recents: const <String>['😀', '🎉'], searchMode: true),
    );
    await tester.pump();

    await tester.tap(find.text('😀'));
    await tester.pump();

    expect(selected, ['😀']);
    expect(sources, [EmojiPickSource.search]);
  });

  group('emojiBackspace', () {
    test('deletes grapheme before caret', () {
      final controller = TextEditingController(text: 'hello');
      controller.selection = const TextSelection.collapsed(offset: 3);
      emojiBackspace(controller);
      expect(controller.text, 'helo');
      expect(controller.selection.baseOffset, 2);
      controller.dispose();
    });

    test('deletes selection', () {
      final controller = TextEditingController(text: 'hello');
      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 4,
      );
      emojiBackspace(controller);
      expect(controller.text, 'ho');
      expect(controller.selection.baseOffset, 1);
      controller.dispose();
    });
  });
}
