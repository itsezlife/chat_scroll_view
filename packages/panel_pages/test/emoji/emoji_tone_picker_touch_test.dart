/// The tone picker a finger opens: the reference mobile client's, a card with
/// an arrow under the pressed emoji, its options followed by the finger, with
/// haptics.
///
/// **Seam:** [EmojiPage] under the touch arrangement with the fixture source,
/// a fake host and preferences, long-pressed with a finger, observed through
/// where the picker is, what it marks, the picks and preferences, and the
/// haptic calls on the platform channel. Geometry: 8 columns of 43.75 x 45
/// cells in a 360 x 480 page, the 36 px strip and the 50 px field above.
library;

import 'package:catalog_assets/catalog_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_pages/panel_pages.dart';
import 'package:panel_pages/testing.dart';
import 'package:panel_shell/testing.dart';

import 'emoji_fixtures.dart' as fixtures;

void main() {
  late FakeCollectionSource source;
  late FakeSearchSource search;
  late FakePreferenceStore preferences;
  late FakePanelPageHost host;
  late AssetCacheScope assets;
  late List<String> haptics;

  setUp(() {
    source = fixtures.source(count: 0);
    search = FakeSearchSource({});
    preferences = FakePreferenceStore();
    host = FakePanelPageHost(pageId: 'emoji');
    assets = PageAssets.createScope();
    haptics = [];
    addTearDown(() {
      source.dispose();
      search.dispose();
      preferences.dispose();
      host.dispose();
      assets.dispose();
    });
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add('${call.arguments}');
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      PanelShellTestScope(
        child: FakeSearchFieldScope(
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (context) => Center(
                  child: SizedBox(
                    width: 360,
                    height: 480,
                    child: EmojiPage(
                      host: host,
                      source: source,
                      searchSource: search,
                      preferences: preferences,
                      entryOf: fixtures.entryOf,
                      assets: assets,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The cell at [column] of the first row of the section whose header starts
  // [top] px under the strip and the field.
  Rect cell(WidgetTester tester, {required double top, int column = 0}) {
    final origin = tester.getTopLeft(find.byType(EmojiPage));
    return Rect.fromLTWH(
      origin.dx + 5 + 43.75 * column,
      origin.dy + 36 + 50 + top + 27,
      43.75,
      45,
    );
  }

  // 👍 is the first cell of the people section (after the smileys' row), 💑
  // the third.
  const peopleTop = 72.0;

  Finder picker() => find.byType(EmojiTonePicker);

  Future<TestGesture> longPress(WidgetTester tester, Rect at) async {
    final finger = await tester.startGesture(at.center);
    await tester.pump(const Duration(milliseconds: 700));
    return finger;
  }

  group('one person', () {
    testWidgets('a card of the emoji as it is and its five tones, its arrow '
        'on the glyph\'s top, the current tone over the pressed glyph', (
      tester,
    ) async {
      await pumpPage(tester);
      final thumb = cell(tester, top: peopleTop);

      final finger = await longPress(tester, thumb);

      final box = tester.getRect(picker());
      expect(box.size, const Size(222, 47));
      // Nothing chosen yet: the emoji as it is (option 0) is over the glyph.
      expect(box.left + 5, thumb.left + 6);
      expect(box.bottom, thumb.top + (45 - 32) / 2);
      expect(tester.widget<EmojiTonePicker>(picker()).marked, 0);
      await finger.up();
    });

    testWidgets('puts a chosen tone over the pressed glyph', (tester) async {
      await preferences.setPreferredVariant(
        fixtures.thumbsUp.base,
        fixtures.thumbsUp.variants[2].key,
      );
      await pumpPage(tester);
      final thumb = cell(tester, top: peopleTop);

      final finger = await longPress(tester, thumb);

      // Option 3 (the third tone) sits at 5 + 36 * 3 in the card.
      expect(tester.getRect(picker()).left + 5 + 36 * 3, thumb.left + 6);
      expect(tester.widget<EmojiTonePicker>(picker()).marked, 3);
      await finger.up();
    });

    testWidgets('the finger moves the selection in 36 px steps once it has '
        'left a small slop, and lifting it picks and remembers', (
      tester,
    ) async {
      await pumpPage(tester);
      final thumb = cell(tester, top: peopleTop);
      final finger = await longPress(tester, thumb);

      await finger.moveBy(const Offset(8, 0));
      await tester.pump();
      expect(
        tester.widget<EmojiTonePicker>(picker()).marked,
        0,
        reason: 'inside the slop',
      );

      await finger.moveTo(thumb.center + const Offset(36 * 3, 0));
      await tester.pump();
      expect(tester.widget<EmojiTonePicker>(picker()).marked, 3);

      await finger.up();
      await tester.pump(const Duration(milliseconds: 300));
      final chosen = fixtures.thumbsUp.variants[2].key;
      expect(host.picks.single.key, chosen);
      expect(preferences.preferredVariant(fixtures.thumbsUp.base), chosen);
      expect(picker(), findsNothing);
    });

    // As Flutter maps them on Android: the long press of the reference client
    // is `vibrate` (no type), its cursor tick `selectionClick`, its key tap
    // `mediumImpact`.
    testWidgets('a long-press buzz on open, a tick per change and a key tap '
        'on the choice', (tester) async {
      await pumpPage(tester);
      final thumb = cell(tester, top: peopleTop);

      final finger = await longPress(tester, thumb);
      expect(haptics, ['null']);

      await finger.moveTo(thumb.center + const Offset(36, 0));
      await tester.pump();
      await finger.moveTo(thumb.center + const Offset(72, 0));
      await tester.pump();
      expect(haptics.skip(1), [
        'HapticFeedbackType.selectionClick',
        'HapticFeedbackType.selectionClick',
      ]);

      await finger.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(haptics.last, 'HapticFeedbackType.mediumImpact');
    });

    testWidgets('slides the mark to the next option over 125 ms', (
      tester,
    ) async {
      await pumpPage(tester);
      final thumb = cell(tester, top: peopleTop);
      final finger = await longPress(tester, thumb);

      await finger.moveTo(thumb.center + const Offset(36, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final mark = tester.getRect(find.byKey(EmojiTonePicker.markKey));
      final box = tester.getRect(picker());
      // From option 0 (3 px in) towards option 1 (39 px in), 36 x 36.
      expect(mark.size, const Size(36, 36));
      expect(mark.left - box.left, inExclusiveRange(3, 39));

      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tester.getRect(find.byKey(EmojiTonePicker.markKey)).left - box.left,
        39,
      );
      await finger.up();
    });
  });

  group('two people', () {
    // Option [tone] of row [row] (0 or 1), relative to the picker.
    Offset compound(WidgetTester tester, int row, int tone) =>
        tester.getTopLeft(picker()) +
        Offset(
          32.0 * (1 + tone) + 8 + 4 * (1 + tone) + 16,
          3 + 33.0 * row + 16,
        );

    testWidgets('a card of the emoji as it is beside a row of tones per '
        'person, which stays when the finger lifts', (tester) async {
      await pumpPage(tester);
      final couple = cell(tester, top: peopleTop, column: 2);

      final finger = await longPress(tester, couple);
      expect(tester.getSize(picker()).width, 225);
      expect(tester.getSize(picker()).height, closeTo(75.66, 0.01));

      await finger.up();
      await tester.pump(const Duration(milliseconds: 300));
      expect(picker(), findsOneWidget);
      expect(host.picks, isEmpty);
    });

    testWidgets('every tone of a row shows the emoji, the other person '
        'greyed; both in one tone is the one-tone sequence', (tester) async {
      await pumpPage(tester);
      final hands = cell(tester, top: peopleTop, column: 3);
      final finger = await longPress(tester, hands);
      await finger.up();
      await tester.pump(const Duration(milliseconds: 300));

      final rows = tester.widget<EmojiTonePicker>(picker()).rowOptions!;
      for (final row in rows) {
        expect(row, [
          for (final tone in [
            '\u{1F3FB}',
            '\u{1F3FC}',
            '\u{1F3FD}',
            '\u{1F3FE}',
            '\u{1F3FF}',
          ])
            fixtures.key('🤝$tone'),
        ]);
      }
      expect(
        find.descendant(of: picker(), matching: find.byType(ColorFiltered)),
        findsNWidgets(10),
        reason: 'one greyed person per tone',
      );

      // Both in the same tone is the one-tone sequence.
      await tester.tapAt(compound(tester, 0, 2));
      await tester.pump();
      expect(
        preferences.preferredVariant(fixtures.handshake.base),
        fixtures.key('🤝\u{1F3FD}'),
      );
      await tester.tapAt(compound(tester, 1, 4));
      await tester.pump();
      expect(
        preferences.preferredVariant(fixtures.handshake.base),
        fixtures.key('🫱\u{1F3FD}\u200D🫲\u{1F3FF}'),
      );
    });

    testWidgets('a tap on a row sets that person\'s tone and keeps the '
        'choice at once; a tone for one person alone is given to both', (
      tester,
    ) async {
      await pumpPage(tester);
      final couple = cell(tester, top: peopleTop, column: 2);
      final finger = await longPress(tester, couple);
      await finger.up();
      await tester.pump(const Duration(milliseconds: 300));
      ContentKey$Unicode? chosen() =>
          preferences.preferredVariant(fixtures.couple.base);

      await tester.tapAt(compound(tester, 0, 1));
      await tester.pump();
      expect(chosen(), fixtures.key('💑\u{1F3FC}\u{1F3FC}'));

      await tester.tapAt(compound(tester, 1, 0));
      await tester.pump();
      expect(chosen(), fixtures.key('💑\u{1F3FC}\u{1F3FB}'));
      expect(host.picks, isEmpty, reason: 'nothing is inserted');

      // A press outside closes it.
      await tester.tapAt(tester.getTopLeft(find.byType(EmojiPage)));
      await tester.pumpAndSettle();
      expect(picker(), findsNothing);
    });
  });
}
