/// The time pill's status motion per platform: Android cross-fades the
/// clock into the check (150 ms, the incoming glyph from half size) unless
/// the row is entering, and slides the first check aside as the second
/// comes (220 ms, even while entering); iOS turns the clock's frame every
/// 6 s and its hand every second while sending and pops a check from 1.3×
/// in 0.1 s; desktop swaps the glyph; reduce motion jumps to the end.
///
/// **Seam:** a `DemoDeliveryMeta` pumped with one delivery and then
/// another, on the test's fake clock; observed through the `DemoStatusMotion`
/// its `DemoMessageMeta` paints from (the transition and the clock's turns)
/// and through the policy's values.
library;

import 'package:chat_outbox/chat_outbox.dart';
import 'package:chat_scroll_view_example/src/app/app_platform_policy.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_delivery.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_status_motion.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message_meta.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_row_appearance.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final at = DateTime(2026, 11, 28, 12, 30);

  Future<void> pumpMeta(
    WidgetTester tester,
    DemoDelivery? delivery, {
    bool entering = false,
    bool reduceMotion = false,
  }) => tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Center(
          child: DemoRowEntering(
            entering: entering,
            child: DemoDeliveryMeta(
              createdAt: at,
              color: Colors.white,
              delivery: delivery,
              edited: false,
            ),
          ),
        ),
      ),
    ),
  );

  DemoStatusMotion motionOf(WidgetTester tester) =>
      tester.widget<DemoMessageMeta>(find.byType(DemoMessageMeta)).motion!;

  group('policy', () {
    test('Android: a 150 ms cross-fade from half size, a 220 ms slide', () {
      const policy = DemoStatusMotionPolicy.android();
      expect(policy.crossFade, const Duration(milliseconds: 150));
      expect(policy.crossFadeScaleFrom, 0.5);
      expect(policy.checkSlide, const Duration(milliseconds: 220));
      expect(policy.suppressedWhileEntering, isTrue);
      expect(policy.clockFramePeriod, isNull);
      expect(policy.checkPop, isNull);
    });

    test('iOS: the clock turns, a check pops from 1.3 in 0.1 s', () {
      const policy = DemoStatusMotionPolicy.ios();
      expect(policy.clockFramePeriod, const Duration(seconds: 6));
      expect(policy.clockHandPeriod, const Duration(seconds: 1));
      expect(policy.checkPop, const Duration(milliseconds: 100));
      expect(policy.checkPopFrom, 1.3);
      expect(policy.crossFade, isNull);
      expect(policy.checkSlide, isNull);
    });

    test('desktop: no motion', () {
      const policy = DemoStatusMotionPolicy.desktop();
      expect(policy.crossFade, isNull);
      expect(policy.checkSlide, isNull);
      expect(policy.clockFramePeriod, isNull);
      expect(policy.checkPop, isNull);
    });

    group('the preset of the app platform, the web by its live window '
        'and input', () {
      Future<(DemoStatusMotionPolicy, OutgoingAppearancePolicy)> pick(
        WidgetTester tester,
        AppPlatformPolicy platform, {
        Size size = const Size(400, 800),
        ChromeInputClass input = ChromeInputClass.touch,
      }) async {
        late (DemoStatusMotionPolicy, OutgoingAppearancePolicy) picked;
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(size: size),
            child: ChromeInputClassScope(
              // The initial class is read once per scope.
              key: ValueKey(input),
              initial: input,
              child: Builder(
                builder: (context) {
                  picked = (
                    DemoOutgoingMotion.statusOf(context, platform: platform),
                    DemoOutgoingMotion.appearanceOf(
                      context,
                      platform: platform,
                    ),
                  );
                  return const SizedBox();
                },
              ),
            ),
          ),
        );
        return picked;
      }

      testWidgets('Android, iOS and the desktop app by their family', (
        tester,
      ) async {
        expect(await pick(tester, const AppPlatformPolicy.android()), (
          const DemoStatusMotionPolicy.android(),
          const OutgoingAppearancePolicy.android(),
        ));
        expect(await pick(tester, const AppPlatformPolicy.iOS()), (
          const DemoStatusMotionPolicy.ios(),
          const OutgoingAppearancePolicy.ios(),
        ));
        expect(await pick(tester, const AppPlatformPolicy.desktop()), (
          const DemoStatusMotionPolicy.desktop(),
          const OutgoingAppearancePolicy.desktop(),
        ));
      });

      testWidgets('a compact window touched moves as a phone', (tester) async {
        expect(await pick(tester, const AppPlatformPolicy.web()), (
          const DemoStatusMotionPolicy.android(),
          const OutgoingAppearancePolicy.android(),
        ));
      });

      testWidgets('a wide window, or a compact one with a mouse, does not', (
        tester,
      ) async {
        expect(
          await pick(
            tester,
            const AppPlatformPolicy.web(),
            size: const Size(1200, 800),
          ),
          (
            const DemoStatusMotionPolicy.desktop(),
            const OutgoingAppearancePolicy.desktop(),
          ),
        );
        expect(
          await pick(
            tester,
            const AppPlatformPolicy.web(),
            input: ChromeInputClass.mouse,
          ),
          (
            const DemoStatusMotionPolicy.desktop(),
            const OutgoingAppearancePolicy.desktop(),
          ),
        );
      });
    });
  });

  group('Android', () {
    testWidgets(
      'clock to check cross-fades for 150 ms',
      (tester) async {
        await pumpMeta(tester, DemoDelivery.sending);
        expect(motionOf(tester).transition, isNull);

        await pumpMeta(tester, DemoDelivery.sent);
        expect(
          motionOf(tester).transition,
          isA<DemoStatusTransition>()
              .having((t) => t.kind, 'kind', DemoStatusMotionKind.crossFade)
              .having((t) => t.from, 'from', DemoDelivery.sending)
              .having((t) => t.to, 'to', DemoDelivery.sent),
        );

        await tester.pump(const Duration(milliseconds: 75));
        expect(motionOf(tester).transition?.progress, closeTo(0.5, 0.01));
        await tester.pump(const Duration(milliseconds: 74));
        expect(motionOf(tester).transition, isNotNull);
        await tester.pump(const Duration(milliseconds: 2));
        expect(motionOf(tester).transition, isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets(
      'one check to two slides the first for 220 ms',
      (tester) async {
        await pumpMeta(tester, DemoDelivery.sent);
        await pumpMeta(tester, DemoDelivery.read);
        expect(
          motionOf(tester).transition?.kind,
          DemoStatusMotionKind.checkSlide,
        );

        await tester.pump(const Duration(milliseconds: 219));
        expect(motionOf(tester).transition, isNotNull);
        await tester.pump(const Duration(milliseconds: 2));
        expect(motionOf(tester).transition, isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets(
      'the cross-fade is suppressed while the row is entering',
      (tester) async {
        await pumpMeta(tester, DemoDelivery.sending, entering: true);
        await pumpMeta(tester, DemoDelivery.sent, entering: true);
        expect(motionOf(tester).transition, isNull);

        // The check's slide is not.
        await pumpMeta(tester, DemoDelivery.read, entering: true);
        expect(
          motionOf(tester).transition?.kind,
          DemoStatusMotionKind.checkSlide,
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets(
      'failing cross-fades the clock away',
      (tester) async {
        await pumpMeta(tester, DemoDelivery.sending);
        await pumpMeta(tester, DemoDelivery.notSent);
        expect(
          motionOf(tester).transition?.kind,
          DemoStatusMotionKind.crossFade,
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets(
      'the clock does not turn',
      (tester) async {
        await pumpMeta(tester, DemoDelivery.sending);
        await tester.pump(const Duration(seconds: 2));
        expect(motionOf(tester).clockTurns, 0);
        expect(motionOf(tester).handTurns, 0);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  });

  group('iOS', () {
    testWidgets(
      'the clock frame turns every 6 s, its hand every 1 s',
      (tester) async {
        await pumpMeta(tester, DemoDelivery.sending);
        await tester.pump(const Duration(milliseconds: 1500));

        expect(motionOf(tester).clockTurns, closeTo(0.25, 0.001));
        expect(motionOf(tester).handTurns, closeTo(0.5, 0.001));

        // It stops once sent.
        await pumpMeta(tester, DemoDelivery.sent);
        expect(motionOf(tester).clockTurns, 0);
        expect(tester.hasRunningAnimations, isTrue); // The check's pop.
        await tester.pump(const Duration(milliseconds: 101));
        expect(tester.hasRunningAnimations, isFalse);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );

    testWidgets(
      'a check pops from 1.3 for 0.1 s, the second as well',
      (tester) async {
        await pumpMeta(tester, DemoDelivery.sending);
        await pumpMeta(tester, DemoDelivery.sent);
        expect(
          motionOf(tester).transition?.kind,
          DemoStatusMotionKind.checkPop,
        );
        await tester.pump(const Duration(milliseconds: 99));
        expect(motionOf(tester).transition, isNotNull);
        await tester.pump(const Duration(milliseconds: 2));
        expect(motionOf(tester).transition, isNull);

        await pumpMeta(tester, DemoDelivery.read);
        expect(
          motionOf(tester).transition?.kind,
          DemoStatusMotionKind.checkPop,
        );
        await tester.pump(const Duration(milliseconds: 101));
        expect(motionOf(tester).transition, isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );

    testWidgets(
      'the pop is not held back while the row is entering',
      (tester) async {
        await pumpMeta(tester, DemoDelivery.sending, entering: true);
        await pumpMeta(tester, DemoDelivery.sent, entering: true);
        expect(
          motionOf(tester).transition?.kind,
          DemoStatusMotionKind.checkPop,
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  });

  testWidgets(
    'desktop swaps the glyph at once',
    (tester) async {
      await pumpMeta(tester, DemoDelivery.sending);
      await tester.pump(const Duration(seconds: 1));
      expect(motionOf(tester).clockTurns, 0);
      await pumpMeta(tester, DemoDelivery.sent);
      expect(motionOf(tester).transition, isNull);
      expect(tester.hasRunningAnimations, isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'reduce motion jumps every change to its end',
    (tester) async {
      await pumpMeta(tester, DemoDelivery.sending, reduceMotion: true);
      await tester.pump(const Duration(seconds: 2));
      expect(motionOf(tester).clockTurns, 0);
      expect(motionOf(tester).handTurns, 0);

      await pumpMeta(tester, DemoDelivery.sent, reduceMotion: true);
      expect(motionOf(tester).transition, isNull);
      await pumpMeta(tester, DemoDelivery.read, reduceMotion: true);
      expect(motionOf(tester).transition, isNull);
      expect(tester.hasRunningAnimations, isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'reduce motion on Android too',
    (tester) async {
      await pumpMeta(tester, DemoDelivery.sending, reduceMotion: true);
      await pumpMeta(tester, DemoDelivery.sent, reduceMotion: true);
      expect(motionOf(tester).transition, isNull);
      await pumpMeta(tester, DemoDelivery.read, reduceMotion: true);
      expect(motionOf(tester).transition, isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('another sender message has no motion to follow', (tester) async {
    await pumpMeta(tester, null);
    expect(motionOf(tester).transition, isNull);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets(
    'a meta first built sent shows sent, with no transition',
    (tester) async {
      await pumpMeta(tester, DemoDelivery.read);
      expect(motionOf(tester).transition, isNull);
      expect(tester.hasRunningAnimations, isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
