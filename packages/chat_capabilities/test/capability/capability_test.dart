// Values are built at run time on purpose: equality must hold without
// const canonicalisation.
// ignore_for_file: prefer_const_constructors

import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:content_model/content_model.dart' show ChatEvent;
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

  group('reason', () {
    test('a denied capability gives its reason, an allowed one none', () {
      expect(const Capability.allowed().reason, isNull);
      expect(
        const Capability.denied(DenialReason.everyone()).reason,
        const DenialReason.everyone(),
      );
    });
  });

  group('package reasons', () {
    test('a write access form and a pending send are reasons of their own', () {
      expect(
        DenialReason$NoWriteAccess(WriteAccess$ReadOnly()),
        const DenialReason.noWriteAccess(WriteAccess.readOnly()),
      );
      expect(
        const DenialReason.noWriteAccess(WriteAccess.custom('readOnly')),
        isNot(const DenialReason.noWriteAccess(WriteAccess.readOnly())),
      );
      expect(DenialReason$SendPending(), const DenialReason.sendPending());
      // A host tag that spells a package reason is still the host's.
      expect(
        const DenialReason.other('sendPending'),
        isNot(const DenialReason.sendPending()),
      );
    });
  });

  group('diagnosticForm', () {
    test('names each reason, the date of a restriction left out', () {
      expect(const DenialReason.everyone().diagnosticForm, 'everyone');
      expect(const DenialReason.restricted().diagnosticForm, 'restricted');
      expect(
        DenialReason.restricted(until: DateTime.utc(2030)).diagnosticForm,
        'restrictedUntil',
      );
      expect(
        const DenialReason.unlockable('boost').diagnosticForm,
        'unlockable(boost)',
      );
      expect(const DenialReason.other('tag').diagnosticForm, 'other(tag)');
      expect(
        const DenialReason.noWriteAccess(
          WriteAccess.custom('a-long-host-tag'),
        ).diagnosticForm,
        'noWriteAccess(custom)',
      );
      expect(const DenialReason.sendPending().diagnosticForm, 'sendPending');
    });

    test('a long host string is clipped to what a field holds', () {
      final long = 'k' * 200;
      for (final reason in [
        DenialReason.unlockable(long),
        DenialReason.other(long),
      ]) {
        final form = reason.diagnosticForm;
        expect(form.length, lessThanOrEqualTo(ChatEvent.maxStringFieldLength));
        expect(form, endsWith(')'));
      }
    });

    test('a write access names its form alone', () {
      expect(const WriteAccess.canWrite().diagnosticForm, 'canWrite');
      expect(const WriteAccess.readOnly().diagnosticForm, 'readOnly');
      expect(const WriteAccess.join().diagnosticForm, 'join');
      expect(const WriteAccess.requestToJoin().diagnosticForm, 'requestToJoin');
      expect(
        const WriteAccess.restricted(DenialReason.everyone()).diagnosticForm,
        'restricted',
      );
      expect(const WriteAccess.custom('tag').diagnosticForm, 'custom');
    });
  });
}
