import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:content_model/content_model.dart';
import 'package:emoji_catalog_pack/emoji_catalog_pack.dart';
import 'package:emoji_catalog_pack/generator.dart';
import 'package:test/test.dart';

// The checks below read the committed assets, not fixtures: they are the
// integrity gate for whatever the generator last wrote.

const List<String> _locales = [
  'en',
  'de',
  'es',
  'fr',
  'hi',
  'it',
  'ja',
  'nl',
  'pt',
  'ru',
  'zh',
];

// Gzip budgets in bytes: the largest pack measured with headroom for the next
// Emoji version, the structure and the shortcodes.
const int _packBudget = 52 * 1024;
const int _structureBudget = 16 * 1024;
const int _shortcodesBudget = 16 * 1024;

// Counts of fully-qualified sequences in the pinned Emoji 18.0 emoji-test.txt
// (`grep -c 'fully-qualified'` and the same restricted to lines without a
// skin tone modifier). They change only with the pinned Emoji version.
const int _toneless = 1923;
const int _toned = 2040;

late final Directory _root;
late final EmojiCatalogStructure _structure;
late final Map<String, EmojiKeywordPack> _packs;
late final EmojiShortcodes _shortcodes;

String _read(String path) => File('${_root.path}/$path').readAsStringSync();

bool _hasTone(ContentKey$Unicode key) =>
    key.sequence.runes.any((cp) => cp >= 0x1F3FB && cp <= 0x1F3FF);

ContentKey$Unicode _key(String hex) =>
    ContentKey.parse('unicode:$hex') as ContentKey$Unicode;

int _gzipSize(String text) =>
    GZipCodec(level: 9).encode(utf8.encode(text)).length;

void main() {
  setUpAll(() async {
    final lib = await Isolate.resolvePackageUri(
      Uri.parse('package:emoji_catalog_pack/emoji_catalog_pack.dart'),
    );
    _root = File.fromUri(lib!).parent.parent;
    _structure = EmojiCatalogStructure.decode(_read('assets/structure.tsv'));
    _packs = {
      for (final locale in _locales)
        locale: EmojiKeywordPack.decode(_read('assets/keywords/$locale.tsv')),
    };
    _shortcodes = EmojiShortcodes.decode(_read('assets/shortcodes.tsv'));
  });

  group('structure asset', () {
    test('is the Emoji version the lock pins', () {
      final lock = InputsLock.parse(_read('tool/inputs.lock'));

      expect(_structure.emojiVersion, lock.emojiVersion);
    });

    test('lists no sequence twice', () {
      final keys = [
        for (final entry in _structure.entries) ...[
          entry.base,
          for (final variant in entry.variants) variant.key,
        ],
      ];

      expect(keys.toSet(), hasLength(keys.length));
    });

    test('holds every emoji of the pinned Emoji version', () {
      final keys = [
        for (final entry in _structure.entries) ...[
          entry.base,
          for (final variant in entry.variants) variant.key,
        ],
      ];

      expect(keys.where((k) => !_hasTone(k)), hasLength(_toneless));
      expect(keys.where(_hasTone), hasLength(_toned));
    });

    test('groups them as Unicode does, components excluded', () {
      expect(_structure.groups.map((g) => g.id), [
        'smileys-emotion',
        'people-body',
        'animals-nature',
        'food-drink',
        'travel-places',
        'activities',
        'objects',
        'symbols',
        'flags',
      ]);
    });

    test('has the newest emoji, a ZWJ sequence and a rainbow flag', () {
      final bases = _structure.entries.map((e) => e.base).toSet();

      expect(bases, contains(_key('1FAEB')));
      expect(bases, contains(_key('1F426-200D-1F525')));
      expect(bases, contains(_key('1F3F3-FE0F-200D-1F308')));
    });

    test('keeps a mixed-tone handshake as a variant of the handshake', () {
      final handshake = _structure.entries.singleWhere(
        (e) => e.base == _key('1F91D'),
      );

      expect(
        handshake.keyFor(
          EmojiModifiers(tones: const [SkinTone.light, SkinTone.dark]),
        ),
        _key('1FAF1-1F3FB-200D-1FAF2-1F3FF'),
      );
    });

    test('keeps the woman technologist as a gender variant of the person', () {
      final technologist = _structure.entries.singleWhere(
        (e) => e.base == _key('1F9D1-200D-1F4BB'),
      );

      expect(
        technologist.keyFor(EmojiModifiers(genders: const [EmojiGender.woman])),
        _key('1F469-200D-1F4BB'),
      );
    });

    test('stays within its size budget', () {
      expect(
        _gzipSize(_read('assets/structure.tsv')),
        lessThan(_structureBudget),
      );
    });
  });

  group('keyword packs', () {
    test('exist for exactly the lock locales', () {
      final lock = InputsLock.parse(_read('tool/inputs.lock'));
      final files = Directory(
        '${_root.path}/assets/keywords',
      ).listSync().map((f) => f.uri.pathSegments.last).toList()..sort();

      expect(lock.locales, _locales);
      expect(files, ([for (final l in _locales) '$l.tsv']..sort()));
    });

    test('name every entry and every gender variant', () {
      for (final MapEntry(key: locale, value: pack) in _packs.entries) {
        for (final entry in _structure.entries) {
          expect(
            pack[entry.base]?.spokenName,
            isNotEmpty,
            reason: '$locale ${entry.base}',
          );
          for (final variant in entry.variants) {
            if (variant.modifiers.tones.isEmpty) {
              expect(
                pack[variant.key]?.spokenName,
                isNotEmpty,
                reason: '$locale ${variant.key}',
              );
            }
          }
        }
      }
    });

    test('hold no sequence the structure does not', () {
      final known = {
        for (final entry in _structure.entries) ...[
          entry.base,
          for (final variant in entry.variants) variant.key,
        ],
      };

      for (final pack in _packs.values) {
        expect(pack.records.every((r) => known.contains(r.key)), isTrue);
      }
    });

    test('have no stray whitespace or control characters', () {
      // Control and invisible characters that are never part of a name. ZWJ
      // and ZWNJ are left alone: Hindi conjuncts need them.
      final bad = RegExp(
        r'[\u0000-\u0008\u000B-\u001F\u007F\u200B\u200E\u200F\u2060\uFEFF]',
      );
      for (final MapEntry(key: locale, value: pack) in _packs.entries) {
        for (final record in pack.records) {
          for (final text in [record.spokenName, ...record.keywords]) {
            expect(text, text.trim(), reason: '$locale ${record.key}');
            expect(
              text.contains('  '),
              isFalse,
              reason: '$locale ${record.key}',
            );
            expect(
              text.contains(bad),
              isFalse,
              reason: '$locale ${record.key}',
            );
          }
          expect(
            record.keywords.toSet(),
            hasLength(record.keywords.length),
            reason: '$locale ${record.key}',
          );
        }
      }
    });

    // Country names as the locales themselves write them; the flag is the
    // two regional indicators of the ISO code.
    const countries = {
      'DE': {
        'en': 'Germany',
        'de': 'Deutschland',
        'es': 'Alemania',
        'fr': 'Allemagne',
        'hi': 'जर्मनी',
        'it': 'Germania',
        'ja': 'ドイツ',
        'nl': 'Duitsland',
        'pt': 'Alemanha',
        'ru': 'Германия',
        'zh': '德国',
      },
      'JP': {
        'en': 'Japan',
        'de': 'Japan',
        'es': 'Japón',
        'fr': 'Japon',
        'hi': 'जापान',
        'it': 'Giappone',
        'ja': '日本',
        'nl': 'Japan',
        'pt': 'Japão',
        'ru': 'Япония',
        'zh': '日本',
      },
    };
    for (final MapEntry(key: code, value: names) in countries.entries) {
      test('find the $code flag by its country name in every locale', () {
        final flag = ContentKey$Unicode(
          String.fromCharCodes([
            for (final unit in code.codeUnits) 0x1F1E6 + unit - 0x41,
          ]),
        );
        for (final MapEntry(key: locale, value: name) in names.entries) {
          final record = _packs[locale]![flag]!;

          expect(
            [
              record.spokenName,
              ...record.keywords,
            ].any((t) => t.contains(name)),
            isTrue,
            reason:
                '$locale: "$name" not in ${record.spokenName} ${record.keywords}',
          );
        }
      });
    }

    test('stay within their size budget', () {
      for (final locale in _locales) {
        expect(
          _gzipSize(_read('assets/keywords/$locale.tsv')),
          lessThan(_packBudget),
          reason: locale,
        );
      }
    });
  });

  group('shortcodes asset', () {
    test('comes from the toolkit tag the lock pins', () {
      final lock = InputsLock.parse(_read('tool/inputs.lock'));

      expect(_shortcodes.source, 'emoji-toolkit ${lock.shortcodesRef}');
    });

    test('codes nearly every emoji with a keyword record', () {
      // The toolkit lags Unicode: its newest sequences have no code yet.
      expect(_shortcodes.codes, hasLength(greaterThanOrEqualTo(1900)));
    });

    test('codes only emoji that have a keyword record', () {
      final pack = _packs['en']!;

      for (final key in _shortcodes.codes.keys) {
        expect(pack[key], isNotNull, reason: '$key');
      }
    });

    test('gives an emoji and its gender forms the codes people type', () {
      expect(_shortcodes[_key('1F600')], ':grinning:');
      expect(_shortcodes[_key('1F9D1-200D-1F4BB')], ':technologist:');
      expect(_shortcodes[_key('1F469-200D-1F4BB')], ':woman_technologist:');
    });

    test('gives no two emoji one code', () {
      expect(
        _shortcodes.codes.values.toSet(),
        hasLength(_shortcodes.codes.length),
      );
    });

    test('stays within its size budget', () {
      expect(
        _gzipSize(_read('assets/shortcodes.tsv')),
        lessThan(_shortcodesBudget),
      );
    });
  });

  group('package', () {
    test('declares every asset directory to Flutter', () {
      final pubspec = _read('pubspec.yaml');

      expect(pubspec, contains('- assets/structure.tsv'));
      expect(pubspec, contains('- assets/keywords/'));
      expect(pubspec, contains('- assets/LICENSE-UNICODE.txt'));
      expect(pubspec, contains('- assets/shortcodes.tsv'));
      expect(pubspec, contains('- assets/LICENSE-JOYPIXELS.txt'));
    });

    test('ships the Unicode licence next to the assets', () {
      expect(
        _read('assets/LICENSE-UNICODE.txt'),
        contains('UNICODE LICENSE V3'),
      );
    });

    test('ships the toolkit licence next to the shortcodes', () {
      final licence = _read('assets/LICENSE-JOYPIXELS.txt');

      expect(licence, contains('JoyPixels Non-Artwork'));
      expect(licence, contains('License: MIT'));
    });

    test('reads no other catalog source than the pinned inputs', () {
      final pubspec = _read('pubspec.yaml');

      expect(pubspec, isNot(contains('emoji_data')));
      expect(pubspec, isNot(contains('emoji_picker_flutter')));
    });
  });
}
