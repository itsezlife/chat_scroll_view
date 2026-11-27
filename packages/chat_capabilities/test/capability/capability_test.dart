// Values are built at run time on purpose: equality must hold without
// const canonicalisation.
// ignore_for_file: prefer_const_constructors

import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:test/test.dart';

void main() {
  group('Capability', () {
    test('allowed is allowed and equal to another allowed', () {
      const allowed = Capability.allowed();
      expect(allowed.isAllowed, isTrue);
      // Not canonicalised: built at run time, still equal.
      expect(Capability$Allowed(), allowed);
      expect(Capability$Allowed().hashCode, allowed.hashCode);
    });

    test('denied is not allowed and equal by its reason', () {
      const denied = Capability.denied(DenialReason.everyone());
      expect(denied.isAllowed, isFalse);
      expect(Capability$Denied(DenialReason$Everyone()), denied);
      expect(
        const Capability.denied(DenialReason.other('a')),
        isNot(const Capability.denied(DenialReason.other('b'))),
      );
      expect(denied, isNot(const Capability.allowed()));
    });
  });

  group('DenialReason', () {
    final until = DateTime.utc(2026, 12, 1, 10);

    test('each form is equal by its payload', () {
      expect(DenialReason$Everyone(), const DenialReason.everyone());
      expect(DenialReason$Restricted(), const DenialReason.restricted());
      expect(
        DenialReason.restricted(until: until),
        DenialReason.restricted(until: DateTime.utc(2026, 12, 1, 10)),
      );
      expect(
        DenialReason$Unlockable('boost'),
        const DenialReason.unlockable('boost'),
      );
      expect(DenialReason$Other('tag'), const DenialReason.other('tag'));
    });

    test('forms and payloads tell reasons apart', () {
      expect(
        const DenialReason.restricted(),
        isNot(DenialReason.restricted(until: until)),
      );
      expect(
        const DenialReason.unlockable('x'),
        isNot(const DenialReason.other('x')),
      );
      expect(
        const DenialReason.everyone(),
        isNot(const DenialReason.restricted()),
      );
    });

    test('restricted without until is for good', () {
      expect(const DenialReason$Restricted().until, isNull);
      expect(DenialReason$Restricted(until: until).until, until);
    });
  });

  group('WriteAccess', () {
    test('each form is equal by its payload', () {
      expect(WriteAccess$CanWrite(), const WriteAccess.canWrite());
      expect(WriteAccess$ReadOnly(), const WriteAccess.readOnly());
      expect(WriteAccess$Join(), const WriteAccess.join());
      expect(WriteAccess$RequestToJoin(), const WriteAccess.requestToJoin());
      expect(
        WriteAccess$Restricted(DenialReason$Everyone()),
        const WriteAccess.restricted(DenialReason.everyone()),
      );
      expect(WriteAccess$Custom('topic'), const WriteAccess.custom('topic'));
    });

    test('forms and payloads tell access apart', () {
      expect(
        const WriteAccess.join(),
        isNot(const WriteAccess.requestToJoin()),
      );
      expect(
        const WriteAccess.restricted(DenialReason.everyone()),
        isNot(const WriteAccess.restricted(DenialReason.restricted())),
      );
      expect(
        const WriteAccess.custom('a'),
        isNot(const WriteAccess.custom('b')),
      );
    });

    test('only canWrite lets the user write', () {
      expect(const WriteAccess.canWrite().canWrite, isTrue);
      for (final access in const <WriteAccess>[
        WriteAccess.readOnly(),
        WriteAccess.join(),
        WriteAccess.requestToJoin(),
        WriteAccess.restricted(DenialReason.everyone()),
        WriteAccess.custom('premium'),
      ]) {
        expect(access.canWrite, isFalse, reason: '$access');
      }
    });
  });
}
