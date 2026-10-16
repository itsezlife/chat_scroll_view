import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_presentation/panel_presentation.dart';
import 'package:panel_presentation/testing.dart';
import 'package:panel_shell/panel_shell.dart';
import 'package:panel_shell/testing.dart';

const _ms = Duration(milliseconds: 1);

/// The slot box a host reserves: as tall as the occupancy, with the view in
/// it, under a filler for the chat.
class _Host extends StatefulWidget {
  const _Host({required this.controller});

  final PanelPresentationController controller;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  void initState() {
    super.initState();
    widget.controller.occupancy.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.controller.occupancy.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() => setState(() {});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const Expanded(child: SizedBox.expand()),
      SizedBox(
        key: const ValueKey('slot'),
        height: widget.controller.occupancy.value.bottom,
        child: PanelPresentationView(controller: widget.controller),
      ),
    ],
  );
}

void main() {
  late FakeImeInput ime;
  late ObservableValue<PanelWindow> window;
  late KeyboardHeightStore heights;
  late KeyboardReplacementStrategy keyboard;
  late PanelShellController shell;
  late FakePanelPage emojiPage;
  late PanelPresentationController controller;

  setUp(() async {
    ime = FakeImeInput();
    window = ObservableValue(const PanelWindow(width: 400, height: 600));
    heights = await KeyboardHeightStore.open(FakeKeyValueStore());
    keyboard = KeyboardReplacementStrategy(
      ime: ime,
      heights: heights,
      window: window,
    );
    emojiPage = FakePanelPage('emoji', search: true);
    shell = PanelShellController(
      pages: [emojiPage.page, FakePanelPage('stickers').page],
      preferences: FakePreferenceStore(),
    );
    controller = PanelPresentationController(
      shell: shell,
      policy: const PanelPresentationPolicy$Mobile(),
      strategies: [keyboard],
      window: window.value,
    );
  });

  double bottom() => controller.occupancy.value.bottom;

  Future<void> mount(
    WidgetTester tester, {
    ChromeMotionSpeed speed = ChromeMotionSpeed.normal,
    ChromeMotion? motion,
  }) => tester.pumpWidget(
    PanelShellTestScope(
      speed: speed,
      child: ChromeMotionScope(
        motion: motion,
        child: _Host(controller: controller),
      ),
    ),
  );

  /// Builds the frame, applies the visibility after it and starts the motion
  /// after the cold-open delay.
  Future<void> startOpen(WidgetTester tester) async {
    controller.show();
    await tester.pump();
    await tester.pump();
  }

  Future<void> finishMotion(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  Future<void> tearDownTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    controller.dispose();
    shell.dispose();
    keyboard.dispose();
    window.dispose();
    ime.dispose();
  }

  group('cold open', () {
    testWidgets('grows the slot to the default height, then rests', (
      tester,
    ) async {
      await mount(tester);
      await startOpen(tester);
      expect(controller.state.value, isA<PanelVisibility$Showing>());
      expect(shell.opening.value, isTrue);
      expect(bottom(), 0);

      await tester.pump(const Duration(milliseconds: 49));
      expect(bottom(), 0, reason: 'the page mounts before anything moves');
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(bottom(), inExclusiveRange(0, 200));

      await finishMotion(tester);
      expect(bottom(), 200);
      expect(controller.state.value, isA<PanelVisibility$Shown>());
      expect(shell.opening.value, isFalse);
      expect(shell.visible.value, isTrue);
      await tearDownTree(tester);
    });

    testWidgets('rebuilds nothing under the sheet while the slot grows', (
      tester,
    ) async {
      await mount(tester);
      await startOpen(tester);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 16));
      final built = emojiPage.buildCount;
      expect(built, greaterThan(0));

      var frames = 0;
      while (bottom() < 200 && frames < 60) {
        await tester.pump(const Duration(milliseconds: 16));
        frames++;
      }
      expect(frames, greaterThan(5), reason: 'a real motion, not a jump');
      expect(emojiPage.buildCount, built, reason: 'frames only move the clip');
      await tearDownTree(tester);
    });

    testWidgets('lays the sheet out at full height while the slot grows', (
      tester,
    ) async {
      await mount(tester);
      await startOpen(tester);
      await tester.pump(const Duration(milliseconds: 100));
      expect(bottom(), lessThan(200));
      expect(tester.getSize(find.byType(PanelShell)).height, 200);
      await finishMotion(tester);
      await tearDownTree(tester);
    });

    testWidgets('moves on the listTransition role', (tester) async {
      await mount(
        tester,
        motion: const ChromeMotion.standard().copyWith(
          listTransition: const MotionSpec(Duration(seconds: 1), Curves.linear),
        ),
      );
      await startOpen(tester);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 500));
      expect(bottom(), closeTo(100, 5));
      await tester.pump(const Duration(milliseconds: 600));
      expect(bottom(), 200);
      await tearDownTree(tester);
    });

    testWidgets('lands at once under instant motion', (tester) async {
      await mount(tester, speed: ChromeMotionSpeed.instant);
      await startOpen(tester);
      expect(bottom(), 200);
      expect(controller.state.value, isA<PanelVisibility$Shown>());
      await tearDownTree(tester);
    });
  });

  group('open over the soft keyboard', () {
    testWidgets('takes the slot at once at the keyboard height', (
      tester,
    ) async {
      ime.report(const ImeSample(height: 320));
      await mount(tester);
      await startOpen(tester);

      expect(bottom(), 320);
      expect(keyboard.state.value, KeyboardSlotState.replacing);
      expect(controller.state.value, isA<PanelVisibility$Shown>());
      await tearDownTree(tester);
    });

    testWidgets('keeps the slot while the keyboard goes away beneath', (
      tester,
    ) async {
      ime.report(const ImeSample(height: 320));
      await mount(tester);
      await startOpen(tester);
      ime.rampTo(0, steps: 4);
      await tester.pump();

      expect(bottom(), 320);
      expect(keyboard.state.value, KeyboardSlotState.open);
      await tearDownTree(tester);
    });
  });

  group('cold close', () {
    testWidgets('shrinks the slot, then unmounts the panel', (tester) async {
      await mount(tester);
      await startOpen(tester);
      await finishMotion(tester);

      controller.hide();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(bottom(), inExclusiveRange(0, 200));
      expect(find.byType(PanelShell), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(bottom(), 0);
      expect(controller.state.value, PanelVisibility.hidden);
      expect(find.byType(PanelShell), findsNothing);
      expect(shell.visible.value, isFalse);
      await tearDownTree(tester);
    });
  });

  group('hand-off to the soft keyboard', () {
    Future<void> openThenHide(WidgetTester tester) async {
      await heights.record(PanelOrientation.portrait, 310);
      await mount(tester);
      await startOpen(tester);
      await finishMotion(tester);
      expect(bottom(), 310);
      controller.hide(waitForIme: true);
      await tester.pump();
      await tester.pump();
    }

    testWidgets('keeps the emptied sheet until the keyboard has risen', (
      tester,
    ) async {
      await openThenHide(tester);
      expect(controller.state.value, isA<PanelVisibility$Hiding>());
      expect(bottom(), 310);
      expect(find.byType(PanelShell), findsNothing, reason: 'emptied');
      expect(find.byType(PanelShell, skipOffstage: false), findsOneWidget);

      ime.rampTo(310, steps: 3);
      await tester.pump();
      expect(controller.state.value, PanelVisibility.hidden);
      expect(bottom(), 310, reason: 'the keyboard holds the slot');
      expect(find.byType(PanelShell, skipOffstage: false), findsNothing);
      await tearDownTree(tester);
    });

    testWidgets('closes cold when the keyboard never comes', (tester) async {
      await openThenHide(tester);
      await tester.pump(const Duration(milliseconds: 999));
      expect(controller.state.value, isA<PanelVisibility$Hiding>());
      expect(bottom(), 310);

      await tester.pump(_ms);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(controller.state.value, PanelVisibility.hidden);
      expect(bottom(), 0);
      await tearDownTree(tester);
    });

    testWidgets('showing again restores the content without a flash', (
      tester,
    ) async {
      await openThenHide(tester);
      controller.show();
      await tester.pump();
      await tester.pump();

      expect(bottom(), 310);
      expect(controller.state.value, isA<PanelVisibility$Shown>());
      expect(find.byType(PanelShell), findsOneWidget);
      await tearDownTree(tester);
    });
  });

  group('search', () {
    testWidgets('expands the panel and handleBack closes search first', (
      tester,
    ) async {
      await mount(tester);
      await startOpen(tester);
      await finishMotion(tester);
      expect(bottom(), 200);

      shell.openSearch();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(bottom(), 375);

      expect(controller.handleBack(), isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(shell.search.value.isOpen, isFalse);
      expect(bottom(), 200);
      expect(controller.state.value, isA<PanelVisibility$Shown>());

      expect(controller.handleBack(), isTrue);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(controller.state.value, PanelVisibility.hidden);
      await tearDownTree(tester);
    });

    testWidgets('is capped by what the window leaves', (tester) async {
      await mount(tester);
      await startOpen(tester);
      await finishMotion(tester);

      shell.openSearch();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // 600 high window, no insets, minus the 62 reserve: 538 is no cap.
      expect(bottom(), lessThanOrEqualTo(538));
      await tearDownTree(tester);
    });

    testWidgets('a search that was open when the panel mounted is expanded', (
      tester,
    ) async {
      shell.openSearch();
      await mount(tester);
      await startOpen(tester);
      await finishMotion(tester);
      expect(bottom(), 375);
      await tearDownTree(tester);
    });
  });

  group('safe area', () {
    testWidgets('the panel sheet gets the safe band the host reported', (
      tester,
    ) async {
      ime.report(const ImeSample(height: 0, safeAreaBottom: 48));
      await mount(tester);
      await startOpen(tester);
      await finishMotion(tester);

      expect(bottom(), 248);
      expect(tester.getSize(find.byType(PanelShell)).height, 248);
      expect(find.byType(KeyboardNavBarFade), findsOneWidget);
      expect(keyboard.composerSafeInset.value, 0);
      await tearDownTree(tester);
    });

    testWidgets('a panel without a safe band draws no scrim', (tester) async {
      await mount(tester);
      await startOpen(tester);
      await finishMotion(tester);
      expect(find.byType(KeyboardNavBarFade), findsNothing);
      await tearDownTree(tester);
    });

    testWidgets('the shell is told the band as its own bottom padding', (
      tester,
    ) async {
      ime.report(const ImeSample(height: 0, safeAreaBottom: 40));
      await mount(tester);
      await startOpen(tester);
      await finishMotion(tester);
      final media = MediaQuery.of(tester.element(find.byType(PanelShell)));
      expect(media.padding.bottom, 40);
      expect(media.viewInsets.bottom, 0);
      await tearDownTree(tester);
    });
  });

  group('without a view', () {
    testWidgets('the occupancy follows the keyboard while hidden', (
      tester,
    ) async {
      ime.report(const ImeSample(height: 250, animating: true));
      expect(bottom(), 250);
      ime.report(const ImeSample(height: 310));
      expect(bottom(), 310);
      expect(controller.state.value, PanelVisibility.hidden);
      controller
        ..dispose()
        ..shell.dispose();
      keyboard.dispose();
      window.dispose();
      ime.dispose();
    });

    testWidgets('unmounting the view mid-open lets go of the slot', (
      tester,
    ) async {
      await mount(tester);
      await startOpen(tester);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 100));
      expect(bottom(), greaterThan(0));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(controller.state.value, isA<PanelVisibility$Shown>());
      expect(bottom(), 0);
      expect(keyboard.state.value, KeyboardSlotState.idle);
      await tearDownTree(tester);
    });

    testWidgets('remounting a shown panel lays it out at rest', (tester) async {
      await heights.record(PanelOrientation.portrait, 310);
      controller.show();
      expect(controller.state.value, isA<PanelVisibility$Shown>());
      await mount(tester);
      await tester.pump();
      await tester.pump();
      expect(bottom(), 310);
      expect(find.byType(PanelShell), findsOneWidget);
      await tearDownTree(tester);
    });
  });
}
