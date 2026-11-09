import 'package:bulletins/bulletins.dart';
import 'package:bulletins/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

final class _SlowAndroid extends BulletinPolicy$Android {
  const _SlowAndroid();

  @override
  Duration timeoutOf(BulletinDurationClass duration) =>
      super.timeoutOf(duration) * 2;
}

void main() {
  BulletinPolicyContract.run('android', BulletinPolicy.android);
  BulletinPolicyContract.run('ios', BulletinPolicy.ios);
  BulletinPolicyContract.run('desktop', BulletinPolicy.desktop);
  BulletinPolicyContract.run('a host override', _SlowAndroid.new);

  group('forPlatform', () {
    test('Android and iOS get their own families', () {
      expect(
        BulletinPolicy.forPlatform(TargetPlatform.android, isWeb: false),
        isA<BulletinPolicy$Android>(),
      );
      expect(
        BulletinPolicy.forPlatform(TargetPlatform.iOS, isWeb: false),
        isA<BulletinPolicy$IOS>(),
      );
    });

    test('desktop systems and the web get the desktop family', () {
      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        expect(
          BulletinPolicy.forPlatform(platform, isWeb: false),
          isA<BulletinPolicy$Desktop>(),
        );
      }
      expect(
        BulletinPolicy.forPlatform(TargetPlatform.android, isWeb: true),
        isA<BulletinPolicy$Desktop>(),
      );
    });
  });

  group('android', () {
    const policy = BulletinPolicy.android();

    test('times out after 1500, 2750 and 5000 ms', () {
      expect(
        policy.timeoutOf(BulletinDurationClass.short),
        const Duration(milliseconds: 1500),
      );
      expect(
        policy.timeoutOf(BulletinDurationClass.long),
        const Duration(milliseconds: 2750),
      );
      expect(
        policy.timeoutOf(BulletinDurationClass.prolonged),
        const Duration(milliseconds: 5000),
      );
    });

    test('is a bottom card, 48 high, radius 16, inset 16 / 8', () {
      expect(policy.placement, BulletinPlacement.bottom);
      expect(policy.minHeight, 48);
      expect(policy.cornerRadius, 16);
      expect(
        policy.margin,
        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      );
    });

    test('slides on the 0.8 / 400 spring, swipes, pauses on press', () {
      expect(
        policy.transition,
        isA<BulletinTransition$Slide>()
            .having((t) => t.spring.stiffness, 'stiffness', 400)
            .having((t) => t.dampingRatio, 'damping ratio', 0.8),
      );
      expect(policy.swipeToDismiss, isTrue);
      expect(policy.swipeDismissFraction, closeTo(1 / 3, 1e-9));
      expect(policy.swipeFlingVelocity, 2000);
      expect(policy.pauseOnPress, isTrue);
      expect(policy.pressScale, 0.98);
      expect(policy.followSpring?.stiffness, 900);
      expect(policy.clipsAtObstruction, isTrue);
    });
  });

  group('ios', () {
    const policy = BulletinPolicy.ios();

    test('fades and scales from 0.96 with no gestures', () {
      expect(
        policy.transition,
        isA<BulletinTransition$FadeScale>().having(
          (t) => t.fromScale,
          'from scale',
          0.96,
        ),
      );
      expect(policy.swipeToDismiss, isFalse);
      expect(policy.pauseOnPress, isFalse);
      expect(policy.pressScale, 1);
      expect(policy.clipsAtObstruction, isFalse);
    });

    test('is a bottom card, 50 high, radius 25, side margin 12', () {
      expect(policy.placement, BulletinPlacement.bottom);
      expect(policy.minHeight, 50);
      expect(policy.cornerRadius, 25);
      expect(policy.margin.left, 12);
      expect(policy.margin.right, 12);
    });
  });

  group('desktop', () {
    const policy = BulletinPolicy.desktop();

    test('is a centred toast at most 380 wide that fades', () {
      expect(policy.placement, BulletinPlacement.center);
      expect(policy.maxWidth, 380);
      expect(policy.transition, isA<BulletinTransition$Fade>());
      expect(policy.swipeToDismiss, isFalse);
    });
  });

  group('timeoutFor', () {
    const policy = BulletinPolicy.android();

    test('maps a class through the policy', () {
      expect(
        policy.timeoutFor(BulletinDuration.long),
        const Duration(milliseconds: 2750),
      );
    });

    test('passes an exact duration through', () {
      expect(
        policy.timeoutFor(const BulletinDuration.exactly(Duration(seconds: 4))),
        const Duration(seconds: 4),
      );
    });

    test('has no timeout until dismissed', () {
      expect(policy.timeoutFor(BulletinDuration.untilDismissed), isNull);
    });

    test('a host override changes one value and keeps the rest', () {
      const slow = _SlowAndroid();
      expect(
        slow.timeoutFor(BulletinDuration.short),
        const Duration(milliseconds: 3000),
      );
      expect(slow.cornerRadius, policy.cornerRadius);
    });
  });
}
