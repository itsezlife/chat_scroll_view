import 'package:chat_composer/chat_composer.dart';
import 'package:chat_composer/src/text/list_editing.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/markdown.dart';
import 'package:flutter/widgets.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';

import '../support/simulated_input.dart';

const _bullet = EntityKind.list(listKind: EntityListKind.bullet);
const _bullet1 = EntityKind.list(listKind: EntityListKind.bullet, depth: 1);
const _ordered = EntityKind.list(listKind: EntityListKind.ordered);

void main() {
  late ComposerTextController controller;

  setUp(() => controller = ComposerTextController());
  tearDown(() => controller.dispose());

  void start({bool lists = true, RichText? text, int? caret}) {
    controller.dispose();
    controller = ComposerTextController(initial: text, lists: lists);
    controller.selection = TextSelection.collapsed(
      offset: caret ?? text?.length ?? 0,
    );
  }

  String markdown() => RichTextMarkdown.encode(controller.richText);

  // Backspace on a soft keyboard: the platform reports the line break before
  // the caret gone.
  void backspace() {
    final caret = controller.selection.baseOffset;
    controller.deleteRange(caret - 1, caret);
  }

  group('typed marker', () {
    test('"- " at a line start makes a bullet item and removes the marker', () {
      start();

      controller
        ..type('-')
        ..type(' ');

      expect(controller.text, '');
      expect(controller.isActive(_bullet), isTrue);

      controller.type('a');

      expect(controller.text, 'a');
      expect(controller.richText, RichText('a', const [Entity(0, 1, _bullet)]));
    });

    test('"* " is a bullet too', () {
      start();

      controller
        ..type('*')
        ..type(' ')
        ..type('a');

      expect(controller.richText, RichText('a', const [Entity(0, 1, _bullet)]));
    });

    test('"1. " makes a numbered item', () {
      start();

      controller
        ..type('1')
        ..type('.')
        ..type(' ')
        ..type('a');

      expect(
        controller.richText,
        RichText('a', const [Entity(0, 1, _ordered)]),
      );
    });

    test('"- " in front of a line that has text makes it an item', () {
      start(text: const RichText.plain('word'), caret: 0);

      controller
        ..type('-')
        ..type(' ');

      expect(controller.text, 'word');
      expect(controller.selection.baseOffset, 0);
      expect(
        controller.richText,
        RichText('word', const [Entity(0, 4, _bullet)]),
      );
    });

    test('"- " on a later line takes that line', () {
      start(text: const RichText.plain('one\ntwo'), caret: 4);

      controller
        ..type('-')
        ..type(' ');

      expect(
        controller.richText,
        RichText('one\ntwo', const [Entity(4, 3, _bullet)]),
      );
    });

    test('"- " in the middle of a line stays text', () {
      start();

      controller
        ..type('x')
        ..type('-')
        ..type(' ');

      expect(controller.text, 'x- ');
      expect(controller.richText.entities, isEmpty);
    });

    test('"- " after the marker was typed elsewhere stays text', () {
      start();

      controller
        ..type('a')
        ..type('-')
        ..type(' ');

      expect(controller.text, 'a- ');
    });

    test('is not made inside a quote or a code block', () {
      start(
        text: RichText('quoted', const [Entity(0, 6, EntityKind.quote)]),
        caret: 0,
      );

      controller
        ..type('-')
        ..type(' ');

      expect(controller.text, '- quoted');
      expect(
        controller.richText.entities.map((entity) => entity.kind),
        isNot(contains(_bullet)),
      );
    });

    test('is not made on a line that is an item already', () {
      start(text: RichText('a', const [Entity(0, 1, _bullet)]), caret: 0);

      controller
        ..type('-')
        ..type(' ');

      expect(controller.text, '- a');
    });
  });

  group('Enter', () {
    test('in a non-empty item starts the next of the same kind and depth', () {
      start(text: RichText('a', const [Entity(0, 1, _bullet1)]));

      controller
        ..type('\n')
        ..type('b');

      expect(
        controller.richText,
        RichText('a\nb', const [
          Entity(0, 1, _bullet1),
          Entity(2, 1, _bullet1),
        ]),
      );
      expect(controller.selection.baseOffset, 3);
    });

    test('splits the item at the caret', () {
      start(text: RichText('abcd', const [Entity(0, 4, _ordered)]), caret: 2);

      controller.type('\n');

      expect(
        controller.richText,
        RichText('ab\ncd', const [
          Entity(0, 2, _ordered),
          Entity(3, 2, _ordered),
        ]),
      );
      expect(controller.selection.baseOffset, 3);
    });

    test('keeps the style over the part that moves on', () {
      start(
        text: RichText('abcd', const [
          Entity(0, 4, _bullet),
          Entity(0, 4, EntityKind.bold),
        ]),
        caret: 2,
      );

      controller.type('\n');

      expect(
        controller.richText,
        RichText('ab\ncd', const [
          Entity(0, 2, _bullet),
          Entity(0, 2, EntityKind.bold),
          Entity(3, 2, _bullet),
          Entity(3, 2, EntityKind.bold),
        ]),
      );
    });

    test('in an empty item exits the list', () {
      start(text: RichText('a', const [Entity(0, 1, _bullet)]));

      controller
        ..type('\n')
        ..type('\n');

      expect(controller.text, 'a\n');
      expect(controller.richText.entities, const [Entity(0, 1, _bullet)]);
      expect(controller.isActive(_bullet), isFalse);

      controller.type('plain');

      expect(
        controller.richText,
        RichText('a\nplain', const [Entity(0, 1, _bullet)]),
      );
    });

    test('in an empty nested item goes one level out first', () {
      start(text: RichText('a', const [Entity(0, 1, _bullet1)]));

      controller
        ..type('\n')
        ..type('\n');

      expect(controller.isActive(_bullet), isTrue);

      controller.type('b');

      expect(
        controller.richText,
        RichText('a\nb', const [Entity(0, 1, _bullet1), Entity(2, 1, _bullet)]),
      );
    });

    test('at the start of a non-empty item pushes it down', () {
      start(text: RichText('a', const [Entity(0, 1, _bullet)]), caret: 0);

      controller.type('\n');

      expect(
        controller.richText,
        RichText('\na', const [Entity(1, 1, _bullet)]),
      );
    });

    test('on a soft break\'s empty line opens the next item', () {
      start(text: RichText('a', const [Entity(0, 1, _bullet)]));
      controller
        ..insertSoftBreak()
        ..type('\n')
        ..type('b');

      expect(
        controller.richText,
        RichText('a\nb', const [Entity(0, 1, _bullet), Entity(2, 1, _bullet)]),
      );
    });

    test('outside a list is an ordinary newline', () {
      start(text: const RichText.plain('a'));

      controller.type('\n');

      expect(controller.richText, const RichText.plain('a\n'));
    });

    test('with lists off is an ordinary newline', () {
      start(lists: false, text: RichText('a', const [Entity(0, 1, _bullet)]));

      controller.type('\n');

      expect(controller.richText.plain, 'a\n');
      expect(controller.richText.entities, hasLength(1));
      expect(controller.richText.entities.single.length, 1);
    });
  });

  group('Backspace', () {
    RichText items(EntityKind second) =>
        RichText('a\nb', [const Entity(0, 1, _bullet), Entity(2, 1, second)]);

    test('at the start of a depth-1 item outdents it, again leaves', () {
      start(text: items(_bullet1), caret: 2);

      backspace();

      expect(controller.text, 'a\nb');
      expect(controller.selection.baseOffset, 2);
      expect(controller.richText, items(_bullet));

      backspace();

      expect(controller.text, 'a\nb');
      expect(
        controller.richText,
        RichText('a\nb', const [Entity(0, 1, _bullet)]),
      );

      backspace();

      expect(controller.text, 'ab');
    });

    test('on the first line leaves the list through the command', () {
      start(text: RichText('a', const [Entity(0, 1, _bullet)]), caret: 0);

      expect(controller.canOutdentOrExitListItem, isTrue);
      controller.outdentOrExitListItem();

      expect(controller.richText, const RichText.plain('a'));
      expect(controller.canOutdentOrExitListItem, isFalse);
    });

    test('on an empty item outdents, then leaves', () {
      start(text: RichText('a', const [Entity(0, 1, _bullet1)]));
      controller.type('\n');
      expect(controller.isActive(_bullet), isTrue);

      backspace();
      expect(controller.text, 'a\n');
      expect(controller.isActive(_bullet), isTrue);
      expect(controller.richText.entities, const [Entity(0, 1, _bullet1)]);

      backspace();
      expect(controller.text, 'a\n');
      expect(controller.isActive(_bullet), isFalse);

      backspace();
      expect(controller.text, 'a');
    });

    test('inside an item deletes as usual', () {
      start(text: items(_bullet), caret: 3);

      backspace();

      expect(controller.text, 'a\n');
    });

    test('at a soft break\'s line start joins the lines', () {
      start(text: RichText('a\nb', const [Entity(0, 3, _bullet)]), caret: 2);

      backspace();

      expect(
        controller.richText,
        RichText('ab', const [Entity(0, 2, _bullet)]),
      );
    });

    test('with lists off deletes the line break', () {
      start(lists: false, text: items(_bullet1), caret: 2);

      backspace();

      expect(controller.text, 'ab');
    });
  });

  group('indent', () {
    test('Tab goes one level deeper, at most to depth 3', () {
      start(text: RichText('a', const [Entity(0, 1, _bullet)]));

      for (var depth = 1; depth <= 3; depth++) {
        expect(controller.canIndentListItems, isTrue);
        controller.indentListItems();
        expect(
          controller.richText.entities.single.kind,
          EntityKind.list(listKind: EntityListKind.bullet, depth: depth),
        );
      }

      expect(controller.canIndentListItems, isFalse);
      controller.indentListItems();
      expect(
        controller.richText.entities.single.kind,
        const EntityKind.list(listKind: EntityListKind.bullet, depth: 3),
      );
    });

    test('Shift+Tab goes one level out, down to depth 0', () {
      start(text: RichText('a', const [Entity(0, 1, _bullet1)]));

      controller.outdentListItems();

      expect(controller.richText.entities.single.kind, _bullet);
      expect(controller.canOutdentListItems, isFalse);
    });

    test('moves every item the selection touches', () {
      start(
        text: RichText('a\nb\nc', const [
          Entity(0, 1, _bullet),
          Entity(2, 1, _bullet),
          Entity(4, 1, _bullet),
        ]),
      );
      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 3,
      );

      controller.indentListItems();

      expect(controller.richText.entities.map((entity) => entity.kind), [
        _bullet1,
        _bullet1,
        _bullet,
      ]);
      expect(
        controller.selection,
        const TextSelection(baseOffset: 1, extentOffset: 3),
      );
    });

    test('off a list does nothing', () {
      start(text: const RichText.plain('a'));

      expect(controller.canIndentListItems, isFalse);
      expect(controller.canOutdentListItems, isFalse);
    });

    test('with lists off does nothing', () {
      start(lists: false, text: RichText('a', const [Entity(0, 1, _bullet)]));

      expect(controller.canIndentListItems, isFalse);
    });
  });

  group('soft break', () {
    test(
      'goes on inside the item and is written as two spaces and a break',
      () {
        start();
        controller
          ..type('-')
          ..type(' ')
          ..type('a');

        expect(controller.canInsertSoftBreak, isTrue);
        controller
          ..insertSoftBreak()
          ..type('b');

        expect(controller.text, 'a\nb');
        expect(
          controller.richText,
          RichText('a\nb', const [Entity(0, 3, _bullet)]),
        );
        expect(markdown(), '- a  \nb');
      },
    );

    test('in the middle of an item', () {
      start(text: RichText('ab', const [Entity(0, 2, _bullet)]), caret: 1);

      controller.insertSoftBreak();

      expect(
        controller.richText,
        RichText('a\nb', const [Entity(0, 3, _bullet)]),
      );
      expect(controller.selection.baseOffset, 2);
    });

    test('outside an item does nothing', () {
      start(text: const RichText.plain('a'));

      expect(controller.canInsertSoftBreak, isFalse);
    });
  });

  group('toggleList', () {
    test('makes every non-empty line an item, and again takes them out', () {
      start(text: const RichText.plain('one\n\ntwo'));
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 8,
      );

      controller.toggleList(EntityListKind.bullet);

      expect(
        controller.richText,
        RichText('one\n\ntwo', const [
          Entity(0, 3, _bullet),
          Entity(5, 3, _bullet),
        ]),
      );
      expect(controller.isActive(_bullet), isTrue);

      controller.toggleList(EntityListKind.bullet);

      expect(controller.richText, const RichText.plain('one\n\ntwo'));
    });

    test('changes the kind and keeps depth and soft breaks', () {
      start(
        text: RichText('a\nb\nc', const [
          Entity(0, 3, _bullet1),
          Entity(4, 1, _bullet),
        ]),
      );
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );

      controller.toggleList(EntityListKind.ordered);

      expect(
        controller.richText,
        RichText('a\nb\nc', const [
          Entity(
            0,
            3,
            EntityKind.list(listKind: EntityListKind.ordered, depth: 1),
          ),
          Entity(4, 1, _ordered),
        ]),
      );
    });

    test('at a caret on an empty line makes an empty item, and ends it', () {
      start();

      controller.toggleList(EntityListKind.ordered);
      expect(controller.isActive(_ordered), isTrue);
      expect(controller.listMarkers.single.label, '1.');

      controller.type('x');
      expect(
        controller.richText,
        RichText('x', const [Entity(0, 1, _ordered)]),
      );

      controller.restore(RichText.empty);
      controller.toggleList(EntityListKind.bullet);
      controller.toggleList(EntityListKind.bullet);
      expect(controller.isActive(_bullet), isFalse);
      expect(controller.listMarkers, isEmpty);
    });

    test('with lists off does nothing, and canApply says so', () {
      start(lists: false, text: const RichText.plain('a'));
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 1,
      );

      expect(controller.canApply(_bullet), isFalse);
      controller.toggleList(EntityListKind.bullet);

      expect(controller.richText, const RichText.plain('a'));
    });

    test('canApply follows isActive for lists on', () {
      start(text: const RichText.plain('a'));
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 1,
      );

      expect(controller.canApply(_bullet), isTrue);
      expect(controller.canApply(_ordered), isTrue);
    });
  });

  group('the empty item', () {
    test('ends when the caret leaves its line', () {
      start(text: RichText('a', const [Entity(0, 1, _bullet)]));
      controller.type('\n');
      expect(controller.listMarkers, hasLength(2));

      controller.selection = const TextSelection.collapsed(offset: 0);

      expect(controller.listMarkers, hasLength(1));
      expect(controller.isActive(_bullet), isTrue);
      controller.selection = const TextSelection.collapsed(offset: 2);
      expect(controller.isActive(_bullet), isFalse);
    });

    test('ends on a restore', () {
      start(text: RichText('a', const [Entity(0, 1, _bullet)]));
      controller.type('\n');

      controller.restore(const RichText.plain('x'));

      expect(controller.listMarkers, isEmpty);
    });

    test('becomes an item when a composition lands on it', () {
      start(text: RichText('a', const [Entity(0, 1, _bullet)]));
      controller.type('\n');

      controller.compose('a\nw', const TextRange(start: 2, end: 3));
      controller.compose('a\nwo', const TextRange(start: 2, end: 4));
      expect(controller.listMarkers, hasLength(2));
      controller.commitComposition('a\nwo');

      expect(
        controller.richText,
        RichText('a\nwo', const [Entity(0, 1, _bullet), Entity(2, 2, _bullet)]),
      );
    });
  });

  group('paste', () {
    test('two marker lines become items', () {
      start();

      final pasted = controller.withPastedLists(
        const RichText.plain('- a\n- b'),
      );

      expect(
        pasted,
        RichText('a\nb', const [Entity(0, 1, _bullet), Entity(2, 1, _bullet)]),
      );
    });

    test('a single marker line stays text', () {
      start();

      final pasted = controller.withPastedLists(const RichText.plain('- a'));

      expect(pasted, const RichText.plain('- a'));
    });

    test('nests by indentation and tells the kinds apart', () {
      start();

      final pasted = controller.withPastedLists(
        const RichText.plain('1. a\n    - b\n        - c\n2. d\ntext'),
      );

      expect(
        pasted,
        RichText('a\nb\nc\nd\ntext', const [
          Entity(0, 1, _ordered),
          Entity(2, 1, _bullet1),
          Entity(
            4,
            1,
            EntityKind.list(listKind: EntityListKind.bullet, depth: 2),
          ),
          Entity(6, 1, _ordered),
        ]),
      );
    });

    test('a first marker mid-line continues the line', () {
      start(text: const RichText.plain('x'));

      final pasted = controller.withPastedLists(
        const RichText.plain('- a\n- b\n- c'),
      );

      expect(
        pasted,
        RichText('- a\nb\nc', const [
          Entity(4, 1, _bullet),
          Entity(6, 1, _bullet),
        ]),
      );
    });

    test(
      'is left alone in a quote, in an item, with entities and with lists off',
      () {
        const marked = RichText.plain('- a\n- b');

        start(text: RichText('q', const [Entity(0, 1, EntityKind.quote)]));
        expect(controller.withPastedLists(marked), marked);

        controller.restore(RichText('q', const [Entity(0, 1, _bullet)]));
        expect(controller.withPastedLists(marked), marked);

        controller.restore(RichText.empty);
        final rich = RichText('- a\n- b', const [
          Entity(0, 3, EntityKind.bold),
        ]);
        expect(controller.withPastedLists(rich), rich);

        start(lists: false);
        expect(controller.withPastedLists(marked), marked);
      },
    );

    test('bulk text from the keyboard becomes items too', () {
      start();

      controller.type('- a\n- b');

      expect(
        controller.richText,
        RichText('a\nb', const [Entity(0, 1, _bullet), Entity(2, 1, _bullet)]),
      );
      expect(controller.selection.baseOffset, 3);
    });

    test('a single marker line from the keyboard is text', () {
      start();

      controller.type('- a');

      expect(controller.richText, const RichText.plain('- a'));
    });

    test('bulk text with lists off is text', () {
      start(lists: false);

      controller.type('- a\n- b');

      expect(controller.richText, const RichText.plain('- a\n- b'));
    });
  });

  group('numbering', () {
    test('deleting the middle of three numbered items renumbers the rest', () {
      start(
        text: RichText('a\nb\nc', const [
          Entity(0, 1, _ordered),
          Entity(2, 1, _ordered),
          Entity(4, 1, _ordered),
        ]),
      );
      expect(controller.listMarkers.map((marker) => marker.label), [
        '1.',
        '2.',
        '3.',
      ]);

      controller.replaceRange(2, 4, RichText.empty);

      expect(controller.text, 'a\nc');
      expect(controller.listMarkers.map((marker) => marker.label), [
        '1.',
        '2.',
      ]);
    });

    test('are the numbers the encoded markdown gets', () {
      final text = RichText('a\nb\nc\nd\ne\nf\ng\nh\ni', const [
        Entity(0, 1, _ordered),
        Entity(2, 1, _bullet1),
        Entity(
          4,
          1,
          EntityKind.list(listKind: EntityListKind.ordered, depth: 2),
        ),
        Entity(
          6,
          1,
          EntityKind.list(listKind: EntityListKind.ordered, depth: 2),
        ),
        Entity(8, 1, _ordered),
        Entity(12, 1, _ordered),
        Entity(14, 1, _ordered),
        Entity(16, 1, EntityKind.list(listKind: EntityListKind.bullet)),
      ]);
      start(text: text);

      final shown = controller.listMarkers
          .where((marker) => marker.kind == EntityListKind.ordered)
          .map((marker) => (marker.depth, marker.number))
          .toList();
      // Read back what the encoder wrote.
      final written = [
        for (final line in RichTextMarkdown.encode(text).split('\n'))
          if (RegExp(r'^( *)(\d+)\. ').firstMatch(line) case final match?)
            (match.group(1)!.length ~/ 2, int.parse(match.group(2)!)),
      ];

      expect(shown, written);
    });

    test('a bullet is drawn by depth', () {
      expect(const ListMarker(0, EntityListKind.bullet, 0, 0).label, '•');
      expect(const ListMarker(0, EntityListKind.bullet, 1, 0).label, '◦');
      expect(const ListMarker(0, EntityListKind.ordered, 0, 12).label, '12.');
    });
  });

  group('round trip', () {
    test('a decoded nested list, edited with Tab and Enter, encodes back', () {
      start(text: RichTextMarkdown.decode('- one\n- two'));

      // Caret at the end of "two": Tab, Enter, text.
      controller.indentListItems();
      controller
        ..type('\n')
        ..type('three');

      expect(markdown(), '- one\n  - two\n  - three');

      controller
        ..type('\n')
        ..type('\n')
        ..type('four');

      expect(markdown(), '- one\n  - two\n  - three\n- four');
    });

    test('an item with a soft break survives a restore', () {
      final text = RichTextMarkdown.decode('1. a  \nb\n2. c');
      start(text: text);

      expect(controller.richText, text);
      expect(markdown(), '1. a  \nb\n2. c');
    });
  });

  group('lists off', () {
    test('a list entity is kept, unedited, and nothing paints for it', () {
      start(lists: false, text: RichText('a', const [Entity(0, 1, _bullet)]));

      expect(controller.listMarkers, isEmpty);
      controller.type('b');
      expect(
        controller.richText,
        RichText('ab', const [Entity(0, 2, _bullet)]),
      );
    });

    test('typed markers are text', () {
      start(lists: false);

      controller
        ..type('-')
        ..type(' ')
        ..type('a');

      expect(controller.richText, const RichText.plain('- a'));
    });

    test('Tab, soft break and exit do nothing', () {
      start(
        lists: false,
        text: RichText('a', const [Entity(0, 1, _bullet)]),
        caret: 0,
      );

      expect(controller.canIndentListItems, isFalse);
      expect(controller.canInsertSoftBreak, isFalse);
      expect(controller.canOutdentOrExitListItem, isFalse);
    });
  });

  group('list editing helpers', () {
    test('a pending item compares by value', () {
      expect(
        const PendingListItem(1, EntityListKind.bullet, 0),
        const PendingListItem(1, EntityListKind.bullet, 0),
      );
    });
  });
}
