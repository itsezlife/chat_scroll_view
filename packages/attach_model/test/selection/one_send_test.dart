import 'package:attach_model/attach_model.dart';
import 'package:attach_model/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:test/test.dart';

const _all = [
  AttachPolicy.android(),
  AttachPolicy.ios(),
  AttachPolicy.desktop(),
  AttachPolicy.web(),
];

const _oneSend = AttachLimits(oneSend: true);

void main() {
  final photos = [for (var i = 0; i < 12; i++) AttachItems.photo('p$i')];

  group('limits', () {
    test('oneSend is off by default and in ==, hashCode and copyWith', () {
      expect(const AttachLimits().oneSend, isFalse);
      expect(_oneSend, isNot(const AttachLimits()));
      expect(_oneSend.hashCode, const AttachLimits(oneSend: true).hashCode);
      expect(const AttachLimits().copyWith(oneSend: true), _oneSend);
      expect(_oneSend.copyWith(captionLength: 5).oneSend, isTrue);
    });
  });

  group('selection', () {
    test('one-send mode caps the selection at the album size', () {
      for (final policy in _all) {
        final selection = AttachSelection(policy: policy, limits: _oneSend);
        for (final photo in photos.take(10)) {
          expect(selection.toggle(photo), const AttachToggle.selected());
        }
        expect(
          selection.toggle(photos[10]),
          const AttachToggle.refused(AttachRefusal.capReached),
          reason: '$policy',
        );
        expect(selection.cap, 10);
      }
    });

    test('a smaller album size is the cap', () {
      final selection = AttachSelection(
        policy: const AttachPolicy.android(),
        limits: _oneSend.copyWith(albumSize: 3),
      );
      expect(selection.cap, 3);
    });

    test('without one-send mode the cap is the policy one', () {
      final selection = AttachSelection(
        policy: const AttachPolicy.android(),
        limits: const AttachLimits(),
      );
      expect(selection.cap, 100);
    });

    test('new limits keep the items and signal once', () {
      final selection = AttachSelection(
        policy: const AttachPolicy.android(),
        limits: const AttachLimits(),
      );
      photos.take(11).forEach(selection.toggle);
      var signals = 0;
      selection.changes.addListener(() => signals++);

      selection.limits = _oneSend;
      selection.limits = _oneSend;

      expect(signals, 1);
      expect(selection.length, 11, reason: 'items already picked stay');
      expect(
        selection.refusalOf(photos[11]),
        AttachRefusal.capReached,
        reason: 'no more join',
      );
    });

    test('a kind denied by new limits stays selected and joins no more', () {
      final selection = AttachSelection(
        policy: const AttachPolicy.ios(),
        limits: const AttachLimits(),
      )..toggle(photos[0]);

      selection.limits = const AttachLimits(allowedKinds: {AttachKind.video});

      expect(selection.contains(photos[0].id), isTrue);
      expect(selection.refusalOf(photos[1]), AttachRefusal.kindNotAllowed);
    });
  });

  group('send', () {
    test('"without grouping" is not offered in one-send mode', () {
      SendOptionVisibility visibility(AttachLimits limits) =>
          SendOptionVisibility(
            items: photos.take(3),
            caption: RichText.empty,
            options: const SendOptions(),
            policy: const AttachPolicy.android(),
            limits: limits,
          );
      expect(visibility(const AttachLimits()).withoutGrouping, isTrue);
      expect(visibility(_oneSend).withoutGrouping, isFalse);
    });

    test('an album goes as one group even when asked ungrouped', () {
      for (final policy in _all) {
        final plan = planSend(
          SendRequest(
            items: photos.take(10).toList(),
            caption: RichText.empty,
            options: const SendOptions(grouped: false),
          ),
          policy,
          _oneSend,
        );
        expect(plan, isA<SendPlan$Ready>(), reason: '$policy');
        final sends = (plan as SendPlan$Ready).sends;
        expect(sends, hasLength(1), reason: '$policy');
        expect(
          sends.single,
          isA<PlannedSend$Group>().having((g) => g.items.length, 'items', 10),
        );
      }
    });
  });
}
