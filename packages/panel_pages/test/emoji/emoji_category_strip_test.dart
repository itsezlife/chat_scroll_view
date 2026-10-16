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
import 'package:flutter/rendering.dart';
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
              child: EmojiCategoryStrip(handle: handle),
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

  group('pinned at the bottom (the pointer arrangement)', () {
    // 4 tabs over 360 px: 3 px insets and 88.5 px for each icon.
    const pitch = (360 - 6) / 4;
    double highlightStart(WidgetTester tester) =>
        tester.getTopLeft(find.byKey(EmojiCategoryStrip.highlightKey)).dx;
    double expectedStart(int index) => 3 + index * pitch + (pitch - 28) / 2;

    Future<void> pumpPinned(
      WidgetTester tester, {
      bool disableAnimations = false,
      double width = 360,
    }) => pump(
      tester,
      width: width,
      arrangement: PanelArrangement.pointer,
      disableAnimations: disableAnimations,
    );

    testWidgets('is a 1 px line over 36 px of icons on its own fill', (
      tester,
    ) async {
      await pumpPinned(tester);

      expect(tester.getSize(find.byType(EmojiCategoryStrip)).height, 37);
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
      expect(fills, containsAll([panel.hairline, panel.stripFill]));
      expect(panel.stripFill, isNot(panel.background));
    });

    testWidgets('marks the active category with a 28 px square of radius 8', (
      tester,
    ) async {
      await pumpPinned(tester);

      final marker = find.byKey(EmojiCategoryStrip.highlightKey);
      expect(tester.getSize(marker), const Size(28, 28));
      final decoration =
          tester
                  .widget<DecoratedBox>(
                    find.descendant(
                      of: marker,
                      matching: find.byType(DecoratedBox),
                    ),
                  )
                  .decoration
              as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(8));
      expect(decoration.shape, BoxShape.rectangle);
    });

    testWidgets('puts the square on the first selection without moving it', (
      tester,
    ) async {
      await pumpPinned(tester);

      expect(highlightStart(tester), closeTo(expectedStart(0), 0.01));
    });

    testWidgets('slides the square to the next icon over 400 ms, easing '
        'out', (tester) async {
      await pumpPinned(tester);

      handle.enter('$_symbols', 3);
      await tester.pump(); // the first frame of the slide
      await tester.pump(const Duration(milliseconds: 200));

      final from = expectedStart(0);
      final to = expectedStart(3);
      // An ease-out cubic is 87.5% of the way at half the time.
      expect(highlightStart(tester), closeTo(from + (to - from) * 0.875, 0.5));

      await tester.pump(const Duration(milliseconds: 200));
      expect(highlightStart(tester), closeTo(to, 0.01));
    });

    testWidgets('moves the square at once when animations are disabled', (
      tester,
    ) async {
      await pumpPinned(tester, disableAnimations: true);

      handle.enter('$_symbols', 3);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      expect(highlightStart(tester), closeTo(expectedStart(3), 0.01));
    });

    testWidgets('moves the square at once under instant motion', (
      tester,
    ) async {
      await pump(
        tester,
        arrangement: PanelArrangement.pointer,
        speed: ChromeMotionSpeed.instant,
      );

      handle.enter('$_symbols', 3);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      expect(highlightStart(tester), closeTo(expectedStart(3), 0.01));
    });

    testWidgets('paints nothing under a hovering mouse', (tester) async {
      await pumpPinned(tester);
      List<Color?> fills() => [
        for (final box in tester.widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(EmojiCategoryStrip),
            matching: find.byType(DecoratedBox),
          ),
        ))
          (box.decoration as BoxDecoration).color,
      ];
      final before = fills();

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.bySemanticsLabel('Symbols')));
      await tester.pump();

      expect(fills(), before);
    });

    testWidgets('shows the click cursor over an icon, and none under touch', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      MouseCursor? cursorOver(WidgetTester tester, Offset position) =>
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1);

      await pumpPinned(tester);
      final flags = tester.getCenter(find.bySemanticsLabel('Symbols'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: flags);
      addTearDown(mouse.removePointer);
      await tester.pump();
      expect(cursorOver(tester, flags), SystemMouseCursors.click);

      await pump(tester);
      await mouse.moveTo(flags + const Offset(0, 1));
      await tester.pump();
      expect(cursorOver(tester, flags), isNot(SystemMouseCursors.click));
      semantics.dispose();
    });

    testWidgets('a tap still lands on the category', (tester) async {
      await pumpPinned(tester);

      await _tapTab(tester, 'Symbols');

      expect(handle.jumps, ['$_symbols']);
    });

    testWidgets('scrolls only where the icons would get less than 33 px, and '
        'reveals the active one', (tester) async {
      await pumpPinned(tester, width: 100);

      handle.enter('$_symbols', 3);
      await tester.pumpAndSettle();

      // 4 icons of 33 px and 3 px insets: 138 px in a 100 px strip.
      expect(stripOffset(tester), 38);
    });

    testWidgets('does not scroll when the icons fit', (tester) async {
      await pumpPinned(tester);

      handle.enter('$_symbols', 3);
      await tester.pumpAndSettle();

      expect(stripOffset(tester), 0);
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
