import 'package:emoji_catalog_pack/generator.dart';
import 'package:test/test.dart';

const _source = '''
# emoji-test.txt
# Version: 18.0
#

# group: Smileys & Emotion

# subgroup: face-smiling
1F600                                                  ; fully-qualified     # 😀 E1.0 grinning face
1F603                                                  ; minimally-qualified # 😃 E0.6 grinning face with big eyes

# group: People & Body

# subgroup: hand-fingers-open
1F44B 1F3FB                                            ; fully-qualified     # 👋🏻 E1.0 waving hand: light skin tone
263A                                                   ; unqualified         # ☺ E0.6 smiling face
2764 FE0F 200D 1F525                                   ; fully-qualified     # ❤️‍🔥 E13.1 heart on fire

# group: Component

# subgroup: skin-tone
1F3FB                                                  ; component           # 🏻 E1.0 light skin tone
''';

void main() {
  group('EmojiTestFile.parse', () {
    test('reads the emoji version from the header', () {
      expect(EmojiTestFile.parse(_source).emojiVersion, '18.0');
    });

    test('keeps only fully-qualified lines, in file order', () {
      final entries = EmojiTestFile.parse(_source).entries;

      expect(entries.map((e) => e.codePoints), [
        [0x1F600],
        [0x1F44B, 0x1F3FB],
        [0x2764, 0xFE0F, 0x200D, 0x1F525],
      ]);
    });

    test('tags each entry with its group and subgroup ids', () {
      final entries = EmojiTestFile.parse(_source).entries;

      expect(entries.first.group, 'smileys-emotion');
      expect(entries.first.subgroup, 'face-smiling');
      expect(entries[1].group, 'people-body');
      expect(entries[1].subgroup, 'hand-fingers-open');
    });

    test('reads the English name and the emoji version of each entry', () {
      final entry = EmojiTestFile.parse(_source).entries[1];

      expect(entry.name, 'waving hand: light skin tone');
      expect(entry.since, '1.0');
    });

    test('rejects a file without a version header', () {
      expect(
        () => EmojiTestFile.parse('1F600 ; fully-qualified # x E1.0 y'),
        throwsFormatException,
      );
    });

    test('rejects a data line outside any group', () {
      expect(
        () => EmojiTestFile.parse(
          '# Version: 18.0\n1F600 ; fully-qualified # 😀 E1.0 grinning face',
        ),
        throwsFormatException,
      );
    });
  });
}
