/// The card's enter and leave: a fade in over 150 ms, a fade out over 220 ms
/// with a 5 dp drift away from the selection, and a motion table that decides
/// both.
///
/// **Seam:** `SelectionMenuAppearance` under a `ChromeMotionData`, read through
/// the opacity and offset of its card and a fake clock.
library;

import 'dart:async';

import 'package:chat_composer/src/menu/selection_menu_appearance.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const probe = Key('probe');

  Future<GlobalKey<SelectionMenuAppearanceState>> pumpAppearance(
    WidgetTester tester, {
    bool fitsAbove = true,
    ChromeMotionData motion = ChromeMotionData.standard,
  }) async {
    final key = GlobalKey<SelectionMenuAppearanceState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SelectionMenuAppearance(
            key: key,
            fitsAbove: fitsAbove,
            motion: motion,
            child: const SizedBox(key: probe, width: 120, height: 42),
          ),
        ),
      ),
    );
    return key;
  }

  double opacity(WidgetTester tester) =>
      tester.widget<Opacity>(find.byType(Opacity)).opacity;

  double dy(WidgetTester tester) => tester.getTopLeft(find.byKey(probe)).dy;

  group('enter', () {
    testWidgets('fades in over 150 ms, ease out, without moving', (
      tester,
    ) async {
      await pumpAppearance(tester);
      await tester.pump();

      await tester.pump(const Duration(milliseconds: 75));
      expect(opacity(tester), closeTo(Curves.easeOut.transform(0.5), 1e-6));
      expect(dy(tester), 0);

      await tester.pump(const Duration(milliseconds: 76));
      expect(opacity(tester), 1);
    });

    testWidgets('starts transparent', (tester) async {
      await pumpAppearance(tester);

      expect(opacity(tester), 0);
    });

    testWidgets('an instant speed shows it at once', (tester) async {
      await pumpAppearance(
        tester,
        motion: const ChromeMotionData(speed: ChromeMotionSpeed.instant),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      expect(opacity(tester), 1);
    });
  });

  group('leave', () {
    testWidgets('fades out over 220 ms, ease in', (tester) async {
      final key = await pumpAppearance(tester);
      await tester.pumpAndSettle();

      final done = key.currentState!.dismiss();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));
      // The controller is half way down; ease-in is applied to its value.
      expect(opacity(tester), closeTo(Curves.easeIn.transform(0.5), 1e-3));

      await tester.pump(const Duration(milliseconds: 111));
      await done;
      expect(opacity(tester), 0);
    });

    testWidgets('drifts 5 dp up when the card is above the selection', (
      tester,
    ) async {
      final key = await pumpAppearance(tester);
      await tester.pumpAndSettle();
      final top = dy(tester);

      unawaited(key.currentState!.dismiss());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 110));
      expect(dy(tester) - top, closeTo(-2.5, 0.1));

      await tester.pump(const Duration(milliseconds: 111));
      expect(dy(tester) - top, closeTo(-5, 1e-6));
    });

    testWidgets('and 5 dp down when it is below', (tester) async {
      final key = await pumpAppearance(tester, fitsAbove: false);
      await tester.pumpAndSettle();
      final top = dy(tester);

      unawaited(key.currentState!.dismiss());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 221));

      expect(dy(tester) - top, closeTo(5, 1e-6));
    });

    testWidgets('a second dismiss is ignored', (tester) async {
      final key = await pumpAppearance(tester);
      await tester.pumpAndSettle();

      final first = key.currentState!.dismiss();
      final second = key.currentState!.dismiss();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 221));

      await first;
      await second;
      expect(opacity(tester), 0);
    });

    testWidgets('an instant speed leaves at once', (tester) async {
      final key = await pumpAppearance(
        tester,
        motion: const ChromeMotionData(speed: ChromeMotionSpeed.instant),
      );
      await tester.pumpAndSettle();

      final done = key.currentState!.dismiss();
      await tester.pump();
      await done;

      expect(opacity(tester), 0);
    });

    testWidgets('the motion table decides the durations', (tester) async {
      final key = await pumpAppearance(
        tester,
        motion: ChromeMotionData(
          motion: const ChromeMotion.standard().copyWith(
            menuLeave: const MotionSpec(
              Duration(milliseconds: 100),
              Curves.linear,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      unawaited(key.currentState!.dismiss());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 101));

      expect(opacity(tester), 0);
    });
  });
}
