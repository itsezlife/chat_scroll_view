/// The iOS presentation of the draft options overlay: the content rect
/// springing out of the strip with the action list under it, its layout on
/// a phone and an iPad, its open, close and change motion, the haptic on
/// open, the backdrop's close on contact, reduce motion and the `motion`
/// events.
///
/// **Seam:** `DraftOptionsPolicy$IOS` and its `DraftOptionsSpringSurface`
/// (pure layout), and `DraftOptionsController` opened from a
/// `ComposerHeaderStrip` (or directly) under the composer's scopes, with a
/// `RecordingDraftOptionsHost`, a bubble builder and `RecordingDiagnostics`.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_composer/src/view/composer_header_strip.dart';
import 'package:chat_composer/testing.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart' hide RichText;
import 'package:content_model/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/composer_harness.dart';

final _url = Uri.parse('https://news.example/story?id=7');
final _initial = DraftLinkPart(options: LinkPreviewOptions(url: _url));

const _phone = Size(390, 844);
const _phonePadding = EdgeInsets.only(top: 47, bottom: 34);
const _pad = Size(1024, 768);

// The ease in-out the fades and the close play on.
const _ease = Cubic(0.42, 0, 0.58, 1);

void main() {
  group('policy', () {
    test('the phone surface: radius 30, W − 24 wide, at most 460 tall or '
        'the preview + 3, never under 200, actions 10 under it inset 12', () {
      final surface = const DraftOptionsPolicy$IOS().surface;

      expect(surface, DraftOptionsSpringSurface.phone);
      expect(surface.cornerRadius, 30);
      expect(surface.sideMargin, 12);
      expect(surface.verticalMargin, 24);
      expect(surface.topInsetExtra, 8);
      expect(surface.maxHeight, 460);
      expect(surface.previewExtra, 3);
      expect(surface.minHeight, 200);
      expect(surface.maxWidth, isNull);
      expect(surface.centredOnStrip, isFalse);
      expect(surface.actionsSpacing, 10);
      expect(surface.actionsEdgeInset, 12);
      expect(surface.actionsMinWidth, 250);
      expect(surface.actionsCornerRadius, 14);
      expect(surface.hapticOnOpen, isTrue);
    });

    test('the iPad surface: at most 400 wide, centred on the strip', () {
      final surface = const DraftOptionsPolicy$IOS(iPad: true).surface;

      expect(surface, DraftOptionsSpringSurface.iPad);
      expect(surface.maxWidth, 400);
      expect(surface.centredOnStrip, isTrue);
      expect(surface.cornerRadius, 30);
      expect(surface.hapticOnOpen, isTrue);
    });

    test('the motion: a 0.42 s spring with damping 104 from scale 0.01, the '
        'content fading in over 0.15 s and the actions over 0.05 s; the close '
        '0.2 s ease in-out, the content fading out over 0.16 s', () {
      const motion = DraftOptionsSpringMotion();

      expect(motion.spring.mass, 1);
      expect(motion.spring.stiffness, 900);
      expect(motion.spring.damping, 104);
      expect(motion.springCut, const Duration(milliseconds: 420));
      expect(motion.startScale, 0.01);
      expect(
        motion.contentShowFade,
        const MotionSpec(Duration(milliseconds: 150), _ease),
      );
      expect(
        motion.actionsShowFade,
        const MotionSpec(Duration(milliseconds: 50), _ease),
      );
      expect(
        motion.close,
        const MotionSpec(Duration(milliseconds: 200), _ease),
      );
      expect(
        motion.contentHideFade,
        const MotionSpec(Duration(milliseconds: 160), _ease),
      );
      expect(
        motion.change,
        const MotionSpec(Duration(milliseconds: 500), Curves.easeInOut),
      );
      expect(DraftOptionsSpringSurface.iPad.motion, motion);
    });

    test('the spring grows to 1 at its cut and never past it', () {
      const motion = DraftOptionsSpringMotion();

      expect(motion.grownAt(Duration.zero), 0);
      expect(motion.grownAt(const Duration(milliseconds: 420)), 1);
      var last = 0.0;
      for (var ms = 0; ms <= 420; ms += 10) {
        final grown = motion.grownAt(Duration(milliseconds: ms));
        expect(grown, inInclusiveRange(last, 1));
        last = grown;
      }
    });

    test('a host overrides the surface', () {
      const surface = DraftOptionsSpringSurface(
        cornerRadius: 20,
        hapticOnOpen: false,
      );

      expect(const DraftOptionsPolicy$IOS(surface: surface).surface, surface);
      expect(
        const DraftOptionsPolicy$IOS(iPad: true, surface: surface).surface,
        surface,
      );
    });

    test('the iOS rows are context-menu rows: 44 tall, the label 16 from the '
        'start in 17, the icon 16 from the end', () {
      expect(
        const DraftOptionsPolicy$IOS().linkPage.rowMetrics,
        const DraftLinkRowMetrics(
          height: 44,
          iconSize: 24,
          iconStart: 16,
          labelStart: 16,
          fontSize: 17,
          minWidthBeyondLabel: 76,
          iconAtEnd: true,
        ),
      );
      expect(DraftLinkPagePolicy.ios.separator, DraftLinkSeparator.gap);
      expect(DraftLinkPagePolicy.ios.separatorExtent, 8);
      expect(DraftLinkPagePolicy.ios.labelChange.duration, Duration.zero);
      expect(DraftLinkPagePolicy.android.rowMetrics.iconAtEnd, isFalse);
    });
  });

  group('layout values', () {
    const phone = DraftOptionsSpringSurface.phone;
    const pad = DraftOptionsSpringSurface.iPad;

    test('the content is W − 24 wide on a phone, at most 400 on an iPad', () {
      expect(phone.contentWidth(_phone), 366);
      expect(pad.contentWidth(_pad), 400);
      expect(pad.contentWidth(const Size(380, 700)), 356);
    });

    test('the content is at most 460 tall in a tall window', () {
      final bounds = phone.contentHeightBounds(
        _phone,
        _phonePadding,
        actionsHeight: 200,
      );

      expect(bounds, (min: 200.0, max: 460.0));
    });

    test('a short window takes H − 24 − top inset − bottom safe area, then '
        'less to fit the actions, never under 200', () {
      const window = Size(390, 500);
      const padding = EdgeInsets.only(top: 20);

      // 500 − 24 − (20 + 8) = 448.
      expect(
        phone.contentHeightBounds(window, padding, actionsHeight: 0).max,
        448,
      );
      // 500 − 28 − 10 − 220 = 242.
      expect(
        phone.contentHeightBounds(window, padding, actionsHeight: 220).max,
        242,
      );
      expect(
        phone.contentHeightBounds(window, padding, actionsHeight: 300).max,
        200,
      );
    });

    test('a phone centres the content and its actions as a group, the actions '
        'right-aligned 10 under it', () {
      final frame = phone.place(
        _phone,
        _phonePadding,
        content: const Size(366, 200),
        actions: const Size(250, 180),
      );

      // Top inset 55; room 844 − 55 − 34 = 755; group 390.
      expect(frame.content, const Rect.fromLTWH(12, 237.5, 366, 200));
      expect(frame.actions, const Offset(128, 447.5));
    });

    test('an iPad centres the content on the strip within the margins', () {
      final onStrip = pad.place(
        _pad,
        EdgeInsets.zero,
        content: const Size(400, 300),
        actions: const Size(250, 140),
        strip: const Rect.fromLTWH(600, 700, 300, 40),
      );
      final atEdge = pad.place(
        _pad,
        EdgeInsets.zero,
        content: const Size(400, 300),
        actions: const Size(250, 140),
        strip: const Rect.fromLTWH(900, 700, 200, 40),
      );

      expect(onStrip.content.left, 550);
      expect(onStrip.actions.dx, 700);
      expect(atEdge.content.left, 1024 - 12 - 400);
    });

    test('actions wider than the content keep 12 from the window edge', () {
      final frame = phone.place(
        const Size(300, 700),
        EdgeInsets.zero,
        content: const Size(276, 200),
        actions: const Size(290, 100),
      );

      expect(frame.actions.dx, 12);
    });
  });

  group('the overlay', () {
    late RecordingDiagnostics diagnostics;
    late RecordingDraftOptionsHost host;
    late ManualComposerClock clock;
    late List<MethodCall> haptics;

    setUp(() {
      diagnostics = RecordingDiagnostics.install();
      host = RecordingDraftOptionsHost();
      clock = ManualComposerClock(DateTime(2026, 11, 28));
      haptics = [];
    });

    void sizeWindow(WidgetTester tester, Size size) {
      tester.view
        ..physicalSize = size
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
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
    }

    DraftOptionsController controllerOf(
      DraftOptionsPolicy policy, {
      DraftOptionsBubbleBuilder? bubble,
    }) {
      final controller = DraftOptionsController(
        policy: policy,
        host: host,
        bubbleBuilder: bubble ?? FakeDraftBubbleBuilder().call,
        clock: clock,
        correlation: () => const ChatCorrelation(chatId: 'chat-1'),
      );
      addTearDown(controller.dispose);
      return controller;
    }

    Future<Finder> mountStrip(
      WidgetTester tester,
      DraftOptionsController controller, {
      ChromeMotionSpeed? motionSpeed,
      EdgeInsets viewPadding = _phonePadding,
    }) async {
      await tester.pumpWidget(
        composerHarness(
          viewPadding: viewPadding,
          motionSpeed: motionSpeed,
          Builder(
            builder: (context) => ComposerHeaderStrip(
              header: ComposerHeader.linkPreview(
                url: _url,
                onOpen: (rect) => controller.open(
                  context,
                  value: _initial,
                  page: LinkPreviewState.pending,
                  stripRect: rect,
                ),
              ),
            ),
          ),
        ),
      );
      return find.byType(ComposerHeaderStrip);
    }

    Finder content() => find.byKey(DraftOptionsSpringView.contentKey);
    Finder actions() => find.byKey(DraftOptionsSpringView.actionsKey);
    double opacityOf(WidgetTester tester, Finder child) => tester
        .widget<Opacity>(
          find.ancestor(of: child, matching: find.byType(Opacity)).first,
        )
        .opacity;

    Widget tallBubble(BuildContext context, DraftOptionsPreview preview) =>
        SizedBox(
          height: switch (preview.part.options.media) {
            LinkPreviewMedia.small => 260,
            _ => 300,
          },
        );

    testWidgets('a phone lays the content out W − 24 wide, centred, the '
        'preview + 3 tall, the actions right-aligned 10 under it', (
      tester,
    ) async {
      sizeWindow(tester, _phone);
      final controller = controllerOf(
        const DraftOptionsPolicy.ios(),
        bubble: tallBubble,
      );
      await tester.tap(await mountStrip(tester, controller));
      await tester.pumpAndSettle();

      final rect = tester.getRect(content());
      final list = tester.getRect(actions());
      expect(rect.width, 366);
      expect(rect.left, 12);
      expect(rect.height, 303);
      expect(list.right, rect.right);
      expect(list.top, rect.bottom + 10);
      expect(list.width, greaterThanOrEqualTo(250));
      // The group stands centred between the top inset and the safe area.
      final room = _phone.height - 55 - 34;
      expect(rect.top, 55 + (room - (rect.height + 10 + list.height)) / 2);
      expect(
        tester.widget<ClipRRect>(content()).borderRadius,
        BorderRadius.circular(30),
      );
      expectChromeText(tester, within: find.byType(DraftOptionsOverlay));
    });

    testWidgets('a short preview takes 200, a tall one stops at 460', (
      tester,
    ) async {
      sizeWindow(tester, _phone);
      final short = controllerOf(const DraftOptionsPolicy.ios());
      await tester.tap(await mountStrip(tester, short));
      await tester.pumpAndSettle();

      expect(tester.getRect(content()).height, 200);

      short.dispose();
      await tester.pumpAndSettle();
      clock.advance(const Duration(seconds: 1));
      final tall = controllerOf(
        const DraftOptionsPolicy.ios(),
        bubble: (context, preview) => const SizedBox(height: 900),
      );
      await tester.tap(await mountStrip(tester, tall));
      await tester.pumpAndSettle();

      expect(tester.getRect(content()).height, 460);
    });

    testWidgets('an iPad lays the content at most 400 wide, centred on the '
        'strip', (tester) async {
      sizeWindow(tester, _pad);
      final controller = controllerOf(const DraftOptionsPolicy.ios(iPad: true));
      await tester.pumpWidget(
        composerHarness(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => controller.open(
                context,
                value: _initial,
                page: LinkPreviewState.pending,
                stripRect: const Rect.fromLTWH(600, 700, 300, 40),
              ),
              child: const SizedBox(height: 40),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();

      final rect = tester.getRect(content());
      expect(rect.width, 400);
      expect(rect.left, 550);
      expect(tester.getRect(actions()).right, rect.right);
      expect(
        diagnostics.whereOp(OverlayOp.opened).single.fields['presentation'],
        'ipad',
      );
    });

    testWidgets('the open springs from the strip: the content fades in over '
        '0.15 s, the actions over 0.05 s, both scale from 0.01 on the 0.42 s '
        'spring', (tester) async {
      sizeWindow(tester, _phone);
      final controller = controllerOf(const DraftOptionsPolicy.ios());
      final strip = await mountStrip(tester, controller);
      final stripCentre = tester.getRect(strip).center;
      await tester.tap(strip);
      await tester.pump();

      // At the start the content is a point at the strip's centre line.
      final start = tester.getRect(content());
      expect(start.width, closeTo(366 * 0.01, 0.01));
      expect(start.center.dy, closeTo(stripCentre.dy, 0.01));
      expect(opacityOf(tester, content()), 0);
      expect(opacityOf(tester, actions()), 0);

      await tester.pump(const Duration(milliseconds: 25));
      expect(opacityOf(tester, actions()), closeTo(_ease.transform(0.5), 1e-6));

      await tester.pump(const Duration(milliseconds: 50));
      expect(opacityOf(tester, actions()), 1);
      expect(opacityOf(tester, content()), closeTo(_ease.transform(0.5), 1e-6));

      await tester.pump(const Duration(milliseconds: 135));
      expect(opacityOf(tester, content()), 1);
      final spring = SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 900, damping: 104),
        0,
        1,
        0,
      );
      expect(
        tester.getRect(content()).width,
        closeTo(366 * (0.01 + 0.99 * spring.x(0.21)), 0.01),
      );

      await tester.pump(const Duration(milliseconds: 210));
      final rest = tester.getRect(content());
      expect(rest.width, 366);
      expect(rest.center.dy, isNot(closeTo(stripCentre.dy, 1)));
      expect(diagnostics.whereOp(OverlayOp.motion).single.fields, {
        'presentation': 'ios',
        'phase': 'open',
        'durationMs': 420,
        'reduceMotion': false,
      });
    });

    testWidgets('a tap on the backdrop closes on contact; the content goes '
        'back toward the strip over 0.2 s, fading out over 0.16 s', (
      tester,
    ) async {
      sizeWindow(tester, _phone);
      final controller = controllerOf(const DraftOptionsPolicy.ios());
      final strip = await mountStrip(tester, controller);
      final stripCentre = tester.getRect(strip).center;
      await tester.tap(strip);
      await tester.pumpAndSettle();
      clock.advance(DraftOptionsController.openGuard);
      final rest = tester.getRect(content());

      final press = await tester.startGesture(const Offset(20, 20));
      await tester.pump();

      expect(controller.session?.isClosing, isTrue);
      expect(
        diagnostics.whereOp(OverlayOp.closed).single.fields['trigger'],
        'outside',
      );
      expect(
        diagnostics.whereOp(OverlayOp.scrimDismissed).single.fields['closeOn'],
        'down',
      );

      await tester.pump(const Duration(milliseconds: 80));
      expect(
        opacityOf(tester, content()),
        closeTo(1 - _ease.transform(0.5), 1e-6),
      );

      await tester.pump(const Duration(milliseconds: 20));
      final halfway = tester.getRect(content());
      final eased = _ease.transform(0.5);
      expect(halfway.width, closeTo(366 * (1 - 0.99 * eased), 0.01));
      expect(
        halfway.center.dy,
        closeTo(
          rest.center.dy + (stripCentre.dy - rest.center.dy) * eased,
          0.01,
        ),
      );

      await tester.pump(const Duration(milliseconds: 60));
      expect(opacityOf(tester, content()), 0);

      await press.up();
      await tester.pumpAndSettle();
      expect(find.byType(DraftOptionsOverlay), findsNothing);
      expect(diagnostics.whereOp(OverlayOp.motion).last.fields, {
        'presentation': 'ios',
        'phase': 'close',
        'durationMs': 200,
        'reduceMotion': false,
      });
    });

    testWidgets('the open plays one haptic impact, a burst of taps too', (
      tester,
    ) async {
      sizeWindow(tester, _phone);
      final controller = controllerOf(const DraftOptionsPolicy.ios());
      final strip = await mountStrip(tester, controller);

      await tester.tap(strip);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(strip, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(strip, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(haptics, hasLength(1));
      expect(haptics.single.arguments, 'HapticFeedbackType.mediumImpact');
    });

    testWidgets('a surface without the haptic plays none', (tester) async {
      sizeWindow(tester, _phone);
      final controller = controllerOf(
        const DraftOptionsPolicy.ios(
          surface: DraftOptionsSpringSurface(hapticOnOpen: false),
        ),
      );
      await tester.tap(await mountStrip(tester, controller));
      await tester.pumpAndSettle();

      expect(haptics, isEmpty);
    });

    testWidgets('an edit resizes the content over 0.5 s and reports a change', (
      tester,
    ) async {
      sizeWindow(tester, _phone);
      final controller = controllerOf(
        const DraftOptionsPolicy.ios(),
        bubble: tallBubble,
      );
      await tester.tap(await mountStrip(tester, controller));
      await tester.pumpAndSettle();
      expect(tester.getRect(content()).height, 303);

      controller.session!.edit(
        _initial.copyWith(
          options: _initial.options.copyWith(media: LinkPreviewMedia.small),
        ),
        field: DraftOptionsField.size,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      final midway = tester.getRect(content()).height;
      expect(midway, lessThan(303));
      expect(midway, greaterThan(263));

      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.getRect(content()).height, 263);
      expect(diagnostics.whereOp(OverlayOp.motion).last.fields, {
        'presentation': 'ios',
        'phase': 'change',
        'durationMs': 500,
        'reduceMotion': false,
      });
    });

    testWidgets('reduce motion lands the open and the close on their end '
        'states at once', (tester) async {
      sizeWindow(tester, _phone);
      final controller = controllerOf(const DraftOptionsPolicy.ios());
      await tester.tap(
        await mountStrip(
          tester,
          controller,
          motionSpeed: ChromeMotionSpeed.instant,
        ),
      );
      await tester.pump();

      expect(tester.getRect(content()).width, 366);
      expect(opacityOf(tester, content()), 1);
      expect(opacityOf(tester, actions()), 1);

      // The backdrop keeps its own fade; let it come up before closing.
      await tester.pumpAndSettle();
      clock.advance(DraftOptionsController.openGuard);
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();

      expect(opacityOf(tester, content()), 0);
      expect(opacityOf(tester, actions()), 0);
      expect(
        [
          for (final event in diagnostics.whereOp(OverlayOp.motion))
            event.fields,
        ],
        [
          {
            'presentation': 'ios',
            'phase': 'open',
            'durationMs': 0,
            'reduceMotion': true,
          },
          {
            'presentation': 'ios',
            'phase': 'close',
            'durationMs': 0,
            'reduceMotion': true,
          },
        ],
      );
      await tester.pumpAndSettle();
    });

    testWidgets('the rows put the icon at the end and are 44 tall', (
      tester,
    ) async {
      sizeWindow(tester, _phone);
      final controller = controllerOf(const DraftOptionsPolicy.ios());
      await tester.tap(await mountStrip(tester, controller));
      await tester.pumpAndSettle();

      final row = find.byType(DraftLinkRowView).first;
      final rowRect = tester.getRect(row);
      final icon = tester.getRect(
        find.descendant(of: row, matching: find.byType(AnimatedChromeIcon)),
      );
      expect(rowRect.height, 44);
      expect(icon.right, rowRect.right - 16);
    });
  });
}
