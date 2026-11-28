/// The web's draft options menu: anchored at the strip with no scrim and no
/// preview, opened by hover after 200 ms with a mouse and by a tap with
/// touch, each choice reported at once, its dismiss paths, its side by
/// width class and its style by input class.
///
/// **Seam:** the link preview strip (`ComposerHeaderStrip`) wired to a
/// `DraftOptionsWebMenuController` the way a host wires it, with a
/// `RecordingDraftOptionsHost`, a `ManualComposerClock` and
/// `RecordingDiagnostics` installed.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_composer/src/view/composer_header_strip.dart';
import 'package:chat_composer/testing.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart' hide RichText;
import 'package:content_model/content_model.dart' as model show RichText;
import 'package:content_model/testing.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/composer_harness.dart';

final _url = Uri.parse('https://news.example/story?id=7');
final _other = Uri.parse('https://docs.example/guide');
const _photo = ContentDescriptor(key: ContentKey.external('p'));
final _page = LinkPreviewState.loaded(
  LinkPreview(url: _url, title: 'A story', photo: _photo),
);

void main() {
  late RecordingDiagnostics diagnostics;
  late RecordingDraftOptionsHost host;
  late ManualComposerClock clock;
  final strings = ChromeStringsPresets.english.composer.draftOptions;
  const hoverDelay = Duration(milliseconds: 200);

  setUp(() {
    diagnostics = RecordingDiagnostics.install();
    host = RecordingDraftOptionsHost();
    clock = ManualComposerClock(DateTime(2026, 11, 28));
  });

  /// Mounts the strip [stripWidth] wide (the window's when null) at the
  /// start of the bottom edge, wired to a menu controller; [inputClass]
  /// starts the input class scope.
  Future<DraftOptionsWebMenuController> mount(
    WidgetTester tester, {
    ChromeInputClass inputClass = ChromeInputClass.touch,
    double? stripWidth,
    DraftOptionsWebMenuPolicy menu = DraftOptionsWebMenuPolicy.standard,
  }) async {
    final controller = DraftOptionsWebMenuController(
      policy: DraftOptionsPolicy$Web(menu: menu),
      host: host,
      clock: clock,
      correlation: () => const ChatCorrelation(chatId: 'chat-1'),
      input: () => DraftOptionsInput(
        value: DraftLinkPart(options: LinkPreviewOptions(url: _url)),
        page: _page,
        text: const model.RichText.plain('Read this and that'),
        links: [_url, _other],
      ),
    );
    addTearDown(controller.dispose);
    final strip = ChromeInputClassScope(
      initial: inputClass,
      child: Builder(
        builder: (context) => ComposerHeaderStrip(
          header: ComposerHeader.linkPreview(
            url: _url,
            page: LinkPreview(url: _url, title: 'A story'),
            onOpen: (rect) => controller.open(context, rect),
            onHover: (rect) => controller.hover(context, rect),
          ),
        ),
      ),
    );
    await tester.pumpWidget(
      composerHarness(switch (stripWidth) {
        final width? => Align(
          alignment: AlignmentDirectional.centerStart,
          child: SizedBox(width: width, child: strip),
        ),
        null => strip,
      }),
    );
    return controller;
  }

  Finder strip() => find.byType(ComposerHeaderStrip);
  Finder menu() => find.byKey(DraftOptionsWebMenuController.menuKey);

  Future<void> tapStrip(WidgetTester tester) async {
    await tester.tap(strip(), warnIfMissed: false);
    await tester.pumpAndSettle();
  }

  /// Past the opening's guard, so a press lands on the catcher.
  void pastGuard() => clock.advance(ChromeTapTiming.repeatGuard);

  Future<TestGesture> mouseOver(WidgetTester tester, Offset at) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 1));
    await mouse.moveTo(at);
    await tester.pump();
    return mouse;
  }

  group('opening', () {
    testWidgets('a tap with touch opens a menu anchored at the strip, with '
        'no scrim, no overlay and no preview', (tester) async {
      await mount(tester);

      await tapStrip(tester);

      expect(menu(), findsOneWidget);
      expect(find.byType(ChromeScrim), findsNothing);
      expect(find.byType(DraftOptionsOverlay), findsNothing);
      for (final label in [
        strings.moveUp,
        strings.shrinkPhoto,
        strings.doNotPreview,
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      // No apply row: each choice applies at once.
      expect(find.text(strings.applyChanges), findsNothing);
      // No link choice in the menu, even with two links in the text.
      expect(find.text(strings.chooseLinkHint), findsNothing);
      final menuRect = tester.getRect(menu());
      final stripRect = tester.getRect(strip());
      expect(menuRect.bottom, stripRect.top - 8);
      expect(menuRect.right, stripRect.right - 8);
      expectChromeText(tester, within: menu());
      expect(
        diagnostics.whereOp(OverlayOp.webMenuOpened).single,
        isChatEvent(
          level: ChatEventLevel.debug,
          category: ChatEventCategory.overlay,
          correlation: const ChatCorrelation(chatId: 'chat-1'),
          fields: {
            'inputClass': 'touch',
            'widthClass': 'medium',
            'trigger': 'tap',
            'side': 'towardStart',
          },
        ),
      );
    });

    testWidgets('a mouse resting on the strip opens it after 200 ms', (
      tester,
    ) async {
      await mount(tester, inputClass: ChromeInputClass.mouse);

      await mouseOver(tester, tester.getCenter(strip()));
      clock.advance(hoverDelay - const Duration(milliseconds: 1));
      await tester.pumpAndSettle();
      expect(menu(), findsNothing);

      clock.advance(const Duration(milliseconds: 1));
      await tester.pumpAndSettle();

      expect(menu(), findsOneWidget);
      expect(
        diagnostics.whereOp(OverlayOp.webMenuOpened).single.fields,
        containsPair('trigger', 'hover'),
      );
      expect(
        diagnostics.whereOp(OverlayOp.webMenuOpened).single.fields,
        containsPair('inputClass', 'mouse'),
      );
    });

    testWidgets('a mouse leaving the strip before 200 ms opens nothing', (
      tester,
    ) async {
      await mount(tester, inputClass: ChromeInputClass.mouse);

      final mouse = await mouseOver(tester, tester.getCenter(strip()));
      clock.advance(const Duration(milliseconds: 150));
      await mouse.moveTo(const Offset(5, 5));
      await tester.pump();
      clock.advance(hoverDelay);
      await tester.pumpAndSettle();

      expect(menu(), findsNothing);
      expect(diagnostics.whereOp(OverlayOp.webMenuOpened), isEmpty);
    });

    testWidgets('a burst of taps on the strip opens one menu and leaves it '
        'up', (tester) async {
      final controller = await mount(tester);

      await tester.tap(strip(), warnIfMissed: false);
      await tester.pump();
      await tester.tap(strip(), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(menu(), findsOneWidget);
      expect(controller.isOpen, isTrue);
      expect(diagnostics.whereOp(OverlayOp.webMenuOpened), hasLength(1));
      expect(diagnostics.whereOp(OverlayOp.webMenuClosed), isEmpty);
    });

    testWidgets('denied link previews open no menu', (tester) async {
      final controller = await mount(tester);
      controller.linkPreviewsAllowed = false;

      await tapStrip(tester);

      expect(menu(), findsNothing);
      expect(diagnostics.whereOp(OverlayOp.openRefused).single.fields, {
        'why': 'denied',
      });
    });
  });

  group('choices', () {
    testWidgets('a choice is reported at once and closes the menu', (
      tester,
    ) async {
      await mount(tester);
      await tapStrip(tester);
      pastGuard();

      await tester.tap(find.text(strings.moveUp));
      await tester.pumpAndSettle();

      expect(host.edits.single.invertMedia, isTrue);
      expect(menu(), findsNothing);
      expect(diagnostics.whereOp(OverlayOp.editReported).single.fields, {
        'field': 'position',
        'mode': 'live',
      });
      expect(diagnostics.whereOp(OverlayOp.webMenuClosed).single.fields, {
        'trigger': 'choice',
      });
    });

    testWidgets('a burst of taps on a row applies once', (tester) async {
      await mount(tester);
      await tapStrip(tester);
      pastGuard();

      final row = tester.getCenter(find.text(strings.shrinkPhoto));
      await tester.tapAt(row);
      await tester.pump();
      await tester.tapAt(row);
      await tester.pumpAndSettle();

      expect(host.edits, hasLength(1));
      expect(host.edits.single.options.media, LinkPreviewMedia.small);
      expect(diagnostics.whereOp(OverlayOp.webMenuClosed), hasLength(1));
    });

    testWidgets('remove drops the preview and closes as a choice', (
      tester,
    ) async {
      await mount(tester);
      await tapStrip(tester);
      pastGuard();

      await tester.tap(find.text(strings.doNotPreview));
      await tester.pumpAndSettle();

      expect(host.edits.single.options.removed, isTrue);
      expect(menu(), findsNothing);
      expect(diagnostics.whereOp(OverlayOp.webMenuClosed).single.fields, {
        'trigger': 'choice',
      });
    });
  });

  group('dismissal', () {
    testWidgets('a press outside lands on the catcher and closes it', (
      tester,
    ) async {
      await mount(tester);
      await tapStrip(tester);
      pastGuard();

      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(menu(), findsNothing);
      expect(host.edits, isEmpty);
      expect(diagnostics.whereOp(OverlayOp.webMenuClosed).single.fields, {
        'trigger': 'outside',
      });
    });

    testWidgets('the close plays the reveal backwards over 200 ms', (
      tester,
    ) async {
      await mount(tester);
      await tapStrip(tester);
      pastGuard();

      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(menu(), findsOneWidget);
      final scale = tester.widget<ScaleTransition>(
        find.ancestor(of: menu(), matching: find.byType(ScaleTransition)),
      );
      expect(scale.scale.value, inExclusiveRange(0.8, 1));

      await tester.pump(const Duration(milliseconds: 101));
      expect(menu(), findsNothing);
    });

    testWidgets('a mouse leaving the strip and the menu closes it after the '
        'grace', (tester) async {
      await mount(tester, inputClass: ChromeInputClass.mouse);
      final mouse = await mouseOver(tester, tester.getCenter(strip()));
      clock.advance(hoverDelay);
      await tester.pumpAndSettle();
      expect(menu(), findsOneWidget);

      await mouse.moveTo(const Offset(20, 20));
      await tester.pump();
      clock.advance(DraftOptionsWebMenuPolicy.standard.leaveGrace);
      await tester.pumpAndSettle();

      expect(menu(), findsNothing);
      expect(diagnostics.whereOp(OverlayOp.webMenuClosed).single.fields, {
        'trigger': 'leave',
      });
    });

    testWidgets('a mouse moving from the strip into the menu keeps it open', (
      tester,
    ) async {
      await mount(tester, inputClass: ChromeInputClass.mouse);
      final mouse = await mouseOver(tester, tester.getCenter(strip()));
      clock.advance(hoverDelay);
      await tester.pumpAndSettle();

      await mouse.moveTo(tester.getCenter(menu()));
      await tester.pump();
      clock.advance(DraftOptionsWebMenuPolicy.standard.leaveGrace * 2);
      await tester.pumpAndSettle();

      expect(menu(), findsOneWidget);
      expect(diagnostics.whereOp(OverlayOp.webMenuClosed), isEmpty);
    });

    testWidgets('a secondary click closes it', (tester) async {
      await mount(tester, inputClass: ChromeInputClass.mouse);
      final mouse = await mouseOver(tester, tester.getCenter(strip()));
      clock.advance(hoverDelay);
      await tester.pumpAndSettle();
      pastGuard();

      await mouse.removePointer();
      final secondary = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryButton,
      );
      await secondary.down(tester.getCenter(menu()));
      await secondary.up();
      await secondary.removePointer();
      await tester.pumpAndSettle();

      expect(host.edits, isEmpty);

      expect(menu(), findsNothing);
      expect(diagnostics.whereOp(OverlayOp.webMenuClosed).single.fields, {
        'trigger': 'secondaryClick',
      });
    });

    testWidgets('denied link previews close it, then report the preview '
        'removed', (tester) async {
      final controller = await mount(tester);
      await tapStrip(tester);

      controller.linkPreviewsAllowed = false;
      await tester.pump();
      expect(host.edits, isEmpty);
      await tester.pumpAndSettle();

      expect(menu(), findsNothing);
      expect(host.edits.single.options.removed, isTrue);
      expect(diagnostics.whereOp(OverlayOp.webMenuClosed).single.fields, {
        'trigger': 'denied',
      });
    });
  });

  group('layout by width class', () {
    // Compact mouse rows, so the menu fits on either side of the anchor at
    // these widths and the preferred side is the one taken.
    Future<Rect> menuAt(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await mount(tester, inputClass: ChromeInputClass.mouse, stripWidth: 308);
      await tester.tap(strip(), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      return tester.getRect(menu());
    }

    double anchor(WidgetTester tester) => tester.getRect(strip()).right - 8;

    testWidgets('at 600 wide it opens toward the end of the anchor', (
      tester,
    ) async {
      final rect = await menuAt(tester, 600);

      expect(rect.left, anchor(tester));
      expect(
        diagnostics.whereOp(OverlayOp.webMenuOpened).single.fields,
        containsPair('side', 'towardEnd'),
      );
    });

    testWidgets('at 601 wide it opens toward the start', (tester) async {
      final rect = await menuAt(tester, 601);

      expect(rect.right, anchor(tester));
      expect(
        diagnostics.whereOp(OverlayOp.webMenuOpened).single.fields,
        containsPair('widthClass', 'medium'),
      );
    });

    testWidgets('a resize across 600 moves an open menu to the other side', (
      tester,
    ) async {
      final wide = await menuAt(tester, 900);
      expect(wide.right, anchor(tester));

      tester.view.physicalSize = const Size(590, 800);
      await tester.pumpAndSettle();

      expect(tester.getRect(menu()).left, anchor(tester));
    });
  });

  group('style by input class', () {
    testWidgets('touch: a solid surface with 48 rows in 16 text', (
      tester,
    ) async {
      await mount(tester);
      await tapStrip(tester);

      expect(tester.widget(menu()), isA<DecoratedBox>());
      final row = find.ancestor(
        of: find.text(strings.moveUp),
        matching: find.byType(DraftLinkRowView),
      );
      expect(tester.getSize(row).height, 48);
      expect(
        tester.widget<Text>(find.text(strings.moveUp)).style?.fontSize,
        16,
      );
      final ink = tester.widget<ChromeInk>(
        find.descendant(of: row, matching: find.byType(ChromeInk)),
      );
      expect(ink.kind, ChromeInkKind.ripple);
    });

    testWidgets('mouse: menu glass with compact rows and pointer presses', (
      tester,
    ) async {
      await mount(tester, inputClass: ChromeInputClass.mouse);
      await mouseOver(tester, tester.getCenter(strip()));
      clock.advance(hoverDelay);
      await tester.pumpAndSettle();

      final glass = tester.widget<GlassSurface>(menu());
      expect(glass.material, GlassMaterial.menu);
      final row = find.ancestor(
        of: find.text(strings.moveUp),
        matching: find.byType(DraftLinkRowView),
      );
      expect(tester.getSize(row).height, 36);
      final ink = tester.widget<ChromeInk>(
        find.descendant(of: row, matching: find.byType(ChromeInk)),
      );
      expect(ink.kind, ChromeInkKind.pointer);
      expectChromeText(tester, within: menu());
    });
  });
}
