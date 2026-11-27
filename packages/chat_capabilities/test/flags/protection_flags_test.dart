import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:test/test.dart';

void main() {
  const copy = ProtectionFlags.copy;
  const forward = ProtectionFlags.forward;
  const save = ProtectionFlags.save;
  const captureBlocked = ProtectionFlags.captureBlocked;

  group('bit order (the serialised form)', () {
    test('pins each flag to its bit', () {
      expect(ProtectionFlags.none.bits, 0);
      expect(copy.bits, 1 << 0);
      expect(forward.bits, 1 << 1);
      expect(save.bits, 1 << 2);
      expect(captureBlocked.bits, 1 << 3);
      expect(ProtectionFlags.values, [copy, forward, save, captureBlocked]);
    });

    test('stays within 31 flags, a JavaScript small integer', () {
      expect(ProtectionFlags.values.length, lessThanOrEqualTo(31));
      for (final flag in ProtectionFlags.values) {
        expect(flag.bits, lessThan(1 << 31));
      }
    });
  });

  group('set operations', () {
    test('contains, isEmpty, union, intersection, without', () {
      final copyForward = copy | forward;
      expect(copyForward.contains(copy), isTrue);
      expect(copyForward.contains(save), isFalse);
      expect(ProtectionFlags.none.isEmpty, isTrue);
      expect(copyForward.isEmpty, isFalse);
      expect(copyForward & (forward | save), forward);
      expect(copyForward.without(copy), forward);
    });

    test('iterates and names in bit order', () {
      final flags = captureBlocked | copy | save;
      expect(flags.flags, [copy, save, captureBlocked]);
      expect(flags.names, ['copy', 'save', 'captureBlocked']);
      expect(ProtectionFlags.none.names, isEmpty);
    });
  });

  group('fromBits', () {
    test('ignores unknown bits and keeps the known ones', () {
      final decoded = ProtectionFlags.fromBits((1 << 1) | (1 << 3) | (1 << 9));
      expect(decoded, forward | captureBlocked);
    });
  });

  group('ChatProtection.forMessage', () {
    test('a protected message in an open chat denies copy, forward, save', () {
      expect(
        const ChatProtection().forMessage(messageProtected: true),
        copy | forward | save,
      );
    });

    test('an unprotected message takes the chat flags', () {
      const chat = ChatProtection(copy: false, save: false);
      expect(chat.forMessage(messageProtected: false), copy | save);
      expect(chat.forMessage(messageProtected: false), chat.flags);
      expect(
        const ChatProtection().forMessage(messageProtected: false),
        ProtectionFlags.none,
      );
    });

    test('captureBlocked comes from the chat only', () {
      expect(
        const ChatProtection()
            .forMessage(messageProtected: true)
            .contains(captureBlocked),
        isFalse,
      );
      const blocking = ChatProtection(captureBlocked: true);
      expect(
        blocking.forMessage(messageProtected: true),
        copy | forward | save | captureBlocked,
      );
      expect(blocking.forMessage(messageProtected: false), captureBlocked);
    });
  });
}
