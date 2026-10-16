/// The emoji page as a user and the shell see it.
///
/// **Seam:** [EmojiPage] mounted under the chrome scopes with a fake source and
/// search source, a fake page host and a real asset scope, observed through the
/// picks and requests the host received, the preferences, the controller and
/// what is on screen. Geometry: 8 columns of 43.75 x 45 cells in a 360 x 480
/// page with the 36 px strip above, so the first cell's centre is
/// (5 + 21.875, 36 + 27 + 22.5) from the page's top left.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
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
    addTearDown(() {
      source.dispose();
      search.dispose();
      preferences.dispose();
      host.dispose();
      assets.dispose();
      swapped.dispose();
    });
  });

  Widget page({
    CollectionSource? withSource,
    bool deferChrome = false,
    GlyphAtlasHostFactory? atlas,
    TextDirection direction = TextDirection.ltr,
  }) => PanelShellTestScope(
    textDirection: direction,
    child: Overlay(
      initialEntries: [
        OverlayEntry(
          builder: (context) => ValueListenableBuilder<CollectionSource?>(
            valueListenable: swapped,
            builder: (context, _, _) => Center(
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
      ],
    ),
  );

  Offset origin(WidgetTester tester) =>
      tester.getTopLeft(find.byType(EmojiPage));

  /// The centre of the cell at [row], [column] of a section whose header
  /// starts [top] px below the strip.
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
        (strip ? 36 : 0) + top + 27 + 45 * row + 22.5,
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

      // One header, one strip tab; People has a header but no tab of its own.
      expect(find.semantics.byLabel('People'), findsOneWidget);
      expect(find.semantics.byLabel('Smileys'), findsNWidgets(2));
      expect(find.semantics.byLabel('Recently used'), findsNothing);
      handle.dispose();
    });

    testWidgets('an empty search narrows the page to the recents', (
      tester,
    ) async {
      source = fixtures.source(recents: ['❤']);
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      final model = controller().catalog;
      expect(model.maxScrollExtent, greaterThan(0));

      host.searchState = const PanelSearchState(isOpen: true);
      await tester.pumpAndSettle();

      // One section of one row: nothing left to scroll.
      expect(model.maxScrollExtent, 0);
    });
  });

  group('the recents header action', () {
    testWidgets('asks the host to clear the emoji recents, and clears none '
        'itself', (tester) async {
      source = fixtures.source(recents: ['❤'], count: 0);
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      // The action sits at the trailing end of the recents header.
      await tester.tapAt(origin(tester) + const Offset(330, 36 + 13));
      await tester.pump();

      expect(host.clearRecentsRequests, [SemanticKind.unicodeEmoji]);
      expect(host.picks, isEmpty);
    });

    testWidgets('is labelled', (tester) async {
      final handle = tester.ensureSemantics();
      source = fixtures.source(recents: ['❤'], count: 0);
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();

      expect(find.semantics.byLabel('Clear recent emoji'), findsOneWidget);
      handle.dispose();
    });
  });

  group('the variant picker', () {
    // count: 0 puts 👍 at the first cell of the people section, which starts
    // after the smileys' one row (27 + 45).
    const peopleTop = 72.0;

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
      final picker = tester.getTopLeft(find.byType(EmojiVariantPicker));
      // The fourth option's centre.
      await gesture.moveTo(
        picker +
            EmojiVariantPickerMetrics.centerOf(
              3,
              fixtures.thumbsUp.variants.length + 1,
            ),
      );
      await tester.pump();
      await gesture.up();
      await tester.pump();

      final chosen = fixtures.thumbsUp.variants[2].key;
      expect(host.picks.single.key, chosen);
      expect(host.picks.single.source, PickSource.collection);
      expect(preferences.preferredVariant(fixtures.thumbsUp.base), chosen);
      expect(find.byType(EmojiVariantPicker), findsNothing);
    });

    testWidgets('choosing the base forgets the choice', (tester) async {
      await preferences.setPreferredVariant(
        fixtures.thumbsUp.base,
        fixtures.thumbsUp.variants.first.key,
      );
      final gesture = await pressThumb(tester);

      await gesture.up();
      await tester.pump();

      expect(host.picks.single.key, fixtures.thumbsUp.base);
      expect(preferences.preferredVariant(fixtures.thumbsUp.base), isNull);
    });

    testWidgets('a pick from the recents is not a preference', (tester) async {
      source = fixtures.source(recents: ['👍'], count: 0);
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(cell(tester, top: 0));
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byType(EmojiVariantPicker), findsOneWidget);

      await gesture.up();
      await tester.pump();

      expect(host.picks.single.source, PickSource.recents);
      expect(preferences.preferredVariant(fixtures.thumbsUp.base), isNull);
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
      await tester.pump();

      expect(host.picks.single.key, fixtures.thumbsUp.variants[3].key);
      expect(find.byType(EmojiVariantPicker), findsNothing);
      handle.dispose();
    });

    testWidgets('is labelled, with its options', (tester) async {
      final handle = tester.ensureSemantics();
      final gesture = await pressThumb(tester);

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
}
