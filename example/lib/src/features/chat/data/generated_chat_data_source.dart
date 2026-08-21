import 'dart:async';
import 'dart:math';

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';

/// How [GeneratedChatDataSource] builds message body text.
enum GeneratedMessageStyle {
  /// Classic lorem ipsum paragraphs (length varies by id).
  lorem,

  /// Short, medium, and long conversational phrases (~30/50/20 mix).
  varied,
}

/// In-memory [ChatDataSource] that synthesizes messages on demand.
///
/// Pass [messageCount] to define ids `0..messageCount-1`. Content is
/// deterministic for a given [seed] — the same id always yields the same
/// text until [updateMessage] / [editMessage] replaces it.
///
/// ```dart
/// final ds = GeneratedChatDataSource(messageCount: 10_000);
/// ```
class GeneratedChatDataSource extends ChatDataSource {
  /// Creates a data source with [messageCount] synthetic messages.
  GeneratedChatDataSource({
    required this.messageCount,
    this.style = GeneratedMessageStyle.varied,
    this.seed = 42,
    this.senders = _defaultSenders,
    this.fetchDelay = Duration.zero,
    DateTime? baseTime,
  }) : baseTime = baseTime ?? DateTime(2026, 1, 1) {
    if (messageCount > 0) {
      seedBoundaries(
        oldestKnownId: 0,
        newestKnownId: messageCount - 1,
        reachedOldest: true,
        reachedNewest: true,
      );
    } else {
      seedBoundaries(reachedOldest: true, reachedNewest: true);
    }
  }

  /// Number of messages available at construction (`0..messageCount-1`).
  final int messageCount;

  /// Lorem ipsum vs varied conversational phrases.
  final GeneratedMessageStyle style;

  /// Root seed — combined with message id for per-row determinism.
  final int seed;

  /// Sender labels rotated across generated rows.
  final List<String> senders;

  /// Artificial latency applied to every [fetchRange] (demo / stress tests).
  final Duration fetchDelay;

  /// Anchor timestamp for id `0`; each subsequent id adds one minute.
  final DateTime baseTime;

  /// Messages created via [sendMessage] / [insertMessage] past [messageCount].
  /// Survives LRU eviction so [fetchRange] can re-serve them.
  final Map<int, IChatMessage> _tailOverrides = <int, IChatMessage>{};

  static const _defaultSenders = ['Alice', 'Bob', 'Charlie', 'Dana'];

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async {
    if (fetchDelay > Duration.zero) {
      await Future<void>.delayed(fetchDelay);
    }

    if (messageCount <= 0 && newestKnownId == null) return const [];

    final upper = newestKnownId ?? messageCount - 1;
    if (upper < 0) return const [];

    final lo = fromId.clamp(0, upper);
    final hi = toId.clamp(0, upper);

    final result = <IChatMessage>[];
    for (var id = lo; id <= hi; id++) {
      final cached = getMessage(id);
      if (cached != null) {
        result.add(cached);
        continue;
      }
      final override = _tailOverrides[id];
      if (override != null) {
        result.add(override);
        continue;
      }
      if (id < messageCount) {
        result.add(_generateMessage(id));
      }
    }
    return result;
  }

  /// Demo integrator: append a new message at the tail via [insertMessage].
  UserChatMessage sendMessage({
    required String sender,
    required String content,
  }) {
    final id = nextInsertId;
    final now = DateTime.now();
    final message = UserChatMessage(
      id: id,
      sender: sender,
      createdAt: now,
      updatedAt: now,
      content: content,
    );
    _tailOverrides[id] = message;
    insertMessage(message, reason: 'demo-send');
    return message;
  }

  /// Demo integrator: edit an existing message via [updateMessage].
  void editMessage(UserChatMessage message, String newContent) {
    updateMessage(
      UserChatMessage(
        id: message.id,
        sender: message.sender,
        createdAt: message.createdAt,
        updatedAt: DateTime.now(),
        content: newContent,
      ),
      reason: 'demo-edit',
    );
  }

  /// Demo integrator: delete one or more messages via [removeMessages].
  @override
  void removeMessages(Iterable<int> ids, {Object? reason}) =>
      super.removeMessages(ids, reason: reason ?? 'demo-delete');

  /// Scans the full synthetic range for [query] (already lower-cased).
  ///
  /// Prefers cached / edited rows via [getMessage]; otherwise synthesizes
  /// content without writing into the chunk cache.
  Future<List<int>> searchAllMessageIds(
    String query, {
    required bool Function() isCancelled,
  }) async {
    final oldest = oldestKnownId;
    final newest = newestKnownId;
    if (oldest == null || newest == null || query.isEmpty) return const [];

    final hits = <int>[];
    const yieldEvery = 64;
    for (var id = oldest; id <= newest; id++) {
      if (isCancelled()) return hits;
      final message =
          getMessage(id) ?? (id < messageCount ? _generateMessage(id) : null);
      if (message == null) continue;
      final text = message.text;
      if (text != null && text.toLowerCase().contains(query)) {
        hits.add(id);
      }
      if ((id - oldest) % yieldEvery == yieldEvery - 1) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    return hits;
  }

  UserChatMessage _generateMessage(int id) {
    final rng = Random(seed ^ (id * 0x9E3779B9));
    final time = baseTime.add(Duration(minutes: id));
    return UserChatMessage(
      id: id,
      sender: senders[id % senders.length],
      createdAt: time,
      updatedAt: time,
      content: switch (style) {
        GeneratedMessageStyle.lorem => _loremContent(rng, id),
        GeneratedMessageStyle.varied => _variedContent(rng),
      },
    );
  }
}

String _loremContent(Random rng, int id) {
  const words = [
    'lorem',
    'ipsum',
    'dolor',
    'sit',
    'amet',
    'consectetur',
    'adipiscing',
    'elit',
    'sed',
    'do',
    'eiusmod',
    'tempor',
    'incididunt',
    'ut',
    'labore',
    'et',
    'dolore',
    'magna',
    'aliqua',
    'enim',
    'ad',
    'minim',
    'veniam',
    'quis',
    'nostrud',
    'exercitation',
    'ullamco',
    'laboris',
    'nisi',
    'aliquip',
    'ex',
    'ea',
    'commodo',
    'consequat',
  ];
  final wordCount = 3 + (id % 40) + rng.nextInt(8);
  final buffer = StringBuffer('Message $id: ');
  for (var i = 0; i < wordCount; i++) {
    if (i > 0) buffer.write(' ');
    final word = words[rng.nextInt(words.length)];
    buffer.write(i == 0 ? word[0].toUpperCase() + word.substring(1) : word);
  }
  buffer.write('.');
  return buffer.toString();
}

const _shortPhrases = [
  'Hello!',
  'Sure thing.',
  'Got it, thanks.',
  'On my way.',
  'Sounds good.',
  'OK',
  'Yes',
  'No problem',
  'See you later!',
  'BRB',
];

const _mediumPhrases = [
  'The quick brown fox jumps over the lazy dog near the riverbank.',
  'I was thinking we could meet up tomorrow at the coffee shop downtown.',
  'Can you send me the latest version of the document when you get a chance?',
  'The weather has been really unpredictable lately, hard to plan anything.',
  'Just finished reading that book you recommended — it was fantastic!',
  'We should probably discuss the project timeline before the meeting.',
  'I made some changes to the code, let me know if it looks good to you.',
  'The restaurant on 5th avenue has amazing pasta, we should go sometime.',
];

const _longPhrases = [
  'The first rule of Fight Club is: you do not talk about Fight Club. '
      'The second rule of Fight Club is: you DO NOT talk about Fight Club! '
      'Third rule of Fight Club: if someone yells "stop!", goes limp, '
      'or taps out, the fight is over. Fourth rule: only two guys to a fight.',
  'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod '
      'tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim '
      'veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea '
      'commodo consequat. Duis aute irure dolor in reprehenderit in voluptate '
      'velit esse cillum dolore eu fugiat nulla pariatur.',
  'According to all known laws of aviation, there is no way a bee should be '
      'able to fly. Its wings are too small to get its fat little body off the '
      'ground. The bee, of course, flies anyway because bees do not care what '
      'humans think is impossible. Yellow, black. Yellow, black.',
  'In the beginning the Universe was created. This has made a lot of people '
      'very angry and been widely regarded as a bad move. Many were '
      'increasingly of the opinion that they had all made a big mistake in '
      'coming down from the trees in the first place.',
];

String _variedContent(Random rng) {
  final roll = rng.nextDouble();
  if (roll < 0.3) {
    return _shortPhrases[rng.nextInt(_shortPhrases.length)];
  }
  if (roll < 0.8) {
    return _mediumPhrases[rng.nextInt(_mediumPhrases.length)];
  }
  return _longPhrases[rng.nextInt(_longPhrases.length)];
}
