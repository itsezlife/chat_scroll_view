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
        final snapshot = ChromeStringsSnapshot.of(entry.value);
        expect(snapshot, isNotEmpty);
        for (final item in snapshot.entries) {
          expect(item.value.trim(), isNotEmpty, reason: item.key);
        }
      });
    }

    test('both presets define exactly the same keys', () {
      expect(
        ChromeStringsSnapshot.of(ChromeStringsPresets.russian).keys,
        ChromeStringsSnapshot.of(ChromeStringsPresets.english).keys,
      );
    });

    test('the snapshot lists every member of every group', () {
      // A member added to a group but not to ChromeStringsSnapshot.of would
      // escape the checks above, so compare against the declarations.
      final keys = ChromeStringsSnapshot.of(ChromeStringsPresets.english).keys;
      final groups = {
        'panel': 'lib/src/strings/panel_strings.dart',
        'composer': 'lib/src/strings/composer_strings.dart',
        'semantics': 'lib/src/strings/semantics_strings.dart',
        'formatting': 'lib/src/strings/formatting_strings.dart',
        'editMenu': 'lib/src/strings/edit_menu_strings.dart',
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
      final english = ChromeStringsSnapshot.of(ChromeStringsPresets.english);
      final russian = ChromeStringsSnapshot.of(ChromeStringsPresets.russian);
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
        ChromeStringsPresets.english.panel.categoryTitle('people'),
        'Smileys & People',
      );
      expect(
        ChromeStringsPresets.russian.panel.categoryTitle('people'),
        'Смайлики и люди',
      );
      expect(
        ChromeStringsPresets.english.panel.categoryTitle('custom-set'),
        'custom-set',
      );
    });

    test('the desktop menu keeps the reference client\'s Qt mnemonics', () {
      final e = ChromeStringsPresets.english.editMenu;
      expect(
        [e.undoAction, e.redoAction, e.cutAction, e.copyAction, e.pasteAction],
        ['&Undo', '&Redo', 'Cu&t', '&Copy', '&Paste'],
      );
      expect(e.deleteAction, 'Delete');
      expect(e.selectAllAction, 'Select All');
    });

    test('the desktop formatting rows use the desktop wording', () {
      final e = ChromeStringsPresets.english.editMenu;
      expect(e.monospaceAction, 'Monospace');
      expect(e.createLinkAction, 'Create link');
      expect(e.clearFormattingAction, 'Clear formatting');
    });

    test('the menu labels are the reference client\'s English wording', () {
      final f = ChromeStringsPresets.english.formatting;
      expect(
        [
          f.quoteAction,
          f.spoilerAction,
          f.boldAction,
          f.italicAction,
          f.monoAction,
          f.strikethroughAction,
          f.underlineAction,
          f.createLinkAction,
          f.editLinkAction,
          f.removeLinkAction,
          f.codeBlockAction,
          f.bulletListAction,
          f.numberedListAction,
          f.clearFormattingAction,
          f.moreAction,
          f.backAction,
        ],
        [
          'Quote',
          'Spoiler',
          'Bold',
          'Italic',
          'Mono',
          'Strikethrough',
          'Underline',
          'Create Link',
          'Edit Link',
          'Remove Link',
          'Code block',
          'Bullet list',
          'Numbered list',
          'Regular',
          'More',
          'Back',
        ],
      );
    });

    test('a numbered list item label carries its number', () {
      expect(
        ChromeStringsPresets.english.formatting.numberedListItem(3),
        contains('3'),
      );
      expect(
        ChromeStringsPresets.russian.formatting.numberedListItem(3),
        contains('3'),
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
