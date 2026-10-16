/// A loaded section whose items change (a glyph found missing is dropped)
/// shows its new items.
///
/// **Seam:** a [CatalogPage] in a [PanelShell] over a source whose loaded
/// collection is replaced, observed through what a tap on a cell picks.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen/listen.dart' as listen;
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

const _faces = CollectionId.set('faces');

class _Policy extends CatalogPagePolicy {
  const _Policy();

  @override
  SectionLayout? layoutOf(
    Collection collection, {
    PanelArrangement arrangement = PanelArrangement.touch,
  }) =>
      const SectionLayout.grid(spanCount: 4, cellExtent: 40, headerExtent: 24);
}

// A source whose one collection is loaded from the start and replaced on
// demand.
final class _Source implements CollectionSource {
  _Source(List<String> glyphs)
    : _collections = listen.ValueNotifier([_of(glyphs)]);

  final listen.ValueNotifier<List<Collection>> _collections;

  static Collection _of(List<String> glyphs) => Collection(
    id: _faces,
    metadata: const CollectionMetadata(title: 'Faces'),
    contents: CollectionContents.loaded([
      for (final glyph in glyphs)
        CollectionItem.bare(ContentKey.unicode(glyph)),
    ]),
  );

  void show(List<String> glyphs) => _collections.value = [_of(glyphs)];

  @override
  listen.ValueListenable<List<Collection>> get collections => _collections;

  @override
  Future<void> load(CollectionId id) async {}

  @override
  Future<void> loadMore(CollectionId id) async {}

  @override
  void dispose() => _collections.dispose();
}

void main() {
  late _Source source;
  late AssetCacheScope assets;
  late PanelShellController shell;
  late List<ContentPicked> picks;

  setUp(() {
    source = _Source(['🍏', '🍐', '🍊', '🍋', '🍌', '🍉']);
    assets = PageAssets.createScope();
    picks = [];
    shell = PanelShellController(
      pages: [
        PanelPage(
          id: 'faces',
          tab: const PanelTab(icon: ChromeIconId.emoji, labelKey: 'emoji'),
          builder: (context, host) => CatalogPage(
            host: host,
            source: source,
            policy: const _Policy(),
            assets: assets,
          ),
        ),
      ],
      preferences: FakePreferenceStore(),
    );
    shell.events.listen((event) {
      if (event case final ContentPicked pick) picks.add(pick);
    });
    addTearDown(() {
      shell.dispose();
      source.dispose();
      assets.dispose();
    });
  });

  Future<ContentKey> pickCell(WidgetTester tester, int column) async {
    final viewport = tester.getRect(find.byType(PanelCatalogViewport));
    // Four columns share the width; the first row is under a 24 px header.
    await tester.tapAt(
      viewport.topLeft + Offset(viewport.width / 4 * (column + 0.5), 44),
    );
    await tester.pump();
    return picks.last.key;
  }

  testWidgets('an item dropped from a loaded section leaves the grid', (
    tester,
  ) async {
    await tester.pumpWidget(
      PanelShellTestScope(
        child: PanelShell(controller: shell, announcer: FakePanelAnnouncer()),
      ),
    );
    await tester.pumpAndSettle();
    expect(await pickCell(tester, 1), const ContentKey.unicode('🍐'));

    source.show(['🍏', '🍊', '🍋', '🍌', '🍉']);
    await tester.pumpAndSettle();

    expect(await pickCell(tester, 1), const ContentKey.unicode('🍊'));
  });
}
