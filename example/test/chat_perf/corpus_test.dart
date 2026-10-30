import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/chat_perf/corpus.dart';

void main() {
  test('the same id yields the same content on every launch', () {
    const a = BenchCorpus(count: 500);
    const b = BenchCorpus(count: 500);
    for (final id in [0, 1, 17, 250, 499]) {
      expect(a.messageAt(id).text, b.messageAt(id).text);
      expect(a.messageAt(id).sender, b.messageAt(id).sender);
      expect(a.messageAt(id).createdAt, b.messageAt(id).createdAt);
    }
  });

  test('content does not depend on the history size or access order', () {
    const small = BenchCorpus(count: 100);
    const large = BenchCorpus(count: 5000);
    expect(small.messageAt(42).text, large.messageAt(42).text);
    final first = large.messageAt(4000).text;
    large.messageAt(1);
    expect(large.messageAt(4000).text, first);
  });

  test('a pinned literal guards accidental corpus changes', () {
    // Changing content requires bumping kCorpusVersion and this literal.
    expect(kCorpusVersion, 1);
    expect(const BenchCorpus(count: 10).messageAt(0).text, isNotEmpty);
    expect(const BenchCorpus(count: 10).messageAt(3).text, _pinned3);
  });

  test('mixes short, medium and long text', () {
    const c = BenchCorpus(count: 1000);
    final lengths = [for (var i = 0; i < 1000; i++) c.messageAt(i).text.length];
    expect(lengths.any((l) => l < 20), isTrue);
    expect(lengths.any((l) => l > 120), isTrue);
  });

  test('the data source serves the whole history with no gaps', () async {
    final source = BenchDataSource(const BenchCorpus(count: 300));
    expect(source.newestKnownId, 299);
    expect(source.oldestKnownId, 0);
    final got = await source.fetchRange(fromId: 10, toId: 20);
    expect([for (final m in got) m.id], [for (var i = 10; i <= 20; i++) i]);
  });
}

// Recorded from corpus v1; see kCorpusVersion.
const _pinned3 = 'OK';
