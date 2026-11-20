import 'dart:async';

import 'package:attach_model/testing.dart';
import 'package:attach_sheet/attach_sheet.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pages_rig.dart';

void main() {
  const android = AttachSheetPolicy.android();
  const ios = AttachSheetPolicy.ios();

  group('registry', () {
    test('keeps the host order and starts on the first page', () {
      final registry = AttachPageRegistry([
        rowsPage('gallery'),
        rowsPage('files'),
        rowsPage('location'),
      ]);
      expect(registry.pages.map((p) => p.id), [
        AttachPageId.gallery,
        AttachPageId.files,
        const AttachPageId('location'),
      ]);
      expect(registry.initial, AttachPageId.gallery);
    });

    test('starts on the page the host names', () {
      final registry = AttachPageRegistry([
        rowsPage('gallery'),
        rowsPage('files'),
      ], initial: AttachPageId.files);
      expect(registry.initial, AttachPageId.files);
    });

    test('refuses an empty list, a repeated id or an unknown initial page', () {
      expect(() => AttachPageRegistry(const []), throwsArgumentError);
      expect(
        () => AttachPageRegistry([rowsPage('a'), rowsPage('a')]),
        throwsArgumentError,
      );
      expect(
        () => AttachPageRegistry([
          rowsPage('a'),
        ], initial: const AttachPageId('b')),
        throwsArgumentError,
      );
    });
  });

  group('tabs', () {
    testWidgets('one tab per page, in order', (tester) async {
      final rig = await PagesRig.open(
        tester,
        policy: android,
        pages: [rowsPage('gallery'), rowsPage('files'), rowsPage('music')],
      );
      final xs = [
        for (final id in ['gallery', 'files', 'music'])
          tester.getCenter(rig.tab(id)).dx,
      ];
      expect(xs, orderedEquals([...xs]..sort()));
      expect(rig.shows('gallery'), isTrue);
    });

    testWidgets('a tap switches the page', (tester) async {
      final rig = await PagesRig.open(
        tester,
        policy: android,
        pages: [rowsPage('gallery'), rowsPage('files')],
      );
      await rig.tapTab('files');
      expect(rig.shows('files'), isTrue);
      expect(rig.shows('gallery'), isFalse);
    });

    testWidgets('a single tab collapses the row', (tester) async {
      final rig = await PagesRig.open(
        tester,
        policy: ios,
        pages: [rowsPage('gallery')],
      );
      expect(rig.tab('gallery'), findsNothing);
      expect(rig.shows('gallery'), isTrue);
    });

    testWidgets('the tab bar hides while the selection is not empty', (
      tester,
    ) async {
      final rig = await PagesRig.open(
        tester,
        policy: android,
        pages: [rowsPage('gallery'), rowsPage('files')],
      );
      double shown() => tester
          .widget<GlassSurface>(
            find.byKey(const ValueKey('attach-tab-bar-glass')),
          )
          .opacity;
      expect(shown(), 1);

      rig.selection.toggle(AttachItems.photo('p'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(shown(), inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(shown(), 0);

      rig.selection.clear();
      await tester.pumpAndSettle();
      expect(shown(), 1);
    });

    testWidgets('re-tapping the shown tab scrolls its page to the top and '
        'expands the sheet', (tester) async {
      late AttachPageScope gallery;
      final rig = await PagesRig.open(
        tester,
        policy: ios,
        pages: [
          rowsPage('gallery', onScope: (s) => gallery = s),
          rowsPage('files'),
        ],
      );
      rig.tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(300);
      await tester.pump();

      await rig.tapTab('gallery');

      expect(gallery.scrollController.offset, 0);
      expect(rig.top, 24);
    });
  });

  group('hooks', () {
    testWidgets('a page asks the sheet to expand', (tester) async {
      late AttachPageScope scope;
      final rig = await PagesRig.open(
        tester,
        policy: android,
        pages: [rowsPage('gallery', onScope: (s) => scope = s)],
      );
      scope.requestExpansion();
      await tester.pumpAndSettle();
      expect(rig.top, 24);
    });

    testWidgets('a tab switch takes the sheet to the height the new page had, '
        'on the page spring, with the new page coming in', (tester) async {
      late AttachPageScope gallery;
      final rig = await PagesRig.open(
        tester,
        policy: ios,
        pages: [
          rowsPage('gallery', onScope: (s) => gallery = s),
          rowsPage('files'),
        ],
      );
      final rest = rig.top;
      gallery.requestExpansion();
      await tester.pumpAndSettle();
      expect(rig.top, 24);

      // Files was never raised: the sheet goes down to its rest as Files
      // comes in, after the old page has left (180 ms).
      await rig.tapTab('files');
      expect(rig.top, closeTo(rest, 0.5));

      // Gallery was at the top when left: back there.
      await rig.tapTab('gallery');
      expect(rig.top, 24);
    });

    testWidgets('Android: the tab bar leaves while the sheet is at its top '
        '(380 ms, ease out quint) and comes back as it goes down', (
      tester,
    ) async {
      late AttachPageScope gallery;
      final rig = await PagesRig.open(
        tester,
        policy: android,
        pages: [
          rowsPage('gallery', onScope: (s) => gallery = s),
          rowsPage('files'),
        ],
      );
      double opacity() => tester
          .widget<GlassSurface>(
            find.byKey(const ValueKey('attach-tab-bar-glass')),
          )
          .opacity;
      expect(opacity(), 1);
      gallery.requestExpansion();
      await tester.pumpAndSettle();
      expect(rig.top, 24);
      expect(opacity(), 0);

      final sheet = AttachSheetController.of(
        tester.element(find.byKey(const ValueKey('gallery-row-0'))),
      );
      unawaited(sheet.collapse());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(rig.top, greaterThan(24));
      await tester.pump(const Duration(milliseconds: 100));
      expect(opacity(), inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(opacity(), 1);
    });

    testWidgets('iOS: the tab bar stays at the top', (tester) async {
      late AttachPageScope gallery;
      final rig = await PagesRig.open(
        tester,
        policy: ios,
        pages: [
          rowsPage('gallery', onScope: (s) => gallery = s),
          rowsPage('files'),
        ],
      );
      gallery.requestExpansion();
      await tester.pumpAndSettle();
      expect(rig.tab('files').hitTestable(), findsOneWidget);
    });

    testWidgets('a page too short to scroll still drags the sheet down and '
        'closes it', (tester) async {
      final rig = await PagesRig.open(
        tester,
        policy: android,
        pages: [
          AttachPage(
            id: const AttachPageId('short'),
            label: 'short',
            icon: const SizedBox(width: 24, height: 24),
            kind: AttachPageKind.selection,
            builder: (context, scope) => ListView(
              controller: scope.scrollController,
              children: const [SizedBox(key: ValueKey('row'), height: 50)],
            ),
          ),
        ],
      );
      final rest = rig.top;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('row'))),
      );
      await gesture.moveBy(const Offset(0, 20));
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      expect(rig.top, greaterThan(rest + 30), reason: 'it follows the drag');
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, 30));
        await tester.pump();
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(rig.outcome, isA<AttachOutcome$Cancelled>());
    });

    testWidgets('a page moves the resting height', (tester) async {
      late AttachPageScope scope;
      final rig = await PagesRig.open(
        tester,
        policy: android,
        pages: [rowsPage('gallery', onScope: (s) => scope = s)],
      );
      scope.topOffset = 500;
      await tester.pumpAndSettle();
      expect(rig.top, 500);
    });

    testWidgets('a page turns the pan off', (tester) async {
      late AttachPageScope scope;
      final rig = await PagesRig.open(
        tester,
        policy: android,
        pages: [rowsPage('gallery', onScope: (s) => scope = s)],
      );
      final rest = rig.top;
      scope.panEnabled = false;
      await tester.drag(
        find.byKey(const ValueKey('gallery-row-1')),
        const Offset(0, -100),
      );
      await tester.pumpAndSettle();
      expect(rig.top, rest);
    });

    testWidgets('a page header shows in the pinned header', (tester) async {
      late AttachPageScope scope;
      await PagesRig.open(
        tester,
        policy: android,
        pages: [rowsPage('gallery', onScope: (s) => scope = s)],
      );
      scope.headerItems = const Text('Albums', key: ValueKey('albums'));
      await tester.pump();
      expect(find.byKey(const ValueKey('albums')), findsOneWidget);
    });

    testWidgets('a dismiss guard can keep the sheet open', (tester) async {
      late AttachPageScope scope;
      final rig = await PagesRig.open(
        tester,
        policy: android,
        pages: [rowsPage('gallery', onScope: (s) => scope = s)],
      );
      var asked = 0;
      scope.dismissGuard = () async {
        asked++;
        return false;
      };
      await tester.tapAt(const Offset(200, 60));
      await tester.pumpAndSettle();
      expect(asked, 1);
      expect(rig.outcome, isNull);

      scope.dismissGuard = null;
      await tester.tapAt(const Offset(200, 60));
      await tester.pumpAndSettle();
      expect(rig.outcome, const AttachOutcome.cancelled());
    });

    testWidgets('active follows the shown tab; onShow and onHide', (
      tester,
    ) async {
      final scopes = <String, AttachPageScope>{};
      final rig = await PagesRig.open(
        tester,
        policy: android,
        pages: [
          rowsPage('gallery', onScope: (s) => scopes['gallery'] = s),
          rowsPage('files', onScope: (s) => scopes['files'] = s),
        ],
      );
      final events = <String>[];
      scopes['gallery']!.isActive.addListener(
        () => events.add('gallery ${scopes['gallery']!.isActive.value}'),
      );
      expect(scopes['gallery']!.isActive.value, isTrue);

      await rig.tapTab('files');
      expect(scopes['gallery']!.isActive.value, isFalse);
      expect(scopes['files']!.isActive.value, isTrue);

      await rig.tapTab('gallery');
      expect(events, ['gallery false', 'gallery true']);
    });
  });

  group('host pages', () {
    testWidgets('are built once and reused within one open', (tester) async {
      final builds = <String>[];
      final rig = await PagesRig.open(
        tester,
        policy: android,
        pages: [
          rowsPage('gallery', builds: builds),
          rowsPage('poll', kind: AttachPageKind.host, builds: builds),
        ],
      );
      await rig.tapTab('poll');
      await rig.tapTab('gallery');
      await rig.tapTab('poll');
      expect(builds.where((b) => b == 'poll'), hasLength(1));
    });

    testWidgets('finish hands the payload to the host', (tester) async {
      late AttachPageScope scope;
      final rig = await PagesRig.open(
        tester,
        policy: android,
        pages: [
          rowsPage('gallery'),
          rowsPage(
            'location',
            kind: AttachPageKind.host,
            onScope: (s) => scope = s,
          ),
        ],
      );
      await rig.tapTab('location');
      scope.finish(const {'lat': 1, 'lng': 2});
      await tester.pumpAndSettle();
      expect(
        rig.outcome,
        const AttachOutcome.custom(AttachPageId('location'), {
          'lat': 1,
          'lng': 2,
        }),
      );
    });

    testWidgets('a main button replaces the tabs', (tester) async {
      late AttachPageScope scope;
      final rig = await PagesRig.open(
        tester,
        policy: android,
        pages: [
          rowsPage('gallery'),
          rowsPage('bot', kind: AttachPageKind.host, onScope: (s) => scope = s),
        ],
      );
      await rig.tapTab('bot');
      var pressed = 0;
      scope.mainButton = AttachMainButton(
        label: 'Continue',
        onPressed: () => pressed++,
      );
      await tester.pumpAndSettle();
      expect(find.text('Continue'), findsOneWidget);
      expect(rig.tab('gallery'), findsNothing);

      await tester.tap(find.text('Continue'));
      expect(pressed, 1);

      scope.mainButton = null;
      await tester.pumpAndSettle();
      expect(rig.tab('gallery'), findsOneWidget);
    });
  });

  group('permission badge', () {
    testWidgets('Android marks a tab missing its permission; a tap asks', (
      tester,
    ) async {
      final granted = ValueNotifier(false);
      addTearDown(granted.dispose);
      var requests = 0;
      final rig = await PagesRig.open(
        tester,
        policy: android,
        pages: [
          rowsPage('gallery'),
          rowsPage(
            'music',
            permission: AttachPagePermission(
              granted: granted,
              request: () async => requests++,
            ),
          ),
        ],
      );
      expect(
        find.descendant(
          of: rig.tab('music'),
          matching: find.byKey(const ValueKey('attach-tab-badge')),
        ),
        findsOneWidget,
      );

      await rig.tapTab('music');
      expect(requests, 1);
      expect(rig.shows('gallery'), isTrue);

      granted.value = true;
      await tester.pump();
      expect(find.byKey(const ValueKey('attach-tab-badge')), findsNothing);
      await rig.tapTab('music');
      expect(rig.shows('music'), isTrue);
    });

    testWidgets('iOS shows no badge and switches', (tester) async {
      final granted = ValueNotifier(false);
      addTearDown(granted.dispose);
      final rig = await PagesRig.open(
        tester,
        policy: ios,
        pages: [
          rowsPage('gallery'),
          rowsPage(
            'music',
            permission: AttachPagePermission(
              granted: granted,
              request: () async {},
            ),
          ),
        ],
      );
      expect(find.byKey(const ValueKey('attach-tab-badge')), findsNothing);
      await rig.tapTab('music');
      expect(rig.shows('music'), isTrue);
    });
  });
}
