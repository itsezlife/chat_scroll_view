/// The suite's seeded, suite-owned corpus and its data source.
///
/// Independent of the demo's generated source, so a demo change cannot move
/// engine numbers. Every message is a pure function of its id: the same id
/// yields the same content on every launch, whatever the history size or the
/// access order. Uses only the public `chat_scroll_view` API.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';

/// Recorded in every report. Bump it, and the pinned literal in
/// `test/chat_perf/corpus_test.dart`, whenever any message's content changes:
/// that is an explicit re-baseline.
const int kCorpusVersion = 1;

const _short = ['Hello!', 'Sure thing.', 'Got it, thanks.', 'On my way.', 'OK'];
const _medium = [
  'The quick brown fox jumps over the lazy dog near the riverbank.',
  'I was thinking we could meet up tomorrow at the coffee shop downtown.',
  'Can you send me the latest version of the document when you get a chance?',
  'We should probably discuss the project timeline before the meeting.',
];
const _long = [
  'The first rule of Fight Club is: you do not talk about Fight Club. The '
      'second rule of Fight Club is: you DO NOT talk about Fight Club! Third '
      'rule of Fight Club: if someone yells stop, goes limp, or taps out, the '
      'fight is over. Fourth rule: only two guys to a fight.',
  'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod '
      'tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim '
      'veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea '
      'commodo consequat. Duis aute irure dolor in reprehenderit.',
];

/// A 32-bit integer mix of [value] and [salt]; stable on every platform.
int _mix(int value, int salt) {
  var h = (value * 0x45d9f3b + salt * 0x119de1f3) & 0xffffffff;
  h = ((h >> 16) ^ h) * 0x45d9f3b & 0xffffffff;
  h = ((h >> 16) ^ h) * 0x45d9f3b & 0xffffffff;
  return (h >> 16) ^ h;
}

/// One corpus message.
final class BenchMessage implements IChatMessage {
  const BenchMessage({
    required this.id,
    required this.sender,
    required this.text,
    required this.createdAt,
  });

  @override
  final int id;

  @override
  final String sender;
  final String text;

  @override
  final DateTime createdAt;

  @override
  DateTime get updatedAt => createdAt;
}

/// Sender of the viewer's own messages.
const String kBenchSelf = 'me';

/// A history of [count] messages with ids `0..count-1`.
final class BenchCorpus {
  const BenchCorpus({required this.count});

  final int count;

  static final _epoch = DateTime.utc(2026);

  /// The message with [id]; depends on [id] alone.
  BenchMessage messageAt(int id) {
    final roll = _mix(id, 1) % 100;
    final pool = roll < 30 ? _short : (roll < 80 ? _medium : _long);
    // Sender runs of one to four messages; one in three runs is the viewer's.
    final run = _mix(id ~/ 3, 2);
    final sender = run % 3 == 0 ? kBenchSelf : 'user${run % 2}';
    return BenchMessage(
      id: id,
      sender: sender,
      text: pool[_mix(id, 3) % pool.length],
      // Twenty minutes apart: about 72 messages a day, so day boundaries recur.
      createdAt: _epoch.add(Duration(minutes: id * 20)),
    );
  }
}

/// A fully seeded, instant data source over a [BenchCorpus].
final class BenchDataSource extends ChatDataSource {
  BenchDataSource(this.corpus) {
    upsertMessages([
      for (var i = 0; i < corpus.count; i++) corpus.messageAt(i),
    ]);
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: corpus.count - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
  }

  final BenchCorpus corpus;

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => [
    for (var i = fromId; i <= toId; i++)
      if (i >= 0 && i < corpus.count) corpus.messageAt(i),
  ];
}
