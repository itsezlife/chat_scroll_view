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

import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_shell/testing.dart';

final class _Handle implements CatalogStripHandle {
  _Handle(List<CollectionId> ids) : entries = ObservableValue(_entries(ids));

  @override
  final ObservableValue<List<CatalogStripEntry>> entries;

  final events = EventNotifier<PanelCatalogScrollEvent>();

  @override
  String? currentSectionId;

  final jumps = <String>[];
  Completer<void>? pending;

  @override
  EventObservable<PanelCatalogScrollEvent> get scrollEvents => events;

  @override
  Future<void> jumpToSection(String sectionId) {
    jumps.add(sectionId);
    return (pending = Completer<void>()).future;
  }

  void setIds(List<CollectionId> ids) => entries.value = _entries(ids);

  void enter(String sectionId, int index) {
    currentSectionId = sectionId;
    events.publish(PanelCatalogCurrentSectionChanged(index, sectionId));
  }

  void dispose() {
    entries.dispose();
    events.dispose();
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
const _smileys = CollectionId.category('smileys-emotion');
const _people = CollectionId.category('people-body');
const _animals = CollectionId.category('animals-nature');
const _flags = CollectionId.category('flags');

void main() {
  late _Handle handle;

  setUp(
    () => handle = _Handle([_recents, _smileys, _people, _animals, _flags]),
  );
  tearDown(() => handle.dispose());

  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    PanelShellTestScope(
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: 360, child: EmojiCategoryStrip(handle: handle)),
      ),
    ),
  );

  bool selected(WidgetTester tester, String label) =>
      tester
          .getSemantics(find.bySemanticsLabel(label))
          .getSemanticsData()
          .flagsCollection
          .isSelected ==
      Tristate.isTrue;

  group('the tabs', () {
    testWidgets('are one per category, with people folded into smileys', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);

      for (final label in [
        'Recently used',
        'Smileys',
        'Animals & nature',
        'Flags',
      ]) {
        expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
      }
      expect(find.bySemanticsLabel('People'), findsNothing);
      semantics.dispose();
    });

    testWidgets('leave out a category the page does not show', (tester) async {
      final semantics = tester.ensureSemantics();
      handle.setIds([_smileys, _flags]);
      await pump(tester);

      expect(find.bySemanticsLabel('Recently used'), findsNothing);
      expect(find.bySemanticsLabel('Animals & nature'), findsNothing);
      semantics.dispose();
    });

    testWidgets('follow the sections the catalogue holds', (tester) async {
      final semantics = tester.ensureSemantics();
      handle.setIds([_smileys, _flags]);
      await pump(tester);

      handle.setIds([_recents, _smileys, _flags]);
      await tester.pump();

      expect(find.bySemanticsLabel('Recently used'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('are not drawn for a single category', (tester) async {
      handle.setIds([_smileys, _people]);
      await pump(tester);

      expect(tester.getSize(find.byType(EmojiCategoryStrip)).height, 0);
    });

    testWidgets('are labelled, and the strip with them', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);

      expect(find.bySemanticsLabel('Categories'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Flags')),
        matchesSemantics(
          label: 'Flags',
          isButton: true,
          hasSelectedState: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
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

      expect(selected(tester, 'Animals & nature'), isTrue);
      semantics.dispose();
    });

    testWidgets('follows the section the user scrolls into', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);

      handle.enter('$_people', 2);
      await tester.pump();
      expect(selected(tester, 'Smileys'), isTrue);

      handle.enter('$_flags', 4);
      await tester.pump();
      expect(selected(tester, 'Flags'), isTrue);
      expect(selected(tester, 'Smileys'), isFalse);
      semantics.dispose();
    });

    testWidgets('stays on the tab when scrolling stays in its category', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      handle.enter('$_smileys', 1);
      await tester.pump();

      handle.enter('$_people', 2);
      await tester.pump();

      expect(selected(tester, 'Smileys'), isTrue);
      semantics.dispose();
    });
  });

  group('a tap', () {
    testWidgets('lands on the first section of the category', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);

      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is Semantics && w.properties.label == 'Smileys',
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

      await _tapTab(tester, 'Flags');
      handle.enter('$_animals', 3); // The catalogue flies over it.
      await tester.pump();
      expect(selected(tester, 'Flags'), isTrue);

      handle.currentSectionId = '$_flags';
      handle.pending!.complete();
      await tester.pump();
      expect(selected(tester, 'Flags'), isTrue);
      semantics.dispose();
    });

    testWidgets('is ignored while a jump runs', (tester) async {
      await pump(tester);
      await _tapTab(tester, 'Flags');

      await _tapTab(tester, 'Animals & nature');

      expect(handle.jumps, ['$_flags']);
    });

    testWidgets('keeps its tab after the jump even where the content ended '
        'before the header reached the top', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      await _tapTab(tester, 'Animals & nature');

      // The catalogue could only scroll as far as the end, which is in flags.
      handle.currentSectionId = '$_flags';
      handle.pending!.complete();
      await tester.pump();

      expect(selected(tester, 'Animals & nature'), isTrue);
      semantics.dispose();
    });

    testWidgets('gives way to the section the user then scrolls into', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester);
      await _tapTab(tester, 'Animals & nature');
      handle.pending!.complete();
      await tester.pump();

      handle.enter('$_smileys', 1);
      await tester.pump();

      expect(selected(tester, 'Smileys'), isTrue);
      semantics.dispose();
    });

    testWidgets('can be made again once the jump ended', (tester) async {
      await pump(tester);
      await _tapTab(tester, 'Flags');
      handle.pending!.complete();
      await tester.pump();

      await _tapTab(tester, 'Animals & nature');

      expect(handle.jumps, ['$_flags', '$_animals']);
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
