/// The emoji page as a user and the shell see it.
///
/// **Seam:** [EmojiPage] mounted under the chrome scopes with a fake source and
/// search source, a fake page host and a real asset scope, observed through the
/// picks and requests the host received, the preferences, the controller and
/// what is on screen. Geometry: 8 columns of 43.75 x 45 cells in a 360 x 480
/// page with the 36 px strip above, so the first cell's centre is
/// (5 + 21.875, 36 + 27 + 22.5) from the page's top left.
library;

import 'dart:ui' show Tristate;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/glyph_atlas.dart';
import 'package:catalog_assets/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen/listen.dart' as listen;
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/panel_catalog_diagnostics.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_pages/testing.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

import 'emoji_fixtures.dart' as fixtures;

void main() {
  late FakeCollectionSource source;
  late FakeSearchSource search;
  late FakePreferenceStore preferences;
  late FakePanelPageHost host;
  late AssetCacheScope assets;
  late ValueNotifier<CollectionSource?> swapped;
  late ValueNotifier<double> density;

  setUp(() {
    source = fixtures.source();
    search = FakeSearchSource({
      'japan': FakePages([
        [fixtures.item('🇯🇵')],
      ]),
    });
    preferences = FakePreferenceStore();
    host = FakePanelPageHost(pageId: 'emoji');
    assets = PageAssets.createScope();
    swapped = ValueNotifier<CollectionSource?>(null);
    density = ValueNotifier<double>(2);
    addTearDown(() {
      source.dispose();
      search.dispose();
      preferences.dispose();
      host.dispose();
      assets.dispose();
      swapped.dispose();
      density.dispose();
    });
  });

  Widget page({
    CollectionSource? withSource,
    bool deferChrome = false,
    GlyphAtlasHostFactory? atlas,
    TextDirection direction = TextDirection.ltr,
  }) => PanelShellTestScope(
    textDirection: direction,
    child: FakeSearchFieldScope(
      child: Overlay(
        initialEntries: [
          OverlayEntry(
            builder: (context) => ListenableBuilder(
              listenable: Listenable.merge([swapped, density]),
              builder: (context, _) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(devicePixelRatio: density.value),
                child: Center(
                  child: SizedBox(
                    width: 360,
                    height: 480,
                    child: EmojiPage(
                      host: host,
                      source: swapped.value ?? withSource ?? source,
                      searchSource: search,
                      preferences: preferences,
                      entryOf: fixtures.entryOf,
                      assets: assets,
                      deferChrome: deferChrome,
                      atlasHostFactory: atlas,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Offset origin(WidgetTester tester) =>
      tester.getTopLeft(find.byType(EmojiPage));

  /// The centre of the cell at [row], [column] of a section whose header
  /// starts [top] px below the strip and the search field's band.
  Offset cell(
    WidgetTester tester, {
    required double top,
    int row = 0,
    int column = 0,
    bool strip = true,
  }) =>
      origin(tester) +
      Offset(
        5 + 43.75 * (column + 0.5),
        (strip ? 36 : 0) + 50 + top + 27 + 45 * row + 22.5,
      );

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
  }

  EmojiPageController controller() =>
      host.controllers.peek<EmojiPageController>('emoji')!;

  List<Collection> collections() => source.collections.value;

  group('loading', () {
    testWidgets('asks every collection to load as soon as it is listed', (
      tester,
    ) async {
      await pumpPage(tester);

      for (final collection in collections()) {
        expect(
          collection.contents,
          isA<CollectionContents$Loaded>(),
          reason: '${collection.id}',
        );
      }
    });

    testWidgets('keeps its catalogue controller where the scaffold looks', (
      tester,
    ) async {
      await pumpPage(tester);

      expect(
        host.controllers.peek<CatalogPageController>('emoji'),
        same(controller()),
      );
    });
  });

  group('picking', () {
    testWidgets('a tap picks the emoji from its collection', (tester) async {
      source = fixtures.source(count: 0);
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      // Smileys: 😀 is the first cell.
      await tester.tapAt(cell(tester, top: 0));
      await tester.pump();

      expect(host.picks, [
        (
          key: fixtures.key('😀'),
          kind: SemanticKind.unicodeEmoji,
          source: PickSource.collection,
        ),
      ]);
    });

    testWidgets('a tap in the recents picks it as a recent', (tester) async {
      source = fixtures.source(recents: ['❤', '😀'], count: 0);
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      await tester.tapAt(cell(tester, top: 0));
      await tester.pump();

      expect(host.picks.single.key, fixtures.key('❤'));
      expect(host.picks.single.source, PickSource.recents);
    });

    testWidgets('a tap on a result picks it as a search pick', (tester) async {
      await pumpPage(tester);

      host.searchState = const PanelSearchState(isOpen: true, query: 'japan');
      await tester.pump(DebouncedSearch.defaultDebounce);
      await tester.pumpAndSettle();
      await tester.tapAt(cell(tester, top: 0, strip: false));
      await tester.pump();

      expect(host.picks.single.key, fixtures.key('🇯🇵'));
      expect(host.picks.single.source, PickSource.search);
    });
  });

  group('sections', () {
    testWidgets('are titled by the panel strings, recents only when there are '
        'some', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpPage(tester);

      // One header and one strip tab each.
      expect(find.semantics.byLabel('Food & Drink'), findsNWidgets(2));
      expect(find.semantics.byLabel('Smileys & People'), findsNWidgets(2));
      expect(find.semantics.byLabel('Recently used'), findsNothing);
      handle.dispose();
    });

    testWidgets('an empty search keeps the whole catalogue on screen', (
      tester,
    ) async {
      source = fixtures.source(recents: ['❤']);
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      final model = controller().catalog;
      final before = model.maxScrollExtent;
      expect(before, greaterThan(0));

      host.searchState = const PanelSearchState(isOpen: true);
      await tester.pumpAndSettle();

      // The strip's 36 px leave with the open search; no section does.
      expect(model.maxScrollExtent, closeTo(before, 40));
    });
  });

  group('the recents', () {
    testWidgets('have no header button: the header is a title', (tester) async {
      final handle = tester.ensureSemantics();
      source = fixtures.source(recents: ['❤'], count: 0);
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      expect(find.semantics.byLabel('Clear recent emoji'), findsNothing);
      await tester.tapAt(origin(tester) + const Offset(330, 36 + 50 + 13));
      await tester.pump();
      expect(host.clearRecentsRequests, isEmpty);
      handle.dispose();
    });

    testWidgets('a long press on a recent asks the host to clear them, and '
        'picks nothing', (tester) async {
      source = fixtures.source(recents: ['❤'], count: 0);
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(cell(tester, top: 0));
      await tester.pump(const Duration(milliseconds: 700));
      await gesture.up();
      await tester.pump();

      expect(host.clearRecentsRequests, [SemanticKind.unicodeEmoji]);
      expect(host.picks, isEmpty);
    });

    testWidgets('a tap on a recent still picks it', (tester) async {
      source = fixtures.source(recents: ['❤'], count: 0);
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      await tester.tapAt(cell(tester, top: 0));
      await tester.pump();

      expect(host.picks.single.key, fixtures.key('❤'));
      expect(host.clearRecentsRequests, isEmpty);
    });
  });

  group('the variant picker', () {
    // count: 0 puts 👍 at the first cell of the people section, which starts
    // after the smileys' one row (27 + 45).
    const peopleTop = 72.0;

    // The centre of option [index] of the open picker: its card sits inside the
    // shadow margin, and the option is one grid cell of 43.75 x 45.
    Offset pickerOptionCenter(WidgetTester tester, int index) {
      final outer = tester.getTopLeft(find.byType(EmojiVariantPicker));
      const cell = Size(43.75, 45);
      final layout = EmojiVariantPickerLayout(
        count: fixtures.thumbsUp.variants.length + 1,
        cell: cell,
      );
      return outer +
          const Offset(
            EmojiVariantPickerLayout.shadowMargin,
            EmojiVariantPickerLayout.shadowMargin,
          ) +
          layout.optionRect(index).center;
    }

    Future<TestGesture> pressThumb(WidgetTester tester) async {
      source = fixtures.source(count: 0);
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(cell(tester, top: peopleTop));
      await tester.pump(const Duration(milliseconds: 700));
      return gesture;
    }

    testWidgets('opens on a long press with the base and every variant of the '
        'entry', (tester) async {
      final gesture = await pressThumb(tester);

      expect(find.byType(EmojiVariantPicker), findsOneWidget);
      final picker = tester.widget<EmojiVariantPicker>(
        find.byType(EmojiVariantPicker),
      );
      expect(picker.options, [
        fixtures.thumbsUp.base,
        for (final variant in fixtures.thumbsUp.variants) variant.key,
      ]);
      expect(picker.selected, 0);
      await gesture.up();
      await tester.pump();
    });

    testWidgets('releasing on an option picks it and remembers it for the '
        'base', (tester) async {
      final gesture = await pressThumb(tester);
      // The fourth option's centre.
      await gesture.moveTo(pickerOptionCenter(tester, 3));
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));

      final chosen = fixtures.thumbsUp.variants[2].key;
      expect(host.picks.single.key, chosen);
      expect(host.picks.single.source, PickSource.collection);
      expect(preferences.preferredVariant(fixtures.thumbsUp.base), chosen);
      expect(find.byType(EmojiVariantPicker), findsNothing);
    });

    testWidgets('choosing the base is a choice too: it is remembered as the '
        'base itself', (tester) async {
      await preferences.setPreferredVariant(
        fixtures.thumbsUp.base,
        fixtures.thumbsUp.variants.first.key,
      );
      final gesture = await pressThumb(tester);

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 300));

      expect(host.picks.single.key, fixtures.thumbsUp.base);
      expect(
        preferences.preferredVariant(fixtures.thumbsUp.base),
        fixtures.thumbsUp.base,
      );
    });

    testWidgets('an emoji without variants has no long press', (tester) async {
      source = fixtures.source(count: 0);
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      // ❤ is the second smiley.
      final gesture = await tester.startGesture(
        cell(tester, top: 0, column: 1),
      );
      await tester.pump(const Duration(milliseconds: 700));
      await gesture.up();
      await tester.pump();

      expect(find.byType(EmojiVariantPicker), findsNothing);
      expect(host.picks.single.key, fixtures.key('❤'));
    });

    testWidgets('is cancelled when the page leaves mid-press', (tester) async {
      final gesture = await pressThumb(tester);
      expect(find.byType(EmojiVariantPicker), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(find.byType(EmojiVariantPicker), findsNothing);
      await gesture.up();
      expect(host.picks, isEmpty);
    });

    testWidgets('opened without a pointer stays until an option is tapped', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      source = fixtures.source(count: 0);
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      tester.semantics.performAction(
        find.semantics.byLabel('👍'),
        SemanticsAction.longPress,
      );
      await tester.pump();
      expect(find.byType(EmojiVariantPicker), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(EmojiVariantPicker), findsOneWidget);

      await tester.tap(find.text('👍\u{1F3FE}'));
      await tester.pumpAndSettle();

      expect(host.picks.single.key, fixtures.thumbsUp.variants[3].key);
      expect(find.byType(EmojiVariantPicker), findsNothing);
      handle.dispose();
    });

    testWidgets('is labelled, with its options', (tester) async {
      final handle = tester.ensureSemantics();
      final gesture = await pressThumb(tester);
      // The picker fades in: a node is in the tree once it shows.
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.bySemanticsLabel('Show variants'), findsOneWidget);
      expect(find.bySemanticsLabel('👍\u{1F3FD}'), findsOneWidget);
      await gesture.up();
      await tester.pump();
      handle.dispose();
    });
  });

  group('swapping the data source at runtime', () {
    testWidgets('shows and picks from the new source without a throw', (
      tester,
    ) async {
      source = fixtures.source(count: 0);
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      final replacement = fixtures.source(recents: ['🇯🇵'], count: 0);
      addTearDown(replacement.dispose);

      swapped.value = replacement;
      await tester.pumpAndSettle();
      await tester.tapAt(cell(tester, top: 0));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(host.picks.single.key, fixtures.key('🇯🇵'));
      for (final collection in replacement.collections.value) {
        expect(collection.contents, isA<CollectionContents$Loaded>());
      }
    });
  });

  group('the glyph atlas', () {
    late FakeBakeFrameSource frames;

    GlyphAtlasHostFactory factory() =>
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
        );

    setUp(() {
      frames = FakeBakeFrameSource();
    });

    GlyphAtlas? atlas() => controller().atlasHost?.atlas.value;

    testWidgets('is planned for what the page shows, once it is loaded', (
      tester,
    ) async {
      source = fixtures.source(recents: ['🔥'], count: 3);
      await tester.pumpWidget(page(atlas: factory()));
      await tester.pumpAndSettle();

      final glyphs = atlas()!.index.glyphs;
      for (final collection in source.collections.value) {
        if (collection.id == CollectionId.recent) continue;
        final contents = collection.contents as CollectionContents$Loaded;
        for (final item in contents.items) {
          expect(glyphs, contains((item.key as ContentKey$Unicode).sequence));
        }
      }
      expect(
        glyphs.last,
        '🔥',
        reason: 'recents the catalogue lacks come last',
      );
    });

    testWidgets('is the glyph source of the scope, and the grid draws no '
        'paragraph where glyphs are baked', (tester) async {
      PanelCatalogDiagnostics.reset();
      await tester.pumpWidget(page(atlas: factory()));
      await tester.pumpAndSettle();

      expect(assets.glyphSource, same(atlas()));
      expect(PanelCatalogDiagnostics.glyphParagraphDraws, 0);
    });

    testWidgets('is sized for the density of the view and replanned when it '
        'changes', (tester) async {
      density.value = 2;
      await tester.pumpWidget(page(atlas: factory()));
      await tester.pumpAndSettle();
      final first = atlas()!;

      density.value = 3;
      await tester.pumpAndSettle();

      expect(atlas(), isNot(same(first)));
      expect(
        atlas()!.index.layout.glyphSize,
        greaterThan(first.index.layout.glyphSize),
      );
      expect(assets.glyphSource, same(atlas()), reason: 'rebound in place');
    });

    testWidgets('bakes only while the panel is visible', (tester) async {
      host.visible = false;
      await tester.pumpWidget(page(atlas: factory()));
      await tester.pumpAndSettle();
      expect(frames.hasPendingRequest, isFalse);

      host.visible = true;
      await tester.pump();

      expect(frames.hasPendingRequest, isTrue);
      host.opening = true;
      await tester.pump();
      expect(frames.hasPendingRequest, isFalse);
    });

    testWidgets('survives the page: closing and reopening does not bake '
        'again', (tester) async {
      await tester.pumpWidget(page(atlas: factory()));
      await tester.pumpAndSettle();
      final first = atlas()!;

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(page(atlas: factory()));
      await tester.pumpAndSettle();

      expect(atlas(), same(first));
      expect(assets.glyphSource, same(first));
    });

    testWidgets('is released with the shell controller', (tester) async {
      await tester.pumpWidget(page(atlas: factory()));
      await tester.pumpAndSettle();
      final first = atlas()!;
      final atlasHost = controller().atlasHost!;

      await tester.pumpWidget(const SizedBox());
      host.controllers.disposeAll();

      expect(atlasHost.atlas.value, isNull);
      expect(first.spriteOf('😀'), isNull);
      expect(assets.glyphSource, isNull, reason: 'the scope lets it go');
    });

    testWidgets('stays the glyph source of the scope when the page leaves', (
      tester,
    ) async {
      await tester.pumpWidget(page(atlas: factory()));
      await tester.pumpAndSettle();
      final first = atlas()!;

      await tester.pumpWidget(const SizedBox());

      expect(assets.glyphSource, same(first));
    });

    testWidgets('keeps drawing the glyphs of a surface outside the panel after '
        'the panel closes', (tester) async {
      // The composer's inline emoji draw through the scope the panel shares.
      const spec = AssetSpec(pixelWidth: 72, pixelHeight: 72);
      final outside = assets.attach(
        fixtures.key('😀'),
        spec,
        const AssetProfile(),
      );
      addTearDown(outside.detach);
      await tester.pumpWidget(page(atlas: factory()));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        for (var i = 0; i < 200 && frames.hasPendingRequest; i++) {
          frames.pump();
          await pumpEventQueue();
        }
      });
      expect(outside.paintable.sprite, isNotNull, reason: 'open: the atlas');

      await tester.pumpWidget(const SizedBox());

      expect(outside.paintable.sprite, isNotNull, reason: 'closed: the atlas');
      expect(outside.readiness.stage, AssetStage.full);
    });

    testWidgets('after the controller is gone a surface outside the panel is '
        'drawn as text again, never a circle for good', (tester) async {
      const spec = AssetSpec(pixelWidth: 72, pixelHeight: 72);
      final outside = assets.attach(
        fixtures.key('😀'),
        spec,
        const AssetProfile(),
      );
      addTearDown(outside.detach);
      await tester.pumpWidget(page(atlas: factory()));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());

      host.controllers.disposeAll();

      expect(outside.readiness.stage, AssetStage.full, reason: 'the text');
      expect(outside.paintable.sprite, isNull);
    });

    testWidgets('a source that lists its collections late: the glyphs shown '
        'meanwhile are circles that move onto the atlas, never paragraphs', (
      tester,
    ) async {
      PanelCatalogDiagnostics.reset();
      final slow = fixtures.source()..pause();
      addTearDown(slow.dispose);
      await tester.pumpWidget(page(withSource: slow, atlas: factory()));
      await tester.pump();

      expect(controller().atlasHost!.atlas.value, isNull, reason: 'no plan');
      expect(assets.glyphSource, isNotNull, reason: 'waiting for the atlas');
      const spec = AssetSpec(pixelWidth: 72, pixelHeight: 72);
      final early = assets.attach(
        fixtures.key('😀'),
        spec,
        const AssetProfile(),
      );
      addTearDown(early.detach);
      expect(early.readiness.stage, AssetStage.placeholder);

      slow.resume();
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        for (var i = 0; i < 200 && frames.hasPendingRequest; i++) {
          frames.pump();
          await pumpEventQueue();
        }
      });

      expect(assets.glyphSource, same(atlas()));
      expect(early.paintable.sprite, isNotNull);
      expect(PanelCatalogDiagnostics.glyphParagraphDraws, 0);
    });

    testWidgets('on a platform that bakes nothing the glyphs that waited are '
        'drawn as text', (tester) async {
      final slow = fixtures.source()..pause();
      addTearDown(slow.dispose);
      GlyphAtlasHostFactory noAtlas() =>
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
            atlasFactory: (_) => null,
          );
      await tester.pumpWidget(page(withSource: slow, atlas: noAtlas()));
      await tester.pump();
      const spec = AssetSpec(pixelWidth: 72, pixelHeight: 72);
      final early = assets.attach(
        fixtures.key('😀'),
        spec,
        const AssetProfile(),
      );
      addTearDown(early.detach);
      expect(early.readiness.stage, AssetStage.placeholder);

      slow.resume();
      await tester.pumpAndSettle();

      expect(assets.glyphSource, isNull);
      expect(early.readiness.stage, AssetStage.full);
    });

    testWidgets('is planned again behind the old art when a variant is chosen '
        'for the first time', (tester) async {
      final mutable = _MutableSource(glyphs: ['😀', '👍']);
      addTearDown(mutable.dispose);
      await tester.pumpWidget(page(withSource: mutable, atlas: factory()));
      await tester.pumpAndSettle();
      final first = atlas()!;

      mutable.show(['😀', fixtures.thumbsUp.variants[2].key.sequence]);
      await tester.pump();

      expect(atlas(), isNot(same(first)));
      expect(
        atlas()!.index.placementOf(fixtures.thumbsUp.variants[2].key.sequence),
        isNotNull,
      );
      expect(assets.glyphSource, same(atlas()));
    });

    testWidgets('is not planned with no factory: glyphs are drawn as text', (
      tester,
    ) async {
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      expect(controller().atlasHost, isNull);
      expect(assets.glyphSource, isNull);
    });
  });

  group('the paced mount', () {
    Finder strip() => find.byType(EmojiCategoryStrip);

    testWidgets('mounts the strip with the grid by default', (tester) async {
      await tester.pumpWidget(page());

      expect(find.byType(PanelCatalogViewport), findsOneWidget);
      expect(strip(), findsOneWidget);
    });

    testWidgets('a deferred page mounts the grid, then (after the shell\'s '
        'search field) the strip, one frame each', (tester) async {
      await tester.pumpWidget(page(deferChrome: true));

      expect(find.byType(PanelCatalogViewport), findsOneWidget);
      expect(strip(), findsNothing);

      await tester.pump(); // The frame of the shell's search field.
      expect(strip(), findsNothing);

      await tester.pump();
      expect(strip(), findsOneWidget);
    });

    testWidgets('the grid does not move when the strip arrives', (
      tester,
    ) async {
      await tester.pumpWidget(page(deferChrome: true));
      final before = tester.getTopLeft(find.byType(PanelCatalogViewport));

      await tester.pump();
      await tester.pump();

      expect(tester.getTopLeft(find.byType(PanelCatalogViewport)), before);
    });
  });

  group('the strip follows the catalogue', () {
    bool selected(WidgetTester tester, String label) =>
        tester
            .getSemantics(
              find.descendant(
                of: find.byType(EmojiCategoryStrip),
                matching: find.bySemanticsLabel(label),
              ),
            )
            .getSemanticsData()
            .flagsCollection
            .isSelected ==
        Tristate.isTrue;

    testWidgets('scrolling into a category activates its tab', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpPage(tester);
      expect(selected(tester, 'Smileys & People'), isTrue);

      controller().catalog.jumpTo(controller().catalog.maxScrollExtent);
      await tester.pumpAndSettle();

      expect(selected(tester, 'Symbols'), isTrue);
      expect(selected(tester, 'Smileys & People'), isFalse);
      handle.dispose();
    });

    testWidgets('a tap lands the category under the strip', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpPage(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(EmojiCategoryStrip),
          matching: find.bySemanticsLabel('Animals & Nature'),
        ),
      );
      await tester.pumpAndSettle();

      expect(selected(tester, 'Animals & Nature'), isTrue);
      expect(controller().catalog.offset, greaterThan(0));
      handle.dispose();
    });

    testWidgets('is not shown over search results', (tester) async {
      await pumpPage(tester);

      host.searchState = const PanelSearchState(isOpen: true, query: 'japan');
      await tester.pump(DebouncedSearch.defaultDebounce);
      await tester.pumpAndSettle();

      expect(find.byType(EmojiCategoryStrip), findsNothing);
    });
  });

  group('search', () {
    testWidgets('shows results for the shell query, as one section', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpPage(tester);

      host.searchState = const PanelSearchState(isOpen: true, query: 'japan');
      await tester.pump(DebouncedSearch.defaultDebounce);
      await tester.pumpAndSettle();

      expect(find.semantics.byLabel('Search result'), findsOneWidget);
      expect(find.semantics.byLabel('Smileys & People'), findsNothing);
      expect(host.searchResultCounts, [1]);
      handle.dispose();
    });

    testWidgets('says so when nothing is found', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpPage(tester);

      host.searchState = const PanelSearchState(isOpen: true, query: 'zzzz');
      await tester.pump(DebouncedSearch.defaultDebounce);
      await tester.pumpAndSettle();

      expect(find.semantics.byLabel('No emoji found'), findsOneWidget);
      expect(host.searchResultCounts, [0]);
      handle.dispose();
    });
  });

  group('reading direction', () {
    testWidgets('a right-to-left page fills the grid from the right', (
      tester,
    ) async {
      source = fixtures.source(recents: ['❤', '😀'], count: 0);
      await tester.pumpWidget(page(direction: TextDirection.rtl));
      await tester.pumpAndSettle();

      // The first recent, ❤, is in the rightmost column.
      await tester.tapAt(
        origin(tester) + const Offset(360 - 5 - 43.75 / 2, 36 + 50 + 27 + 22.5),
      );
      await tester.pump();

      expect(host.picks.single.key, fixtures.key('❤'));
    });
  });
}

/// A source whose collections the test replaces by hand: one category of the
/// glyphs it is told to show, already loaded.
final class _MutableSource implements CollectionSource {
  _MutableSource({required List<String> glyphs})
    : _collections = listen.ValueNotifier(_of(glyphs));

  final listen.ValueNotifier<List<Collection>> _collections;

  static List<Collection> _of(List<String> glyphs) => [
    Collection(
      id: CollectionId.recent,
      contents: CollectionContents.loaded(const []),
    ),
    Collection(
      id: const CollectionId.category('people'),
      contents: CollectionContents.loaded([
        for (final glyph in glyphs) fixtures.item(glyph),
      ]),
    ),
  ];

  void show(List<String> glyphs) => _collections.value = _of(glyphs);

  @override
  listen.ValueListenable<List<Collection>> get collections => _collections;

  @override
  Future<void> load(CollectionId id) async {}

  @override
  Future<void> loadMore(CollectionId id) async {}

  @override
  void dispose() => _collections.dispose();
}
