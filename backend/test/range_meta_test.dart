import 'package:chat_demo_backend/models/range_meta.dart';
import 'package:test/test.dart';

void main() {
  group('RangeMeta.compute', () {
    const total = 10004;

    test('first range has no older messages', () {
      final meta = RangeMeta.compute(fromId: 0, toId: 63, totalMessages: total);
      expect(meta.hasOlder, isFalse);
      expect(meta.hasNewer, isTrue);
      expect(meta.oldestId, 0);
      expect(meta.newestId, 10003);
    });

    test('middle range has older and newer', () {
      final meta = RangeMeta.compute(
        fromId: 5000,
        toId: 5063,
        totalMessages: total,
      );
      expect(meta.hasOlder, isTrue);
      expect(meta.hasNewer, isTrue);
    });

    test('last range has no newer messages', () {
      final meta = RangeMeta.compute(
        fromId: 9920,
        toId: 10003,
        totalMessages: total,
      );
      expect(meta.hasOlder, isTrue);
      expect(meta.hasNewer, isFalse);
      expect(meta.requestedTo, 10003);
    });

    test('empty conversation', () {
      final meta = RangeMeta.compute(fromId: 0, toId: 10, totalMessages: 0);
      expect(meta.hasOlder, isFalse);
      expect(meta.hasNewer, isFalse);
      expect(meta.oldestId, isNull);
      expect(meta.newestId, isNull);
    });
  });
}
