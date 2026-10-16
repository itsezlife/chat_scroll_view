import 'package:flutter_test/flutter_test.dart';
import 'package:panel_pages/src/bake/bake_activity_port.dart';

/// A [BakeActivityPort] under test, with the one thing a contract cannot ask
/// the port itself: whether the baker behind it is being held back.
typedef BakeActivityPortProbe = ({
  BakeActivityPort port,
  bool Function() isHeldBack,
});

/// Runs the [BakeActivityPort] contract against the ports [create] returns.
///
/// [create] is called once per test and must return a port whose baker is
/// otherwise free to run, so that [BakeActivityPortProbe.isHeldBack] is false
/// until motion is reported.
void runBakeActivityPortContract(BakeActivityPortProbe Function() create) {
  group('BakeActivityPort contract', () {
    late BakeActivityPortProbe probe;
    final first = Object();
    final second = Object();

    setUp(() => probe = create());

    test('is not held back before any motion is reported', () {
      expect(probe.isHeldBack(), isFalse);
    });

    test('holds the baker back while a surface moves and frees it at rest', () {
      probe.port.reportScrolling(reporter: first, scrolling: true);
      expect(probe.isHeldBack(), isTrue);

      probe.port.reportScrolling(reporter: first, scrolling: false);
      expect(probe.isHeldBack(), isFalse);
    });

    test('treats motion as the union over reporters', () {
      probe.port
        ..reportScrolling(reporter: first, scrolling: true)
        ..reportScrolling(reporter: second, scrolling: true)
        ..reportScrolling(reporter: second, scrolling: false);
      expect(probe.isHeldBack(), isTrue, reason: 'the first still moves');

      probe.port.reportScrolling(reporter: first, scrolling: false);
      expect(probe.isHeldBack(), isFalse);
    });

    test('counts one surface reporting twice as one surface', () {
      probe.port
        ..reportScrolling(reporter: first, scrolling: true)
        ..reportScrolling(reporter: first, scrolling: true)
        ..reportScrolling(reporter: first, scrolling: false);

      expect(probe.isHeldBack(), isFalse);
    });

    test('ignores a rest from a surface that never moved', () {
      probe.port
        ..reportScrolling(reporter: first, scrolling: true)
        ..reportScrolling(reporter: second, scrolling: false);

      expect(probe.isHeldBack(), isTrue);
    });

    test('accepts a band that is empty or holds unknown glyphs', () {
      probe.port
        ..prioritise(const [])
        ..prioritise(const ['not-in-any-plan']);

      expect(probe.isHeldBack(), isFalse);
    });
  });
}
