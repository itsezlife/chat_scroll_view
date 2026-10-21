/// The category strip of the emoji page: which tabs it shows, which one is
/// active, and where a tap lands.
///
/// **Seam:** [EmojiCategoryStrip] over a fake [CatalogStripHandle] the test
/// steers (the sections, the catalogue's events, the answer to a jump), under
/// the chrome scopes, observed through the semantics of its tabs and the jumps
/// the handle received.
library;

import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen/listen.dart' as listen;
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

final class _Handle implements CatalogStripHandle {
  _Handle(List<CollectionId> ids)
    : entries = listen.ValueNotifier(_entries(ids));

  @override
  final listen.ValueNotifier<List<CatalogStripEntry>> entries;

  final events = StreamController<PanelCatalogScrollEvent>.broadcast(
    sync: true,
  );

  @override
  String? currentSectionId;

  final jumps = <String>[];
  Completer<void>? pending;

  @override
  Stream<PanelCatalogScrollEvent> get scrollEvents => events.stream;

  @override
  Future<void> jumpToSection(String sectionId) {
    jumps.add(sectionId);
    return (pending = Completer<void>()).future;
  }

  void setIds(List<CollectionId> ids) => entries.value = _entries(ids);

  void enter(String sectionId, int index) {
    currentSectionId = sectionId;
    events.add(PanelCatalogCurrentSectionChanged(index, sectionId));
  }

  void dispose() {
    entries.dispose();
    unawaited(events.close());
  }
}

List<CatalogStripEntry> _entries(List<CollectionId> ids) => [
  for (final id in ids)
    CatalogStripEntry(
      sectionId: '$id',
      collection: Collection(id: id),
    ),
];

const _recents = CollectionId.recent;
const _smileys = CollectionId.category('people');
const _food = CollectionId.category('food');
const _animals = CollectionId.category('nature');
const _symbols = CollectionId.category('symbols');

void main() {
  late _Handle handle;

  setUp(() => handle = _Handle([_recents, _smileys, _animals, _symbols]));
  tearDown(() => handle.dispose());

  Future<void> pump(
    WidgetTester tester, {
    double width = 360,
    ChromeMotionSpeed speed = ChromeMotionSpeed.normal,
    PanelArrangement arrangement = PanelArrangement.touch,
    bool disableAnimations = false,
    EmojiStripLayout layout = EmojiStripLayout.automatic,
  }) => tester.pumpWidget(
    PanelShellTestScope(
      speed: speed,
      child: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: PanelArrangementScope(
          arrangement: arrangement,
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: EmojiCategoryStrip(handle: handle, layout: layout),
            ),
          ),
        ),
      ),
    ),
  );

  double stripOffset(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(
          of: find.byType(EmojiCategoryStrip),
          matching: find.byType(Scrollable),
        ),
      )
      .position
      .pixels;

  bool selected(WidgetTester tester, String label) =>
      tester
          .getSemantics(find.bySemanticsLabel(label))
          .getSemanticsData()
          .flagsCollection
          .isSelected ==
      Tristate.isTrue;

  testWidgets('on a transparent shell paints no fill of its own', (
    tester,
  ) async {
    await tester.pumpWidget(
      PanelShellTestScope(
        child: PanelBackgroundScope(
          color: const Color(0x00000000),
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 360,
              child: EmojiCategoryStrip(handle: handle),
            ),
          ),
        ),
      ),
    );
    final panel = ChromeThemeScope.panelOf(
      tester.element(find.byType(EmojiCategoryStrip)),
    );

    expect(
      find.descendant(
        of: find.byType(EmojiCategoryStrip),
        matching: find.byWidgetPredicate(
          (w) => w is ColoredBox && w.color == panel.background,
        ),
      ),
      findsNothing,
    );
  });

  group('the tabs', () {
    testWidgets('are the reference client\'s, one per category, with no tab '
        'of their own for flags or people', (tester) async {
      final semantics = tester.ensureSemantics();
      handle.setIds([_recents, _smileys, _animals, _food, _symbols]);
      await pump(tester);

      for (final label in [
        'Recently used',
        'Smileys & People',
        'Animals & Nature',
        'Food & Drink',
        'Symbols',
      ]) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      for (final label in ['People', 'Flags']) {
        expect(find.bySemanticsLabel(label), findsNothing, reason: label);
      }
      semantics.dispose();
    });

    testWidgets('leave out a category the page does not show', (tester) async {
      final semantics = tester.ensureSemantics();
      handle.setIds([_smileys, _symbols]);
      await pump(tester);

      expect(find.bySemanticsLabel('Recently used'), findsNothing);
      expect(find.bySemanticsLabel('Animals & Nature'), findsNothing);
      semantics.dispose();
    });

    testWidgets('follow the sections the catalogue holds', (tester) async {
      final semantics = tester.ensureSemantics();
      handle.setIds([_smileys, _symbols]);
      await pump(tester);

      handle.setIds([_recents, _smileys, _symbols]);
      await tester.pump();

      expect(find.bySemanticsLabel('Recently used'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('are not drawn for a single category', (tester) async {
      handle.setIds([_smileys]);
      await pump(tester);

      expect(tester.getSize(find.byType(EmojiCategoryStrip)).height, 0);
    });

    testWidgets('are labelled, and the strip with them', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);

      expect(find.bySemanticsLabel('Categories'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Symbols')),
        matchesSemantics(
          label: 'Symbols',
          isButton: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    });
  });

  group('revealing the active tab', () {
    // 4 tabs of 30 + 3 in a 100 px strip: the last one starts off screen.
    testWidgets('slides over the fade role at normal speed', (tester) async {
      await pump(tester, width: 100);

      handle.enter('$_symbols', 3);
      await tester.pump();
      await tester.pump(); // the animation's first frame
      await tester.pump(const Duration(milliseconds: 100));
      final partway = stripOffset(tester);
      await tester.pump(const Duration(milliseconds: 150));

      expect(partway, greaterThan(0));
      expect(stripOffset(tester), greaterThan(partway));
      await tester.pumpAndSettle();
      expect(stripOffset(tester), 51);
    });

    testWidgets('lands at once when motion is instant', (tester) async {
      await pump(tester, width: 100, speed: ChromeMotionSpeed.instant);

      handle.enter('$_symbols', 3);
      await tester.pump();

      expect(stripOffset(tester), 51);
    });
  });

  group('the active tab', () {
    testWidgets('is the first before the catalogue says anything', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);

      expect(selected(tester, 'Recently used'), isTrue);
      semantics.dispose();
    });

    testWidgets('is the one of the section the catalogue is in when the strip '
        'mounts late', (tester) async {
      final semantics = tester.ensureSemantics();
      handle.currentSectionId = '$_animals';
      await pump(tester);

      expect(selected(tester, 'Animals & Nature'), isTrue);
      semantics.dispose();
    });

    testWidgets('follows the section the user scrolls into', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);

      handle.enter('$_animals', 2);
      await tester.pump();
      expect(selected(tester, 'Animals & Nature'), isTrue);

      handle.enter('$_symbols', 3);
      await tester.pump();
      expect(selected(tester, 'Symbols'), isTrue);
      expect(selected(tester, 'Animals & Nature'), isFalse);
      semantics.dispose();
    });
  });

  group('a tap', () {
    testWidgets('lands on the first section of the category', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);

      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Smileys & People',
        ),
      );
      await tester.pump();

      expect(handle.jumps, ['$_smileys']);
      semantics.dispose();
    });

    testWidgets('makes its tab active at once, and the catalogue cannot move '
        'it away until the jump ends', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);

      await _tapTab(tester, 'Symbols');
      handle.enter('$_animals', 2); // The catalogue flies over it.
      await tester.pump();
      expect(selected(tester, 'Symbols'), isTrue);

      handle.currentSectionId = '$_symbols';
      handle.pending!.complete();
      await tester.pump();
      expect(selected(tester, 'Symbols'), isTrue);
      semantics.dispose();
    });

    testWidgets('is ignored while a jump runs', (tester) async {
      await pump(tester);
      await _tapTab(tester, 'Symbols');

      await _tapTab(tester, 'Animals & Nature');

      expect(handle.jumps, ['$_symbols']);
    });

    testWidgets('keeps its tab after the jump even where the content ended '
        'before the header reached the top', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      await _tapTab(tester, 'Animals & Nature');

      // The catalogue could only scroll as far as the end, which is in flags.
      handle.currentSectionId = '$_symbols';
      handle.pending!.complete();
      await tester.pump();

      expect(selected(tester, 'Animals & Nature'), isTrue);
      semantics.dispose();
    });

    testWidgets('gives way to the section the user then scrolls into', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      await _tapTab(tester, 'Animals & Nature');
      handle.pending!.complete();
      await tester.pump();

      handle.enter('$_smileys', 1);
      await tester.pump();

      expect(selected(tester, 'Smileys & People'), isTrue);
      semantics.dispose();
    });

    testWidgets('can be made again once the jump ended', (tester) async {
      await pump(tester);
      await _tapTab(tester, 'Symbols');
      handle.pending!.complete();
      await tester.pump();

      await _tapTab(tester, 'Animals & Nature');

      expect(handle.jumps, ['$_symbols', '$_animals']);
    });
  });

  group('with packs under touch: the reference mobile client\'s strip', () {
    const categories = [
      CollectionId.category('people'),
      CollectionId.category('nature'),
      CollectionId.category('food'),
      CollectionId.category('activity'),
      CollectionId.category('travel'),
      CollectionId.category('objects'),
      CollectionId.category('symbols'),
    ];
    // Seven categories: an open group is 32 px a category, at most 5.7 of
    // them, before it scrolls.
    const openWidth = 32 * 5.7;

    void withPack() => handle.entries.value = [
      ..._entries([_recents, ...categories]),
      const CatalogStripEntry(
        sectionId: 'pack',
        collection: Collection(
          id: CollectionId.set('pack'),
          metadata: CollectionMetadata(title: 'Pack'),
        ),
      ),
    ];

    double groupWidth(WidgetTester tester) =>
        tester.getSize(find.byKey(EmojiCategoryStrip.groupKey)).width;

    testWidgets('folds the categories into one group between the recents and '
        'a tab per pack', (tester) async {
      final semantics = tester.ensureSemantics();
      withPack();
      await pump(tester);

      expect(find.byKey(EmojiCategoryStrip.groupKey), findsOneWidget);
      final recents = tester.getRect(find.bySemanticsLabel('Recently used'));
      final group = tester.getRect(find.byKey(EmojiCategoryStrip.groupKey));
      final pack = tester.getRect(find.bySemanticsLabel('Pack'));
      expect(recents, const Rect.fromLTWH(11, 3, 30, 30));
      // 3 px apart, the group closed while the recents are active.
      expect(group, const Rect.fromLTWH(44, 3, 30, 30));
      expect(pack, const Rect.fromLTWH(77, 3, 30, 30));
      semantics.dispose();
    });

    testWidgets('opens the group while a category is active, over 475 ms '
        'easing out, and closes it in a pack', (tester) async {
      withPack();
      await pump(tester);

      handle.enter('${categories.first}', 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        groupWidth(tester),
        moreOrLessEquals(
          30 + (openWidth - 30) * Curves.easeOutQuint.transform(100 / 475),
          epsilon: .5,
        ),
      );
      await tester.pumpAndSettle();
      expect(groupWidth(tester), moreOrLessEquals(openWidth));

      handle.enter('pack', 8);
      await tester.pumpAndSettle();
      expect(groupWidth(tester), moreOrLessEquals(30));
    });

    testWidgets('closes the group easing out over 475 ms, as it opens, with '
        'the pack beside it moving with it', (tester) async {
      final semantics = tester.ensureSemantics();
      withPack();
      await pump(tester);
      handle.enter('${categories.first}', 1);
      await tester.pumpAndSettle();

      handle.enter('pack', 8);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final eased = Curves.easeOutQuint.transform(100 / 475);
      expect(
        groupWidth(tester),
        moreOrLessEquals(openWidth + (30 - openWidth) * eased, epsilon: .5),
      );
      final group = tester.getRect(find.byKey(EmojiCategoryStrip.groupKey));
      final pack = tester.getRect(find.bySemanticsLabel('Pack'));
      expect(pack.left - group.right, moreOrLessEquals(3));
      semantics.dispose();
    });

    testWidgets('keeps the pill on the open group, unstretched, as the '
        'category inside it changes', (tester) async {
      withPack();
      await pump(tester);
      handle.enter('${categories.first}', 1);
      await tester.pumpAndSettle();
      final group = tester.getRect(find.byKey(EmojiCategoryStrip.groupKey));

      handle.enter('${categories[2]}', 3);
      await tester.pump();
      // Half-way through a slide, where a moving pill is widest.
      await tester.pump(const Duration(milliseconds: 60));

      final strip = tester.getTopLeft(find.byType(EmojiCategoryStrip));
      expect(
        find.byType(EmojiCategoryStrip),
        paints..rrect(
          rrect: RRect.fromRectAndRadius(
            group.shift(-strip),
            const Radius.circular(15),
          ),
        ),
      );
    });

    testWidgets('a tap on a pack lands on it and makes it active', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      withPack();
      await pump(tester);

      await _tapTab(tester, 'Pack');

      expect(handle.jumps, ['pack']);
      expect(selected(tester, 'Pack'), isTrue);
      semantics.dispose();
    });

    testWidgets('a closed group shows its first category, and a tap on it '
        'lands there and opens the group', (tester) async {
      final semantics = tester.ensureSemantics();
      withPack();
      await pump(tester);

      await _tapTab(tester, 'Smileys & People');
      await tester.pumpAndSettle();

      expect(handle.jumps, ['${categories.first}']);
      expect(groupWidth(tester), moreOrLessEquals(openWidth));
      semantics.dispose();
    });

    testWidgets('opens at once when animations are disabled', (tester) async {
      withPack();
      await pump(tester, disableAnimations: true);

      handle.enter('${categories.first}', 1);
      await tester.pump();
      await tester.pump();

      expect(groupWidth(tester), moreOrLessEquals(openWidth));
    });

    testWidgets('stays the plain row without a pack, or when the host asks '
        'for it', (tester) async {
      handle.entries.value = _entries([_recents, ...categories]);
      await pump(tester);
      expect(find.byKey(EmojiCategoryStrip.groupKey), findsNothing);

      withPack();
      await pump(tester, layout: EmojiStripLayout.plain);
      expect(find.byKey(EmojiCategoryStrip.groupKey), findsNothing);
    });
  });

  group('pinned at the bottom (the pointer arrangement): the reference '
      'desktop client\'s footer', () {
    final all = [
      _recents,
      for (final id in [
        'people',
        'nature',
        'food',
        'activity',
        'travel',
        'objects',
        'symbols',
      ])
        CollectionId.category(id),
    ];
    const categoryLabels = [
      'Smileys & People',
      'Animals & Nature',
      'Food & Drink',
      'Activity',
      'Travel & Places',
      'Objects',
      'Symbols',
    ];

    // The grouped layout unless a test says otherwise: the reference client
    // groups as soon as there is a pack, and these tests mostly have none.
    Future<void> pumpPinned(
      WidgetTester tester, {
      bool disableAnimations = false,
      double width = 345,
      ChromeMotionSpeed speed = ChromeMotionSpeed.normal,
      EmojiStripLayout layout = EmojiStripLayout.grouped,
    }) => pump(
      tester,
      width: width,
      arrangement: PanelArrangement.pointer,
      disableAnimations: disableAnimations,
      speed: speed,
      layout: layout,
    );

    Rect marker(WidgetTester tester) =>
        tester.getRect(find.byKey(EmojiCategoryStrip.highlightKey));

    BorderRadiusGeometry? markerRadius(WidgetTester tester) {
      final box = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byKey(EmojiCategoryStrip.highlightKey),
          matching: find.byType(DecoratedBox),
        ),
      );
      return (box.decoration as BoxDecoration).borderRadius;
    }

    Rect slot(WidgetTester tester, String label) => tester.getRect(
      find.descendant(
        of: find.byType(EmojiCategoryStrip),
        matching: find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == label,
        ),
      ),
    );

    group('with no pack (automatic)', () {
      testWidgets('gives the recents and every category a 30 px slot of its '
          'own from 3 px in, as the grouped footer does, nothing folded', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        handle.setIds(all);
        await pumpPinned(tester, layout: EmojiStripLayout.automatic);

        expect(
          slot(tester, 'Recently used'),
          const Rect.fromLTWH(3, 0, 30, 36),
        );
        for (var i = 0; i < categoryLabels.length; i++) {
          expect(
            slot(tester, categoryLabels[i]),
            Rect.fromLTWH(3 + (i + 1) * 30, 0, 30, 36),
            reason: categoryLabels[i],
          );
        }
        expect(marker(tester), const Rect.fromLTWH(4, 4, 28, 28));
        semantics.dispose();
      });

      testWidgets('moves the 28 px square to the active category', (
        tester,
      ) async {
        handle.setIds(all);
        await pumpPinned(tester, layout: EmojiStripLayout.automatic);

        handle.enter('${all[3]}', 3);
        await tester.pumpAndSettle();

        expect(marker(tester), const Rect.fromLTWH(3 + 3 * 30 + 1, 4, 28, 28));
        expect(markerRadius(tester), BorderRadius.circular(8));
      });

      testWidgets('groups as soon as there is a pack', (tester) async {
        final semantics = tester.ensureSemantics();
        handle.entries.value = [
          ..._entries(all),
          const CatalogStripEntry(
            sectionId: 'pack-0',
            collection: Collection(
              id: CollectionId.set('p0'),
              metadata: CollectionMetadata(title: 'Pack 0'),
            ),
          ),
        ];
        await pumpPinned(tester, layout: EmojiStripLayout.automatic);

        expect(slot(tester, 'Recently used').width, 30);
        expect(
          find.bySemanticsLabel('Symbols'),
          findsNothing,
          reason: 'folded',
        );
        semantics.dispose();
      });

      testWidgets('a host can ask for the plain layout with packs too', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        handle.entries.value = [
          ..._entries(all),
          const CatalogStripEntry(
            sectionId: 'pack-0',
            collection: Collection(
              id: CollectionId.set('p0'),
              metadata: CollectionMetadata(title: 'Pack 0'),
            ),
          ),
        ];
        await pumpPinned(tester, layout: EmojiStripLayout.plain);

        expect(
          slot(tester, 'Symbols'),
          const Rect.fromLTWH(3 + 7 * 30, 0, 30, 36),
        );
        expect(
          slot(tester, 'Pack 0'),
          const Rect.fromLTWH(3 + 8 * 30, 0, 30, 36),
        );
        semantics.dispose();
      });
    });

    testWidgets('is 36 px of icons on its own fill, with no line over it', (
      tester,
    ) async {
      handle.setIds(all);
      await pumpPinned(tester);

      expect(tester.getSize(find.byType(EmojiCategoryStrip)).height, 36);
      final panel = ChromeThemeScope.panelOf(
        tester.element(find.byType(EmojiCategoryStrip)),
      );
      final fills = tester
          .widgetList<ColoredBox>(
            find.descendant(
              of: find.byType(EmojiCategoryStrip),
              matching: find.byType(ColoredBox),
            ),
          )
          .map((box) => box.color);
      expect(fills, contains(panel.stripFill));
      expect(fills, isNot(contains(panel.hairline)));
    });

    testWidgets('puts the recents in a 30 px slot 3 px in, then every '
        'category folded into one icon while the recents are active', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      handle.setIds(all);
      await pumpPinned(tester);

      expect(slot(tester, 'Recently used'), const Rect.fromLTWH(3, 0, 30, 36));
      expect(
        slot(tester, 'Smileys & People'),
        const Rect.fromLTWH(33, 0, 30, 36),
      );
      expect(find.bySemanticsLabel('Symbols'), findsNothing);
      expect(selected(tester, 'Recently used'), isTrue);
      expect(marker(tester), const Rect.fromLTWH(4, 4, 28, 28));
      expect(markerRadius(tester), BorderRadius.circular(8));
      semantics.dispose();
    });

    testWidgets('opens the categories into their icons while one is active, '
        'under a pill of radius 14, the category told by its colour', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      handle.setIds(all);
      await pumpPinned(tester);

      handle.enter('${all[3]}', 3);
      await tester.pumpAndSettle();

      // 345 px leave the group every icon: 7 of 30 px after the recents.
      for (var i = 0; i < categoryLabels.length; i++) {
        expect(
          slot(tester, categoryLabels[i]).left,
          33 + i * 30,
          reason: categoryLabels[i],
        );
      }
      expect(marker(tester), const Rect.fromLTWH(34, 4, 208, 28));
      expect(markerRadius(tester), BorderRadius.circular(14));
      expect(selected(tester, 'Food & Drink'), isTrue);
      expect(selected(tester, 'Smileys & People'), isFalse);
      semantics.dispose();
    });

    testWidgets('slides the marker over 400 ms, easing out, as the catalogue '
        'moves into another section', (tester) async {
      handle.setIds(all);
      await pumpPinned(tester);

      handle.enter('${all[1]}', 1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The group is open by 240 ms; at 300 ms an ease-out cubic is 98.4% of
      // the way: the width goes from the recents' 28 to the pill's 208.
      expect(
        marker(tester).width,
        closeTo(28 + 180 * (1 - 0.25 * 0.25 * 0.25), 0.5),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(marker(tester).width, 208);
    });

    testWidgets('moves at once when animations are disabled, or the motion '
        'is instant', (tester) async {
      handle.setIds(all);
      await pumpPinned(tester, disableAnimations: true);
      handle.enter('${all[1]}', 1);
      await tester.pump();
      expect(marker(tester).width, 208);

      await pumpPinned(tester, speed: ChromeMotionSpeed.instant);
      handle.enter('$_recents', 0);
      await tester.pump();
      expect(marker(tester).width, 28);
    });

    group('with packs', () {
      List<CatalogStripEntry> withPacks(int count) => [
        ..._entries(all),
        for (var i = 0; i < count; i++)
          CatalogStripEntry(
            sectionId: 'pack-$i',
            collection: Collection(
              id: CollectionId.set('p$i'),
              metadata: CollectionMetadata(title: 'Pack $i'),
            ),
          ),
      ];

      testWidgets('gives each pack a 30 px slot after the categories, and a '
          'click lands on it', (tester) async {
        final semantics = tester.ensureSemantics();
        handle.entries.value = withPacks(2);
        await pumpPinned(tester);

        expect(slot(tester, 'Pack 0'), const Rect.fromLTWH(63, 0, 30, 36));
        expect(slot(tester, 'Pack 1'), const Rect.fromLTWH(93, 0, 30, 36));

        await _tapTab(tester, 'Pack 1');
        expect(handle.jumps, ['pack-1']);
        expect(selected(tester, 'Pack 1'), isTrue);
        semantics.dispose();
      });

      testWidgets('opening the group slides what follows it linearly over '
          '240 ms, and the marker grows inside the group, never past it', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        handle.entries.value = withPacks(1);
        await pumpPinned(tester);
        expect(slot(tester, 'Pack 0').left, 63);

        handle.enter('${all[1]}', 1);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));

        // A quarter of the way from 30 to 210.
        const group = 30 + 180 * 0.25;
        expect(slot(tester, 'Pack 0').left, closeTo(3 + 30 + group, 0.5));
        expect(marker(tester).right, lessThanOrEqualTo(3 + 30 + group));

        await tester.pump(const Duration(milliseconds: 180));
        expect(slot(tester, 'Pack 0').left, closeTo(3 + 30 + 210, 0.01));
        await tester.pumpAndSettle();
        expect(marker(tester), const Rect.fromLTWH(34, 4, 208, 28));
        semantics.dispose();
      });

      testWidgets('a click puts the marker on the icon at once', (
        tester,
      ) async {
        handle.entries.value = withPacks(2);
        await pumpPinned(tester);

        await _tapTab(tester, 'Pack 1');
        await tester.pump(const Duration(milliseconds: 16));

        expect(marker(tester), const Rect.fromLTWH(94, 4, 28, 28));
      });

      testWidgets('centres the active icon, scrolling linearly over 400 ms, '
          'when they overflow', (tester) async {
        final semantics = tester.ensureSemantics();
        // 10 packs: 3 + 30 + 30 + 300 + 3 = 366 px in 345, 21 px to scroll.
        handle.entries.value = withPacks(10);
        await pumpPinned(tester);
        expect(slot(tester, 'Pack 9').right, 363);

        handle.enter('pack-9', 17);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(slot(tester, 'Pack 9').right, closeTo(363 - 21 / 2, 0.01));

        await tester.pump(const Duration(milliseconds: 200));
        expect(slot(tester, 'Pack 9').right, 342);
        semantics.dispose();
      });

      testWidgets('the wheel scrolls them at once, held to their ends', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        handle.entries.value = withPacks(10);
        await pumpPinned(tester);
        final at = tester.getCenter(find.byType(EmojiCategoryStrip));

        tester.binding.handlePointerEvent(
          PointerScrollEvent(position: at, scrollDelta: const Offset(0, 15)),
        );
        await tester.pump();
        expect(slot(tester, 'Recently used').left, 3 - 15);

        tester.binding.handlePointerEvent(
          PointerScrollEvent(position: at, scrollDelta: const Offset(50, 0)),
        );
        await tester.pump();
        expect(slot(tester, 'Recently used').left, 3 - 21);
        semantics.dispose();
      });

      testWidgets('a mouse drag scrolls them and picks nothing', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        handle.entries.value = withPacks(10);
        await pumpPinned(tester);

        final mouse = await tester.startGesture(
          tester.getCenter(find.bySemanticsLabel('Pack 5')),
          kind: PointerDeviceKind.mouse,
        );
        await mouse.moveBy(const Offset(-15, 0));
        await tester.pump();
        await mouse.up();
        await tester.pump();

        expect(slot(tester, 'Recently used').left, 3 - 15);
        expect(handle.jumps, isEmpty);
        semantics.dispose();
      });

      testWidgets('fades an edge with icons beyond it', (tester) async {
        handle.entries.value = withPacks(10);
        await pumpPinned(tester);
        int fades() => tester
            .widgetList<DecoratedBox>(
              find.descendant(
                of: find.byType(EmojiCategoryStrip),
                matching: find.byType(DecoratedBox),
              ),
            )
            .where((box) => (box.decoration as BoxDecoration).gradient != null)
            .length;
        expect(fades(), 1, reason: 'the end only');

        tester.binding.handlePointerEvent(
          PointerScrollEvent(
            position: tester.getCenter(find.byType(EmojiCategoryStrip)),
            scrollDelta: const Offset(10, 0),
          ),
        );
        await tester.pump();
        expect(fades(), 2);
      });

      testWidgets('a narrower group shows five and a half categories and '
          'centres the active one in it', (tester) async {
        final semantics = tester.ensureSemantics();
        // 5 packs: 345 + 30 - 7 * 30 = 165, the least a group is.
        handle.entries.value = withPacks(5);
        await pumpPinned(tester);

        handle.enter('${all[7]}', 7);
        await tester.pumpAndSettle();

        expect(marker(tester).width, 165 - 2);
        // The last category's icon ends at the group's end.
        expect(slot(tester, 'Symbols').right, closeTo(33 + 165, 0.01));
        semantics.dispose();
      });
    });
  });
}

Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byType(EmojiCategoryStrip),
      matching: find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == label,
      ),
    ),
  );
  await tester.pump();
}
