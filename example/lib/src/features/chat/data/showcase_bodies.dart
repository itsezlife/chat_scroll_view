import 'package:chat_scroll_view_example/src/features/chat/data/animated_emoji_pack.dart';

/// Message bodies that show the inline layer and the emoji-only bodies working
/// in the reference host: custom emoji painted in the text, spoilers (with an
/// embed inside), mentions, usernames and hashtags, and messages of nothing but
/// emoji in each of the layouts.
///
/// Markdown as the wire carries it. The custom emoji are the animated pack's
/// documents, which the app's asset pipeline knows, so they paint; a body can
/// say a document the pipeline does not know, which keeps the cache's
/// placeholder (no failed stage is ever shown), or a target no resolver knows,
/// which paints its alternative text.
abstract final class ShowcaseBodies {
  /// The bodies, in the order a showcase conversation shows them.
  static final List<String> all = List.unmodifiable(<String>[
    // Custom emoji in the text: several to a line, at a line start and end,
    // adjacent.
    'Launch day ${_emoji('1f680')} went ${_emoji('1f389')} great '
        '${_emoji('1f525')}',
    '${_emoji('1f44d')} at the start of a line, and at the end ${_emoji('2728')}',
    'Reactions: ${_emoji('1f600')}${_emoji('1f602')}${_emoji('1f60d')}'
        '${_emoji('1f929')} all in a row',
    'Two lines, each with one.\n${_emoji('2764_fe0f')} second line '
        '${_emoji('1f973')}',
    // An emoji the cache does not know keeps its placeholder; a target that is
    // not content shows its alternative text.
    'A document nobody described: ![:lost:](document:missing-1) stays a '
        'placeholder',
    'A target no resolver knows: ![:lost:](sticker:42) shows its text',
    // Spoilers.
    'The answer is ||forty-two|| and nothing else',
    'Hidden with an embed inside: ||the secret ${_emoji('1f525')} word||',
    // Mentions, usernames and hashtags.
    'Thanks [@Ann](mention:42) and [@bob](username:bob), see '
        '[#release](hashtag:release) for notes',
    'A plain link too: [flutter.dev](https://flutter.dev)',
    // Messages of nothing but emoji: a lone unicode emoji with an animated
    // sticker, a lone custom emoji, enlarged text of three, five and twelve,
    // and a multi-line arrangement.
    '\u{1F44D}',
    _emoji('1f680'),
    '\u{1F389}\u{1F525}\u{1F680}',
    '\u{1F600}${_emoji('1f602')}\u{1F60D}${_emoji('1f929')}\u{1F970}',
    '\u{1F600}\u{1F602}\u{1F60D}\u{1F929}\u{1F970}\u{1F973}'
        '\u{1F60E}\u{1F913}\u{1F914}\u{1F644}\u{1F62C}\u{1F631}',
    '\u{1F44D}\n\n\u{1F44D} \u{1F44D}',
  ]);

  // `![glyph](document:id)` of the pack's emoji [code].
  static String _emoji(String code) {
    final item = AnimatedEmojiPack.emoji.singleWhere(
      (item) => item.code == code,
    );
    return '![${item.sequence}](${item.key.encoded})';
  }
}
