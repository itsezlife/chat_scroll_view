/// The emoji page as the first page of a real [PanelShell].
///
/// **Seam:** the shell controller's public surface (events, search state,
/// presence) with a `PanelShell` mounted over an [EmojiPage], and an atlas host
/// built by the page's factory on fake bake parts, observed through what the
/// host of the shell would receive and the frames the bake asks for.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
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
  late FakeBakeFrameSource frames;
  late PanelShellController shell;
  late List<PanelEvent> events;
  var deferChrome = false;

  setUp(() {
    deferChrome = false;
    preferences = FakePreferenceStore();
    source = fixtures.source(recents: ['😀'], count: 40);
    search = FakeSearchSource({
      'cat': FakePages([
        [fixtures.item('🐱')],
      ]),
    });
    assets = PageAssets.createScope();
    frames = FakeBakeFrameSource();
    events = [];
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
            deferChrome: deferChrome,
            atlasHostFactory:
                ({
                  required devicePixelRatio,
                  required glyphBoxExtent,
                  required visible,
                  required opening,
                }) => GlyphAtlasHost(
                  frames: frames,
                  devicePixelRatio: devicePixelRatio,
                  glyphBoxExtent: glyphBoxExtent,
                  visible: visible,
                  opening: opening,
                  rasteriser: FakeGlyphRasteriser(),
                  newStore: FakeGlyphPageStore.new,
                ),
          ),
        ),
      ],
      preferences: preferences,
    );
    shell.events.listen(events.add);
    addTearDown(() {
      shell.dispose();
      source.dispose();
      search.dispose();
      assets.dispose();
    });
  });

  Future<void> pumpShell(WidgetTester tester, {bool defer = false}) async {
    await tester.pumpWidget(
      PanelShellTestScope(
        child: Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (context) => PanelShell(
                controller: shell,
                announcer: FakePanelAnnouncer(),
                deferSearchField: defer,
              ),
            ),
          ],
        ),
      ),
    );
  }

  test('is the shell\'s page with search, a strip and backspace', () {
    final page = shell.selectedPage;
    expect(page.capabilities.search, isTrue);
    expect(page.capabilities.topStrip, isTrue);
    expect(page.capabilities.actions.map((a) => a.id), ['backspace']);
  });

  testWidgets('a tap is a pick the host hears, and the host records it', (
    tester,
  ) async {
    await pumpShell(tester);
    await tester.pumpAndSettle();

    await tester.tapAt(
      tester.getTopLeft(find.byType(PanelCatalogViewport)) +
          const Offset(27, 27 + 23),
    );
    await tester.pump();

    expect(events.whereType<ContentPicked>().single.key, fixtures.key('😀'));
    expect(events.whereType<ContentPicked>().single.source, PickSource.recents);
  });

  testWidgets('the clear action of the recents reaches the host', (
    tester,
  ) async {
    await pumpShell(tester);
    await tester.pumpAndSettle();

    final viewport = tester.getTopRight(find.byType(PanelCatalogViewport));
    await tester.tapAt(viewport + const Offset(-30, 13));
    await tester.pump();

    expect(
      events.whereType<ClearRecentsRequested>().single.kind,
      SemanticKind.unicodeEmoji,
    );
  });

  testWidgets('dragging the catalogue releases the search focus and keeps '
      'search open', (tester) async {
    await pumpShell(tester);
    await tester.pumpAndSettle();
    shell.openSearch();
    await tester.pumpAndSettle();
    expect(shell.search.value.wantsFocus, isTrue);

    await tester.drag(find.byType(PanelCatalogViewport), const Offset(0, -80));
    await tester.pumpAndSettle();

    expect(shell.search.value.isOpen, isTrue);
    expect(shell.search.value.wantsFocus, isFalse);
  });

  testWidgets('a query is searched through the search source and the results '
      'replace the catalogue', (tester) async {
    final counts = <int>[];
    shell.searchResultCounts.listen(counts.add);
    await pumpShell(tester);
    await tester.pumpAndSettle();

    shell
      ..openSearch()
      ..setQuery('zzz');
    await tester.pump(DebouncedSearch.defaultDebounce);
    await tester.pumpAndSettle();

    expect(find.byType(EmojiCategoryStrip), findsNothing);
    expect(counts, [0], reason: 'the search found nothing, and said so');
  });

  testWidgets('the search field keeps its focus as results come and go', (
    tester,
  ) async {
    await pumpShell(tester);
    await tester.pumpAndSettle();
    shell.openSearch();
    await tester.pumpAndSettle();
    final field = find.byType(EditableText);
    expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);

    for (final query in ['cat', 'zzzz', 'cat']) {
      await tester.enterText(field, query);
      await tester.pump(DebouncedSearch.defaultDebounce);
      await tester.pumpAndSettle();

      expect(
        tester.widget<EditableText>(field).focusNode.hasFocus,
        isTrue,
        reason: 'after "$query"',
      );
      expect(shell.search.value.wantsFocus, isTrue, reason: '"$query"');
    }
  });

  group('the panel presence', () {
    testWidgets('pauses the bake while the panel is hidden or opening', (
      tester,
    ) async {
      await pumpShell(tester);
      await tester.pumpAndSettle();
      expect(frames.hasPendingRequest, isFalse, reason: 'hidden');

      shell.updatePresence(visible: true, opening: true);
      await tester.pump();
      expect(frames.hasPendingRequest, isFalse, reason: 'opening');

      shell.updatePresence(visible: true, opening: false);
      await tester.pump();
      expect(frames.hasPendingRequest, isTrue, reason: 'at rest');
    });
  });

  group('a cold mount', () {
    testWidgets('spreads the grid, the search field and the strip over three '
        'frames', (tester) async {
      deferChrome = true;
      await pumpShell(tester, defer: true);

      expect(find.byType(PanelCatalogViewport), findsOneWidget);
      expect(find.byType(EditableText), findsNothing);
      expect(find.byType(EmojiCategoryStrip), findsNothing);

      await tester.pump();
      expect(find.byType(EditableText), findsOneWidget);
      expect(find.byType(EmojiCategoryStrip), findsNothing);

      await tester.pump();
      expect(find.byType(EmojiCategoryStrip), findsOneWidget);
    });

    testWidgets('mounts everything at once when the panel replaces the '
        'keyboard', (tester) async {
      await pumpShell(tester);

      expect(find.byType(EditableText), findsOneWidget);
      expect(find.byType(EmojiCategoryStrip), findsOneWidget);
    });
  });
}
