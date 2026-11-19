import 'package:attach_model/src/policy/attach_policy.dart';
import 'package:test/test.dart';

/// The suite every [AttachPolicy] passes, stock or a host's.
abstract final class AttachPolicyContract {
  /// Runs the contract over [policy]. Call it inside a `group`.
  static void run(AttachPolicy policy) {
    test('a cap, when it has one, takes at least one item', () {
      expect(policy.selectionCap, anyOf(isNull, greaterThanOrEqualTo(1)));
    });
  }
}
