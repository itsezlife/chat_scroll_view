import 'package:bulletins/bulletins.dart';
import 'package:bulletins/testing.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _surface = Size(400, 800);

/// The surface a host mounts over: chrome scopes, a fixed size, and a
/// recorder for announcements.
class _Harness {
  _Harness({
    BulletinPolicy policy = const BulletinPolicy.android(),
    EdgeInsets obstruction = EdgeInsets.zero,
    this.tracksObstruction = false,
  }) : clock = ManualBulletinClock(),
       obstruction = ValueNotifier(obstruction) {
    controller = BulletinController(policy: policy, clock: clock);
  }

  final ManualBulletinClock clock;
  late final BulletinController controller;
  final ValueNotifier<EdgeInsets> obstruction;
  final bool tracksObstruction;
  final announced = <String>[];

  Widget app({
    BulletinBuilders builders = const BulletinBuilders(),
    ChromeMotionSpeed speed = ChromeMotionSpeed.normal,
    bool mounted = true,
  }) => Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: const MediaQueryData(size: _surface),
      child: ChromeThemeScope(
        palette: const ChromePalette.light(),
        child: ChromeStringsScope(
          strings: ChromeStringsPresets.english,
          child: ChromeMotionScope(
            speed: speed,
            child: Center(
              child: SizedBox.fromSize(
                size: _surface,
                child: mounted
                    ? BulletinHost(
                        controller: controller,
                        obstruction: obstruction,
                        tracksObstruction: tracksObstruction,
                        builders: builders,
                        announce: (_, message) => announced.add(message),
                        child: const SizedBox.expand(),
                      )
                    : const SizedBox.expand(),
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

Rect _surfaceRect(WidgetTester tester) =>
    tester.getRect(find.byType(BulletinHost));

void main() {
  late _Harness h;

  tearDown(() => h.dispose());

  group('showing', () {
    testWidgets('a bulletin appears, enters and starts its timer', (
      tester,
    ) async {
      h = _Harness();
      await tester.pumpWidget(h.app());
      final handle = h.controller.show(const Bulletin(message: 'Copied'));
      await tester.pump();
      expect(find.text('Copied'), findsOneWidget);
      expect(handle.isEntered, isFalse);

      await tester.pumpAndSettle();
      expect(handle.isEntered, isTrue);
      h.clock.advance(const Duration(milliseconds: 1500));
      expect(handle.exit, BulletinExit.timedOut);

      await tester.pumpAndSettle();
      expect(find.text('Copied'), findsNothing);
    });

    testWidgets('under instant motion it enters on the next frame', (
      tester,
    ) async {
      h = _Harness();
      await tester.pumpWidget(h.app(speed: ChromeMotionSpeed.instant));
      final handle = h.controller.show(const Bulletin(message: 'Copied'));
      await tester.pump();
      await tester.pump();
      expect(handle.isEntered, isTrue);
    });

    testWidgets('a replacement leaves while the new one enters', (
      tester,
    ) async {
      h = _Harness(policy: const BulletinPolicy.ios());
      await tester.pumpWidget(h.app());
      h.controller.show(const Bulletin(message: 'One'));
      await tester.pumpAndSettle();
      h.controller.show(const Bulletin(message: 'Two'));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('One'), findsOneWidget);
      expect(find.text('Two'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('One'), findsNothing);
      expect(find.text('Two'), findsOneWidget);
    });

    testWidgets('it is announced with its spoken label', (tester) async {
      h = _Harness();
      await tester.pumpWidget(h.app());
      h.controller.show(
        const Bulletin(title: 'Stickers removed', message: 'Cats'),
      );
      await tester.pump();
      expect(h.announced, ['Stickers removed\nCats']);
    });

    testWidgets('unmounting the host closes it as the surface gone', (
      tester,
    ) async {
      h = _Harness();
      await tester.pumpWidget(h.app());
      final handle = h.controller.show(const Bulletin(message: 'Copied'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(h.app(mounted: false));
      expect(handle.exit, BulletinExit.surfaceGone);
    });
  });

  group('layout', () {
    testWidgets('a bottom bulletin sits above the obstruction', (tester) async {
      h = _Harness(obstruction: const EdgeInsets.only(bottom: 100));
      await tester.pumpWidget(h.app());
      h.controller.show(const Bulletin(message: 'Copied'));
      await tester.pumpAndSettle();
      final card = tester.getRect(find.byType(BulletinCard));
      final surface = _surfaceRect(tester);
      // The Android policy keeps 16 from the sides of the free area and 8
      // from its bottom.
      expect(card.bottom, surface.bottom - 100 - 8);
      expect(card.left, surface.left + 16);
      expect(card.right, surface.right - 16);
      expect(card.height, greaterThanOrEqualTo(48));
    });

    testWidgets('it follows the obstruction when it moves', (tester) async {
      h = _Harness(obstruction: const EdgeInsets.only(bottom: 100));
      await tester.pumpWidget(h.app());
      h.controller.show(
        const Bulletin(
          message: 'Copied',
          duration: BulletinDuration.untilDismissed,
        ),
      );
      await tester.pumpAndSettle();
      h.obstruction.value = const EdgeInsets.only(bottom: 300);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final moving = tester.getRect(find.byType(BulletinCard)).bottom;
      final surface = _surfaceRect(tester);
      expect(moving, lessThan(surface.bottom - 108));
      expect(moving, greaterThan(surface.bottom - 308));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byType(BulletinCard)).bottom,
        surface.bottom - 300 - 8,
      );
    });

    testWidgets(
      'a tracked obstruction moves the bulletin on the frame it changes',
      (tester) async {
        h = _Harness(
          obstruction: const EdgeInsets.only(bottom: 100),
          tracksObstruction: true,
        );
        await tester.pumpWidget(h.app());
        h.controller.show(
          const Bulletin(
            message: 'Copied',
            duration: BulletinDuration.untilDismissed,
          ),
        );
        await tester.pumpAndSettle();
        final surface = _surfaceRect(tester);
        // A keyboard rising and falling frame by frame: the bulletin sits 8
        // above the obstruction on every frame, as the content under it does.
        for (final bottom in [
          140.0,
          210.0,
          290.0,
          340.0,
          360.0,
          250.0,
          100.0,
        ]) {
          h.obstruction.value = EdgeInsets.only(bottom: bottom);
          await tester.pump(const Duration(milliseconds: 16));
          expect(
            tester.getRect(find.byType(BulletinCard)).bottom,
            surface.bottom - bottom - 8,
            reason: 'obstruction $bottom',
          );
        }
      },
    );

    testWidgets('a desktop bulletin is centred and at most 380 wide', (
      tester,
    ) async {
      h = _Harness(policy: const BulletinPolicy.desktop());
      await tester.pumpWidget(h.app());
      h.controller.show(const Bulletin(message: 'Copied'));
      await tester.pumpAndSettle();
      final card = tester.getRect(find.byType(BulletinCard));
      final surface = _surfaceRect(tester);
      expect(card.center.dx, closeTo(surface.center.dx, 0.5));
      expect(card.center.dy, closeTo(surface.center.dy, 0.5));
      expect(card.width, lessThanOrEqualTo(380));
    });

    testWidgets('a top bulletin sits below the top obstruction', (
      tester,
    ) async {
      h = _Harness(obstruction: const EdgeInsets.only(top: 60));
      await tester.pumpWidget(h.app());
      h.controller.show(
        const Bulletin(message: 'Copied', placement: BulletinPlacement.top),
      );
      await tester.pumpAndSettle();
      final card = tester.getRect(find.byType(BulletinCard));
      expect(card.top, _surfaceRect(tester).top + 60 + 8);
    });
  });

  group('gestures', () {
    testWidgets('pressing holds the timer where the policy says', (
      tester,
    ) async {
      h = _Harness();
      await tester.pumpWidget(h.app());
      final handle = h.controller.show(const Bulletin(message: 'Copied'));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(BulletinCard)),
      );
      await tester.pump();
      expect(handle.isPaused, isTrue);
      await gesture.up();
      await tester.pump();
      expect(handle.isPaused, isFalse);
    });

    testWidgets('pressing does not hold the timer on iOS', (tester) async {
      h = _Harness(policy: const BulletinPolicy.ios());
      await tester.pumpWidget(h.app());
      final handle = h.controller.show(const Bulletin(message: 'Copied'));
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(BulletinCard)),
      );
      await tester.pump();
      expect(handle.isPaused, isFalse);
      await gesture.up();
    });

    testWidgets('a swipe past a third of the width throws it away', (
      tester,
    ) async {
      h = _Harness();
      await tester.pumpWidget(h.app());
      final handle = h.controller.show(const Bulletin(message: 'Copied'));
      await tester.pumpAndSettle();
      await tester.timedDrag(
        find.byType(BulletinCard),
        const Offset(200, 0),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      expect(handle.exit, BulletinExit.swiped);
      expect(find.text('Copied'), findsNothing);
    });

    testWidgets('a short slow drag springs back', (tester) async {
      h = _Harness();
      await tester.pumpWidget(h.app());
      final handle = h.controller.show(const Bulletin(message: 'Copied'));
      await tester.pumpAndSettle();
      final before = tester.getRect(find.byType(BulletinCard));
      await tester.timedDrag(
        find.byType(BulletinCard),
        const Offset(40, 0),
        const Duration(seconds: 1),
      );
      await tester.pumpAndSettle();
      expect(handle.isClosed, isFalse);
      expect(tester.getRect(find.byType(BulletinCard)), before);
    });

    testWidgets('no swipe on iOS', (tester) async {
      h = _Harness(policy: const BulletinPolicy.ios());
      await tester.pumpWidget(h.app());
      final handle = h.controller.show(const Bulletin(message: 'Copied'));
      await tester.pumpAndSettle();
      await tester.timedDrag(
        find.byType(BulletinCard),
        const Offset(300, 0),
        const Duration(milliseconds: 100),
      );
      await tester.pumpAndSettle();
      expect(handle.isClosed, isFalse);
    });

    testWidgets('a tap on the body calls onTap and keeps the bulletin', (
      tester,
    ) async {
      h = _Harness(policy: const BulletinPolicy.ios());
      var taps = 0;
      await tester.pumpWidget(h.app());
      final handle = h.controller.show(
        Bulletin(message: 'Copied', onTap: () => taps++),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copied'));
      expect(taps, 1);
      expect(handle.isClosed, isFalse);
    });
  });

  group('action', () {
    testWidgets('Undo is labelled from the strings and undoes', (tester) async {
      h = _Harness();
      var undos = 0;
      var commits = 0;
      await tester.pumpWidget(h.app());
      final handle = h.controller.show(
        Bulletin(
          message: 'Stickers removed',
          action: BulletinAction.undo(
            onUndo: () => undos++,
            onCommit: () => commits++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(handle.exit, BulletinExit.undone);
      expect((undos, commits), (1, 0));
    });

    testWidgets('a button shows its label and runs', (tester) async {
      h = _Harness();
      var presses = 0;
      await tester.pumpWidget(h.app());
      final handle = h.controller.show(
        Bulletin(
          message: 'GIF saved',
          action: BulletinAction.button(
            label: 'View',
            onPressed: () => presses++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('View'));
      expect(presses, 1);
      expect(handle.exit, BulletinExit.actionPressed);
    });

    testWidgets('the stock action presses with the chrome ink in the accent', (
      tester,
    ) async {
      h = _Harness();
      await tester.pumpWidget(h.app());
      h.controller.show(
        Bulletin(
          message: 'GIF saved',
          action: BulletinAction.button(label: 'View', onPressed: () {}),
        ),
      );
      await tester.pumpAndSettle();
      final ink = tester.widget<ChromeInk>(
        find.ancestor(of: find.text('View'), matching: find.byType(ChromeInk)),
      );
      expect(ink.color.a, lessThan(1));
      expect(ink.onTap, isNotNull);
      h.controller.dismiss();
      await tester.pumpAndSettle();
    });

    testWidgets('the spoken dismiss action dismisses', (tester) async {
      h = _Harness();
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(h.app());
      final handle = h.controller.show(const Bulletin(message: 'Copied'));
      await tester.pumpAndSettle();
      tester.semantics.customAction(
        find.semantics.byLabel('Copied'),
        const CustomSemanticsAction(label: 'Dismiss'),
      );
      await tester.pump();
      expect(handle.exit, BulletinExit.dismissed);
      semantics.dispose();
    });
  });

  group('builders', () {
    testWidgets('the host resolves a thumbnail and a custom frame', (
      tester,
    ) async {
      h = _Harness();
      final seen = <Object>[];
      await tester.pumpWidget(
        h.app(
          builders: BulletinBuilders(
            thumbnail: (context, source, view) {
              seen.add(source);
              return const SizedBox(key: ValueKey('thumb'));
            },
            frame: (context, view, child) => DecoratedBox(
              key: const ValueKey('frame'),
              decoration: const BoxDecoration(),
              child: child,
            ),
          ),
        ),
      );
      h.controller.show(
        const Bulletin(
          message: 'Added to favourites',
          leading: BulletinLeading.thumbnail('sticker-1'),
        ),
      );
      await tester.pumpAndSettle();
      expect(seen, contains('sticker-1'));
      expect(find.byKey(const ValueKey('thumb')), findsOneWidget);
      expect(find.byKey(const ValueKey('frame')), findsOneWidget);
    });

    testWidgets('an animation without a builder keeps an empty slot', (
      tester,
    ) async {
      h = _Harness();
      await tester.pumpWidget(h.app());
      h.controller.show(
        const Bulletin(
          message: 'Copied',
          leading: BulletinLeading.animation('copy'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(BulletinLeadingSlot), findsOneWidget);
      expect(
        tester.getSize(find.byType(BulletinLeadingSlot)).width,
        const BulletinPolicy.android().leadingWidth,
      );
    });

    testWidgets('the countdown shows the seconds left', (tester) async {
      h = _Harness();
      await tester.pumpWidget(h.app());
      h.controller.show(
        Bulletin(
          message: 'Removed',
          leading: const BulletinLeading.countdown(),
          action: BulletinAction.undo(onUndo: () {}),
        ),
      );
      // The ring redraws every frame, so nothing settles: pump past the
      // enter instead.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('5'), findsOneWidget);
      h.clock.advance(const Duration(milliseconds: 1200));
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.text('4'), findsOneWidget);
      h.controller.dismiss();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('an icon leading draws the chrome icon', (tester) async {
      h = _Harness();
      await tester.pumpWidget(h.app());
      h.controller.show(
        const Bulletin(
          message: 'Copied',
          leading: BulletinLeading.icon(ChromeIconId.confirm),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ChromeIcon), findsOneWidget);
    });
  });
}
