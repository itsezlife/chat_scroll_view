import 'package:chat_wallpaper/chat_wallpaper.dart';
import 'package:chat_wallpaper/src/motion/freeform_keyframes.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'keyframes_harness.dart';

const _oneMs = Duration(milliseconds: 1);

ChatWallpaperMotionController _motion() {
  final motion = ChatWallpaperMotionController(vsync: const TestVSync());
  addTearDown(motion.dispose);
  return motion;
}

/// Starts the ticker, then runs strictly past [duration] so the controller
/// reports completion.
Future<void> _runPast(WidgetTester tester, Duration duration) async {
  await tester.pump();
  await tester.pump(duration + _oneMs);
}

void main() {
  group('ChatWallpaperMotionController', () {
    testWidgets('starts settled at phase 0', (tester) async {
      final motion = _motion();

      expect(motion.phase, 0);
      expect(motion.progress, 1);
      expect(motion.isAnimating, isFalse);
    });

    testWidgets(
      'advance moves to the previous phase over shiftDuration with the motion curve',
      (tester) async {
        final motion = _motion();
        const half = Duration(milliseconds: 250);
        expect(ChatWallpaperMotionController.shiftDuration, half * 2);

        motion.advance();
        expect(motion.phase, 7);
        expect(motion.progress, 0);

        await tester.pump();
        await tester.pump(half);
        expect(motion.isAnimating, isTrue);
        expect(
          motion.progress,
          closeTo(ChatWallpaperMotionController.curve.transform(0.5), 1e-9),
        );

        await tester.pump(half + _oneMs);
        expect(motion.phase, 7);
        expect(motion.progress, 1);
        expect(motion.isAnimating, isFalse);
      },
    );

    testWidgets('uses the cubic Bézier (0.33, 0, 0, 1) curve', (tester) async {
      const curve = ChatWallpaperMotionController.curve;
      expect((curve.a, curve.b, curve.c, curve.d), (0.33, 0.0, 0.0, 1.0));
    });

    testWidgets('wraps around the eight-phase ring', (tester) async {
      final motion = _motion();
      final phases = <int>[];

      for (var step = 0; step < FreeformGradient.phaseCount; step++) {
        motion.advance();
        await _runPast(tester, ChatWallpaperMotionController.shiftDuration);
        phases.add(motion.phase);
      }

      expect(phases, [7, 6, 5, 4, 3, 2, 1, 0]);
    });

    testWidgets('advance reports that a shift started', (tester) async {
      final motion = _motion();

      expect(motion.advance(), isTrue);
      await _runPast(tester, ChatWallpaperMotionController.shiftDuration);
    });

    testWidgets('ignores advance while a shift is running', (tester) async {
      final motion = _motion()..advance();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final progress = motion.progress;

      expect(motion.advance(), isFalse);
      expect(motion.phase, 7);
      expect(motion.progress, progress);

      await _runPast(tester, ChatWallpaperMotionController.shiftDuration);
      expect(motion.phase, 7);
      expect(motion.isAnimating, isFalse);
    });

    testWidgets('advance is a silent no-op when animations are disabled', (
      tester,
    ) async {
      final motion = _motion()..disableAnimations = true;
      var notifications = 0;
      motion.addListener(() => notifications++);

      expect(motion.advance(), isFalse);
      await tester.pump();
      expect(motion.phase, 0);
      expect(motion.progress, 1);
      expect(motion.isAnimating, isFalse);
      expect(notifications, 0);
    });

    testWidgets('disabling animations settles a running shift at its target', (
      tester,
    ) async {
      final motion = _motion()..advance();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      motion.disableAnimations = true;

      expect(motion.phase, 7);
      expect(motion.progress, 1);
      expect(motion.isAnimating, isFalse);
    });

    testWidgets('disabling animations mid-swirl lands on the final phase', (
      tester,
    ) async {
      final motion = _motion()..swirl();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      motion.disableAnimations = true;

      expect(motion.phase, 4);
      expect(motion.progress, 1);
      expect(motion.isAnimating, isFalse);
    });

    testWidgets('swirl moves four phases across swirlDuration', (tester) async {
      final motion = _motion();
      final phases = <int>[];
      motion.addListener(() {
        if (phases.lastOrNull != motion.phase) phases.add(motion.phase);
      });
      expect(
        ChatWallpaperMotionController.swirlDuration,
        const Duration(seconds: 2),
      );
      expect(ChatWallpaperMotionController.swirlSteps, 4);

      expect(motion.swirl(), isTrue);
      await tester.pump();
      const frame = Duration(milliseconds: 16);
      var elapsed = Duration.zero;
      for (
        ;
        elapsed + frame < ChatWallpaperMotionController.swirlDuration;
        elapsed += frame
      ) {
        await tester.pump(frame);
      }
      expect(motion.isAnimating, isTrue);

      await tester.pump(
        ChatWallpaperMotionController.swirlDuration - elapsed + _oneMs,
      );
      expect(phases, [7, 6, 5, 4]);
      expect(motion.phase, 4);
      expect(motion.progress, 1);
      expect(motion.isAnimating, isFalse);
    });

    testWidgets('swirl splits the eased run into equal steps', (tester) async {
      final motion = _motion()..swirl();
      const curve = ChatWallpaperMotionController.curve;
      const duration = ChatWallpaperMotionController.swirlDuration;
      await tester.pump();

      await tester.pump(duration * 0.3);
      final eased =
          curve.transform(0.3) * ChatWallpaperMotionController.swirlSteps;
      final step = eased.floor();
      expect(motion.phase, (-(step + 1)) % FreeformGradient.phaseCount);
      expect(motion.progress, closeTo(eased - step, 1e-6));

      await _runPast(tester, duration);
    });

    testWidgets('swirl is a silent no-op when animations are disabled', (
      tester,
    ) async {
      final motion = _motion()..disableAnimations = true;
      var notifications = 0;
      motion.addListener(() => notifications++);

      expect(motion.swirl(), isFalse);
      await tester.pump();
      expect(motion.phase, 0);
      expect(motion.progress, 1);
      expect(motion.isAnimating, isFalse);
      expect(notifications, 0);
    });

    testWidgets('ignores swirl and advance while swirling', (tester) async {
      final motion = _motion()..swirl();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final (phase, progress) = (motion.phase, motion.progress);

      expect(motion.swirl(), isFalse);
      expect(motion.advance(), isFalse);
      expect((motion.phase, motion.progress), (phase, progress));

      await _runPast(tester, ChatWallpaperMotionController.swirlDuration);
      expect(motion.phase, 4);
    });

    testWidgets('ignores swirl while shifting', (tester) async {
      final motion = _motion()..advance();
      await tester.pump();

      expect(motion.swirl(), isFalse);

      await _runPast(tester, ChatWallpaperMotionController.shiftDuration);
      expect(motion.phase, 7);
    });

    testWidgets(
      'holds only the resting keyframe while animations are disabled and warms the ring once enabled',
      (tester) async {
        const fill = ChatWallpaper$Freeform(
          Color(0xFFDBDDBB),
          Color(0xFF6BA587),
          Color(0xFFD5D88D),
          Color(0xFF88B884),
        );
        const resting = {(phase: 0, third: FreeformKeyframes.perStep)};
        final motion = _motion()..disableAnimations = true;
        final keyframes = motion.acquireKeyframes(fill);
        addTearDown(() => motion.releaseKeyframes(fill));
        await decode(tester, () => heldBy(keyframes).isNotEmpty);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        expect(heldBy(keyframes), resting);

        motion.disableAnimations = false;
        await decode(
          tester,
          () => heldBy(keyframes).length == FreeformKeyframes.ringLength,
        );

        motion.disableAnimations = true;
        expect(heldBy(keyframes), resting);
      },
    );

    group('spin', () {
      const quarter = Duration(milliseconds: 250);
      const spinStep = ChatWallpaperMotionController.spinStepDuration;
      const spinReturn = ChatWallpaperMotionController.spinReturnDuration;

      (int, double) position(ChatWallpaperMotionController motion) =>
          (motion.phase, motion.progress);

      /// Releases [hold] and runs its return out, so no ticker outlives the test.
      Future<void> releaseAndSettle(
        WidgetTester tester,
        ChatWallpaperSpinHold hold,
      ) async {
        hold.release();
        await _runPast(tester, spinReturn);
      }

      testWidgets(
        'turns one phase forward per spinStepDuration, linearly, while held',
        (tester) async {
          final motion = _motion();
          expect(spinStep, const Duration(seconds: 1));

          final hold = motion.holdSpin();
          await tester.pump();
          expect(motion.isAnimating, isTrue);
          expect(position(motion), (0, 1.0));

          await tester.pump(quarter);
          expect(motion.phase, 0);
          expect(motion.progress, closeTo(0.75, 1e-9));

          await tester.pump(quarter * 3);
          expect(position(motion), (1, 1.0));

          await tester.pump(spinStep * 1.5);
          expect(motion.phase, 2);
          expect(motion.progress, closeTo(0.5, 1e-9));

          await tester.pump(spinStep * 6.5);
          expect(position(motion), (1, 1.0));
          expect(motion.isAnimating, isTrue);

          await releaseAndSettle(tester, hold);
        },
      );

      testWidgets(
        'releasing eases back to the current step start at spinReturnDuration per step',
        (tester) async {
          final motion = _motion();
          expect(spinReturn, const Duration(milliseconds: 500));
          final hold = motion.holdSpin();
          await tester.pump();
          await tester.pump(spinStep + quarter);

          hold.release();
          await tester.pump();
          await tester.pump(spinReturn * 0.125);
          expect(motion.phase, 1);
          expect(motion.progress, closeTo(0.875, 1e-6));
          expect(motion.isAnimating, isTrue);

          await tester.pump(spinReturn * 0.125 + _oneMs);
          expect(position(motion), (1, 1.0));
          expect(motion.isAnimating, isFalse);

          await tester.pump(spinStep);
          expect(position(motion), (1, 1.0));
        },
      );

      testWidgets('releasing on a step boundary rests there at once', (
        tester,
      ) async {
        final motion = _motion();
        final hold = motion.holdSpin();
        await tester.pump();
        await tester.pump(spinStep * 2);

        hold.release();

        expect(position(motion), (2, 1.0));
        expect(motion.isAnimating, isFalse);
      });

      testWidgets(
        'ignores advance and swirl while spinning and while returning',
        (tester) async {
          final motion = _motion();
          final hold = motion.holdSpin();
          await tester.pump();
          await tester.pump(quarter);

          expect(motion.advance(), isFalse);
          expect(motion.swirl(), isFalse);
          await tester.pump(quarter);
          expect(motion.phase, 0);
          expect(motion.progress, closeTo(0.5, 1e-9));

          hold.release();
          await tester.pump();
          expect(motion.advance(), isFalse);
          expect(motion.swirl(), isFalse);

          await tester.pump(spinReturn);
          expect(position(motion), (0, 1.0));
          expect(motion.advance(), isTrue);
          await _runPast(tester, ChatWallpaperMotionController.shiftDuration);
          expect(motion.phase, 7);
        },
      );

      testWidgets(
        'keeps spinning until the last of several holds is released',
        (tester) async {
          final motion = _motion();
          final first = motion.holdSpin();
          final second = motion.holdSpin();
          await tester.pump();
          await tester.pump(quarter);

          first
            ..release()
            ..release();
          await tester.pump(spinStep);
          expect(motion.phase, 1);
          expect(motion.progress, closeTo(0.75, 1e-9));
          expect(motion.isAnimating, isTrue);

          second.release();
          await tester.pump();
          await tester.pump(spinReturn);
          expect(position(motion), (1, 1.0));
          expect(motion.isAnimating, isFalse);
        },
      );

      testWidgets(
        'a hold taken while returning resumes the spin from where it is',
        (tester) async {
          final motion = _motion();
          final hold = motion.holdSpin();
          await tester.pump();
          await tester.pump(quarter * 2);
          hold.release();
          await tester.pump();
          await tester.pump(spinReturn * 0.25);
          expect(motion.progress, closeTo(0.75, 1e-6));

          final again = motion.holdSpin();
          await tester.pump();
          await tester.pump(quarter);
          expect(motion.phase, 0);
          expect(motion.progress, closeTo(0.5, 1e-6));
          expect(motion.isAnimating, isTrue);

          await releaseAndSettle(tester, again);
        },
      );

      testWidgets('a hold taken during a shift spins once the shift settles', (
        tester,
      ) async {
        final motion = _motion()..advance();
        final hold = motion.holdSpin();
        await tester.pump();
        await tester.pump(quarter);
        expect(motion.phase, 7);
        expect(motion.progress, lessThan(1));

        await tester.pump(ChatWallpaperMotionController.shiftDuration);
        expect(position(motion), (7, 1.0));
        expect(motion.isAnimating, isTrue);

        await tester.pump();
        await tester.pump(spinStep);
        expect(position(motion), (0, 1.0));

        await releaseAndSettle(tester, hold);
      });

      testWidgets('a hold does nothing while animations are disabled', (
        tester,
      ) async {
        final motion = _motion()..disableAnimations = true;
        var notifications = 0;
        motion.addListener(() => notifications++);

        final hold = motion.holdSpin();
        await tester.pump();
        await tester.pump(spinStep);
        hold.release();

        expect(position(motion), (0, 1.0));
        expect(motion.isAnimating, isFalse);
        expect(notifications, 0);
      });

      testWidgets(
        'disabling animations mid-spin settles at the current step start',
        (tester) async {
          final motion = _motion()..holdSpin();
          await tester.pump();
          await tester.pump(spinStep * 2 + quarter);

          motion.disableAnimations = true;

          expect(position(motion), (2, 1.0));
          expect(motion.isAnimating, isFalse);
          await tester.pump(spinStep);
          expect(position(motion), (2, 1.0));
        },
      );

      testWidgets('re-enabling animations while held spins again', (
        tester,
      ) async {
        final motion = _motion()..disableAnimations = true;
        final hold = motion.holdSpin();
        motion.disableAnimations = false;
        await tester.pump();
        await tester.pump(spinStep);

        expect(position(motion), (1, 1.0));
        expect(motion.isAnimating, isTrue);

        await releaseAndSettle(tester, hold);
      });

      testWidgets('releasing a hold after dispose is a no-op', (tester) async {
        final motion = ChatWallpaperMotionController(vsync: const TestVSync());
        final hold = motion.holdSpin();
        await tester.pump();
        motion.dispose();

        hold.release();
      });
    });
  });

  group('ChatWallpaperMotionStateMixin', () {
    Widget host({required bool disableAnimations}) => MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: const _MotionHost(),
    );

    ChatWallpaperMotionController motionOf(WidgetTester tester) => tester
        .state<_MotionHostState>(find.byType(_MotionHost))
        .wallpaperMotion;

    testWidgets('mirrors the reduced-motion setting from MediaQuery', (
      tester,
    ) async {
      await tester.pumpWidget(host(disableAnimations: true));
      final motion = motionOf(tester);
      expect(motion.disableAnimations, isTrue);

      await tester.pumpWidget(host(disableAnimations: false));
      expect(motionOf(tester), same(motion));
      expect(motion.disableAnimations, isFalse);
    });

    testWidgets('disposes the controller with the state', (tester) async {
      await tester.pumpWidget(host(disableAnimations: false));
      final motion = motionOf(tester)..advance();
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());

      expect(() => motion.addListener(() {}), throwsFlutterError);
    });
  });
}

class _MotionHost extends StatefulWidget {
  const _MotionHost();

  @override
  State<_MotionHost> createState() => _MotionHostState();
}

class _MotionHostState extends State<_MotionHost>
    with SingleTickerProviderStateMixin, ChatWallpaperMotionStateMixin {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
