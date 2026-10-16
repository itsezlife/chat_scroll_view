import 'dart:io';

import 'package:chrome_foundation/testing.dart';
import 'package:flutter_test/flutter_test.dart';

/// Strings that are the same word in English and Russian.
const _sameInBoth = {'panel.tabLabel[gif]'};

void main() {
  final presets = {
    'english': ChromeStringsPresets.english,
    'russian': ChromeStringsPresets.russian,
  };

  group('completeness', () {
    for (final entry in presets.entries) {
      test('${entry.key}: every key has a non-empty value', () {
        final snapshot = describeChromeStrings(entry.value);
        expect(snapshot, isNotEmpty);
        for (final item in snapshot.entries) {
          expect(item.value.trim(), isNotEmpty, reason: item.key);
        }
      });
    }

    test('both presets define exactly the same keys', () {
      expect(
        describeChromeStrings(ChromeStringsPresets.russian).keys,
        describeChromeStrings(ChromeStringsPresets.english).keys,
      );
    });

    test('the snapshot lists every member of every group', () {
      // A member added to a group but not to describeChromeStrings would
      // escape the checks above, so compare against the declarations.
      final keys = describeChromeStrings(ChromeStringsPresets.english).keys;
      final groups = {
        'panel': 'lib/src/strings/panel_strings.dart',
        'composer': 'lib/src/strings/composer_strings.dart',
        'semantics': 'lib/src/strings/semantics_strings.dart',
      };
      final field = RegExp(r'^  final .+ (\w+);$', multiLine: true);
      for (final group in groups.entries) {
        final declared = field
            .allMatches(File(group.value).readAsStringSync())
            .map((m) => '${group.key}.${m[1]}')
            .toSet();
        expect(declared, isNotEmpty, reason: group.value);
        final listed = keys
            .where((k) => k.startsWith('${group.key}.'))
            .map((k) => k.split('(').first.split('[').first)
            .toSet();
        expect(listed, declared, reason: group.key);
      }
    });

    test('the russian preset is not the english one', () {
      final english = describeChromeStrings(ChromeStringsPresets.english);
      final russian = describeChromeStrings(ChromeStringsPresets.russian);
      for (final key in english.keys.where((k) => !_sameInBoth.contains(k))) {
        expect(russian[key], isNot(english[key]), reason: key);
      }
    });
  });

  group('data-dependent wording', () {
    test('english search result count pluralises', () {
      final s = ChromeStringsPresets.english.semantics;
      expect(s.searchResultCount(0), 'No results');
      expect(s.searchResultCount(1), '1 result');
      expect(s.searchResultCount(2), '2 results');
    });

    test('russian follows the one / few / many rules', () {
      final s = ChromeStringsPresets.russian.semantics;
      expect(s.searchResultCount(1), '1 результат');
      expect(s.searchResultCount(2), '2 результата');
      expect(s.searchResultCount(4), '4 результата');
      expect(s.searchResultCount(5), '5 результатов');
      expect(s.searchResultCount(11), '11 результатов');
      expect(s.searchResultCount(21), '21 результат');
      expect(s.searchResultCount(22), '22 результата');
      expect(s.searchResultCount(111), '111 результатов');
    });

    test('names and page ids are interpolated', () {
      expect(
        ChromeStringsPresets.english.composer.replyTo('Alice'),
        contains('Alice'),
      );
      expect(
        ChromeStringsPresets.russian.composer.replyTo('Алиса'),
        contains('Алиса'),
      );
      expect(
        ChromeStringsPresets.english.semantics.pageSelected('Stickers'),
        contains('Stickers'),
      );
    });

    test('a tab label for an unknown page id falls back to the id', () {
      expect(ChromeStringsPresets.english.panel.tabLabel('custom'), 'custom');
    });

    test('category ids resolve to titles and an unknown one to itself', () {
      expect(
        ChromeStringsPresets.english.panel.categoryTitle('flags'),
        'Flags',
      );
      expect(
        ChromeStringsPresets.russian.panel.categoryTitle('flags'),
        'Флаги',
      );
      expect(
        ChromeStringsPresets.english.panel.categoryTitle('custom-set'),
        'custom-set',
      );
    });

    test('known page ids resolve to their tab names', () {
      expect(ChromeStringsPresets.english.panel.tabLabel('emoji'), 'Emoji');
      expect(
        ChromeStringsPresets.russian.panel.tabLabel('stickers'),
        'Стикеры',
      );
    });
  });
}
