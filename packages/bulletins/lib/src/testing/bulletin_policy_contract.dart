import 'package:bulletins/bulletins.dart';
import 'package:flutter_test/flutter_test.dart';

/// The behaviour every [BulletinPolicy] must have, as a test suite to run
/// against an implementation.
abstract final class BulletinPolicyContract {
  /// Runs the behaviour every [BulletinPolicy] must have, against the policy
  /// [create] returns.
  ///
  /// Call it at the top of a test file or inside a `group`. It checks the
  /// policy as a whole, not one family's choices: timeouts are positive and
  /// ordered short ≤ long ≤ prolonged, an exact duration passes through,
  /// `untilDismissed` has none, the metrics are usable, a swipe that is on
  /// has thresholds that can be reached, and the press scale shrinks or
  /// leaves the card.
  static void run(String description, BulletinPolicy Function() create) {
    group('$description bulletin policy contract', () {
      test('timeouts are positive and ordered', () {
        final policy = create();
        final short = policy.timeoutOf(BulletinDurationClass.short);
        final long = policy.timeoutOf(BulletinDurationClass.long);
        final prolonged = policy.timeoutOf(BulletinDurationClass.prolonged);
        expect(short, greaterThan(Duration.zero));
        expect(long, greaterThanOrEqualTo(short));
        expect(prolonged, greaterThanOrEqualTo(long));
      });

      test('an exact duration passes through and untilDismissed has none', () {
        final policy = create();
        const exact = Duration(milliseconds: 1234);
        expect(policy.timeoutFor(const BulletinDuration.exactly(exact)), exact);
        expect(policy.timeoutFor(BulletinDuration.untilDismissed), isNull);
        for (final value in BulletinDurationClass.values) {
          expect(
            policy.timeoutFor(BulletinDuration$Class(value)),
            policy.timeoutOf(value),
          );
        }
      });

      test('the metrics are usable', () {
        final policy = create();
        expect(policy.minHeight, greaterThan(0));
        expect(policy.cornerRadius, greaterThanOrEqualTo(0));
        expect(policy.margin.isNonNegative, isTrue);
        if (policy.maxWidth case final maxWidth?) {
          expect(maxWidth, greaterThan(0));
        }
      });

      test('a swipe that is on can be completed', () {
        final policy = create();
        if (!policy.swipeToDismiss) return;
        expect(policy.swipeDismissFraction, inExclusiveRange(0, 1));
        expect(policy.swipeFlingVelocity, greaterThan(0));
      });

      test('the press scale shrinks the card or leaves it', () {
        final policy = create();
        expect(policy.pressScale, inInclusiveRange(0.5, 1));
      });

      test('a slide spring is stable', () {
        final policy = create();
        if (policy.transition case BulletinTransition$Slide(
          :final stiffness,
          :final dampingRatio,
        )) {
          expect(stiffness, greaterThan(0));
          expect(dampingRatio, greaterThan(0));
        }
        if (policy.transition case BulletinTransition$FadeScale(
          :final fromScale,
        )) {
          expect(fromScale, inExclusiveRange(0, 1));
        }
      });
    });
  }
}
