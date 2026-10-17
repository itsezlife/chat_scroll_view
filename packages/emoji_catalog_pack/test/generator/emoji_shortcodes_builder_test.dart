import 'dart:convert';

import 'package:content_model/content_model.dart';
import 'package:emoji_catalog_pack/emoji_catalog_pack.dart';
import 'package:emoji_catalog_pack/generator.dart';
import 'package:test/test.dart';

// A woman technologist is a variant of the technologist; a light-skinned one
// is a tone variant of the technologist. The flag carries FE0F here and not in
// the toolkit, the fog face the other way round; 1FAEB has no code.
final _structure = EmojiCatalogStructure.decode(
  '@emoji-catalog-structure\t1\n'
  '@emoji\t18.0\n'
  '@group\tpeople-body\n'
  '@subgroup\tperson\n'
  '1F9D1-200D-1F4BB\t1F9D1-1F3FB-200D-1F4BB/1/\t1F469-200D-1F4BB//w\n'
  '@subgroup\tface\n'
  '1F636-200D-1F32B\n'
  '1FAEB\n'
  '@subgroup\tflag\n'
  '1F3F3-FE0F\n',
);

Map<String, Object?> _emoji(String fullyQualified, String shortname) => {
  'shortname': shortname,
  'code_points': {'fully_qualified': fullyQualified},
};

final Map<String, Object?> _toolkit = {
  '1f9d1-1f4bb': _emoji('1f9d1-200d-1f4bb', ':technologist:'),
  '1f9d1-1f3fb-1f4bb': _emoji('1f9d1-1f3fb-200d-1f4bb', ':technologist_tone1:'),
  '1f469-1f4bb': _emoji('1f469-200d-1f4bb', ':woman_technologist:'),
  '1f636-1f32b': _emoji('1f636-200d-1f32b-fe0f', ':face_in_clouds:'),
  '1f3f3': _emoji('1f3f3', ':flag_white:'),
  '1f600': _emoji('1f600', ':grinning:'),
};

EmojiShortcodes _build([Map<String, Object?>? toolkit]) =>
    EmojiShortcodesBuilder.build(
      structure: _structure,
      toolkitJson: jsonEncode(toolkit ?? _toolkit),
      source: 'emoji-toolkit 11.0.0',
    );

ContentKey$Unicode _key(String hex) =>
    ContentKey.parse('unicode:$hex') as ContentKey$Unicode;

void main() {
  group('EmojiShortcodesBuilder.build', () {
    test('codes every entry and gender-only variant the toolkit has, in '
        'order', () {
      expect(_build().codes, {
        _key('1F9D1-200D-1F4BB'): ':technologist:',
        _key('1F469-200D-1F4BB'): ':woman_technologist:',
        _key('1F636-200D-1F32B'): ':face_in_clouds:',
        _key('1F3F3-FE0F'): ':flag_white:',
      });
    });

    test('leaves out the tone variants, which show their entry', () {
      expect(_build()[_key('1F9D1-1F3FB-200D-1F4BB')], isNull);
    });

    test('matches a sequence whatever either side spells of FE0F', () {
      final shortcodes = _build();

      expect(shortcodes[_key('1F3F3-FE0F')], ':flag_white:');
      expect(shortcodes[_key('1F636-200D-1F32B')], ':face_in_clouds:');
    });

    test('skips an emoji the toolkit has no code for', () {
      expect(_build()[_key('1FAEB')], isNull);
    });

    test('stamps where the codes come from', () {
      expect(_build().source, 'emoji-toolkit 11.0.0');
    });

    test('rejects a toolkit entry it cannot read', () {
      expect(
        () => _build({
          ..._toolkit,
          '1f603': {'shortname': ':smiley:'},
        }),
        throwsFormatException,
      );
      expect(
        () => _build({..._toolkit, '1f603': _emoji('1f603', '')}),
        throwsFormatException,
      );
      expect(
        () => EmojiShortcodesBuilder.build(
          structure: _structure,
          toolkitJson: '[]',
          source: 'emoji-toolkit 11.0.0',
        ),
        throwsFormatException,
      );
    });

    test('rejects two toolkit entries for one sequence', () {
      expect(
        () => _build({
          ..._toolkit,
          '1f3f3-fe0f': _emoji('1f3f3-fe0f', ':white_flag:'),
        }),
        throwsFormatException,
      );
    });
  });
}
