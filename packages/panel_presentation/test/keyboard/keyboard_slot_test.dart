import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen/listen.dart' as listen;
import 'package:panel_presentation/panel_presentation.dart';
import 'package:panel_presentation/testing.dart';

/// 200 ms, linear: halfway through is exactly half way.
const _slide = MotionSpec(Duration(milliseconds: 200), Curves.linear);
const _search = MotionSpec(Duration(milliseconds: 100), Curves.linear);
const _ms = Duration(milliseconds: 1);

const _portrait = PanelWindow(width: 400, height: 800);
const _landscape = PanelWindow(width: 800, height: 400);

/// A keyboard slot over scripted collaborators.
final class _Rig {
  _Rig._(this.kv, this.heights, this.window, this.slot);

  static Future<_Rig> create({
    PanelWindow window = _portrait,
    FakeKeyValueStore? kv,
  }) async {
    final store = kv ?? FakeKeyValueStore();
    final heights = await KeyboardHeightStore.open(store);
    final windowValue = listen.ValueNotifier<PanelWindow>(window);
    final rig = _Rig._(
      store,
      heights,
      windowValue,
      KeyboardSlot(
        ime: ime,
        heights: heights,
        window: windowValue,
        clock: clock,
      ),
    );
    return rig;
  }

  static late FakeImeInput ime;
  static late ManualPanelClock clock;

  final FakeKeyValueStore kv;
  final KeyboardHeightStore heights;
  final listen.ValueNotifier<PanelWindow> window;
  final KeyboardSlot slot;

  double get bottom => slot.occupancy.value.bottom;
  KeyboardSlotState get state => slot.state.value;

  /// Runs the cold-open delay and the whole slide.
  void finishMotion([MotionSpec spec = _slide]) {
    clock.advance(const Duration(seconds: 1));
    slot.advance(spec.duration * 2);
  }

  void settled(double height, {double safe = 0}) =>
      ime.report(ImeSample(height: height, safeAreaBottom: safe));

  void moving(double height, {double safe = 0}) => ime.report(
    ImeSample(height: height, animating: true, safeAreaBottom: safe),
  );
}

void main() {
  late _Rig rig;

  setUp(() async {
    _Rig.ime = FakeImeInput();
    _Rig.clock = ManualPanelClock();
    rig = await _Rig.create();
    addTearDown(() {
      rig.slot.dispose();
      rig.window.dispose();
      _Rig.ime.dispose();
    });
  });

  group('idle', () {
    test('follows the soft keyboard sample for sample', () {
      expect(rig.state, KeyboardSlotState.idle);
      expect(rig.bottom, 0);
      rig.moving(120);
      expect(rig.bottom, 120);
      rig.moving(310);
      rig.settled(310);
      expect(rig.bottom, 310);
      rig.moving(40);
      expect(rig.bottom, 40);
      rig.settled(0);
      expect(rig.bottom, 0);
    });

    test('takes no animation: the occupancy is the sample', () {
      rig.settled(310);
      expect(rig.slot.animating.value, isFalse);
    });
  });

  group('cold open', () {
    test('waits the cold-open delay, then grows to the default height', () {
      rig.slot.open(_slide);
      expect(rig.state, KeyboardSlotState.opening);
      expect(rig.bottom, 0);
      expect(rig.slot.animating.value, isFalse);

      _Rig.clock.advance(const Duration(milliseconds: 49));
      rig.slot.advance(const Duration(milliseconds: 100));
      expect(rig.bottom, 0, reason: 'nothing moves before the delay');

      _Rig.clock.advance(_ms);
      expect(rig.slot.animating.value, isTrue);
      rig.slot.advance(const Duration(milliseconds: 100));
      expect(rig.bottom, 100);
      expect(rig.state, KeyboardSlotState.opening);

      rig.slot.advance(const Duration(milliseconds: 100));
      expect(rig.bottom, 200);
      expect(rig.state, KeyboardSlotState.open);
      expect(rig.slot.animating.value, isFalse);
    });

    test('opens to the stored height of the current orientation', () async {
      await rig.heights.record(PanelOrientation.portrait, 310);
      await rig.heights.record(PanelOrientation.landscape, 190);
      rig.slot.open(_slide);
      rig.finishMotion();
      expect(rig.bottom, 310);
    });

    test('a larger window class defaults to a taller panel', () async {
      rig.window.value = const PanelWindow(width: 900, height: 1200);
      rig.slot.open(_slide);
      rig.finishMotion();
      expect(rig.bottom, const KeyboardReplacementTuning().expandedHeight);
    });

    test('the sheet keeps its full height while the slot grows', () {
      rig.slot.open(_slide);
      expect(rig.slot.layoutHeight, 200);
      _Rig.clock.advance(const Duration(milliseconds: 50));
      rig.slot.advance(const Duration(milliseconds: 100));
      expect(rig.bottom, 100);
      expect(rig.slot.layoutHeight, 200, reason: 'content must not reflow');
    });

    test('an instant motion lands open at once, without the delay', () {
      rig.slot.open(const MotionSpec(Duration.zero, Curves.linear));
      expect(rig.state, KeyboardSlotState.open);
      expect(rig.bottom, 200);
    });

    test('animate: false lands open at once', () {
      rig.slot.open(_slide, animate: false);
      expect(rig.state, KeyboardSlotState.open);
      expect(rig.bottom, 200);
    });

    test('opening twice changes nothing', () {
      rig.slot.open(_slide);
      rig.finishMotion();
      rig.slot.open(_slide);
      expect(rig.state, KeyboardSlotState.open);
      expect(rig.bottom, 200);
    });
  });

  group('open from the soft keyboard', () {
    test('claims the slot at once at the keyboard height', () {
      rig.settled(310);
      rig.slot.open(_slide);
      expect(rig.state, KeyboardSlotState.replacing);
      expect(rig.bottom, 310);
      expect(rig.slot.animating.value, isFalse);
    });

    test('is at least as tall as the keyboard it replaces', () async {
      await rig.heights.record(PanelOrientation.portrait, 300);
      rig.settled(320);
      rig.slot.open(_slide);
      expect(rig.bottom, 320);
    });

    test('uses the stored height when the keyboard is shorter', () async {
      await rig.heights.record(PanelOrientation.portrait, 340);
      rig.settled(310);
      rig.slot.open(_slide);
      expect(rig.bottom, 340);
    });

    test('holds through the keyboard glitch 310, 0, 310, 200, 0', () {
      rig.settled(310);
      rig.slot.open(_slide);
      for (final h in <double>[0, 310, 200, 0]) {
        rig.settled(h);
        expect(rig.bottom, 310, reason: 'sample $h');
      }
      expect(rig.state.holdsSlot, isTrue);
    });

    test('is open once the keyboard has gone from beneath', () {
      rig.settled(310);
      rig.slot.open(_slide);
      rig.moving(150);
      expect(rig.state, KeyboardSlotState.replacing);
      rig.settled(0);
      expect(rig.state, KeyboardSlotState.open);
      expect(rig.bottom, 310);
    });

    test('a rising keyboard never closes the panel', () {
      rig.settled(300);
      rig.slot.open(_slide);
      rig
        ..settled(0)
        ..settled(0)
        ..settled(300);
      expect(rig.state.holdsSlot, isTrue);
      expect(rig.bottom, 300);
    });
  });

  group('cold close', () {
    test('shrinks to nothing and releases the slot', () {
      rig.slot.open(_slide);
      rig.finishMotion();

      rig.slot.close(_slide);
      expect(rig.state, KeyboardSlotState.closing);
      rig.slot.advance(const Duration(milliseconds: 100));
      expect(rig.bottom, 100);
      expect(rig.slot.layoutHeight, 200, reason: 'content must not reflow');
      rig.slot.advance(const Duration(milliseconds: 100));
      expect(rig.bottom, 0);
      expect(rig.state, KeyboardSlotState.idle);
    });

    test('never publishes a negative extent', () {
      rig.slot.open(_slide);
      rig.finishMotion();
      rig.slot.close(_slide);
      var lowest = double.infinity;
      rig.slot.occupancy.addListener(() {
        if (rig.bottom < lowest) lowest = rig.bottom;
      });
      for (var i = 0; i < 30; i++) {
        rig.slot.advance(const Duration(milliseconds: 10));
      }
      expect(lowest, greaterThanOrEqualTo(0));
    });

    test('closing an idle slot changes nothing', () {
      rig.slot.close(_slide);
      expect(rig.state, KeyboardSlotState.idle);
    });

    test('reopening mid-close turns the slot back from where it is', () {
      rig.slot.open(_slide);
      rig.finishMotion();
      rig.slot.close(_slide);
      rig.slot.advance(const Duration(milliseconds: 100));
      expect(rig.bottom, 100);

      rig.slot.open(_slide);
      expect(rig.state, KeyboardSlotState.opening);
      expect(rig.bottom, 100, reason: 'no jump');
      rig.slot.advance(const Duration(milliseconds: 100));
      expect(rig.bottom, 150);
      rig.slot.advance(const Duration(milliseconds: 100));
      expect(rig.bottom, 200);
      expect(rig.state, KeyboardSlotState.open);
    });

    test('while the keyboard rises beneath, the larger of the two shows', () {
      rig.slot.open(_slide);
      rig.finishMotion();
      rig.slot.close(_slide);
      rig.moving(150);
      rig.slot.advance(const Duration(milliseconds: 200));
      expect(rig.state, KeyboardSlotState.idle);
      expect(rig.bottom, 150);
    });
  });

  group('close to the soft keyboard', () {
    Future<void> openCold() async {
      await rig.heights.record(PanelOrientation.portrait, 310);
      rig.slot.open(_slide);
      rig.finishMotion();
      expect(rig.bottom, 310);
    }

    test(
      'holds the slot while the keyboard rises, then hands it over',
      () async {
        await openCold();
        rig.slot.close(_slide, waitForIme: true);
        expect(rig.state, KeyboardSlotState.handOffToIme);
        expect(rig.bottom, 310);

        rig
          ..moving(60)
          ..moving(180)
          ..moving(300);
        expect(rig.bottom, 310);
        expect(rig.state, KeyboardSlotState.handOffToIme);

        rig.settled(310);
        expect(rig.state, KeyboardSlotState.idle);
        expect(rig.bottom, 310);
      },
    );

    test('a keyboard that is already up takes over at once', () {
      rig.settled(310);
      rig.slot.open(_slide);
      rig.slot.close(_slide, waitForIme: true);
      expect(rig.state, KeyboardSlotState.idle);
      expect(rig.bottom, 310);
    });

    test(
      'a zero before the keyboard has risen does not release the hold',
      () async {
        await openCold();
        rig.slot.close(_slide, waitForIme: true);
        rig.settled(0);
        rig.moving(0);
        expect(rig.state, KeyboardSlotState.handOffToIme);
        expect(rig.bottom, 310);
      },
    );

    test(
      'does not dip below the held height when the keyboard undershoots',
      () async {
        await rig.heights.record(PanelOrientation.portrait, 310.4);
        rig.slot.open(_slide);
        rig.finishMotion();
        rig.slot.close(_slide, waitForIme: true);

        rig.settled(309.33);
        expect(rig.state, KeyboardSlotState.idle);
        expect(rig.bottom, 310.4);
        rig.settled(309.69);
        expect(rig.bottom, 310.4);
        rig.settled(310.4);
        expect(rig.bottom, 310.4);
      },
    );

    test('follows a real descent after the hand-off, to zero', () async {
      await rig.heights.record(PanelOrientation.portrait, 310.4);
      rig.slot.open(_slide);
      rig.finishMotion();
      rig.slot.close(_slide, waitForIme: true);
      rig.settled(309.33);

      for (final h in <double>[308, 280, 200, 100, 40, 8]) {
        rig.moving(h);
        expect(rig.bottom, h, reason: 'descent at $h');
      }
      rig.settled(0);
      expect(rig.bottom, 0);
    });

    test('a settled zero right after the hand-off is a real hide', () async {
      await openCold();
      rig.slot.close(_slide, waitForIme: true);
      rig.settled(310);
      rig.settled(0);
      expect(rig.bottom, 0);
    });

    test('gives up after the fallback timeout and closes cold', () async {
      await openCold();
      rig.slot.close(_slide, waitForIme: true);

      _Rig.clock.advance(const Duration(milliseconds: 999));
      expect(rig.state, KeyboardSlotState.handOffToIme);
      expect(rig.bottom, 310);

      _Rig.clock.advance(_ms);
      expect(rig.state, KeyboardSlotState.closing);
      rig.slot.advance(const Duration(milliseconds: 100));
      expect(rig.bottom, 155);
      rig.slot.advance(const Duration(milliseconds: 100));
      expect(rig.state, KeyboardSlotState.idle);
      expect(rig.bottom, 0);
    });

    test('the fallback timeout is cancelled by the hand-off', () async {
      await openCold();
      rig.slot.close(_slide, waitForIme: true);
      expect(_Rig.clock.pendingCount, 1);
      rig.settled(310);
      expect(_Rig.clock.pendingCount, 0);
    });

    test('the fallback timeout comes from the tuning', () async {
      final slot = KeyboardSlot(
        ime: _Rig.ime,
        heights: rig.heights,
        window: rig.window,
        clock: _Rig.clock,
        tuning: const KeyboardReplacementTuning(
          handOffTimeout: Duration(milliseconds: 300),
        ),
      );
      addTearDown(slot.dispose);
      slot.open(_slide, animate: false);
      slot.close(_slide, waitForIme: true);
      _Rig.clock.advance(const Duration(milliseconds: 300));
      expect(slot.state.value, KeyboardSlotState.closing);
    });

    test(
      'opening again during the hand-off keeps the slot without a jump',
      () async {
        await openCold();
        rig.slot.close(_slide, waitForIme: true);
        rig.slot.open(_slide);
        expect(rig.state, KeyboardSlotState.open);
        expect(rig.bottom, 310);
        expect(_Rig.clock.pendingCount, 0);
      },
    );

    test('a plain close during the hand-off closes cold', () async {
      await openCold();
      rig.slot.close(_slide, waitForIme: true);
      rig.slot.close(_slide);
      expect(rig.state, KeyboardSlotState.closing);
      expect(_Rig.clock.pendingCount, 0);
      rig.slot.advance(const Duration(milliseconds: 200));
      expect(rig.state, KeyboardSlotState.idle);
      expect(rig.bottom, 0);
    });

    test('closing to the keyboard twice changes nothing', () async {
      await openCold();
      rig.slot.close(_slide, waitForIme: true);
      rig.slot.close(_slide, waitForIme: true);
      expect(rig.state, KeyboardSlotState.handOffToIme);
      expect(_Rig.clock.pendingCount, 1);
    });

    test('the emptied sheet keeps the full height', () async {
      await openCold();
      rig.slot.close(_slide, waitForIme: true);
      expect(rig.slot.layoutHeight, 310);
    });
  });

  group('search', () {
    setUp(() async {
      rig.slot.open(_slide);
      rig.finishMotion();
      expect(rig.bottom, 200);
    });

    test('grows the panel by the expansion and back', () {
      rig.slot.setSearch(open: true, availableMax: 1000, spec: _search);
      rig.slot.advance(const Duration(milliseconds: 50));
      expect(rig.bottom, 287.5);
      rig.slot.advance(const Duration(milliseconds: 50));
      expect(rig.bottom, 375);
      expect(rig.state, KeyboardSlotState.open);

      rig.slot.setSearch(open: false, availableMax: 1000, spec: _search);
      rig.slot.advance(const Duration(milliseconds: 100));
      expect(rig.bottom, 200);
    });

    test('the sheet follows the growing slot', () {
      rig.slot.setSearch(open: true, availableMax: 1000, spec: _search);
      rig.slot.advance(const Duration(milliseconds: 50));
      expect(rig.slot.layoutHeight, 287.5);
    });

    test('is capped by the space the window leaves', () {
      rig.slot.setSearch(open: true, availableMax: 300, spec: _search);
      rig.slot.advance(const Duration(milliseconds: 100));
      expect(rig.bottom, 300);
    });

    test('never shrinks below the keyboard-sized height', () {
      rig.slot.setSearch(open: true, availableMax: 120, spec: _search);
      rig.slot.advance(const Duration(milliseconds: 100));
      expect(rig.bottom, 200);
    });

    test('takes the full expansion when the space is unknown', () {
      rig.slot.setSearch(
        open: true,
        availableMax: double.infinity,
        spec: _search,
      );
      rig.slot.advance(const Duration(milliseconds: 100));
      expect(rig.bottom, 375);
    });

    test('expands while the soft keyboard is up beneath', () {
      rig.slot.setSearch(open: true, availableMax: 1000, spec: _search);
      rig.slot.advance(const Duration(milliseconds: 100));
      rig.moving(150);
      rig.settled(300);
      expect(rig.bottom, 375, reason: 'the larger of keyboard and panel');

      rig.slot.setSearch(open: false, availableMax: 1000, spec: _search);
      rig.slot.advance(const Duration(milliseconds: 100));
      expect(rig.bottom, 300, reason: 'the keyboard still holds the slot');
      expect(rig.state.holdsSlot, isTrue);
    });

    test(
      'a hand-off collapses to the keyboard-sized height, not the expanded',
      () {
        rig.slot.setSearch(open: true, availableMax: 1000, spec: _search);
        rig.slot.advance(const Duration(milliseconds: 100));
        rig.slot.close(_search, waitForIme: true);
        expect(rig.state, KeyboardSlotState.handOffToIme);

        rig.slot.advance(const Duration(milliseconds: 100));
        expect(rig.bottom, 200);
        expect(rig.slot.animating.value, isFalse);
      },
    );

    test(
      'closing search that never expanded leaves the running motion alone',
      () {
        rig.slot.close(_slide);
        rig.slot.advance(const Duration(seconds: 1));
        rig.slot.open(_slide);
        _Rig.clock.advance(const Duration(milliseconds: 50));
        rig.slot.advance(const Duration(milliseconds: 50));
        rig.slot.setSearch(open: false, availableMax: 1000, spec: _search);
        rig.slot.advance(const Duration(milliseconds: 50));
        expect(rig.bottom, 100, reason: 'still on the 200 ms slide');
      },
    );

    test('is ignored while the slot is idle', () {
      rig.slot.close(_slide);
      rig.slot.advance(const Duration(seconds: 1));
      rig.slot.setSearch(open: true, availableMax: 1000, spec: _search);
      rig.slot.advance(const Duration(seconds: 1));
      expect(rig.bottom, 0);
    });

    test('a later open starts keyboard-sized even after an expanded close', () {
      rig.slot.setSearch(open: true, availableMax: 1000, spec: _search);
      rig.slot.advance(const Duration(milliseconds: 100));
      rig.slot.close(_slide);
      rig.slot.advance(const Duration(seconds: 1));
      rig.slot.open(_slide);
      rig.finishMotion();
      expect(rig.bottom, 200);
    });

    test('searching on a panel that is still opening retargets it', () {
      rig.slot.close(_slide);
      rig.slot.advance(const Duration(seconds: 1));
      rig.slot.open(_slide);
      rig.slot.setSearch(open: true, availableMax: 1000, spec: _search);
      rig.finishMotion();
      expect(rig.bottom, 375);
    });
  });

  group('rotation', () {
    test(
      'an open panel resizes to the height of the new orientation',
      () async {
        await rig.heights.record(PanelOrientation.portrait, 310);
        await rig.heights.record(PanelOrientation.landscape, 190);
        rig.slot.open(_slide);
        rig.finishMotion();
        expect(rig.bottom, 310);

        rig.window.value = _landscape;
        expect(rig.bottom, 190);
        expect(rig.state, KeyboardSlotState.open);

        rig.window.value = _portrait;
        expect(rig.bottom, 310);
      },
    );

    test(
      'an idle slot opens to the height of the orientation it is in',
      () async {
        await rig.heights.record(PanelOrientation.portrait, 310);
        await rig.heights.record(PanelOrientation.landscape, 190);
        rig.window.value = _landscape;
        rig.slot.open(_slide);
        rig.finishMotion();
        expect(rig.bottom, 190);
      },
    );

    test('a window resize inside one orientation changes nothing', () async {
      await rig.heights.record(PanelOrientation.portrait, 310);
      rig.slot.open(_slide);
      rig.finishMotion();
      rig.window.value = const PanelWindow(width: 420, height: 900);
      expect(rig.bottom, 310);
    });

    test('rotating during a hand-off holds the new height', () async {
      await rig.heights.record(PanelOrientation.portrait, 310);
      await rig.heights.record(PanelOrientation.landscape, 190);
      rig.slot.open(_slide);
      rig.finishMotion();
      rig.slot.close(_slide, waitForIme: true);
      rig.window.value = _landscape;
      expect(rig.bottom, 190);
      rig.settled(190);
      expect(rig.state, KeyboardSlotState.idle);
      expect(rig.bottom, 190);
    });
  });

  group('measuring the keyboard', () {
    test('records a settled height in the orientation it was measured', () {
      rig.settled(310);
      expect(rig.heights.heightFor(PanelOrientation.portrait), 310);
      rig.window.value = _landscape;
      rig.settled(200);
      expect(rig.heights.heightFor(PanelOrientation.landscape), 200);
    });

    test('never records a reading taken while the keyboard moves', () {
      rig
        ..moving(120)
        ..moving(250)
        ..moving(310);
      expect(rig.heights.heightFor(PanelOrientation.portrait), isNull);
      rig.settled(310);
      expect(rig.heights.heightFor(PanelOrientation.portrait), 310);
    });

    test('records the keyboard without its bottom safe area', () {
      rig.settled(344, safe: 34);
      expect(rig.heights.heightFor(PanelOrientation.portrait), 310);
    });

    test('ignores a settled height below the sanity floor', () {
      rig.settled(59);
      expect(rig.heights.heightFor(PanelOrientation.portrait), isNull);
    });

    test('does not record while the panel holds the slot', () {
      rig.slot.open(_slide);
      rig.finishMotion();
      rig.settled(310);
      expect(rig.heights.heightFor(PanelOrientation.portrait), isNull);
    });

    test('records the keyboard that took over after a hand-off', () async {
      rig.slot.open(_slide);
      rig.finishMotion();
      rig.slot.close(_slide, waitForIme: true);
      rig.settled(210);
      expect(rig.heights.heightFor(PanelOrientation.portrait), 210);
    });
  });

  group('safe area', () {
    test('the composer keeps the whole band while nothing covers it', () {
      rig.settled(0, safe: 34);
      expect(rig.slot.composerSafeInset.value, 34);
    });

    test('the keyboard covers the band, so the composer drops its share', () {
      rig.settled(344, safe: 34);
      expect(rig.slot.composerSafeInset.value, 0);
    });

    test('the band is whatever the occupancy has not covered yet', () {
      rig.settled(0, safe: 34);
      rig.slot.open(_slide);
      _Rig.clock.advance(const Duration(milliseconds: 50));
      rig.slot.advance(const Duration(milliseconds: 20));
      expect(rig.bottom, closeTo(23.4, 0.01));
      expect(rig.slot.composerSafeInset.value, closeTo(10.6, 0.01));
      rig.slot.advance(const Duration(milliseconds: 20));
      expect(rig.slot.composerSafeInset.value, 0);
    });

    test('the bottom space is never less than the safe band', () {
      rig.settled(0, safe: 34);
      rig.slot.open(_slide);
      _Rig.clock.advance(const Duration(milliseconds: 50));
      for (var i = 0; i < 25; i++) {
        rig.slot.advance(const Duration(milliseconds: 10));
        expect(
          rig.bottom + rig.slot.composerSafeInset.value,
          greaterThanOrEqualTo(34),
        );
      }
    });

    test('the panel grows by the safe band: content height plus the band', () {
      rig.settled(0, safe: 34);
      rig.slot.open(_slide);
      rig.finishMotion();
      expect(rig.bottom, 234);
      expect(rig.slot.layoutHeight, 234);
      expect(rig.slot.safeBottom, 34);
    });

    test('opening over a keyboard lands at the height of that keyboard', () {
      rig.settled(344, safe: 34);
      rig.slot.open(_slide);
      expect(rig.bottom, 344);
    });

    test('a changed safe area resizes the open panel', () {
      rig.settled(0, safe: 34);
      rig.slot.open(_slide);
      rig.finishMotion();
      rig.settled(0, safe: 48);
      expect(rig.bottom, 248);
    });
  });

  group('lifecycle', () {
    test('reset puts the slot back to the keyboard alone', () {
      rig.slot.open(_slide);
      rig.finishMotion();
      rig.moving(90);
      rig.slot.reset();
      expect(rig.state, KeyboardSlotState.idle);
      expect(rig.bottom, 90);
      expect(rig.slot.animating.value, isFalse);
    });

    test('reset cancels a pending hand-off timeout', () {
      rig.slot.open(_slide);
      rig.finishMotion();
      rig.slot.close(_slide, waitForIme: true);
      rig.slot.reset();
      expect(_Rig.clock.pendingCount, 0);
    });

    test('dispose stops listening and cancels timers', () {
      rig.slot.open(_slide);
      rig.finishMotion();
      rig.slot.close(_slide, waitForIme: true);
      rig.slot.dispose();
      expect(_Rig.clock.pendingCount, 0);
      rig.settled(310);
      rig.window.value = _landscape;
      expect(rig.slot.dispose, returnsNormally);
    });
  });
}
