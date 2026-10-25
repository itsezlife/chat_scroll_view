import 'package:chat_composer/src/menu/composer_formatting_option.dart';
import 'package:chat_composer/src/menu/composer_menu_policy.dart';
import 'package:chat_composer/src/menu/selection_menu_items.dart';
import 'package:chat_composer/src/text/composer_text_controller.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';

/// Which items the selection menu offers for which selection, in which order,
/// which of them can be chosen, and what each one does.
///
/// **Seam:** `SelectionMenuItems.of` over a `ComposerTextController`, read as
/// the list it returns.
void main() {
  final strings = ChromeStringsPresets.english.formatting;
  late ComposerTextController text;
  var linkAsked = 0;

  setUp(() {
    // The field's list editing is on, as in a composer built with lists: the
    // menu's list items follow the host's command (`toggleList`) and, below,
    // the controller's own switch.
    text = ComposerTextController(lists: true);
    linkAsked = 0;
  });
  tearDown(() => text.dispose());

  List<SelectionMenuItem> items({
    Set<ComposerFormattingOption> options = ComposerFormattingOption.standard,
    List<SelectionMenuClipboardItem> clipboard = const [],
    bool canLink = true,
    bool lists = false,
  }) => SelectionMenuItems.of(
    text: text,
    options: options,
    strings: strings,
    clipboard: clipboard,
    canLink: canLink,
    onLink: () => linkAsked++,
    toggleList: (kind) =>
        lists ? () => text.insert(RichText.plain('list:${kind.name}')) : null,
  );

  List<SelectionMenuItemKind> kinds({
    Set<ComposerFormattingOption> options = ComposerFormattingOption.standard,
    bool lists = false,
  }) => [for (final item in items(options: options, lists: lists)) item.kind];

  SelectionMenuItem item(
    SelectionMenuItemKind kind, {
    Set<ComposerFormattingOption> options = ComposerFormattingOption.standard,
    bool lists = false,
  }) => items(
    options: options,
    lists: lists,
  ).singleWhere((candidate) => candidate.kind == kind);

  void select(RichText rich, int from, int to) => text.restore(
    rich,
    selection: TextSelection(baseOffset: from, extentOffset: to),
  );

  const plain = RichText.plain('one two three');
  final link = RichText('see link', const [
    Entity(4, 4, EntityKind.link('https://a.b')),
  ]);

  group('over a plain selection', () {
    setUp(() => select(plain, 4, 7));

    test('the styles, then the line kinds, the link, and Regular', () {
      expect(kinds(), [
        SelectionMenuItemKind.bold,
        SelectionMenuItemKind.italic,
        SelectionMenuItemKind.underline,
        SelectionMenuItemKind.strikethrough,
        SelectionMenuItemKind.mono,
        SelectionMenuItemKind.spoiler,
        SelectionMenuItemKind.quote,
        SelectionMenuItemKind.codeBlock,
        SelectionMenuItemKind.createLink,
        SelectionMenuItemKind.clearFormatting,
      ]);
    });

    test('with lists on, Link comes before the lists', () {
      expect(
        kinds(options: ComposerFormattingOption.all, lists: true),
        containsAllInOrder([
          SelectionMenuItemKind.codeBlock,
          SelectionMenuItemKind.createLink,
          SelectionMenuItemKind.bulletList,
          SelectionMenuItemKind.numberedList,
          SelectionMenuItemKind.clearFormatting,
        ]),
      );
    });

    test('Regular is there but cannot be chosen: nothing to clear', () {
      expect(item(SelectionMenuItemKind.clearFormatting).enabled, isFalse);
    });

    test('hiding the unavailable leaves Regular out and keeps the rest', () {
      final hidden = SelectionMenuItems.of(
        text: text,
        options: ComposerFormattingOption.standard,
        strings: strings,
        clipboard: const [],
        onLink: () {},
        toggleList: (_) => null,
        unavailableActions: ComposerUnavailableActions.hide,
      );
      expect(
        [for (final item in hidden) item.kind],
        [
          for (final kind in kinds())
            if (kind != SelectionMenuItemKind.clearFormatting) kind,
        ],
      );
      expect(hidden.every((item) => item.enabled), isTrue);
    });

    test('every other formatting item can be chosen', () {
      for (final item in items().where(
        (item) =>
            !item.kind.isClipboard &&
            item.kind != SelectionMenuItemKind.clearFormatting,
      )) {
        expect(item.enabled, isTrue, reason: '${item.kind}');
      }
    });

    test('the labels are the host\'s strings', () {
      expect(item(SelectionMenuItemKind.bold).label, strings.boldAction);
      expect(
        item(SelectionMenuItemKind.createLink).label,
        strings.createLinkAction,
      );
      expect(
        item(SelectionMenuItemKind.codeBlock).label,
        strings.codeBlockAction,
      );
    });

    test(
      'Bold, Italic, Mono, Strikethrough and Underline show their own style',
      () {
        expect(
          item(SelectionMenuItemKind.italic).labelStyle,
          SelectionMenuLabelStyle.italic,
        );
        expect(
          item(SelectionMenuItemKind.mono).labelStyle,
          SelectionMenuLabelStyle.mono,
        );
        expect(
          item(SelectionMenuItemKind.strikethrough).labelStyle,
          SelectionMenuLabelStyle.strike,
        );
        expect(
          item(SelectionMenuItemKind.underline).labelStyle,
          SelectionMenuLabelStyle.underline,
        );
        expect(
          item(SelectionMenuItemKind.bold).labelStyle,
          SelectionMenuLabelStyle.bold,
        );
        expect(
          item(SelectionMenuItemKind.spoiler).labelStyle,
          SelectionMenuLabelStyle.plain,
        );
      },
    );

    test('a label shows its effect on the base style', () {
      const base = TextStyle(fontSize: 16);
      expect(
        SelectionMenuLabelStyle.bold.apply(base).fontWeight,
        FontWeight.bold,
      );
      expect(
        SelectionMenuLabelStyle.italic.apply(base).fontStyle,
        FontStyle.italic,
      );
      expect(
        SelectionMenuLabelStyle.underline.apply(base).decoration,
        TextDecoration.underline,
      );
      expect(
        SelectionMenuLabelStyle.strike.apply(base).decoration,
        TextDecoration.lineThrough,
      );
      expect(SelectionMenuLabelStyle.mono.apply(base).fontFamily, 'monospace');
      expect(SelectionMenuLabelStyle.plain.apply(base), base);
    });

    test('the Mono label is drawn in a real monospace face on iOS', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      expect(
        SelectionMenuLabelStyle.mono.apply(const TextStyle()).fontFamily,
        'Menlo',
      );
    });

    test('the Mono label over a packaged font is monospace', () {
      const base = TextStyle(fontFamily: 'Body', package: 'app_ui');
      expect(SelectionMenuLabelStyle.mono.apply(base).fontFamily, 'monospace');
    });

    test('no item is marked as applied', () {
      expect(items().where((item) => item.selected), isEmpty);
    });

    test('clipboard items come first, as given', () {
      final listed = items(
        clipboard: [
          SelectionMenuClipboardItem(
            kind: SelectionMenuItemKind.copy,
            label: 'Copy',
            onSelected: () {},
          ),
          SelectionMenuClipboardItem(
            kind: SelectionMenuItemKind.selectAll,
            label: 'Select all',
            onSelected: () {},
            after: SelectionMenuAfter.stay,
          ),
        ],
      );

      expect(listed.first.kind, SelectionMenuItemKind.copy);
      expect(listed[1].kind, SelectionMenuItemKind.selectAll);
      expect(listed[1].after, SelectionMenuAfter.stay);
      expect(listed[2].kind, SelectionMenuItemKind.bold);
    });
  });

  group('over other selections', () {
    test('a bold selection marks Bold as applied and offers Regular', () {
      select(
        RichText('bold word', const [Entity(0, 4, EntityKind.bold)]),
        0,
        4,
      );

      expect(item(SelectionMenuItemKind.bold).selected, isTrue);
      expect(item(SelectionMenuItemKind.italic).selected, isFalse);
      expect(kinds(), contains(SelectionMenuItemKind.clearFormatting));
    });

    test('a selection in code greys the styles code cannot hold', () {
      // Inside the code, not over all of it.
      select(
        RichText('some code', const [Entity(5, 4, EntityKind.code)]),
        6,
        8,
      );

      expect(item(SelectionMenuItemKind.mono).selected, isTrue);
      expect(item(SelectionMenuItemKind.mono).enabled, isTrue);
      for (final kind in [
        SelectionMenuItemKind.bold,
        SelectionMenuItemKind.italic,
        SelectionMenuItemKind.underline,
        SelectionMenuItemKind.strikethrough,
        SelectionMenuItemKind.spoiler,
        SelectionMenuItemKind.createLink,
      ]) {
        expect(kinds(), contains(kind), reason: '$kind is listed');
        expect(item(kind).enabled, isFalse, reason: '$kind is greyed');
      }
    });

    test('an already quoted selection leaves out Quote', () {
      select(RichText('quoted', const [Entity(0, 6, EntityKind.quote)]), 0, 6);

      expect(kinds(), isNot(contains(SelectionMenuItemKind.quote)));
      expect(item(SelectionMenuItemKind.clearFormatting).enabled, isTrue);
    });

    test('a selection in a code block marks Code block as applied', () {
      select(
        RichText('code', const [Entity(0, 4, EntityKind.codeBlock())]),
        0,
        4,
      );

      expect(item(SelectionMenuItemKind.codeBlock).selected, isTrue);
    });

    test('a collapsed caret lists the formatting; only the line kinds and '
        'Link can be chosen', () {
      text.restore(plain, selection: const TextSelection.collapsed(offset: 3));

      expect(kinds(), hasLength(10));
      final enabled = {
        for (final item in items().where((item) => item.enabled)) item.kind,
      };
      expect(enabled, {
        SelectionMenuItemKind.quote,
        SelectionMenuItemKind.codeBlock,
        SelectionMenuItemKind.createLink,
      });
    });

    test('a collapsed caret keeps the clipboard items first', () {
      text.restore(plain, selection: const TextSelection.collapsed(offset: 3));
      final listed = items(
        clipboard: [
          SelectionMenuClipboardItem(
            kind: SelectionMenuItemKind.paste,
            label: 'Paste',
            onSelected: () {},
          ),
        ],
      );

      expect(listed.first.kind, SelectionMenuItemKind.paste);
      expect(listed.first.enabled, isTrue);
    });

    test('with no selection at all there is only the clipboard', () {
      text.restore(plain);
      text.selection = const TextSelection.collapsed(offset: -1);

      expect(kinds(), isEmpty);
    });
  });

  group('links', () {
    test('offer Create over text with no link', () {
      select(plain, 4, 7);

      expect(kinds(), contains(SelectionMenuItemKind.createLink));
      expect(kinds(), isNot(contains(SelectionMenuItemKind.editLink)));
    });

    test(
      'are one Link row: Create, or Edit over a link, and Remove with it',
      () {
        select(link, 4, 8);

        expect(kinds(), contains(SelectionMenuItemKind.editLink));
        expect(kinds(), contains(SelectionMenuItemKind.removeLink));
        expect(kinds(), isNot(contains(SelectionMenuItemKind.createLink)));
        expect(
          item(SelectionMenuItemKind.editLink).label,
          strings.editLinkAction,
        );
        expect(
          item(SelectionMenuItemKind.removeLink).label,
          strings.removeLinkAction,
        );
      },
    );

    test('Create ask for the URL, and keeps the selection for it', () {
      select(plain, 4, 7);

      final create = item(SelectionMenuItemKind.createLink)..onSelected();

      expect(linkAsked, 1);
      expect(create.after, SelectionMenuAfter.dismissKeepingSelection);
    });

    test('Remove takes the link off and keeps the text', () {
      select(link, 4, 8);

      item(SelectionMenuItemKind.removeLink).onSelected();

      expect(text.richText, const RichText.plain('see link'));
    });

    test('are left out without a prompt', () {
      select(plain, 4, 7);

      expect([
        for (final item in items(canLink: false)) item.kind,
      ], isNot(contains(SelectionMenuItemKind.createLink)));
    });

    test('are greyed over a selection that cannot hold one', () {
      select(
        RichText('some code', const [Entity(5, 4, EntityKind.code)]),
        5,
        9,
      );

      expect(item(SelectionMenuItemKind.createLink).enabled, isFalse);
    });

    test('Remove is offered only while the selection touches a link', () {
      select(plain, 4, 7);
      expect(kinds(), isNot(contains(SelectionMenuItemKind.removeLink)));

      select(link, 4, 8);
      expect(item(SelectionMenuItemKind.removeLink).enabled, isTrue);
      expect(
        [for (final item in items()) item.kind].where(
          (kind) =>
              kind == SelectionMenuItemKind.createLink ||
              kind == SelectionMenuItemKind.editLink,
        ),
        [SelectionMenuItemKind.editLink],
      );
    });
  });

  group('options', () {
    setUp(() => select(plain, 4, 7));

    test('an empty set is a clipboard menu', () {
      expect(kinds(options: const {}), isEmpty);
    });

    test('only the options named are offered, in the menu\'s order', () {
      expect(
        kinds(
          options: const {
            ComposerFormattingOption.underline,
            ComposerFormattingOption.bold,
          },
        ),
        [SelectionMenuItemKind.bold, SelectionMenuItemKind.underline],
      );
    });

    test('the list items need both the option and lists being on', () {
      expect(
        kinds(options: ComposerFormattingOption.all),
        isNot(contains(SelectionMenuItemKind.bulletList)),
      );
      expect(
        kinds(options: ComposerFormattingOption.all, lists: true),
        containsAllInOrder([
          SelectionMenuItemKind.codeBlock,
          SelectionMenuItemKind.createLink,
          SelectionMenuItemKind.bulletList,
          SelectionMenuItemKind.numberedList,
        ]),
      );
      expect(
        kinds(lists: true),
        isNot(contains(SelectionMenuItemKind.bulletList)),
      );
    });

    test('a controller with list editing off offers no list item', () {
      text.dispose();
      text = ComposerTextController();
      select(plain, 4, 7);

      expect(
        kinds(options: ComposerFormattingOption.all, lists: true),
        isNot(contains(SelectionMenuItemKind.bulletList)),
      );
    });
  });

  group('each item calls its command', () {
    setUp(() => select(plain, 4, 7));

    test('the styles toggle over the selection', () {
      for (final (kind, entity) in [
        (SelectionMenuItemKind.bold, EntityKind.bold),
        (SelectionMenuItemKind.italic, EntityKind.italic),
        (SelectionMenuItemKind.underline, EntityKind.underline),
        (SelectionMenuItemKind.strikethrough, EntityKind.strike),
        (SelectionMenuItemKind.spoiler, EntityKind.spoiler),
        (SelectionMenuItemKind.mono, EntityKind.code),
      ]) {
        select(plain, 4, 7);

        item(kind).onSelected();

        expect(text.richText.entities, [Entity(4, 3, entity)], reason: '$kind');
      }
    });

    test('Quote quotes the line', () {
      item(SelectionMenuItemKind.quote).onSelected();

      expect(text.richText.entities, [const Entity(0, 13, EntityKind.quote)]);
    });

    test('Code block makes the line a block', () {
      item(SelectionMenuItemKind.codeBlock).onSelected();

      expect(text.richText.entities, [
        const Entity(0, 13, EntityKind.codeBlock()),
      ]);
    });

    test('Regular clears the formatting', () {
      select(
        RichText('bold word', const [Entity(0, 4, EntityKind.bold)]),
        0,
        4,
      );

      item(SelectionMenuItemKind.clearFormatting).onSelected();

      expect(text.richText, const RichText.plain('bold word'));
    });

    test('a bold item over bold text turns bold off', () {
      select(
        RichText('bold word', const [Entity(0, 4, EntityKind.bold)]),
        0,
        4,
      );

      item(SelectionMenuItemKind.bold).onSelected();

      expect(text.richText.entities, isEmpty);
    });

    test('the list items call the list command they are given', () {
      item(
        SelectionMenuItemKind.bulletList,
        options: ComposerFormattingOption.all,
        lists: true,
      ).onSelected();

      expect(text.richText.plain, contains('list:bullet'));
    });

    test('list items are marked with a bullet and a number', () {
      expect(SelectionMenuItemKind.bulletList.listMarker, '\u2022');
      expect(SelectionMenuItemKind.numberedList.listMarker, '1.');
      expect(SelectionMenuItemKind.bold.listMarker, isNull);
    });

    test('every formatting item dismisses to a caret', () {
      for (final item in items()) {
        if (item.kind == SelectionMenuItemKind.createLink) continue;
        expect(item.after, SelectionMenuAfter.dismiss, reason: '${item.kind}');
      }
    });
  });

  test('every item has a label', () {
    select(plain, 4, 7);
    for (final item in items(
      options: ComposerFormattingOption.all,
      lists: true,
    )) {
      expect(item.label, isNotEmpty, reason: '${item.kind}');
    }
  });
}
