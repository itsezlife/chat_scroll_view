/// How the host aggregates occluding chrome into what the viewport reserves:
/// `bottomPadding = composer extent + occupancy.bottom`, `inlineEnd` applied
/// in layout, and the top as safe area plus header plus search.
library;

import 'package:chat_scroll_view_example/src/features/chat/utils/chat_viewport_insets.dart';
import 'package:content_model/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen/listen.dart';
import 'package:panel_presentation/panel_presentation.dart';
import 'package:panel_presentation/testing.dart';

void main() {
  late ValueNotifier<double> extent;
  late ValueNotifier<PanelOccupancy> occupancy;
  late ChatViewportInsets insets;

  setUp(() {
    extent = ValueNotifier<double>(0);
    occupancy = ValueNotifier<PanelOccupancy>(PanelOccupancy.zero);
    insets = ChatViewportInsets(composerExtent: extent, occupancy: occupancy);
  });

  tearDown(() {
    insets.dispose();
    extent.dispose();
    occupancy.dispose();
  });

  group('bottom', () {
    test('is seeded before the composer has published its extent', () {
      expect(insets.bottomPadding.value, ChatViewportInsets.composerSeed);
    });

    test('is the composer extent plus the presentation occupancy', () {
      extent.value = 120;
      occupancy.value = const PanelOccupancy(bottom: 300);

      expect(insets.bottomPadding.value, 420);

      occupancy.value = PanelOccupancy.zero;

      expect(insets.bottomPadding.value, 120);
    });

    test('follows the extent frame by frame while the composer animates', () {
      occupancy.value = const PanelOccupancy(bottom: 200);
      final seen = <double>[];
      insets.bottomPadding.addListener(
        () => seen.add(insets.bottomPadding.value),
      );

      extent
        ..value = 80
        ..value = 96
        ..value = 112;

      expect(seen, [280, 296, 312]);
    });

    test('a change that leaves the sum alone does not notify', () {
      extent.value = 100;
      var ticks = 0;
      insets.bottomPadding.addListener(() => ticks++);

      extent.value = 100;
      occupancy.value = const PanelOccupancy(inlineEnd: 380);

      expect(ticks, 0);
    });
  });

  group('inline end', () {
    test('is the occupancy of a docked section, not padding at the bottom', () {
      occupancy.value = const PanelOccupancy(inlineEnd: 380);

      expect(insets.inlineEnd.value, 380);
      expect(insets.bottomPadding.value, ChatViewportInsets.composerSeed);
    });
  });

  group('top', () {
    test('is safe top plus header reserve plus search reserve', () {
      expect(insets.topPadding.value, 0);

      insets
        ..setSafeTop(20)
        ..headerReserve.value = 52;

      expect(insets.chromeTop.value, 72);
      expect(insets.topPadding.value, 72);

      insets.setSearchReserve(56);

      expect(insets.chromeTop.value, 72, reason: 'search sits below chromeTop');
      expect(insets.topPadding.value, 128);
    });

    test('identical values do not notify', () {
      var ticks = 0;
      insets.topPadding.addListener(() => ticks++);

      insets
        ..setSafeTop(0)
        ..setSearchReserve(0)
        ..headerReserve.value = 0;

      expect(ticks, 0);
    });
  });

  group('with a keyboard presentation', () {
    test('the soft keyboard is counted once, through the occupancy', () async {
      final ime = FakeImeInput();
      final window = ValueNotifier(const PanelWindow(width: 400, height: 800));
      final keyboard = KeyboardReplacementStrategy(
        ime: ime,
        heights: await KeyboardHeightStore.open(FakeKeyValueStore()),
        window: window,
      );
      addTearDown(() {
        keyboard.dispose();
        window.dispose();
        ime.dispose();
      });
      final aggregated = ChatViewportInsets(
        composerExtent: extent,
        occupancy: keyboard.occupancy,
      );
      addTearDown(aggregated.dispose);
      extent.value = 100;

      ime.report(const ImeSample(height: 300, safeAreaBottom: 34));

      expect(aggregated.bottomPadding.value, 400);
    });
  });

  test('disposing stops following without disposing what it was given', () {
    insets.dispose();
    // A disposed notifier refuses listeners and assignments, so these would
    // fail had the aggregate disposed what it was given.
    var heard = 0;
    extent.addListener(() => heard++);
    occupancy.addListener(() => heard++);
    extent.value = 10;
    occupancy.value = const PanelOccupancy(bottom: 5);

    expect(heard, 2);
    expect(insets.bottomPadding.value, ChatViewportInsets.composerSeed);
  });
}
