/// The suite's seeded, suite-owned corpus and its data source.
///
/// Independent of the demo's generated source, so a demo change cannot move
/// engine numbers. Every message is a pure function of its id: the same id
/// yields the same content on every launch, whatever the history size or the
/// access order. Uses only the public `chat_scroll_view` API.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';

import 'bench_setup.dart';
import 'corpus_rich.dart';

/// Recorded in every report. Bump it, and the pinned literal in
/// `test/chat_perf/corpus_test.dart`, whenever any message's content changes:
/// that is an explicit re-baseline.
const int kCorpusVersion = 2;

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

final String _tallText = [
  for (var i = 1; i <= 140; i++) 'Tall message, line $i of 140.',
].join('\n');

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
    this.revision = 0,
    this.markdown = false,
  });

  @override
  final int id;

  @override
  final String sender;
  final String text;

  @override
  final DateTime createdAt;

  /// Edits so far; each one moves [updatedAt].
  final int revision;

  /// Whether [text] is markdown source drawn by the viewport's markdown body
  /// (the `rich` profile's designated messages and regions); false is plain
  /// text.
  final bool markdown;

  @override
  DateTime get updatedAt => createdAt.add(Duration(seconds: revision));

  /// This message with [text] as its next revision.
  BenchMessage edited(String text) => BenchMessage(
    id: id,
    sender: sender,
    text: text,
    createdAt: createdAt,
    revision: revision + 1,
    markdown: markdown,
  );
}

/// Sender of the viewer's own messages.
const String kBenchSelf = 'me';

/// Which designated content a corpus carries.
enum BenchProfile {
  /// Plain text only.
  plain,

  /// Plain text, plus the designated targets, the markdown-heavy region and
  /// the code-heavy region of `corpus_rich.dart`.
  rich,
}

/// A history of [count] messages with ids `0..count-1`.
final class BenchCorpus {
  const BenchCorpus({required this.count, this.profile = BenchProfile.plain});

  final int count;

  /// The designated content layered over the plain generator.
  final BenchProfile profile;

  static final _epoch = DateTime.utc(2026);

  /// The message with [id]; depends on [id] alone.
  BenchMessage messageAt(int id) {
    if (id == kTallMessageId) {
      return BenchMessage(
        id: id,
        sender: 'user0',
        text: _tallText,
        createdAt: _epoch.add(Duration(minutes: id * 20)),
      );
    }
    final roll = _mix(id, 1) % 100;
    final rich = profile == BenchProfile.rich ? richTextOf(id) : null;
    final pool = roll < 30 ? _short : (roll < 80 ? _medium : _long);
    // Sender runs of one to four messages; one in three runs is the viewer's.
    final run = _mix(id ~/ 3, 2);
    final sender = run % 3 == 0 ? kBenchSelf : 'user${run % 2}';
    return BenchMessage(
      id: id,
      sender: sender,
      text: rich ?? pool[_mix(id, 3) % pool.length],
      markdown: rich != null,
      // Twenty minutes apart: about 72 messages a day, so day boundaries recur.
      createdAt: _epoch.add(Duration(minutes: id * 20)),
    );
  }
}

/// A seeded data source over a [BenchCorpus]: the whole history up front, or
/// (lazy) fetched on demand after the [BenchSetup]'s latency.
final class BenchDataSource extends ChatDataSource {
  BenchDataSource(this.corpus, {this.setup = const BenchSetup()}) {
    if (!setup.lazy) {
      upsertMessages([
        for (var i = 0; i < corpus.count; i++) corpus.messageAt(i),
      ]);
    }
    seedBoundaries(
      oldestKnownId: 0,
      newestKnownId: corpus.count - 1,
      reachedOldest: true,
      reachedNewest: true,
    );
  }

  final BenchCorpus corpus;
  final BenchSetup setup;

  /// [fetchRange] calls so far: whether a window's drag reached unloaded
  /// chunks, read beside the placeholders it saw.
  int fetches = 0;

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async {
    fetches++;
    final delay = setup.latency.delayFor(fromId);
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return [
      for (var i = fromId; i <= toId; i++)
        if (i >= 0 && i < corpus.count) corpus.messageAt(i),
    ];
  }
}
