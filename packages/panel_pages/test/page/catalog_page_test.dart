/// The page scaffold as a whole: what a user and the shell see of it.
///
/// **Seam:** [CatalogPage] mounted under the chrome scopes with fake sources, a
/// fake page host and a fake bake port, observed through the picks and reports
/// the host received, the sources' state, the controller's offset and the
/// policy callbacks. Geometry is the viewport's, set here by one section
/// layout: 4 columns of 80 x 40 cells under a 24 px header in a 320 x 480
/// viewport, so the first cell's centre is (40, 44).
library;

import 'dart:async';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_pages/testing.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

const _faces = CollectionId.set('faces');
const _animals = CollectionId.set('animals');

String _glyph(int i) => String.fromCharCode(0x1F600 + i);

CollectionItem _item(int i) =>
    CollectionItem.bare(ContentKey.unicode(_glyph(i)));

FakePages _pages(List<int> sizes) {
  var next = 0;
  return FakePages([
    for (final size in sizes) [for (var i = 0; i < size; i++) _item(next++)],
  ]);
}

FakeCollectionSource _source({
  List<int> faces = const [8],
  List<int> animals = const [4],
}) => FakeCollectionSource([
  FakeCollectionSpec(
    _faces,
    metadata: const CollectionMetadata(title: 'Faces'),
    pages: _pages(faces),
  ),
  FakeCollectionSpec(
    _animals,
    metadata: const CollectionMetadata(title: 'Animals'),
    pages: _pages(animals),
  ),
]);

const _layout = SectionLayout.grid(
  spanCount: 4,
  cellExtent: 40,
  headerExtent: 24,
);

class _Policy extends CatalogPagePolicy {
  _Policy({this.longPress = false, this.strip = false});

  final bool longPress;
  final bool strip;
  final List<String> sectionActions = [];
  final List<String> sessionLog = [];
  CatalogStripHandle? stripHandle;

  @override
  double get stripExtent => strip ? 40 : 0;

  @override
  SectionLayout? layoutOf(Collection collection) => _layout;

  @override
  CatalogSectionAction? actionOf(Collection collection, PanelStrings strings) =>
      const CatalogSectionAction(id: 'more', label: 'More');

  @override
  bool hasLongPress(CatalogLeafHit hit, Collection collection) => longPress;

  @override
  CatalogLongPressSession? beginLongPress(
    BuildContext context,
    CatalogLeafHit hit,
    Collection collection,
    LongPressStartDetails details,
  ) {
    sessionLog.add('begin ${hit.sectionId}/${hit.index}');
    return _Session(sessionLog);
  }

  @override
  void onSectionAction(
    Collection collection,
    String actionId,
    PanelPageHost host,
  ) => sectionActions.add('${collection.id}/$actionId');

  @override
  Widget? buildStrip(BuildContext context, CatalogStripHandle handle) {
    if (!strip) return null;
    stripHandle = handle;
    return const SizedBox(height: 40, width: 320, key: ValueKey('strip'));
  }
}

class _Session implements CatalogLongPressSession {
  _Session(this.log);

  final List<String> log;

  @override
  void update(LongPressMoveUpdateDetails details) => log.add('update');

  @override
  void end(LongPressEndDetails details) => log.add('end');

  @override
  void cancel() => log.add('cancel');
}

void main() {
  late FakeCollectionSource source;
  late FakePanelPageHost host;
  late FakeBakeActivityPort bake;
  late AssetCacheScope assets;
  late _Policy policy;

  setUp(() {
    source = _source();
    host = FakePanelPageHost();
    bake = FakeBakeActivityPort();
    assets = PageAssets.createScope();
    policy = _Policy();
    addTearDown(() {
      source.dispose();
      host.dispose();
      assets.dispose();
    });
  });

  Widget page({
    CollectionSource? withSource,
    SearchSource? search,
    BakeActivityPort? port,
    CatalogPagePolicy? withPolicy,
  }) => PanelShellTestScope(
    child: Center(
      child: SizedBox(
        width: 320,
        height: 480,
        child: CatalogPage(
          host: host,
          source: withSource ?? source,
          searchSource: search,
          policy: withPolicy ?? policy,
          assets: assets,
          bake: port ?? bake,
        ),
      ),
    ),
  );

  Future<void> pumpPage(
    WidgetTester tester, {
    CollectionSource? withSource,
    SearchSource? search,
    CatalogPagePolicy? withPolicy,
  }) async {
    await tester.pumpWidget(
      page(withSource: withSource, search: search, withPolicy: withPolicy),
    );
    await tester.pumpAndSettle();
  }

  Offset origin(WidgetTester tester) =>
      tester.getTopLeft(find.byType(PanelCatalogViewport));

  Future<void> tapCell(
    WidgetTester tester, {
    int row = 0,
    int column = 0,
  }) async {
    await tester.tapAt(
      origin(tester) + Offset(40.0 + 80 * column, 44.0 + 40 * row),
    );
    await tester.pump();
  }

  PanelCatalogController catalog() =>
      host.controllers.peek<CatalogPageController>('page')!.catalog;

  group('loading', () {
    testWidgets('loads the sections that come near, from the source', (
      tester,
    ) async {
      await pumpPage(tester);

      expect(
        source.collections.value.map((collection) => collection.contents),
        everyElement(isA<CollectionContents$Loaded>()),
      );
    });

    testWidgets('pages a section whose end is near', (tester) async {
      source.dispose();
      source = _source(faces: [4, 4, 4], animals: [4]);
      await pumpPage(tester);

      final faces = source.collections.value.first.contents;
      expect(faces, isA<CollectionContents$Loaded>());
      expect((faces as CollectionContents$Loaded).items, hasLength(12));
    });
  });

  group('picking', () {
    testWidgets('a tap on a cell picks its content from the collection', (
      tester,
    ) async {
      await pumpPage(tester);

      await tapCell(tester, column: 1);

      expect(host.picks, [
        (
          key: ContentKey.unicode(_glyph(1)),
          kind: SemanticKind.unicodeEmoji,
          source: PickSource.collection,
        ),
      ]);
    });

    testWidgets('a tap on a skeleton picks nothing', (tester) async {
      source.pause();
      await tester.pumpWidget(page());
      await tester.pump();

      await tapCell(tester);

      expect(host.picks, isEmpty);
    });
  });

  group('swapping the data source at runtime', () {
    testWidgets('shows and picks from the new source', (tester) async {
      await pumpPage(tester);
      final next = FakeCollectionSource([
        const FakeCollectionSpec(
          _animals,
          pages: FakePages([
            [CollectionItem.bare(ContentKey.unicode('🐶'))],
          ]),
        ),
      ]);
      addTearDown(next.dispose);

      await pumpPage(tester, withSource: next);
      await tapCell(tester);

      expect(host.picks.single.key, const ContentKey.unicode('🐶'));
    });
  });

  group('search', () {
    late FakeSearchSource search;

    setUp(() {
      search = FakeSearchSource({
        'cat': const FakePages([
          [CollectionItem.bare(ContentKey.unicode('🐱'))],
        ]),
      });
      addTearDown(search.dispose);
    });

    testWidgets('shows results for the shell query and picks them as search', (
      tester,
    ) async {
      await pumpPage(tester, search: search);

      host.searchState = const PanelSearchState(isOpen: true, query: 'cat');
      await tester.pump(DebouncedSearch.defaultDebounce);
      await tester.pumpAndSettle();
      await tapCell(tester);

      expect(host.picks.single.key, const ContentKey.unicode('🐱'));
      expect(host.picks.single.source, PickSource.search);
      expect(host.searchResultCounts, [1]);
    });

    testWidgets('puts the browse offset back when the results go', (
      tester,
    ) async {
      source.dispose();
      source = _source(faces: [80], animals: [40]);
      await pumpPage(tester, search: search);
      catalog().jumpTo(300);
      await tester.pump();

      host.searchState = const PanelSearchState(isOpen: true, query: 'cat');
      await tester.pump(DebouncedSearch.defaultDebounce);
      await tester.pumpAndSettle();
      expect(catalog().offset, 0);

      host.searchState = PanelSearchState.closed;
      await tester.pumpAndSettle();

      expect(catalog().offset, 300);
    });
  });

  group('reporting to the shell', () {
    testWidgets('a drag is reported with its deltas, then rest', (
      tester,
    ) async {
      source.dispose();
      source = _source(faces: [80], animals: [40]);
      await pumpPage(tester);

      await tester.drag(
        find.byType(PanelCatalogViewport),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();

      expect(host.scrollActivity.whereType<PageScrollDrag>(), isNotEmpty);
      expect(host.scrollActivity.last, isA<PageScrollIdle>());
    });

    testWidgets('taking hold of the catalogue releases the search focus', (
      tester,
    ) async {
      source.dispose();
      source = _source(faces: [80], animals: [40]);
      await pumpPage(tester);
      expect(host.searchFocusReleases, 0);

      await tester.drag(
        find.byType(PanelCatalogViewport),
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();

      expect(host.searchFocusReleases, 1);
    });

    testWidgets('a tap does not release the search focus', (tester) async {
      await pumpPage(tester);

      await tapCell(tester);

      expect(host.searchFocusReleases, 0);
    });

    testWidgets('selecting the tab again scrolls back to the start', (
      tester,
    ) async {
      source.dispose();
      source = _source(faces: [80], animals: [40]);
      await pumpPage(tester);
      catalog().jumpTo(400);
      await tester.pump();

      host.reselect();
      await tester.pumpAndSettle();

      expect(catalog().offset, 0);
      expect(host.scrollActivity, contains(isA<PageScrollJump>()));
    });
  });

  group('the bake hand-off', () {
    testWidgets('hears of the visible band once the catalogue rests', (
      tester,
    ) async {
      await pumpPage(tester);

      expect(bake.prioritised, isNotEmpty);
      expect(bake.prioritised.last.first, _glyph(0));
    });

    testWidgets('hears of motion while the catalogue moves', (tester) async {
      source.dispose();
      source = _source(faces: [80], animals: [40]);
      await pumpPage(tester);

      final gesture = await tester.startGesture(
        origin(tester) + const Offset(100, 300),
      );
      await gesture.moveBy(const Offset(0, -60));
      await tester.pump();
      expect(bake.isScrolling, isTrue);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(bake.isScrolling, isFalse);
    });

    testWidgets('a baker set later is told what is on screen', (tester) async {
      await pumpPage(tester);
      final next = FakeBakeActivityPort();

      await tester.pumpWidget(page(port: next));

      expect(next.prioritised, isNotEmpty);
    });

    testWidgets('tells the baker the surface rests when the page goes', (
      tester,
    ) async {
      source.dispose();
      source = _source(faces: [80], animals: [40]);
      await pumpPage(tester);
      final gesture = await tester.startGesture(
        origin(tester) + const Offset(100, 300),
      );
      await gesture.moveBy(const Offset(0, -60));
      await tester.pump();
      expect(bake.isScrolling, isTrue);

      await tester.pumpWidget(const SizedBox());

      expect(bake.isScrolling, isFalse);
      await gesture.up();
    });
  });

  group('long press', () {
    testWidgets('reaches the session the policy begins', (tester) async {
      policy = _Policy(longPress: true);
      await pumpPage(tester);

      final gesture = await tester.startGesture(
        origin(tester) + const Offset(40, 44),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(5, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(policy.sessionLog, [
        'begin CollectionId.set(faces)/0',
        'update',
        'end',
      ]);
      expect(host.picks, isEmpty);
    });

    testWidgets('is cancelled when the page leaves mid-press', (tester) async {
      policy = _Policy(longPress: true);
      await pumpPage(tester);
      final gesture = await tester.startGesture(
        origin(tester) + const Offset(40, 44),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));

      await tester.pumpWidget(const SizedBox());

      expect(policy.sessionLog.last, 'cancel');
      await gesture.up();
    });

    testWidgets('is cancelled when the page stops being the selected one', (
      tester,
    ) async {
      policy = _Policy(longPress: true);
      await pumpPage(tester);
      final gesture = await tester.startGesture(
        origin(tester) + const Offset(40, 44),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));

      host.active = false;

      expect(policy.sessionLog.last, 'cancel');
      await gesture.up();
    });

    testWidgets('a cell without one stays a plain tap', (tester) async {
      await pumpPage(tester);

      await tapCell(tester);

      expect(policy.sessionLog, isEmpty);
      expect(host.picks, hasLength(1));
    });
  });

  group('the top strip', () {
    testWidgets('is built by the policy above the catalogue', (tester) async {
      policy = _Policy(strip: true);
      await pumpPage(tester);

      expect(find.byKey(const ValueKey('strip')), findsOneWidget);
      expect(policy.stripHandle!.entries.value, hasLength(2));
    });

    testWidgets('jumps the catalogue to a section', (tester) async {
      source.dispose();
      source = _source(faces: [80], animals: [40]);
      policy = _Policy(strip: true);
      await pumpPage(tester);

      unawaited(policy.stripHandle!.jumpToSection('CollectionId.set(animals)'));
      await tester.pumpAndSettle();

      expect(catalog().offset, greaterThan(0));
    });

    testWidgets('is not built while search results show', (tester) async {
      final search = FakeSearchSource({});
      addTearDown(search.dispose);
      policy = _Policy(strip: true);
      await pumpPage(tester, search: search);

      host.searchState = const PanelSearchState(isOpen: true, query: 'cat');
      await tester.pump(DebouncedSearch.defaultDebounce);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('strip')), findsNothing);
    });
  });

  group('section actions', () {
    testWidgets('a tap on the header action reaches the policy', (
      tester,
    ) async {
      await pumpPage(tester);

      // "More" is 60 px of Ahem text, inset 8 px at both ends of a 320 px row.
      await tester.tapAt(origin(tester) + const Offset(290, 12));
      await tester.pump();

      expect(policy.sectionActions, ['CollectionId.set(faces)/more']);
    });
  });

  group('roving focus keys', () {
    Future<void> focusGrid(WidgetTester tester) async {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
    }

    testWidgets('Tab enters the grid on the first cell in view', (
      tester,
    ) async {
      await pumpPage(tester);

      await focusGrid(tester);

      expect(catalog().focusedLeaf?.index, 0);
    });

    testWidgets('the arrows move focus by cell and Enter picks', (
      tester,
    ) async {
      await pumpPage(tester);
      await focusGrid(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(catalog().focusedLeaf?.index, 5);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(host.picks.single.key, ContentKey.unicode(_glyph(5)));
    });

    testWidgets('Home and End go to the ends of the catalogue', (tester) async {
      await pumpPage(tester);
      await focusGrid(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pump();
      expect(catalog().focusedLeaf?.sectionId, 'CollectionId.set(animals)');

      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pump();
      expect(catalog().focusedLeaf?.sectionId, 'CollectionId.set(faces)');
      expect(catalog().focusedLeaf?.index, 0);
    });

    testWidgets('Space activates like Enter', (tester) async {
      await pumpPage(tester);
      await focusGrid(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();

      expect(host.picks, hasLength(1));
    });

    testWidgets('losing focus ends roving focus', (tester) async {
      await pumpPage(tester);
      await focusGrid(tester);

      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      expect(catalog().focusedLeaf, isNull);
    });
  });

  group('across a presentation switch', () {
    testWidgets('a remounted page finds its scroll position', (tester) async {
      source.dispose();
      source = _source(faces: [80], animals: [40]);
      await pumpPage(tester);
      catalog().jumpTo(240);
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      expect(catalog().offset, 240);
    });
  });
}
