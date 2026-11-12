import 'package:bulletins/bulletins.dart';
import 'package:bulletins/testing.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _surface = Size(400, 800);

/// The iOS card's spring curve, as its non-spring fallback draws it.
const _spring = Cubic(0.23, 1, 0.32, 1);

/// An iOS host over a fixed surface whose child counts its taps.
class _Harness {
  _Harness({
    BulletinPolicy policy = const BulletinPolicy.ios(),
    EdgeInsets obstruction = EdgeInsets.zero,
  }) : clock = ManualBulletinClock(),
       obstruction = ValueNotifier(obstruction) {
    controller = BulletinController(policy: policy, clock: clock);
  }

  final ManualBulletinClock clock;
  late final BulletinController controller;
  final ValueNotifier<EdgeInsets> obstruction;
  int surfaceTaps = 0;

  Widget app({BulletinBuilders? builders}) => Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: const MediaQueryData(size: _surface),
      child: ChromeThemeScope(
        palette: const ChromePalette.light(),
        child: ChromeStringsScope(
          strings: ChromeStringsPresets.english,
          child: ChromeMotionScope(
            child: Center(
              child: SizedBox.fromSize(
                size: _surface,
                child: BulletinHost(
                  controller: controller,
                  obstruction: obstruction,
                  builders: builders ?? BulletinIOS.builders(),
                  announce: (_, _) {},
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => surfaceTaps++,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  void dispose() {
    controller.dispose();
    obstruction.dispose();
  }
}

Rect _card(WidgetTester tester) => tester.getRect(find.byType(BulletinCard));

Rect _surfaceRect(WidgetTester tester) =>
    tester.getRect(find.byType(BulletinHost));

TextStyle _style(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!;

/// The opacity and scale the card is drawn with.
({double opacity, double scale}) _look(WidgetTester tester) {
  final opacity = tester
      .widgetList<Opacity>(
        find.ancestor(
          of: find.byType(BulletinCard),
          matching: find.byType(Opacity),
        ),
      )
      .fold<double>(1, (value, o) => value * o.opacity);
  final scale = tester
      .widgetList<Transform>(
        find.ancestor(
          of: find.byType(BulletinCard),
          matching: find.byType(Transform),
        ),
      )
      .fold<double>(1, (value, t) => value * t.transform.entry(0, 0));
  return (opacity: opacity, scale: scale);
}

void main() {
  group('policy', () {
    BulletinPolicyContract.run(
      'elevated ios',
      () => const BulletinPolicy$IOS(elevated: true, narrow: true),
    );

    const policy = BulletinPolicy.ios();

    test('times a plain notice 3 s and one with Undo 5 s', () {
      expect(
        policy.timeoutOf(BulletinDurationClass.short),
        const Duration(seconds: 3),
      );
      expect(
        policy.timeoutOf(BulletinDurationClass.long),
        const Duration(seconds: 3),
      );
      expect(
        policy.timeoutOf(BulletinDurationClass.prolonged),
        const Duration(seconds: 5),
      );
    });

    test('keeps 12 from every edge, 49 more above an elevated bottom', () {
      expect(policy.margin, const EdgeInsets.all(12));
      expect(
        const BulletinPolicy$IOS(elevated: true).margin,
        const EdgeInsets.fromLTRB(12, 12, 12, 61),
      );
      expect(
        const BulletinPolicy$IOS(sideInset: 8, bottomInset: 20).margin,
        const EdgeInsets.fromLTRB(8, 8, 8, 28),
      );
      expect(
        const BulletinPolicy$IOS(elevated: true, bottomInset: 0).margin,
        const EdgeInsets.all(12),
      );
    });

    test('is full width, or 210 when narrow', () {
      expect(policy.maxWidth, isNull);
      expect(const BulletinPolicy$IOS(narrow: true).maxWidth, 210);
    });

    test('has the iOS card metrics', () {
      expect(policy.minHeight, 50);
      expect(policy.cornerRadius, 25);
      expect(policy.leadingWidth, 50);
      expect(policy.iconSize, 32);
      expect(policy.contentPadding, const EdgeInsets.fromLTRB(16, 10, 16, 10));
      expect(policy.messageTextSize, 14);
      expect(policy.titleTextSize, 14);
      expect(policy.subtitleTextSize, 14);
    });

    test('fades and scales on the iOS card timings', () {
      expect(
        policy.transition,
        const BulletinTransition.fadeScale(
          enter: BulletinFadeScaleMotion(
            opacity: MotionSpec(Duration(milliseconds: 300), Curves.easeInOut),
            scale: MotionSpec(Duration(milliseconds: 500), _spring),
          ),
          exit: BulletinFadeScaleMotion(
            opacity: MotionSpec(Duration(milliseconds: 250), Curves.easeOut),
            scale: MotionSpec(Duration(milliseconds: 500), _spring),
          ),
        ),
      );
    });
  });

  group('layout', () {
    late _Harness h;
    tearDown(() => h.dispose());

    testWidgets('a one-line card is 50 high, 12 from the edges', (
      tester,
    ) async {
      h = _Harness();
      await tester.pumpWidget(h.app());
      h.controller.show(const Bulletin(message: 'Copied'));
      await tester.pumpAndSettle();
      final surface = _surfaceRect(tester);
      final card = _card(tester);
      expect(card.left - surface.left, 12);
      expect(surface.right - card.right, 12);
      expect(surface.bottom - card.bottom, 12);
      expect(card.height, 50);
    });

    testWidgets('it sits above the keyboard and an elevated bar', (
      tester,
    ) async {
      h = _Harness(
        policy: const BulletinPolicy$IOS(elevated: true),
        obstruction: const EdgeInsets.only(bottom: 300),
      );
      await tester.pumpWidget(h.app());
      h.controller.show(const Bulletin(message: 'Copied'));
      await tester.pumpAndSettle();
      expect(_surfaceRect(tester).bottom - _card(tester).bottom, 300 + 49 + 12);
    });

    testWidgets('at the top it sits 12 under the top obstruction', (
      tester,
    ) async {
      h = _Harness(obstruction: const EdgeInsets.only(top: 47));
      await tester.pumpWidget(h.app());
      h.controller.show(
        const Bulletin(message: 'Copied', placement: BulletinPlacement.top),
      );
      await tester.pumpAndSettle();
      expect(_card(tester).top - _surfaceRect(tester).top, 47 + 12);
    });

    testWidgets('a narrow card is 210 wide and centred', (tester) async {
      h = _Harness(policy: const BulletinPolicy$IOS(narrow: true));
      await tester.pumpWidget(h.app());
      h.controller.show(const Bulletin(message: 'Copied'));
      await tester.pumpAndSettle();
      expect(_card(tester).width, 210);
      expect(_card(tester).center.dx, _surfaceRect(tester).center.dx);
    });

    testWidgets('text starts 50 in after a leading, 16 without', (
      tester,
    ) async {
      h = _Harness();
      await tester.pumpWidget(h.app());
      h.controller.show(
        const Bulletin(
          message: 'Copied',
          leading: BulletinLeading.icon(ChromeIconId.send),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('Copied')).left - _card(tester).left, 50);

      h.controller.show(const Bulletin(message: 'Saved'));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('Saved')).left - _card(tester).left, 16);
    });

    testWidgets('title is 14 semibold, message 14 and several lines', (
      tester,
    ) async {
      h = _Harness();
      await tester.pumpWidget(h.app());
      final long = List.filled(40, 'word').join(' ');
      h.controller.show(Bulletin(title: 'Pack removed', message: long));
      await tester.pumpAndSettle();
      final title = _style(tester, 'Pack removed');
      expect(title.fontSize, 14);
      expect(title.fontWeight, FontWeight.w600);
      expect(_style(tester, long).fontSize, 14);
      expect(tester.widget<Text>(find.text(long)).maxLines, 5);
      final titleRect = tester.getRect(find.text('Pack removed'));
      final messageRect = tester.getRect(find.text(long));
      expect(messageRect.top - titleRect.bottom, 1);
      expect(messageRect.height, greaterThan(14 * 2));
      // 10 above the text and 10 below it.
      expect(titleRect.top - _card(tester).top, 10);
      expect(_card(tester).bottom - messageRect.bottom, 10);
    });

    testWidgets('a caller line limit wins', (tester) async {
      h = _Harness();
      await tester.pumpWidget(h.app());
      h.controller.show(const Bulletin(message: 'Copied', maxLines: 2));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text('Copied')).maxLines, 2);
    });
  });

  group('leading', () {
    late _Harness h;
    tearDown(() => h.dispose());

    Future<Size> sizeOf(
      WidgetTester tester,
      BulletinLeading leading,
      Key key,
    ) async {
      h = _Harness();
      await tester.pumpWidget(
        h.app(
          builders: BulletinIOS.builders(
            animation: (_, _, _) => SizedBox.expand(key: key),
            thumbnail: (_, _, _) => SizedBox.expand(key: key),
          ),
        ),
      );
      h.controller.show(Bulletin(message: 'Saved', leading: leading));
      await tester.pumpAndSettle();
      return tester.getSize(find.byKey(key));
    }

    testWidgets('an animation plays in 32 by 32', (tester) async {
      const key = ValueKey('a');
      expect(
        await sizeOf(tester, const BulletinLeading.animation('copy'), key),
        const Size.square(32),
      );
    });

    testWidgets('a thumbnail fits 34 by 34, centred in the 50 slot', (
      tester,
    ) async {
      const key = ValueKey('t');
      expect(
        await sizeOf(tester, const BulletinLeading.thumbnail('sticker'), key),
        const Size.square(34),
      );
      final card = _card(tester);
      final thumb = tester.getRect(find.byKey(key));
      expect(thumb.left - card.left, 8);
      expect(thumb.center.dy, card.center.dy);
    });
  });

  group('countdown', () {
    late _Harness h;
    tearDown(() => h.dispose());

    testWidgets('a 30 ring counts whole seconds down in half-second ticks', (
      tester,
    ) async {
      h = _Harness();
      await tester.pumpWidget(h.app());
      h.controller.show(
        Bulletin(
          message: 'Chat deleted',
          leading: const BulletinLeading.countdown(),
          action: BulletinAction.undo(onUndo: () {}),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        tester.getSize(find.byType(BulletinCountdownIOS)),
        const Size.square(30),
      );
      expect(find.text('5'), findsOneWidget);
      expect(_style(tester, '5').fontSize, 16);

      // The countdown ticks every 0.5 s and draws the whole part of what is left: 4.5 is 4.
      h.clock.advance(const Duration(milliseconds: 499));
      await tester.pump();
      expect(find.text('5'), findsOneWidget);
      h.clock.advance(const Duration(milliseconds: 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('4'), findsOneWidget);
      expect(find.text('5'), findsNothing);

      // The last half second shows 0.
      h.clock.advance(const Duration(milliseconds: 4000));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('a digit change slides the new one down from 10 above', (
      tester,
    ) async {
      h = _Harness();
      await tester.pumpWidget(h.app());
      h.controller.show(
        const Bulletin(
          message: 'Chat deleted',
          leading: BulletinLeading.countdown(),
          duration: BulletinDuration.exactly(Duration(seconds: 5)),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      final rest = tester.getCenter(find.text('5'));
      h.clock.advance(const Duration(milliseconds: 600));
      await tester.pump();
      await tester.pump(Duration.zero);
      expect(find.text('5'), findsOneWidget);
      expect(tester.getCenter(find.text('4')).dy, closeTo(rest.dy - 10, 0.5));
      await tester.pump(const Duration(milliseconds: 60));
      final halfway = tester.getCenter(find.text('4')).dy;
      expect(halfway, inExclusiveRange(rest.dy - 10, rest.dy));
      expect(tester.getCenter(find.text('5')).dy, greaterThan(rest.dy));
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.text('5'), findsNothing);
      expect(tester.getCenter(find.text('4')).dy, rest.dy);
    });
  });

  group('action', () {
    late _Harness h;
    tearDown(() => h.dispose());

    testWidgets('Undo is 17 in the accent, 16 from the right edge', (
      tester,
    ) async {
      h = _Harness();
      await tester.pumpWidget(h.app());
      h.controller.show(
        Bulletin(
          message: 'Pack removed',
          action: BulletinAction.undo(onUndo: () {}),
        ),
      );
      await tester.pumpAndSettle();
      final undo = ChromeStringsPresets.english.bulletin.undoAction;
      final style = _style(tester, undo);
      expect(style.fontSize, 17);
      expect(style.fontWeight, FontWeight.w400);
      expect(
        style.color,
        BulletinTokens.fromPalette(const ChromePalette.light()).accent,
      );
      expect(_card(tester).right - tester.getRect(find.text(undo)).right, 16);
    });

    testWidgets('the whole height right of the label undoes', (tester) async {
      h = _Harness();
      var undos = 0;
      await tester.pumpWidget(h.app());
      final handle = h.controller.show(
        Bulletin(
          message: 'Pack removed',
          action: BulletinAction.undo(onUndo: () => undos++),
        ),
      );
      await tester.pumpAndSettle();
      final card = _card(tester);
      await tester.tapAt(Offset(card.right - 6, card.top + 3));
      expect(undos, 1);
      expect(handle.exit, BulletinExit.undone);
    });

    testWidgets('the label dims to 0.4 while pressed and recovers in 0.2 s', (
      tester,
    ) async {
      h = _Harness();
      await tester.pumpWidget(h.app());
      h.controller.show(
        Bulletin(
          message: 'Pack removed',
          action: BulletinAction.button(label: 'View', onPressed: () {}),
        ),
      );
      await tester.pumpAndSettle();
      double opacity() => tester
          .widget<Opacity>(
            find
                .ancestor(of: find.text('View'), matching: find.byType(Opacity))
                .first,
          )
          .opacity;
      expect(opacity(), 1);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('View')),
      );
      await tester.pump(const Duration(milliseconds: 150));
      expect(opacity(), 0.4);
      await gesture.cancel();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(opacity(), closeTo(0.7, 0.01));
      await tester.pump(const Duration(milliseconds: 100));
      expect(opacity(), 1);
    });
  });

  group('motion', () {
    late _Harness h;
    tearDown(() => h.dispose());

    testWidgets('enters by fading in 0.3 s and scaling from 0.96 in 0.5 s', (
      tester,
    ) async {
      h = _Harness();
      await tester.pumpWidget(h.app());
      final handle = h.controller.show(const Bulletin(message: 'Copied'));
      await tester.pump();
      expect(_look(tester).opacity, 0);
      expect(_look(tester).scale, closeTo(0.96, 1e-6));

      await tester.pump(const Duration(milliseconds: 150));
      var look = _look(tester);
      expect(look.opacity, closeTo(Curves.easeInOut.transform(0.5), 1e-3));
      expect(look.scale, closeTo(0.96 + 0.04 * _spring.transform(0.3), 1e-3));

      await tester.pump(const Duration(milliseconds: 150));
      look = _look(tester);
      expect(look.opacity, 1);
      expect(look.scale, lessThan(1));
      expect(handle.isEntered, isFalse);

      await tester.pump(const Duration(milliseconds: 200));
      expect(_look(tester).scale, 1);
      await tester.pump(const Duration(milliseconds: 1));
      expect(handle.isEntered, isTrue);
    });

    testWidgets('leaves by fading out in 0.25 s while shrinking to 0.96', (
      tester,
    ) async {
      h = _Harness();
      await tester.pumpWidget(h.app());
      final handle = h.controller.show(const Bulletin(message: 'Copied'));
      await tester.pumpAndSettle();
      handle.dismiss();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 125));
      final look = _look(tester);
      expect(look.opacity, closeTo(1 - Curves.easeOut.transform(0.5), 1e-3));
      expect(look.scale, closeTo(1 - 0.04 * _spring.transform(0.25), 1e-3));
      await tester.pump(const Duration(milliseconds: 126));
      expect(find.byType(BulletinCard), findsNothing);
    });

    testWidgets('leaving mid-enter starts from what is drawn', (tester) async {
      h = _Harness();
      await tester.pumpWidget(h.app());
      final handle = h.controller.show(const Bulletin(message: 'Copied'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final before = _look(tester);
      handle.dismiss();
      await tester.pump();
      final after = _look(tester);
      expect(after.opacity, closeTo(before.opacity, 1e-3));
      expect(after.scale, closeTo(before.scale, 1e-3));
      await tester.pumpAndSettle();
      expect(find.byType(BulletinCard), findsNothing);
    });
  });

  group('hit testing', () {
    late _Harness h;
    tearDown(() => h.dispose());

    testWidgets('taps outside the card reach the surface', (tester) async {
      h = _Harness();
      await tester.pumpWidget(h.app());
      h.controller.show(const Bulletin(message: 'Copied'));
      await tester.pumpAndSettle();
      final card = _card(tester);
      await tester.tapAt(card.topCenter - const Offset(0, 20));
      await tester.tapAt(_surfaceRect(tester).center);
      expect(h.surfaceTaps, 2);
    });

    testWidgets('a card with nothing to press lets taps through', (
      tester,
    ) async {
      h = _Harness();
      await tester.pumpWidget(h.app());
      h.controller.show(const Bulletin(message: 'Copied'));
      await tester.pumpAndSettle();
      await tester.tapAt(_card(tester).center);
      expect(h.surfaceTaps, 1);
    });

    testWidgets('a card with an action catches taps on its body', (
      tester,
    ) async {
      h = _Harness();
      await tester.pumpWidget(h.app());
      h.controller.show(
        Bulletin(
          message: 'Pack removed',
          action: BulletinAction.undo(onUndo: () {}),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getCenter(find.text('Pack removed')));
      expect(h.surfaceTaps, 0);
    });
  });
}
