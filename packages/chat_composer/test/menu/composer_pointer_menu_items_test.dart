/// The pointer menu's rows: order, labels, hints, which are greyed in which
/// state, and what choosing each one runs.
///
/// **Seam:** [ComposerPointerMenuItems.of] over a real
/// [ComposerTextController], read through the entries it returns.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/widgets.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';

final _strings = ChromeStringsPresets.english.editMenu;
final _windows = ComposerMenuHints.forPlatform(TargetPlatform.windows);

final class _Spy {
  final calls = <String>[];

  ComposerPointerMenuCommands get commands => ComposerPointerMenuCommands(
    undo: () => calls.add('undo'),
    redo: () => calls.add('redo'),
    cut: () => calls.add('cut'),
    copy: () => calls.add('copy'),
    paste: () => calls.add('paste'),
    pastePlain: () => calls.add('pastePlain'),
    delete: () => calls.add('delete'),
    selectAll: () => calls.add('selectAll'),
    editLink: (pointer) => calls.add('editLink ${pointer?.range}'),
    toggleList: (kind) =>
        () => calls.add('list ${kind.name}'),
  );
}

PointerMenuItem _find(List<PointerMenuEntry> entries, Object id) {
  for (final entry in entries) {
    if (entry is PointerMenuItem) {
      if (entry.id == id) return entry;
      if (entry.submenu != null) {
        for (final inner in entry.submenu!) {
          if (inner is PointerMenuItem && inner.id == id) return inner;
        }
      }
    }
  }
  throw StateError('no row $id');
}

bool _has(List<PointerMenuEntry> entries, Object id) => [
  for (final entry in entries)
    if (entry is PointerMenuItem) ...[entry, ...?entry.submenu],
].whereType<PointerMenuItem>().any((item) => item.id == id);

List<Object> _shape(List<PointerMenuEntry> entries) => [
  for (final entry in entries)
    if (entry is PointerMenuItem) entry.id else '-',
];

void main() {
  late ComposerTextController text;
  late _Spy spy;

  setUp(() {
    text = ComposerTextController();
    spy = _Spy();
  });
  tearDown(() => text.dispose());

  void load(RichText value, {int from = 0, int? to}) => text.restore(
    value,
    selection: TextSelection(baseOffset: from, extentOffset: to ?? from),
  );

  ComposerMenuState state({
    bool canUndo = false,
    bool canRedo = false,
    bool canPaste = false,
    bool rich = false,
    ComposerMenuLink? pointerLink,
    ComposerMenuSpelling? spelling,
  }) => ComposerMenuState(
    canUndo: canUndo,
    canRedo: canRedo,
    canPaste: canPaste,
    hasRichClipboard: rich,
    pointerLink: pointerLink,
    spelling: spelling,
  );

  List<PointerMenuEntry> build({
    ComposerMenuState? menuState,
    Set<ComposerFormattingOption>? options,
    bool canLink = true,
    bool spellingOnTop = true,
  }) => ComposerPointerMenuItems.of(
    text: text,
    state: menuState ?? state(),
    commands: spy.commands,
    options: options ?? ComposerFormattingOption.standard,
    strings: _strings,
    hints: _windows,
    canLink: canLink,
    spellingOnTop: spellingOnTop,
  );

  bool enabled(List<PointerMenuEntry> entries, Object id) =>
      _find(entries, id).isEnabled;

  group('order', () {
    test('the message field\'s menu, in the reference order', () {
      load(const RichText.plain('hello'));

      expect(_shape(build()), [
        ComposerMenuAction.undo,
        ComposerMenuAction.redo,
        '-',
        ComposerMenuAction.cut,
        ComposerMenuAction.copy,
        ComposerMenuAction.paste,
        ComposerMenuAction.delete,
        '-',
        ComposerMenuAction.formatting,
        '-',
        ComposerMenuAction.selectAll,
      ]);
    });

    test(
      'Paste as plain text follows Paste when there is a rich clipboard',
      () {
        load(const RichText.plain('hello'));

        final shape = _shape(build(menuState: state(rich: true)));

        expect(shape.sublist(shape.indexOf(ComposerMenuAction.paste)).take(3), [
          ComposerMenuAction.paste,
          ComposerMenuAction.pastePlain,
          ComposerMenuAction.delete,
        ]);
      },
    );

    test('with nothing to format the menu keeps its separator before Select '
        'All', () {
      load(const RichText.plain('hello'));

      expect(_shape(build(options: const {})), [
        ComposerMenuAction.undo,
        ComposerMenuAction.redo,
        '-',
        ComposerMenuAction.cut,
        ComposerMenuAction.copy,
        ComposerMenuAction.paste,
        ComposerMenuAction.delete,
        '-',
        ComposerMenuAction.selectAll,
      ]);
    });

    test('labels and hints are the strings\' and the platform\'s', () {
      load(const RichText.plain('hello'));
      final entries = build();

      expect(_find(entries, ComposerMenuAction.undo).label, '&Undo');
      expect(_find(entries, ComposerMenuAction.undo).hint, 'Ctrl+Z');
      expect(_find(entries, ComposerMenuAction.redo).hint, 'Ctrl+Y');
      expect(_find(entries, ComposerMenuAction.delete).hint, isNull);
      expect(_find(entries, ComposerMenuAction.selectAll).label, 'Select All');
      expect(_find(entries, ComposerMenuAction.selectAll).hint, 'Ctrl+A');
    });
  });

  group('which rows are greyed', () {
    test('an empty field with nothing to paste: everything but Formatting', () {
      final entries = build();

      for (final id in [
        ComposerMenuAction.undo,
        ComposerMenuAction.redo,
        ComposerMenuAction.cut,
        ComposerMenuAction.copy,
        ComposerMenuAction.paste,
        ComposerMenuAction.delete,
        ComposerMenuAction.selectAll,
      ]) {
        expect(enabled(entries, id), isFalse, reason: '$id');
      }
      expect(enabled(entries, ComposerMenuAction.formatting), isTrue);
    });

    test('an empty field with text on the clipboard can paste', () {
      final entries = build(menuState: state(canPaste: true));

      expect(enabled(entries, ComposerMenuAction.paste), isTrue);
      expect(enabled(entries, ComposerMenuAction.selectAll), isFalse);
    });

    test(
      'a caret in text: select all is live, cut copy and delete are not',
      () {
        load(const RichText.plain('hello'), from: 2);
        final entries = build();

        expect(enabled(entries, ComposerMenuAction.selectAll), isTrue);
        for (final id in [
          ComposerMenuAction.cut,
          ComposerMenuAction.copy,
          ComposerMenuAction.delete,
        ]) {
          expect(enabled(entries, id), isFalse, reason: '$id');
        }
      },
    );

    test('a selection: cut, copy and delete are live', () {
      load(const RichText.plain('hello'), from: 1, to: 4);
      final entries = build();

      for (final id in [
        ComposerMenuAction.cut,
        ComposerMenuAction.copy,
        ComposerMenuAction.delete,
      ]) {
        expect(enabled(entries, id), isTrue, reason: '$id');
      }
    });

    test('undo and redo follow the history', () {
      load(const RichText.plain('hello'));

      final entries = build(menuState: state(canUndo: true, canRedo: true));

      expect(enabled(entries, ComposerMenuAction.undo), isTrue);
      expect(enabled(entries, ComposerMenuAction.redo), isTrue);
    });

    test('select all stays live over a text that is all selected', () {
      load(const RichText.plain('hello'), from: 0, to: 5);

      expect(enabled(build(), ComposerMenuAction.selectAll), isTrue);
    });
  });

  group('the Formatting submenu', () {
    List<PointerMenuEntry> submenu(List<PointerMenuEntry> entries) =>
        _find(entries, ComposerMenuAction.formatting).submenu!;

    test('lists the reference rows in order, then the additions', () {
      load(const RichText.plain('hello'), from: 0, to: 5);

      expect(
        _shape(
          submenu(
            build(
              menuState: state(),
              options: ComposerFormattingOption.standard,
            ),
          ),
        ),
        [
          ComposerMenuAction.bold,
          ComposerMenuAction.italic,
          ComposerMenuAction.underline,
          ComposerMenuAction.strikethrough,
          ComposerMenuAction.quote,
          ComposerMenuAction.monospace,
          ComposerMenuAction.spoiler,
          ComposerMenuAction.codeBlock,
          '-',
          ComposerMenuAction.createLink,
          '-',
          ComposerMenuAction.clearFormatting,
        ],
      );
    });

    test('the list rows join the additions only with lists on', () {
      text.dispose();
      text = ComposerTextController(lists: true);
      load(const RichText.plain('hello'), from: 0, to: 5);

      final shape = _shape(
        submenu(build(options: ComposerFormattingOption.all)),
      );

      expect(
        shape.sublist(
          shape.indexOf(ComposerMenuAction.codeBlock),
          shape.indexOf(ComposerMenuAction.codeBlock) + 3,
        ),
        [
          ComposerMenuAction.codeBlock,
          ComposerMenuAction.bulletList,
          ComposerMenuAction.numberedList,
        ],
      );
    });

    test('a row the host did not offer is absent', () {
      load(const RichText.plain('hello'), from: 0, to: 5);

      final shape = _shape(
        submenu(
          build(
            options: const {
              ComposerFormattingOption.bold,
              ComposerFormattingOption.clearFormatting,
            },
          ),
        ),
      );

      expect(shape, [
        ComposerMenuAction.bold,
        '-',
        ComposerMenuAction.clearFormatting,
      ]);
    });

    test('over a selection the style rows are live', () {
      load(const RichText.plain('hello'), from: 0, to: 5);
      final entries = build();

      for (final id in [
        ComposerMenuAction.bold,
        ComposerMenuAction.italic,
        ComposerMenuAction.underline,
        ComposerMenuAction.strikethrough,
        ComposerMenuAction.quote,
        ComposerMenuAction.monospace,
        ComposerMenuAction.spoiler,
        ComposerMenuAction.codeBlock,
      ]) {
        expect(enabled(entries, id), isTrue, reason: '$id');
      }
    });

    test('at a caret every style row is greyed, the line kinds too, and '
        'Create link is live', () {
      load(const RichText.plain('hello'), from: 2);
      final entries = build();

      for (final id in [
        ComposerMenuAction.bold,
        ComposerMenuAction.italic,
        ComposerMenuAction.underline,
        ComposerMenuAction.strikethrough,
        ComposerMenuAction.quote,
        ComposerMenuAction.monospace,
        ComposerMenuAction.spoiler,
        ComposerMenuAction.codeBlock,
        ComposerMenuAction.clearFormatting,
      ]) {
        expect(enabled(entries, id), isFalse, reason: '$id');
      }
      expect(enabled(entries, ComposerMenuAction.createLink), isTrue);
    });

    test('with nothing typed the Formatting row is live and its rows are '
        'greyed', () {
      final entries = build();

      expect(enabled(entries, ComposerMenuAction.formatting), isTrue);
      expect(enabled(entries, ComposerMenuAction.bold), isFalse);
    });

    test('Clear formatting is live only over formatting', () {
      load(const RichText.plain('hello'), from: 0, to: 5);
      expect(enabled(build(), ComposerMenuAction.clearFormatting), isFalse);

      load(
        RichText('hello', const [Entity(0, 5, EntityKind.bold)]),
        from: 0,
        to: 5,
      );
      expect(enabled(build(), ComposerMenuAction.clearFormatting), isTrue);
    });

    test('there are no link rows without a prompt', () {
      load(const RichText.plain('hello'), from: 0, to: 5);

      final entries = build(canLink: false);

      expect(_has(entries, ComposerMenuAction.createLink), isFalse);
      expect(_has(entries, ComposerMenuAction.editLink), isFalse);
    });

    test('hints are the reference keys, none for the additions', () {
      load(const RichText.plain('hello'), from: 0, to: 5);
      final entries = build();

      expect(_find(entries, ComposerMenuAction.bold).hint, 'Ctrl+B');
      expect(_find(entries, ComposerMenuAction.quote).hint, 'Ctrl+Shift+.');
      expect(_find(entries, ComposerMenuAction.codeBlock).hint, isNull);
      expect(_find(entries, ComposerMenuAction.createLink).hint, 'Ctrl+K');
    });
  });

  group('links', () {
    final linked = RichText('go to site now', const [
      Entity(6, 4, EntityKind.link('https://a.example')),
    ]);

    test('a selection touching a link offers Edit and Remove', () {
      load(linked, from: 5, to: 8);
      final entries = build();

      expect(_has(entries, ComposerMenuAction.editLink), isTrue);
      expect(_has(entries, ComposerMenuAction.removeLink), isTrue);
      expect(_has(entries, ComposerMenuAction.createLink), isFalse);
    });

    test('a caret with the pointer over a link offers Edit and Remove', () {
      load(linked, from: 0);
      final entries = build(
        menuState: state(
          pointerLink: const ComposerMenuLink(
            range: TextRange(start: 6, end: 10),
            url: 'https://a.example',
          ),
        ),
      );

      expect(_has(entries, ComposerMenuAction.editLink), isTrue);
      expect(enabled(entries, ComposerMenuAction.editLink), isTrue);
      expect(_has(entries, ComposerMenuAction.removeLink), isTrue);
    });

    test('a selection wins over the pointer\'s link', () {
      load(const RichText.plain('plain text here'), from: 0, to: 5);
      final entries = build(
        menuState: state(
          pointerLink: const ComposerMenuLink(
            range: TextRange(start: 6, end: 10),
            url: 'x',
          ),
        ),
      );

      expect(_has(entries, ComposerMenuAction.createLink), isTrue);
      expect(_has(entries, ComposerMenuAction.editLink), isFalse);
    });

    test('Edit link on the pointer\'s link passes it to the command', () {
      load(linked, from: 0);
      final entries = build(
        menuState: state(
          pointerLink: const ComposerMenuLink(
            range: TextRange(start: 6, end: 10),
            url: 'https://a.example',
          ),
        ),
      );

      _find(entries, ComposerMenuAction.editLink).onSelected!();

      expect(spy.calls, ['editLink TextRange(start: 6, end: 10)']);
    });

    test('Create link on a selection passes no pointer link', () {
      load(const RichText.plain('hello'), from: 0, to: 5);

      _find(build(), ComposerMenuAction.createLink).onSelected!();

      expect(spy.calls, ['editLink null']);
    });

    test('Remove link on the pointer\'s link leaves the selection alone', () {
      load(linked, from: 2);
      final entries = build(
        menuState: state(
          pointerLink: const ComposerMenuLink(
            range: TextRange(start: 6, end: 10),
            url: 'https://a.example',
          ),
        ),
      );

      _find(entries, ComposerMenuAction.removeLink).onSelected!();

      expect(text.richText, const RichText.plain('go to site now'));
      expect(text.selection, const TextSelection.collapsed(offset: 2));
    });
  });

  group('choosing a row', () {
    test('runs its command', () {
      load(const RichText.plain('hello'), from: 0, to: 5);
      final entries = build(
        menuState: state(
          canUndo: true,
          canRedo: true,
          canPaste: true,
          rich: true,
        ),
      );

      for (final id in [
        ComposerMenuAction.undo,
        ComposerMenuAction.redo,
        ComposerMenuAction.cut,
        ComposerMenuAction.copy,
        ComposerMenuAction.paste,
        ComposerMenuAction.pastePlain,
        ComposerMenuAction.delete,
        ComposerMenuAction.selectAll,
      ]) {
        _find(entries, id).onSelected!();
      }

      expect(spy.calls, [
        'undo',
        'redo',
        'cut',
        'copy',
        'paste',
        'pastePlain',
        'delete',
        'selectAll',
      ]);
    });

    test('a style row toggles the style over the selection', () {
      load(const RichText.plain('hello world'), from: 0, to: 5);

      _find(build(), ComposerMenuAction.bold).onSelected!();

      expect(
        text.richText,
        RichText('hello world', const [Entity(0, 5, EntityKind.bold)]),
      );
    });

    test('Monospace toggles inline code', () {
      load(const RichText.plain('hello world'), from: 0, to: 5);

      _find(build(), ComposerMenuAction.monospace).onSelected!();

      expect(
        text.richText,
        RichText('hello world', const [Entity(0, 5, EntityKind.code)]),
      );
    });
  });

  group('spelling', () {
    final spelling = ComposerMenuSpelling(
      range: const TextRange(start: 0, end: 4),
      word: 'helo',
      result: const ComposerWordSpelling(
        isCorrect: false,
        suggestions: ['hello', 'help'],
      ),
      checker: _FakeSpellChecker(),
    );

    test('a wrong word puts the Spelling submenu on top, with a separator', () {
      load(const RichText.plain('helo world'));

      final shape = _shape(build(menuState: state(spelling: spelling)));

      expect(shape.take(3), [
        ComposerMenuAction.spelling,
        '-',
        ComposerMenuAction.undo,
      ]);
    });

    test('an upward menu puts it at the bottom, after a separator', () {
      load(const RichText.plain('helo world'));

      final shape = _shape(
        build(menuState: state(spelling: spelling), spellingOnTop: false),
      );

      expect(shape.skip(shape.length - 3), [
        ComposerMenuAction.selectAll,
        '-',
        ComposerMenuAction.spelling,
      ]);
    });

    test('its rows: Add to Dictionary, Ignore word, then the suggestions', () {
      load(const RichText.plain('helo world'));
      final entries = build(menuState: state(spelling: spelling));

      final rows = _find(entries, ComposerMenuAction.spelling).submenu!;

      expect(_shape(rows), [
        ComposerMenuAction.addToDictionary,
        ComposerMenuAction.ignoreWord,
        '-',
        const ComposerSuggestionId('hello'),
        const ComposerSuggestionId('help'),
      ]);
    });

    test('choosing a suggestion replaces the word', () {
      load(const RichText.plain('helo world'));
      final entries = build(menuState: state(spelling: spelling));
      final rows = _find(entries, ComposerMenuAction.spelling).submenu!;

      (rows.last as PointerMenuItem).onSelected!();

      expect(text.text, 'help world');
    });

    test('a right word has no Spelling row', () {
      load(const RichText.plain('hello world'));
      final right = ComposerMenuSpelling(
        range: const TextRange(start: 0, end: 5),
        word: 'hello',
        result: const ComposerWordSpelling(isCorrect: true),
        checker: _FakeSpellChecker(),
      );

      expect(
        _has(
          build(menuState: state(spelling: right)),
          ComposerMenuAction.spelling,
        ),
        isFalse,
      );
    });

    test('a right word the user added offers Remove from Dictionary', () {
      load(const RichText.plain('hello world'));
      final checker = _FakeSpellChecker();
      final added = ComposerMenuSpelling(
        range: const TextRange(start: 0, end: 5),
        word: 'hello',
        result: const ComposerWordSpelling(
          isCorrect: true,
          inUserDictionary: true,
        ),
        checker: checker,
      );
      final entries = build(menuState: state(spelling: added));

      final rows = _find(entries, ComposerMenuAction.spelling).submenu!;
      (rows.single as PointerMenuItem).onSelected!();

      expect(_shape(rows), [ComposerMenuAction.removeFromDictionary]);
      expect(checker.calls, ['remove hello']);
    });

    test('Add to Dictionary and Ignore word call the checker', () {
      load(const RichText.plain('helo world'));
      final checker = _FakeSpellChecker();
      final entries = build(
        menuState: state(
          spelling: ComposerMenuSpelling(
            range: spelling.range,
            word: spelling.word,
            result: spelling.result,
            checker: checker,
          ),
        ),
      );
      final rows = _find(entries, ComposerMenuAction.spelling).submenu!;

      (rows[0] as PointerMenuItem).onSelected!();
      (rows[1] as PointerMenuItem).onSelected!();

      expect(checker.calls, ['add helo', 'ignore helo']);
    });
  });
}

final class _FakeSpellChecker implements ComposerSpellChecker {
  final calls = <String>[];

  @override
  Future<ComposerWordSpelling> check(String word) async =>
      const ComposerWordSpelling(isCorrect: true);

  @override
  Future<void> addToDictionary(String word) async => calls.add('add $word');

  @override
  Future<void> ignore(String word) async => calls.add('ignore $word');

  @override
  Future<void> removeFromDictionary(String word) async =>
      calls.add('remove $word');
}
