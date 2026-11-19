import 'package:attach_model/src/item/attach_item.dart';
import 'package:attach_model/src/item/attach_limits.dart';
import 'package:attach_model/src/policy/attach_policy.dart';
import 'package:attach_model/src/send/send_options.dart';
import 'package:attach_model/src/send/send_plan.dart';
import 'package:attach_model/src/testing/attach_items.dart';
import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

/// The suite every [AttachPolicy] passes, stock or a host's.
abstract final class AttachPolicyContract {
  /// Runs the contract over [policy]. Call it inside a `group`.
  static void run(AttachPolicy policy) {
    test('a cap, when it has one, takes at least one item', () {
      expect(policy.selectionCap, anyOf(isNull, greaterThanOrEqualTo(1)));
    });

    test('a send group holds two to ten items', () {
      expect(policy.maxGroupSize, inInclusiveRange(2, 10));
    });

    test('a plan sends every item once, in order, with one caption', () {
      final items = <AttachItem>[
        for (var i = 0; i < 23; i++) AttachItems.photo('p$i'),
        AttachItems.animation('g'),
        AttachItems.video('v', timer: const AttachTimer.once()),
        AttachItems.file('f0'),
        AttachItems.file('f1'),
        AttachItems.audio('a'),
      ];
      for (final options in const [
        SendOptions(),
        SendOptions(grouped: false),
        SendOptions(asFiles: true),
      ]) {
        final plan = planSend(
          SendRequest(
            items: items,
            caption: const RichText.plain('caption'),
            options: options,
          ),
          policy,
          const AttachLimits(),
        );
        final sends = switch (plan) {
          SendPlan$Ready(:final sends) => sends,
          SendPlan$Rejected(:final rejection) => fail('rejected: $rejection'),
        };
        final sent = <AttachItemId>[];
        var captions = 0;
        for (final send in sends) {
          switch (send) {
            case PlannedSend$Single(:final item, :final caption):
              sent.add(item.id);
              if (caption != null) captions++;
            case PlannedSend$Group(:final items, :final captionIndex):
              expect(items.length, lessThanOrEqualTo(policy.maxGroupSize));
              sent.addAll(items.map((i) => i.id));
              if (captionIndex != null) captions++;
            case PlannedSend$Text():
              captions++;
          }
        }
        expect(sent, [for (final item in items) item.id], reason: '$options');
        expect(captions, 1, reason: '$options');
      }
    });
  }
}
