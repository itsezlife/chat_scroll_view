/// Fitzpatrick modifiers and skin-tone helpers for Unicode emoji.
abstract final class EmojiSkinTone {
  static const String recentsSectionId = 'recents';

  static const List<String> modifiers = <String>[
    '',
    '\u{1F3FB}',
    '\u{1F3FC}',
    '\u{1F3FD}',
    '\u{1F3FE}',
    '\u{1F3FF}',
  ];

  static const Set<String> skinToneBases = <String>{
    '👋', '🤚', '🖐', '✋', '🖖', '👌', '🤌', '🤏', '✌', '🤞',
    '🤟', '🤘', '🤙', '👈', '👉', '👆', '🖕', '👇', '☝', '👍',
    '👎', '✊', '👊', '🤛', '🤜', '👏', '🙌', '👐', '🤲', '🤝',
    '🙏', '✍', '💅', '🤳', '💪', '🦵', '🦶', '👂', '🦻', '👃',
    '👶', '🧒', '👦', '👧', '🧑', '👱', '👨', '🧔', '👩', '🧓',
    '👴', '👵', '🙍', '🙎', '🙅', '🙆', '💁', '🙋', '🧏', '🙇',
    '🤦', '🤷', '👮', '🕵', '💂', '🥷', '👷', '🤴', '👸', '👳',
    '👲', '🧕', '🤵', '👰', '🤰', '🤱', '👼', '🎅', '🤶', '🦸',
    '🦹', '🧙', '🧚', '🧛', '🧜', '🧝', '🧞', '🧟', '💆', '💇',
    '🚶', '🧍', '🧎', '🏃', '💃', '🕺', '🕴', '👯', '🧖', '🧗',
    '🤸', '🏌', '🏇', '⛷', '🏂', '🏋', '🤼', '🤽', '🤾', '🤹',
    '🧘', '🛀', '🛌',
  };

  static String strip(String glyph) {
    for (var i = modifiers.length - 1; i >= 1; i--) {
      final tone = modifiers[i];
      if (glyph.contains(tone)) {
        return glyph.replaceAll(tone, '');
      }
    }
    return glyph;
  }

  static int indexOf(String glyph) {
    for (var i = 1; i < modifiers.length; i++) {
      if (glyph.contains(modifiers[i])) return i;
    }
    return 0;
  }

  static bool supports(String glyph) =>
      skinToneBases.contains(strip(glyph));

  static String apply(String base, int toneIndex) {
    final plain = strip(base);
    if (toneIndex <= 0 || !skinToneBases.contains(plain)) return plain;
    if (toneIndex >= modifiers.length) return plain;
    return '$plain${modifiers[toneIndex]}';
  }
}
