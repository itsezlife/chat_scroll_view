import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_pages/testing.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

import '../emoji/emoji_fixtures.dart' as fixtures;

// Regenerate with `flutter test --update-goldens test/goldens`.
//
// flutter_test draws text with the Ahem font, so an emoji is a square and
// glyph shapes do not depend on the host platform; the strip's pictures are
// the bundled art, decoded before the first frame. The page is drawn on the
// flat path (token colours, no glass), without an atlas: what is checked is
// layout, tokens, headers, strip and picker, in both reading directions.
//
// The goldens were generated on macOS. Pixel-exact comparison on another
// platform (CI runs Linux) is unconfirmed, as for the shell's goldens: if edge
// anti-aliasing of the rounded shapes differs there, regenerate on the pinned
// platform or add a tolerance comparator.
void main() {
  Future<void> precacheStripArt(WidgetTester tester) =>
      tester.runAsync(() async {
            for (final id in EmojiTabIcons.assets.keys) {
              await EmojiTabIcons.imageFor(EmojiTabIcons.assetKeyOf(id)!);
            }
          })
          as Future<void>;

  Future<void> pumpScene(
    WidgetTester tester, {
    required Brightness brightness,
    required TextDirection direction,
    List<String> recents = const [],
    PanelSearchState search = PanelSearchState.closed,
  }) async {
    final source = fixtures.source(recents: recents, count: 8);
    final searchSource = FakeSearchSource({
      'japan': FakePages([
        [fixtures.item('🇯🇵'), fixtures.item('😀')],
      ]),
    });
    final host = FakePanelPageHost(pageId: 'emoji')..searchState = search;
    final assets = PageAssets.createScope();
    addTearDown(() {
      source.dispose();
      searchSource.dispose();
      host.dispose();
      assets.dispose();
    });
    await tester.binding.setSurfaceSize(const Size(360, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await precacheStripArt(tester);
    await tester.pumpWidget(
      PanelShellTestScope(
        textDirection: direction,
        brightness: brightness,
        size: const Size(360, 480),
        speed: ChromeMotionSpeed.instant,
        child: RepaintBoundary(
          key: const ValueKey('scene'),
          child: ColoredBox(
            color: ChromePalette.forBrightness(brightness).surfaceDim,
            child: FakeSearchFieldScope(
              child: Overlay(
                initialEntries: [
                  OverlayEntry(
                    builder: (context) => EmojiPage(
                      host: host,
                      source: source,
                      searchSource: searchSource,
                      preferences: FakePreferenceStore(),
                      entryOf: fixtures.entryOf,
                      assets: assets,
                      searchDebounce: Duration.zero,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    // The pictures were decoded in real time; the scope picks them up on a
    // turn of the real event loop.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> matches(WidgetTester tester, String name) => expectLater(
    find.byKey(const ValueKey('scene')),
    matchesGoldenFile('emoji_page_$name.png'),
  );

  final variants = {
    'light_ltr': (Brightness.light, TextDirection.ltr),
    'dark_ltr': (Brightness.dark, TextDirection.ltr),
    'light_rtl': (Brightness.light, TextDirection.rtl),
  };

  for (final MapEntry(key: variant, value: (brightness, direction))
      in variants.entries) {
    testWidgets('the grid with recents and the strip, $variant', (
      tester,
    ) async {
      await pumpScene(
        tester,
        brightness: brightness,
        direction: direction,
        recents: ['😀', '❤', '👍'],
      );

      await matches(tester, 'grid_$variant');
    });
  }

  for (final MapEntry(key: variant, value: (brightness, direction))
      in variants.entries.where((e) => !e.key.startsWith('dark'))) {
    testWidgets('the recents alone, with the clear action, $variant', (
      tester,
    ) async {
      await pumpScene(
        tester,
        brightness: brightness,
        direction: direction,
        recents: ['😀', '❤', '👍', '🕵'],
        search: const PanelSearchState(isOpen: true),
      );

      await matches(tester, 'recents_$variant');
    });

    testWidgets('search results, $variant', (tester) async {
      await pumpScene(
        tester,
        brightness: brightness,
        direction: direction,
        search: const PanelSearchState(isOpen: true, query: 'japan'),
      );

      await matches(tester, 'search_$variant');
    });

    testWidgets('the variant picker over the grid, $variant', (tester) async {
      await pumpScene(
        tester,
        brightness: brightness,
        direction: direction,
        recents: ['👍'],
      );
      final cell =
          tester.getTopLeft(find.byType(EmojiPage)) +
          Offset(direction == TextDirection.ltr ? 27 : 360 - 27, 36 + 27 + 22);
      final gesture = await tester.startGesture(cell);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      await matches(tester, 'picker_$variant');
      await gesture.up();
      await tester.pump();
    });
  }

  // The pointer arrangement is the shell's: tabs above the search field, the
  // strip pinned at the bottom, the bar holding backspace above it. Two pages
  // so the tabs show.
  Future<PanelShellController> pumpPointerScene(
    WidgetTester tester, {
    required Brightness brightness,
    required TextDirection direction,
    bool searchOpen = false,
  }) async {
    final source = fixtures.source(recents: ['😀', '❤', '👍'], count: 8);
    final searchSource = FakeSearchSource({});
    final assets = PageAssets.createScope();
    final preferences = FakePreferenceStore();
    final shell = PanelShellController(
      pages: [
        PanelPage(
          id: 'emoji',
          tab: const PanelTab(icon: ChromeIconId.emoji, labelKey: 'emoji'),
          capabilities: EmojiPagePolicy.pageCapabilities,
          builder: (context, host) => EmojiPage(
            host: host,
            source: source,
            searchSource: searchSource,
            preferences: preferences,
            entryOf: fixtures.entryOf,
            assets: assets,
            searchDebounce: Duration.zero,
          ),
        ),
        FakePanelPage('stickers').page,
      ],
      preferences: preferences,
    );
    addTearDown(() {
      shell.dispose();
      source.dispose();
      searchSource.dispose();
      assets.dispose();
    });
    await tester.binding.setSurfaceSize(const Size(360, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await precacheStripArt(tester);
    await tester.pumpWidget(
      PanelShellTestScope(
        textDirection: direction,
        brightness: brightness,
        size: const Size(360, 480),
        speed: ChromeMotionSpeed.instant,
        child: RepaintBoundary(
          key: const ValueKey('scene'),
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (context) => PanelShell(
                  controller: shell,
                  announcer: FakePanelAnnouncer(),
                  arrangement: PanelArrangement.pointer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    if (searchOpen) {
      shell.openSearch(focus: false);
      await tester.pumpAndSettle();
    }
    return shell;
  }

  for (final MapEntry(key: variant, value: (brightness, direction))
      in variants.entries) {
    testWidgets('the pointer arrangement in a shell, $variant', (tester) async {
      await pumpPointerScene(
        tester,
        brightness: brightness,
        direction: direction,
      );

      await matches(tester, 'pointer_grid_$variant');
    });
  }

  testWidgets('the pointer arrangement with search open and no text, '
      'light_ltr', (tester) async {
    await pumpPointerScene(
      tester,
      brightness: Brightness.light,
      direction: TextDirection.ltr,
      searchOpen: true,
    );

    await matches(tester, 'pointer_search_empty_light_ltr');
  });

  testWidgets('the pointer arrangement with a mouse over a cell, light_ltr', (
    tester,
  ) async {
    await pumpPointerScene(
      tester,
      brightness: Brightness.light,
      direction: TextDirection.ltr,
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    // The second cell of the recents row.
    await mouse.moveTo(
      tester.getTopLeft(find.byType(EmojiPage)) + const Offset(70, 130),
    );
    await tester.pump();

    await matches(tester, 'pointer_hover_light_ltr');
  });

  // The third cell of the recents row, 👍: the one with variants.
  Offset thumbCell(WidgetTester tester) =>
      tester.getTopLeft(find.byType(EmojiPage)) +
      const Offset(5 + 43.75 * 2.5, 27 + 22.5);

  for (final MapEntry(key: variant, value: (brightness, direction))
      in variants.entries.where((e) => e.key != 'light_rtl')) {
    testWidgets('the variant picker under a mouse, $variant', (tester) async {
      await pumpPointerScene(
        tester,
        brightness: brightness,
        direction: direction,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      // A recent is held for: the picker opens after the hold. The first
      // option has the pointer's highlight.
      await mouse.down(thumbCell(tester));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      await mouse.moveTo(
        tester.getTopLeft(find.byType(EmojiVariantPicker)) +
            const Offset(10 + 8 + 45 + 8 + 1 + 8 + 45 + 22, 10 + 8 + 22),
      );
      await tester.pump();

      await matches(tester, 'mouse_picker_$variant');
      await mouse.up();
      await tester.pumpAndSettle();
    });

    testWidgets('the recents menu, $variant', (tester) async {
      await pumpPointerScene(
        tester,
        brightness: brightness,
        direction: direction,
      );
      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);

      await mouse.down(thumbCell(tester));
      await mouse.up();
      await tester.pumpAndSettle();

      await matches(tester, 'menu_$variant');
    });
  }
}
