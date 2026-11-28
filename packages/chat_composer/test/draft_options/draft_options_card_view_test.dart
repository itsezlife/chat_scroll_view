/// The Android presentation of the draft options overlay: the card and its
/// glass menu placed in the window, portrait and landscape; the open, close
/// and change motion on the test clock; the dismissal paths (a tap on lift
/// outside, the band above the card's visible top, back); reduce motion;
/// and the `motion` events.
///
/// **Seam:** `DraftOptionsController` with the Android policy opened in a
/// window of a set size, under the composer's scopes, with a
/// `RecordingDraftOptionsHost` and `RecordingDiagnostics` installed.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_composer/testing.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart' hide RichText;
import 'package:content_model/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/composer_harness.dart';

final _url = Uri.parse('https://news.example/story?id=7');
final _initial = DraftLinkPart(options: LinkPreviewOptions(url: _url));
final _loaded = LinkPreviewState.loaded(
  LinkPreview(url: _url, siteName: 'Example News', title: 'A story'),
);

const _card = DraftOptionsCardLayout.android;

void main() {
  late RecordingDiagnostics diagnostics;
  late RecordingDraftOptionsHost host;
  late ManualComposerClock clock;

  setUp(() {
    diagnostics = RecordingDiagnostics.install();
    host = RecordingDraftOptionsHost();
    clock = ManualComposerClock(DateTime(2026, 11, 28));
  });

  /// A bubble [height] tall, taller when the card is above the text by
  /// [aboveExtra].
  DraftOptionsBubbleBuilder bubbleOf({
    double height = 120,
    double aboveExtra = 0,
  }) =>
      (context, preview) => SizedBox(
        key: FakeDraftBubbleBuilder.bubbleKey,
        width: double.infinity,
        height: height + (preview.part.invertMedia ? aboveExtra : 0),
      );

  /// Opens the Android overlay in a [size] window; returns its controller.
  Future<DraftOptionsController> open(
    WidgetTester tester, {
    Size size = const Size(400, 800),
    DraftOptionsBubbleBuilder? bubble,
    ChromeMotionSpeed? motionSpeed,
    Brightness brightness = Brightness.light,
    bool settle = true,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final controller = DraftOptionsController(
      policy: const DraftOptionsPolicy.android(),
      host: host,
      bubbleBuilder: bubble ?? bubbleOf(),
      clock: clock,
      correlation: () => const ChatCorrelation(chatId: 'chat-1'),
    );
    addTearDown(controller.dispose);
    late BuildContext context;
    await tester.pumpWidget(
      composerHarness(
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox(height: 48);
          },
        ),
        brightness: brightness,
        motionSpeed: motionSpeed,
      ),
    );
    controller.open(context, value: _initial, page: _loaded);
    if (settle) {
      await tester.pumpAndSettle();
      clock.advance(const Duration(seconds: 1));
    } else {
      await tester.pump();
    }
    return controller;
  }

  Rect cardRect(WidgetTester tester) =>
      tester.getRect(find.byKey(DraftOptionsCardView.cardKey));
  Rect menuRect(WidgetTester tester) =>
      tester.getRect(find.byKey(DraftOptionsCardView.menuKey));
  Rect headerRect(WidgetTester tester) =>
      tester.getRect(find.byKey(DraftOptionsCardView.headerKey));

  /// The placement the layout gives for what the overlay measured.
  DraftOptionsCardGeometry expected(
    WidgetTester tester, {
    required Size size,
    double content = 120,
  }) => _card.resolve(
    area: size,
    display: size.height,
    menu: menuRect(tester).size,
    content: content,
  );

  double opacityOf(WidgetTester tester) => tester
      .widget<Opacity>(
        find.ancestor(
          of: find.byKey(DraftOptionsCardView.cardKey),
          matching: find.byType(Opacity),
        ),
      )
      .opacity;

  /// The overlay's scale, read from the card's drawn width against its
  /// laid-out one.
  double scaleOf(WidgetTester tester) =>
      cardRect(tester).width /
      tester
          .renderObject<RenderBox>(find.byKey(DraftOptionsCardView.cardKey))
          .size
          .width;

  Iterable<Map<String, Object?>> motions() =>
      diagnostics.whereOp(OverlayOp.motion).map((e) => e.fields);

  group('layout', () {
    for (final size in [const Size(400, 800), const Size(360, 640)]) {
      testWidgets('portrait ${size.width.round()} x ${size.height.round()}: '
          'the card at 8 a side, the menu at the end under it', (tester) async {
        await open(tester, size: size);
        final geometry = expected(tester, size: size);
        final card = cardRect(tester);
        final menu = menuRect(tester);

        expect(card, geometry.card);
        expect(card.left, 8);
        expect(card.right, size.width - 8);
        // The glass inside its 8 padding, at the window's end, its box
        // overlapping the card's bottom by 2.
        expect(menu.right, size.width - 8);
        expect(menu.top, card.bottom - 2 + 8);
        expect(headerRect(tester).top, geometry.visibleTop);
        expect(headerRect(tester).height, 56);
        expect(geometry.topOffset, greaterThan(0));
        // The bubble at the list's bottom, 4 above the card's end.
        expect(
          tester.getRect(find.byKey(FakeDraftBubbleBuilder.bubbleKey)).bottom,
          card.bottom - 4,
        );
        expect(
          tester.widget<PhysicalShape>(
            find.byKey(DraftOptionsCardView.cardKey),
          ),
          isA<PhysicalShape>().having((s) => s.elevation, 'elevation', 4),
        );
        expect(
          tester.widget<GlassSurface>(find.byKey(DraftOptionsCardView.menuKey)),
          isA<GlassSurface>()
              .having((g) => g.material, 'material', GlassMaterial.scrimMenu)
              .having((g) => g.cornerRadius, 'cornerRadius', 12),
        );
      });
    }

    for (final size in [const Size(800, 400), const Size(640, 360)]) {
      testWidgets('landscape ${size.width.round()} x ${size.height.round()}: '
          'the card at full height, the menu beside it', (tester) async {
        await open(tester, size: size);
        final card = cardRect(tester);
        final width = size.width * 0.6;

        expect(card, Rect.fromLTWH(8, 8, width, size.height - 16));
        expect(menuRect(tester).topLeft, Offset(width + 16, 8));
        expect(headerRect(tester).top, 8);
      });
    }

    testWidgets('the header carries the title (18 bold) and subtitle (14)', (
      tester,
    ) async {
      await open(tester);
      final strings = ChromeStringsPresets.english.composer.draftOptions;
      final title = tester.widget<Text>(find.text(strings.linkTitle));
      final subtitle = tester.widget<Text>(find.text(strings.linkSubtitle));

      expect(title.style?.fontSize, 18);
      expect(title.style?.fontWeight, FontWeight.bold);
      expect(subtitle.style?.fontSize, 14);
      expect(
        tester.getTopLeft(find.text(strings.linkTitle)).dx,
        cardRect(tester).left + 18,
      );
      expectChromeText(tester, within: find.byType(DraftOptionsOverlay));
    });
  });

  group('motion', () {
    testWidgets('open: opacity 0 to 1 and scale 0.95 to 1 over 250 ms', (
      tester,
    ) async {
      await open(tester, settle: false);

      expect(opacityOf(tester), 0);
      expect(scaleOf(tester), closeTo(0.95, 1e-6));

      await tester.pump(const Duration(milliseconds: 125));
      final midway = ChromeMotion.androidListCurve.transform(125 / 250);
      expect(opacityOf(tester), closeTo(midway, 0.02));
      expect(scaleOf(tester), closeTo(0.95 + 0.05 * midway, 0.002));

      await tester.pump(const Duration(milliseconds: 125));
      expect(opacityOf(tester), 1);
      expect(scaleOf(tester), 1);
      expect(motions(), [
        {
          'presentation': 'android',
          'phase': 'open',
          'durationMs': 250,
          'reduceMotion': false,
        },
      ]);
      expect(
        diagnostics.events.where((e) => '${e.fields}'.contains('example')),
        isEmpty,
      );
      expect(
        diagnostics.whereOp(OverlayOp.motion).single.correlation,
        const ChatCorrelation(chatId: 'chat-1'),
      );
    });

    testWidgets('close: the reverse over 250 ms, then the overlay goes with '
        'the scrim', (tester) async {
      final controller = await open(tester);

      controller.session!.apply();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 125));
      final midway = 1 - ChromeMotion.androidListCurve.transform(125 / 250);
      expect(opacityOf(tester), closeTo(midway, 0.02));

      await tester.pump(const Duration(milliseconds: 125));
      expect(opacityOf(tester), 0);
      expect(scaleOf(tester), closeTo(0.95, 1e-6));
      await tester.pumpAndSettle();
      expect(find.byType(DraftOptionsOverlay), findsNothing);
      expect(motions().last, {
        'presentation': 'android',
        'phase': 'close',
        'durationMs': 250,
        'reduceMotion': false,
      });
    });

    testWidgets('an option change moves the card 50 ms behind, over 250 ms', (
      tester,
    ) async {
      final controller = await open(tester, bubble: bubbleOf(aboveExtra: 380));
      final before = cardRect(tester);
      final beforeTop = headerRect(tester).top;
      final session = controller.session!;

      session.edit(
        session.value.value.copyWith(invertMedia: true),
        field: DraftOptionsField.position,
      );
      await tester.pump(); // the bubble lays out taller
      await tester.pump(); // the overlay measures it
      final target = expected(tester, size: const Size(400, 800), content: 500);
      expect(target.card.top, isNot(before.top));

      await tester.pump(const Duration(milliseconds: 49));
      expect(cardRect(tester).top, before.top);
      expect(motions().where((m) => m['phase'] == 'change'), isEmpty);

      await tester.pump(const Duration(milliseconds: 2));
      expect(motions().last, {
        'presentation': 'android',
        'phase': 'change',
        'durationMs': 250,
        'reduceMotion': false,
      });
      await tester.pump(const Duration(milliseconds: 125));
      final t = ChromeMotion.androidListCurve.transform(125 / 250);
      expect(
        cardRect(tester).top,
        closeTo(before.top + (target.card.top - before.top) * t, 1),
      );
      expect(
        headerRect(tester).top,
        closeTo(beforeTop + (target.visibleTop - beforeTop) * t, 1),
      );

      await tester.pump(const Duration(milliseconds: 130));
      expect(cardRect(tester), target.card);
      expect(headerRect(tester).top, target.visibleTop);
    });

    testWidgets('then a list that scrolls goes to the top for a card above, '
        'over 250 ms', (tester) async {
      final controller = await open(tester, bubble: bubbleOf(height: 1200));
      final scrollable = find.descendant(
        of: find.byKey(DraftOptionsCardView.cardKey),
        matching: find.byType(Scrollable),
      );
      ScrollPosition position() =>
          tester.state<ScrollableState>(scrollable).position;
      expect(position().pixels, 0);
      final session = controller.session!;

      session.edit(
        session.value.value.copyWith(invertMedia: true),
        field: DraftOptionsField.position,
      );
      await tester.pump(); // lays the change out, then starts the scroll
      await tester.pump(); // its first tick
      await tester.pump(const Duration(milliseconds: 125));
      expect(position().pixels, greaterThan(0));
      expect(position().pixels, lessThan(position().maxScrollExtent));

      await tester.pump(const Duration(milliseconds: 130));
      expect(position().pixels, position().maxScrollExtent);

      session.edit(
        session.value.value.copyWith(invertMedia: false),
        field: DraftOptionsField.position,
      );
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(position().pixels, 0);
    });

    testWidgets('reduce motion lands every motion on its end', (tester) async {
      final controller = await open(
        tester,
        bubble: bubbleOf(aboveExtra: 380),
        motionSpeed: ChromeMotionSpeed.instant,
        settle: false,
      );

      await tester.pump();
      expect(opacityOf(tester), 1);
      expect(scaleOf(tester), 1);
      await tester.pump();
      final session = controller.session!;
      session.edit(
        session.value.value.copyWith(invertMedia: true),
        field: DraftOptionsField.position,
      );
      await tester.pump();
      await tester.pump();
      expect(
        cardRect(tester),
        expected(tester, size: const Size(400, 800), content: 500).card,
      );

      session.apply();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.byType(DraftOptionsOverlay), findsNothing);
      expect(motions().map((m) => (m['phase'], m['durationMs'])), [
        ('open', 0),
        ('change', 0),
        ('close', 0),
      ]);
      expect(motions().every((m) => m['reduceMotion'] == true), isTrue);
    });
  });

  group('dismissal', () {
    testWidgets('a tap outside closes on lift', (tester) async {
      final controller = await open(tester);
      final below = Offset(20, menuRect(tester).bottom + 20);

      final gesture = await tester.startGesture(below);
      await tester.pump();
      expect(controller.session!.isClosing, isFalse);

      await gesture.up();
      await tester.pump();
      expect(controller.session!.isClosing, isTrue);
      expect(host.edits, isEmpty);
      await tester.pumpAndSettle();
      expect(find.byType(DraftOptionsOverlay), findsNothing);
      expect(
        diagnostics.whereOp(OverlayOp.closed).single.fields['trigger'],
        'outside',
      );
    });

    testWidgets('the band above the card\'s visible top passes the tap '
        'through and closes', (tester) async {
      final controller = await open(tester);
      final card = cardRect(tester);
      final visibleTop = headerRect(tester).top;
      expect(visibleTop - card.top, greaterThan(20));

      await tester.tapAt(Offset(card.center.dx, visibleTop - 10));
      await tester.pump();

      expect(controller.session!.isClosing, isTrue);
    });

    testWidgets('a tap on the card or the menu glass does not close', (
      tester,
    ) async {
      final controller = await open(tester);

      await tester.tapAt(headerRect(tester).center);
      await tester.tapAt(
        tester.getCenter(find.byKey(FakeDraftBubbleBuilder.bubbleKey)),
      );
      await tester.pump();

      expect(controller.session!.isClosing, isFalse);
    });

    testWidgets('system back closes', (tester) async {
      final controller = await open(tester);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pump();

      expect(controller.session!.isClosing, isTrue);
      expect(
        diagnostics.whereOp(OverlayOp.closed).single.fields['trigger'],
        'back',
      );
    });

    testWidgets('the Android scrim closes on lift and plays no haptics', (
      tester,
    ) async {
      final haptics = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'HapticFeedback.vibrate') haptics.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await open(tester);

      expect(
        tester.widget<ChromeScrim>(find.byType(ChromeScrim)).controller.preset,
        ChromeScrimPreset.android,
      );
      expect(ChromeScrimPreset.android.closeOn, ChromeScrimCloseOn.up);
      expect(haptics, isEmpty);
    });
  });
}
