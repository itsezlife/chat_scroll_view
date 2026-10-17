/// The tooltip of the reference desktop client over the emoji grid: the code
/// of the emoji a mouse rests on, a second after it got there, by the cursor,
/// until the mouse moves on or leaves.
///
/// **Seam:** a `PanelShell` under `PanelArrangement.pointer` over an
/// [EmojiPage] whose items carry shortcodes, driven by a mouse (and a finger,
/// for the contrast) and observed through the text on screen and where it is.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_catalog/panel_catalog.dart';
import 'package:panel_catalog/src/viewport/render_panel_catalog.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

import 'emoji_fixtures.dart' as fixtures;

const _second = Duration(seconds: 1);
const _frame = Duration(milliseconds: 16);

CollectionItem _coded(String glyph, String? shortcode) =>
    CollectionItem.described(
      ContentDescriptor(
        key: fixtures.key(glyph),
        semanticKind: SemanticKind.unicodeEmoji,
        mediaForm: MediaForm.glyph,
        shortcode: shortcode,
      ),
    );

void main() {
  late FakePreferenceStore preferences;
  late FakeCollectionSource source;
  late FakeSearchSource search;
  late AssetCacheScope assets;
  late PanelShellController shell;

  setUp(() {
    preferences = FakePreferenceStore();
    source = FakeCollectionSource([
      const FakeCollectionSpec(
        CollectionId.recent,
        pages: FakePages([<CollectionItem>[]]),
      ),
      FakeCollectionSpec(
        const CollectionId.category('people'),
        pages: FakePages([
          [
            _coded('😀', ':grinning:'),
            _coded('😃', ':smiley:'),
            _coded('❤', null),
            for (var i = 0; i < 30; i++)
              _coded(String.fromCharCode(0x1F400 + i), null),
          ],
        ]),
      ),
    ]);
    search = FakeSearchSource({});
    assets = PageAssets.createScope();
  });

  tearDown(() {
    shell.dispose();
    source.dispose();
    search.dispose();
    assets.dispose();
  });

  Future<void> pumpShell(WidgetTester tester) async {
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
      ],
      preferences: preferences,
    );
    await tester.pumpWidget(
      PanelShellTestScope(
        child: Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (context) => PanelShell(
                controller: shell,
                announcer: FakePanelAnnouncer(),
                arrangement: PanelArrangement.pointer,
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The global centre of the cell showing [glyph], found by asking the grid
  // what lies under points of its box.
  Offset centerOf(WidgetTester tester, String glyph) {
    final grid = find.byType(PanelCatalogViewport);
    final render = tester.renderObject<RenderPanelCatalog>(grid);
    final box = tester.getRect(grid);
    final key = fixtures.key(glyph);
    Rect? cell;
    for (var y = 0.0; y < box.height; y += 2) {
      for (var x = 0.0; x < box.width; x += 2) {
        if (render.leafAt(Offset(x, y))?.leaf.key != key) continue;
        cell = cell == null
            ? Rect.fromLTWH(x, y, 0, 0)
            : cell.expandToInclude(Rect.fromLTWH(x, y, 0, 0));
      }
    }
    expect(cell, isNotNull, reason: '$glyph is on screen');
    return box.topLeft + cell!.center;
  }

  Future<TestGesture> mouseAt(WidgetTester tester, Offset position) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(position);
    await tester.pump();
    return mouse;
  }

  testWidgets('a mouse resting on an emoji for a second shows its code, '
      'below and before the cursor', (tester) async {
    await pumpShell(tester);
    final at = centerOf(tester, '😀');
    await mouseAt(tester, at);

    await tester.pump(_second - _frame);
    expect(find.text(':grinning:'), findsNothing);

    await tester.pump(_frame);
    expect(find.text(':grinning:'), findsOneWidget);
    // The box: 1 px edge and 5 px padding before the text, 20 px left of the
    // cursor; 1 px edge and 2 px padding above it, 20 px below the cursor.
    expect(
      tester.getTopLeft(find.text(':grinning:')),
      at + const Offset(-20 + 1 + 5, 20 + 1 + 2),
    );
  });

  testWidgets('moving more than 10 px from where it showed hides it; less '
      'does not', (tester) async {
    await pumpShell(tester);
    final mouse = await mouseAt(tester, centerOf(tester, '😀'));
    await tester.pump(_second);

    await mouse.moveBy(const Offset(4, 4));
    await tester.pump();
    expect(find.text(':grinning:'), findsOneWidget);

    await mouse.moveBy(const Offset(-1, 4));
    await tester.pump();
    expect(find.text(':grinning:'), findsNothing);

    // Still on the same emoji: nothing new to say.
    await tester.pump(_second * 2);
    expect(find.text(':grinning:'), findsNothing);
  });

  testWidgets('the next emoji shows its own code a second after the mouse '
      'reached it', (tester) async {
    await pumpShell(tester);
    final mouse = await mouseAt(tester, centerOf(tester, '😀'));
    await tester.pump(_second);

    await mouse.moveTo(centerOf(tester, '😃'));
    await tester.pump(_second - _frame);
    expect(find.text(':grinning:'), findsNothing);
    expect(find.text(':smiley:'), findsNothing);

    await tester.pump(_frame);
    expect(find.text(':smiley:'), findsOneWidget);
  });

  testWidgets('an emoji the data has no code for shows nothing', (
    tester,
  ) async {
    await pumpShell(tester);
    await mouseAt(tester, centerOf(tester, '❤'));

    await tester.pump(_second * 2);

    expect(find.textContaining(':'), findsNothing);
  });

  testWidgets('the mouse leaving the grid hides it, and a mouse that left '
      'before the second shows nothing', (tester) async {
    await pumpShell(tester);
    final mouse = await mouseAt(tester, centerOf(tester, '😀'));
    await tester.pump(_second);
    expect(find.text(':grinning:'), findsOneWidget);

    await mouse.moveTo(const Offset(-50, -50));
    await tester.pump();
    expect(find.text(':grinning:'), findsNothing);

    await mouse.moveTo(centerOf(tester, '😀'));
    await tester.pump(_second ~/ 2);
    await mouse.moveTo(const Offset(-50, -50));
    await tester.pump(_second);
    expect(find.text(':grinning:'), findsNothing);
  });

  testWidgets('a finger held on an emoji shows nothing', (tester) async {
    await pumpShell(tester);

    final finger = await tester.startGesture(centerOf(tester, '😀'));
    await tester.pump(_second * 2);
    expect(find.text(':grinning:'), findsNothing);
    await finger.up();
    await tester.pumpAndSettle();
  });
}
