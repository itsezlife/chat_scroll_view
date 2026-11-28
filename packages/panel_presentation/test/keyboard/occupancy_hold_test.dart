/// The occupancy hold: the keyboard-replacement slot keeps its bottom
/// occupancy at the keyboard's height while the keyboard is hidden, with no
/// animation, until the host releases it; then the slot behaves as before.
///
/// **Seam:** `KeyboardSlot.holdOccupancy` and the hold it returns, over a
/// `FakeImeInput` and a `ManualPanelClock`, with `RecordingDiagnostics`
/// installed; the hold's release motion is moved by `advanceHold`.
library;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen/listen.dart' as listen;
import 'package:panel_presentation/panel_presentation.dart';
import 'package:panel_presentation/testing.dart';

/// 200 ms, linear: halfway through is exactly half way.
const _shrink = MotionSpec(Duration(milliseconds: 200), Curves.linear);
const _slide = MotionSpec(Duration(milliseconds: 200), Curves.linear);

void main() {
  late RecordingDiagnostics diagnostics;
  late FakeImeInput ime;
  late ManualPanelClock clock;
  late listen.ValueNotifier<PanelWindow> window;
  late KeyboardSlot slot;

  setUp(() async {
    diagnostics = RecordingDiagnostics.install();
    ime = FakeImeInput();
    clock = ManualPanelClock();
    window = listen.ValueNotifier(const PanelWindow(width: 400, height: 800));
    final heights = await KeyboardHeightStore.open(FakeKeyValueStore());
    slot = KeyboardSlot(
      ime: ime,
      heights: heights,
      window: window,
      clock: clock,
    );
    addTearDown(() {
      slot.dispose();
      window.dispose();
      ime.dispose();
    });
  });

  double bottom() => slot.occupancy.value.bottom;
  void settled(double height) => ime.report(ImeSample(height: height));
  void moving(double height) =>
      ime.report(ImeSample(height: height, animating: true));

  group('while held', () {
    test('the occupancy stays at the keyboard height as the keyboard hides, '
        'with no animation', () {
      settled(300);
      slot.holdOccupancy(_shrink);

      moving(200);
      expect(bottom(), 300);
      moving(40);
      settled(0);

      expect(bottom(), 300);
      expect(slot.animating.value, isFalse);
      expect(slot.holdAnimating.value, isFalse);
      expect(slot.state.value, KeyboardSlotState.idle);
    });

    test('reports its start with the held height', () {
      settled(300);
      slot.holdOccupancy(_shrink);

      expect(diagnostics.whereOp(PanelPresentationOp.occupancyHold), [
        isChatEvent(
          level: ChatEventLevel.debug,
          category: ChatEventCategory.overlay,
          fields: {'phase': 'start', 'heightPx': 300},
        ),
      ]);
    });

    test('a keyboard taller than the hold still lifts the occupancy', () {
      settled(300);
      slot.holdOccupancy(_shrink);
      settled(340);

      expect(bottom(), 340);
    });
  });

  group('released', () {
    test('a keyboard that reopened takes the held height over', () {
      settled(300);
      final hold = slot.holdOccupancy(_shrink);
      settled(0);
      moving(120);
      expect(bottom(), 300);

      hold.release();
      expect(bottom(), 300, reason: 'the rising keyboard has not reached it');
      moving(250);
      expect(bottom(), 300);
      settled(300);
      expect(bottom(), 300);

      settled(0);
      expect(bottom(), 0, reason: 'the slot follows the keyboard again');
      expect(
        diagnostics.whereOp(PanelPresentationOp.occupancyHold).last,
        isChatEvent(fields: {'phase': 'end', 'heightPx': 300}),
      );
    });

    test('a keyboard that stays down lets the slot shrink with the motion', () {
      settled(300);
      final hold = slot.holdOccupancy(_shrink);
      settled(0);

      hold.release();
      expect(slot.holdAnimating.value, isTrue);
      expect(bottom(), 300);
      slot.advanceHold(const Duration(milliseconds: 100));
      expect(bottom(), 150);
      slot.advanceHold(const Duration(milliseconds: 100));
      expect(bottom(), 0);
      expect(slot.holdAnimating.value, isFalse);

      moving(80);
      expect(bottom(), 80, reason: 'the slot follows the keyboard again');
    });

    test('a keyboard that settles below the held height shrinks the slot to '
        'it', () {
      settled(300);
      final hold = slot.holdOccupancy(_shrink);
      settled(0);
      moving(100);
      hold.release();

      settled(260);
      expect(slot.holdAnimating.value, isTrue);
      slot.advanceHold(const Duration(milliseconds: 200));
      expect(bottom(), 260);
    });

    test('a keyboard still moving after the hand-off timeout gives the held '
        'height up', () {
      settled(300);
      final hold = slot.holdOccupancy(_shrink);
      moving(40);
      hold.release();

      clock.advance(const KeyboardReplacementTuning().handOffTimeout);
      slot.advanceHold(const Duration(milliseconds: 200));

      expect(bottom(), 40);
    });

    test('the panel opens as before once released', () {
      settled(300);
      final hold = slot.holdOccupancy(_shrink);
      settled(0);
      hold.release();
      slot.advanceHold(const Duration(seconds: 1));

      slot.open(_slide);
      clock.advance(const Duration(seconds: 1));
      slot.advance(const Duration(seconds: 1));

      expect(slot.state.value, KeyboardSlotState.open);
      expect(bottom(), 300, reason: 'the measured keyboard height');
    });

    test('release is idempotent; holds are counted', () {
      settled(300);
      final first = slot.holdOccupancy(_shrink);
      final second = slot.holdOccupancy(_shrink);
      settled(0);

      first
        ..release()
        ..release();
      expect(bottom(), 300);
      expect(slot.holdAnimating.value, isFalse);

      second.release();
      expect(slot.holdAnimating.value, isTrue);
      expect(
        diagnostics.whereOp(PanelPresentationOp.occupancyHold),
        hasLength(2),
      );
    });

    test('a hold after dispose is inert', () {
      slot.dispose();

      expect(() => slot.holdOccupancy(_shrink).release(), returnsNormally);
    });
  });

  group('the strategy', () {
    testWidgets('holds and shrinks on frames of its own, with no panel ever '
        'shown', (tester) async {
      final heights = await KeyboardHeightStore.open(FakeKeyValueStore());
      final strategy = KeyboardReplacementStrategy(
        ime: ime,
        heights: heights,
        window: window,
        clock: clock,
      );
      addTearDown(strategy.dispose);
      settled(300);

      final hold = strategy.holdOccupancy(_shrink);
      settled(0);
      expect(strategy.occupancy.value.bottom, 300);

      hold.release();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(strategy.occupancy.value.bottom, closeTo(150, 1));
      await tester.pump(const Duration(milliseconds: 150));
      expect(strategy.occupancy.value.bottom, 0);
      expect(tester.binding.transientCallbackCount, 0);
    });
  });
}
