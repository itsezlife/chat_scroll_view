/// A [CatalogPage] as a real page of a [PanelShell].
///
/// **Seam:** the shell controller's public surface (its events, search state,
/// scroll activity and page registry) with a `PanelShell` mounted, observed
/// through what the host of the shell would receive.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

const _faces = CollectionId.set('faces');

class _Policy extends CatalogPagePolicy {
  const _Policy();

  @override
  PageCapabilities get capabilities => const PageCapabilities(search: true);

  @override
  SectionLayout? layoutOf(
    Collection collection, {
    PanelArrangement arrangement = PanelArrangement.touch,
  }) =>
      const SectionLayout.grid(spanCount: 4, cellExtent: 40, headerExtent: 24);
}

void main() {
  late FakePreferenceStore preferences;
  late FakeCollectionSource source;
  late FakeSearchSource search;
  late AssetCacheScope assets;
  late PanelShellController shell;
  late List<PanelEvent> events;
  late List<PageScrollActivity> activity;
  bool? keepsScrollOnReopen;

  setUp(() {
    keepsScrollOnReopen = null;
    preferences = FakePreferenceStore();
    source = FakeCollectionSource([
      FakeCollectionSpec(
        _faces,
        metadata: const CollectionMetadata(title: 'Faces'),
        pages: FakePages([
          [
            for (var i = 0; i < 120; i++)
              CollectionItem.bare(
                ContentKey.unicode(String.fromCharCode(0x1F600 + i)),
              ),
          ],
        ]),
      ),
    ]);
    search = FakeSearchSource({
      'cat': const FakePages([
        [CollectionItem.bare(ContentKey.unicode('🐱'))],
      ]),
    });
    assets = PageAssets.createScope();
    events = [];
    activity = [];
    shell = PanelShellController(
      pages: [
        PanelPage(
          id: 'emoji',
          tab: const PanelTab(icon: ChromeIconId.emoji, labelKey: 'emoji'),
          capabilities: const _Policy().capabilities,
          builder: (context, host) => CatalogPage(
            host: host,
            source: source,
            searchSource: search,
            policy: const _Policy(),
            assets: assets,
            keepsScrollOnReopen: keepsScrollOnReopen,
          ),
        ),
        PanelPage(
          id: 'stickers',
          tab: const PanelTab(icon: ChromeIconId.emoji, labelKey: 'stickers'),
          builder: (context, host) => const SizedBox.expand(),
        ),
      ],
      preferences: preferences,
    );
    shell.events.listen(events.add);
    shell.scrollActivity.listen(activity.add);
    addTearDown(() {
      shell.dispose();
      source.dispose();
      search.dispose();
      assets.dispose();
    });
  });

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.pumpWidget(
      PanelShellTestScope(
        child: PanelShell(controller: shell, announcer: FakePanelAnnouncer()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapFirstCell(WidgetTester tester) async {
    await tester.tapAt(
      tester.getTopLeft(find.byType(PanelCatalogViewport)) +
          const Offset(20, 44),
    );
    await tester.pump();
  }

  testWidgets('a tap reaches the shell handler as a pick from the collection', (
    tester,
  ) async {
    await pumpShell(tester);

    await tapFirstCell(tester);

    expect(
      events.whereType<ContentPicked>().single,
      const ContentPicked(
        key: ContentKey.unicode('😀'),
        kind: SemanticKind.unicodeEmoji,
      ),
    );
  });

  testWidgets('the shell query becomes search results, picked as search', (
    tester,
  ) async {
    await pumpShell(tester);

    shell
      ..openSearch()
      ..setQuery('cat');
    await tester.pump(DebouncedSearch.defaultDebounce);
    await tester.pumpAndSettle();
    await tapFirstCell(tester);

    expect(
      events.whereType<ContentPicked>().single,
      const ContentPicked(
        key: ContentKey.unicode('🐱'),
        kind: SemanticKind.unicodeEmoji,
        source: PickSource.search,
      ),
    );
  });

  testWidgets('scrolling the catalogue reaches the shell as scroll activity', (
    tester,
  ) async {
    await pumpShell(tester);

    await tester.drag(find.byType(PanelCatalogViewport), const Offset(0, -150));
    await tester.pumpAndSettle();

    expect(activity.whereType<PageScrollDrag>(), isNotEmpty);
    expect(activity.last, isA<PageScrollIdle>());
  });

  testWidgets('a page swiped away and back finds its scroll position', (
    tester,
  ) async {
    await pumpShell(tester);
    await tester.drag(find.byType(PanelCatalogViewport), const Offset(0, -150));
    await tester.pumpAndSettle();
    final offset = shell.controllers
        .peek<CatalogPageController>('emoji')!
        .catalog
        .offset;
    expect(offset, greaterThan(0));

    shell.selectPage('stickers');
    await tester.pumpAndSettle();
    shell.selectPage('emoji');
    await tester.pumpAndSettle();

    expect(
      shell.controllers.peek<CatalogPageController>('emoji')!.catalog.offset,
      offset,
    );
  });

  group('reopening the panel', () {
    // Scrolls the shown panel, hides it as a presentation does (presence
    // first, then the shell goes), shows it again, and returns the offset
    // the catalogue reopens at.
    Future<double> scrollCloseReopen(
      WidgetTester tester, {
      PanelArrangement arrangement = PanelArrangement.touch,
    }) async {
      Future<void> pumpShown() async {
        await tester.pumpWidget(
          PanelShellTestScope(
            child: PanelShell(
              controller: shell,
              arrangement: arrangement,
              announcer: FakePanelAnnouncer(),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      shell.updatePresence(visible: true, opening: false);
      await pumpShown();
      shell.controllers
          .peek<CatalogPageController>('emoji')!
          .catalog
          .jumpTo(300);
      await tester.pumpAndSettle();

      shell.updatePresence(visible: false, opening: false);
      await tester.pumpWidget(const SizedBox());
      shell.updatePresence(visible: true, opening: true);
      await pumpShown();
      shell.updatePresence(visible: true, opening: false);
      await tester.pumpAndSettle();
      return shell.controllers
          .peek<CatalogPageController>('emoji')!
          .catalog
          .offset;
    }

    testWidgets('under touch, the catalogue starts at the top again', (
      tester,
    ) async {
      expect(await scrollCloseReopen(tester), 0);
    });

    testWidgets('under the pointer, it is where it was left', (tester) async {
      expect(
        await scrollCloseReopen(tester, arrangement: PanelArrangement.pointer),
        300,
      );
    });

    testWidgets('a page set to keep its place finds it under touch too', (
      tester,
    ) async {
      keepsScrollOnReopen = true;

      expect(await scrollCloseReopen(tester), 300);
    });
  });
}
