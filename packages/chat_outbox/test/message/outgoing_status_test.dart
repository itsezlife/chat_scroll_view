// Equality is tested on instances built at run time: const ones are canonical
// and would pass by identity alone.
// ignore_for_file: prefer_const_constructors

import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_outbox/chat_outbox.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OutgoingStatus', () {
    test('forms without data are equal across instances', () {
      // Built at run time on purpose: const instances are canonical and
      // would pass by identity.
      OutgoingStatus build(String name) => switch (name) {
        'preparing' => OutgoingStatus.preparing(),
        'uploading' => OutgoingStatus.uploading(),
        'publishing' => OutgoingStatus.publishing(),
        'sent' => OutgoingStatus.sent(),
        _ => OutgoingStatus.cancelled(),
      };
      for (final name in [
        'preparing',
        'uploading',
        'publishing',
        'sent',
        'cancelled',
      ]) {
        expect(build(name), build(name), reason: name);
        expect(build(name).hashCode, build(name).hashCode, reason: name);
      }
    });

    test('different forms are not equal', () {
      final statuses = [
        OutgoingStatus.preparing(),
        OutgoingStatus.uploading(),
        OutgoingStatus.publishing(),
        OutgoingStatus.sent(),
        OutgoingStatus.failed(OutgoingFailure.network()),
        OutgoingStatus.cancelled(),
      ];
      for (var i = 0; i < statuses.length; i++) {
        for (var j = 0; j < statuses.length; j++) {
          if (i == j) continue;
          expect(statuses[i], isNot(statuses[j]));
        }
      }
    });

    test('failed is equal by its failure', () {
      expect(
        OutgoingStatus.failed(OutgoingFailure.rejected('flood')),
        OutgoingStatus.failed(OutgoingFailure.rejected('flood')),
      );
      expect(
        OutgoingStatus.failed(OutgoingFailure.network()),
        isNot(OutgoingStatus.failed(OutgoingFailure.unknown())),
      );
    });

    test('names are the stable forms events and snapshots carry', () {
      expect(
        [
          OutgoingStatus.preparing(),
          OutgoingStatus.uploading(),
          OutgoingStatus.publishing(),
          OutgoingStatus.sent(),
          OutgoingStatus.failed(OutgoingFailure.tooLarge()),
          OutgoingStatus.cancelled(),
        ].map((status) => status.name),
        ['preparing', 'uploading', 'publishing', 'sent', 'failed', 'cancelled'],
      );
    });
  });

  group('OutgoingFailure', () {
    test('forms without data are equal across instances', () {
      final built = [
        for (var round = 0; round < 2; round++)
          [
            OutgoingFailure.network(),
            OutgoingFailure.sourceLost(),
            OutgoingFailure.tooLarge(),
            OutgoingFailure.unknown(),
          ],
      ];
      expect(built[0], built[1]);
      expect(
        built[0].map((failure) => failure.hashCode),
        built[1].map((failure) => failure.hashCode),
      );
    });

    test('rejected is equal by its reason', () {
      expect(
        OutgoingFailure.rejected('flood'),
        OutgoingFailure.rejected('flood'),
      );
      expect(
        OutgoingFailure.rejected('flood'),
        isNot(OutgoingFailure.rejected('banned')),
      );
    });

    test('denied is equal by its action', () {
      expect(
        OutgoingFailure.denied(CapabilityAction.sendPhoto),
        OutgoingFailure.denied(CapabilityAction.sendPhoto),
      );
      expect(
        OutgoingFailure.denied(CapabilityAction.sendPhoto),
        isNot(OutgoingFailure.denied(CapabilityAction.sendVideo)),
      );
    });

    test('the closed set of forms, by their stable names', () {
      final failures = [
        OutgoingFailure.network(),
        OutgoingFailure.rejected('flood'),
        OutgoingFailure.denied(CapabilityAction.sendText),
        OutgoingFailure.sourceLost(),
        OutgoingFailure.tooLarge(),
        OutgoingFailure.unknown(),
      ];
      expect(failures.map((failure) => failure.name), [
        'network',
        'rejected',
        'denied',
        'sourceLost',
        'tooLarge',
        'unknown',
      ]);
      for (var i = 0; i < failures.length; i++) {
        for (var j = 0; j < failures.length; j++) {
          if (i != j) expect(failures[i], isNot(failures[j]));
        }
      }
    });
  });
}
