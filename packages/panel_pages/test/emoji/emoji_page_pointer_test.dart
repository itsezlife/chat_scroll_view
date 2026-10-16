/// The emoji page under the pointer arrangement: where its strip is, what an
/// empty search shows, and how one press of the clear control brings the grid
/// back.
///
/// **Seam:** a `PanelShell` given `PanelArrangement.pointer` (or `touch`, for
/// the contrast) over an [EmojiPage], observed through the geometry of what is
/// on screen, the shell controller's search state and the extent the page
/// reported.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

import 'emoji_fixtures.dart' as fixtures;

void main() {
  late FakePreferenceStore preferences;
  late FakeCollectionSource source;
  late FakeSearchSource search;
  late AssetCacheScope assets;
  late PanelShellController shell;

  setUp(() {
    preferences = FakePreferenceStore();
    source = fixtures.source(recents: ['😀'], count: 40);
    search = FakeSearchSource({
      'cat': FakePages([
        [fixtures.item('🐱')],
      ]),
    });
    assets = PageAssets.createScope();
  });

  tearDown(() {
    shell.dispose();
    source.dispose();
    search.dispose();
    assets.dispose();
  });

  final arrangementOf = ValueNotifier<PanelArrangement>(
    PanelArrangement.pointer,
  );
  tearDownAll(arrangementOf.dispose);

  Future<void> pumpShell(
    WidgetTester tester, {
    required PanelArrangement arrangement,
    bool secondPage = false,
  }) async {
    arrangementOf.value = arrangement;
    shell = PanelShellController(
      pages: [
        PanelPage(
          id: 'emoji',
          tab: const PanelTab(icon: ChromeIconId.emoji, labelKey: 'emoji'),
          capabilities: EmojiPagePolicy.pageCapabilities,
          builder: (context, host) => EmojiPage(
            host: host,
            source: source,
            searchSource: search,
            preferences: preferences,
            entryOf: fixtures.entryOf,
            assets: assets,
          ),
        ),
        if (secondPage) FakePanelPage('stickers').page,
      ],
      preferences: preferences,
    );
    await tester.pumpWidget(
      PanelShellTestScope(
        child: Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (context) => ValueListenableBuilder(
                valueListenable: arrangementOf,
                builder: (context, arrangement, _) => PanelShell(
                  controller: shell,
                  announcer: FakePanelAnnouncer(),
                  arrangement: arrangement,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder strip() => find.byType(EmojiCategoryStrip);
  Finder grid() => find.byType(PanelCatalogViewport);

  group('under the pointer arrangement', () {
    testWidgets('the strip is the last thing in the page, above nothing', (
      tester,
    ) async {
      await pumpShell(tester, arrangement: PanelArrangement.pointer);

      final page = tester.getRect(find.byType(EmojiPage));
      expect(tester.getBottomLeft(strip()).dy, page.bottom);
      expect(tester.getBottomLeft(grid()).dy, tester.getTopLeft(strip()).dy);
      expect(tester.getTopLeft(grid()).dy, page.top);
    });

    testWidgets('the strip is a 1 px line over 36 px of icons', (tester) async {
      await pumpShell(tester, arrangement: PanelArrangement.pointer);

      expect(
        tester.getSize(strip()).height,
        EmojiCategoryStrip.separatorExtent + EmojiCategoryStrip.height,
      );
      expect(EmojiCategoryStrip.separatorExtent, 1);
      expect(EmojiCategoryStrip.height, 36);
    });

    testWidgets('the page tells the shell how tall the strip is, and the '
        'backspace sits right above it', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpShell(tester, arrangement: PanelArrangement.pointer);

      expect(shell.bottomExtent.value, tester.getSize(strip()).height);
      final backspace = tester.getRect(find.bySemanticsLabel('Delete'));
      expect(
        backspace.bottom,
        lessThanOrEqualTo(tester.getTopLeft(strip()).dy),
      );
      semantics.dispose();
    });

    testWidgets('the extent goes when the arrangement does', (tester) async {
      await pumpShell(tester, arrangement: PanelArrangement.pointer);
      expect(shell.bottomExtent.value, greaterThan(0));

      arrangementOf.value = PanelArrangement.touch;
      await tester.pumpAndSettle();

      expect(shell.bottomExtent.value, 0);
      expect(
        tester.getTopLeft(strip()).dy,
        tester.getTopLeft(find.byType(EmojiPage)).dy,
        reason: 'the strip moved to the top',
      );
    });

    testWidgets('results take the strip away and the bar comes down', (
      tester,
    ) async {
      await pumpShell(tester, arrangement: PanelArrangement.pointer);

      shell
        ..openSearch()
        ..setQuery('cat');
      await tester.pump(DebouncedSearch.defaultDebounce);
      await tester.pumpAndSettle();

      expect(strip(), findsNothing);
      expect(shell.bottomExtent.value, 0);
    });

    testWidgets('an empty search keeps the whole catalogue and the strip', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpShell(tester, arrangement: PanelArrangement.pointer);

      shell.openSearch();
      await tester.pumpAndSettle();

      expect(strip(), findsOneWidget);
      expect(find.bySemanticsLabel('Animals & nature'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('one press of the clear control brings the grid back', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpShell(tester, arrangement: PanelArrangement.pointer);
      shell.openSearch();
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), 'cat');
      await tester.pump(DebouncedSearch.defaultDebounce);
      await tester.pumpAndSettle();
      expect(strip(), findsNothing, reason: 'the results are showing');

      await tester.tap(find.bySemanticsLabel('Cancel'));
      await tester.pumpAndSettle();

      expect(shell.search.value.query, '');
      expect(strip(), findsOneWidget);
      expect(find.bySemanticsLabel('Animals & nature'), findsOneWidget);
      expect(find.bySemanticsLabel('Recently used'), findsOneWidget);

      // On an empty field the same control closes search.
      await tester.tap(find.bySemanticsLabel('Cancel'));
      await tester.pumpAndSettle();
      expect(shell.search.value.isOpen, isFalse);
      semantics.dispose();
    });

    testWidgets('two pages put the tabs above the search field and the '
        'strip below the grid', (tester) async {
      await pumpShell(
        tester,
        arrangement: PanelArrangement.pointer,
        secondPage: true,
      );

      expect(find.text('Emoji'), findsOneWidget);
      expect(
        tester.getBottomLeft(find.text('Emoji')).dy,
        lessThan(tester.getTopLeft(find.byType(EditableText)).dy),
      );
      expect(
        tester.getBottomLeft(strip()).dy,
        tester.getBottomLeft(find.byType(EmojiPage)).dy,
      );
    });
  });

  group('under the touch arrangement', () {
    testWidgets('the strip stays above the grid and the shell hears no '
        'extent', (tester) async {
      await pumpShell(tester, arrangement: PanelArrangement.touch);

      expect(
        tester.getTopLeft(strip()).dy,
        tester.getTopLeft(find.byType(EmojiPage)).dy,
      );
      expect(tester.getBottomLeft(strip()).dy, tester.getTopLeft(grid()).dy);
      expect(shell.bottomExtent.value, 0);
    });

    testWidgets('an empty search still narrows the page to the recents, so '
        'the strip has nothing to navigate', (tester) async {
      await pumpShell(tester, arrangement: PanelArrangement.touch);

      shell.openSearch();
      await tester.pumpAndSettle();

      expect(tester.getSize(strip()).height, 0);
    });
  });
}
