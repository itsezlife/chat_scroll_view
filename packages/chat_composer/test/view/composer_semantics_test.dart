import 'dart:ui' show Tristate;

import 'package:chat_composer/chat_composer.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:composer_editable/composer_editable.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/composer_harness.dart';

void main() {
  late ComposerController controller;

  setUp(() => controller = ComposerController());
  tearDown(() => controller.dispose());

  Future<void> show(
    WidgetTester tester,
    ComposerSpec spec, {
    ChromeStrings? strings,
  }) => tester.pumpWidget(
    composerHarness(
      ComposerView(controller: controller, spec: spec),
      strings: strings,
    ),
  );

  testWidgets('every visible action is a labelled button', (tester) async {
    final handle = tester.ensureSemantics();
    await show(
      tester,
      ComposerSpec(
        actions: [
          ActionDescriptor(
            id: 'emoji',
            icon: ChromeIconId.emoji,
            semanticLabel: 'Show emoji panel',
            placement: ActionPlacement.leading,
            onTap: () {},
          ),
          ActionDescriptor(
            id: 'send',
            icon: ChromeIconId.send,
            semanticLabel: 'Send',
            primary: true,
            onTap: () {},
          ),
        ],
      ),
    );

    expect(
      tester.getSemantics(find.bySemanticsLabel('Show emoji panel')),
      matchesSemantics(
        label: 'Show emoji panel',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        isFocusable: true,
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('Send')),
      matchesSemantics(
        label: 'Send',
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        isFocusable: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('a disabled action is announced as disabled', (tester) async {
    final handle = tester.ensureSemantics();
    await show(
      tester,
      ComposerSpec(
        actions: [
          ActionDescriptor(
            id: 'a',
            icon: ChromeIconId.attach,
            semanticLabel: 'Attach',
            enabled: false,
            onTap: () {},
          ),
        ],
      ),
    );

    final data = tester
        .getSemantics(find.bySemanticsLabel('Attach'))
        .getSemanticsData();
    expect(data.flagsCollection.isEnabled, Tristate.isFalse);
    handle.dispose();
  });

  testWidgets('the labels follow the language of the strings scope', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final russian = ChromeStringsPresets.russian;
    await show(
      tester,
      ComposerSpec(
        header: ComposerHeader.reply(
          name: 'Аня',
          preview: 'привет',
          onDismiss: () {},
        ),
      ),
      strings: russian,
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.bySemanticsLabel(russian.composer.dismissHeaderAction),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('${russian.composer.replyTo('Аня')}, привет'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('the header text is a live region and the dismiss a button', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await show(
      tester,
      ComposerSpec(
        header: ComposerHeader.edit(preview: 'old', onDismiss: () {}),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    final header = tester.getSemantics(
      find.bySemanticsLabel('Editing message, old'),
    );
    expect(header.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Cancel'))
          .getSemanticsData()
          .flagsCollection
          .isButton,
      isTrue,
    );
    handle.dispose();
  });

  testWidgets('the field is a text field labelled by the hint', (tester) async {
    final handle = tester.ensureSemantics();
    await show(tester, ComposerSpec());

    final data = tester
        .getSemantics(find.byType(ExtendedTextField))
        .getSemanticsData();
    expect(data.flagsCollection.isTextField, isTrue);
    expect(data.flagsCollection.isMultiline, isTrue);
    expect(data.label, 'Message');
    handle.dispose();
  });

  group('the list gutter', () {
    final items = RichText('Apple\nPear\nPlain', const [
      Entity(0, 5, EntityKind.list(listKind: EntityListKind.bullet)),
      Entity(6, 4, EntityKind.list(listKind: EntityListKind.ordered)),
    ]);
    final formatting = ChromeStringsPresets.english.formatting;

    Future<void> showList(WidgetTester tester, {bool lists = true}) async {
      final listed = ComposerController(
        text: ComposerTextController(initial: items, lists: lists),
      );
      addTearDown(listed.dispose);
      controller = listed;
      await show(tester, ComposerSpec());
    }

    // The markers are nodes of their own, which belong to no widget, so they
    // are found in the semantics tree rather than by a finder.
    Map<String, SemanticsNode> spoken(WidgetTester tester) {
      final found = <String, SemanticsNode>{};
      void visit(SemanticsNode node) {
        final label = node.getSemanticsData().label;
        if (label.isNotEmpty) found[label] = node;
        node.visitChildren((child) {
          visit(child);
          return true;
        });
      }

      visit(tester.binding.renderViews.first.debugSemantics!);
      return found;
    }

    testWidgets('speaks each marker from the strings', (tester) async {
      final handle = tester.ensureSemantics();
      await showList(tester);

      expect(
        spoken(tester).keys,
        containsAll([
          formatting.bulletListItem,
          formatting.numberedListItem(1),
        ]),
      );
      handle.dispose();
    });

    testWidgets('puts each label beside its own line, in the gutter', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await showList(tester);

      final nodes = spoken(tester);
      final bullet = nodes[formatting.bulletListItem]!;
      final numbered = nodes[formatting.numberedListItem(1)]!;
      expect(numbered.rect.top, greaterThan(bullet.rect.top));
      expect(numbered.rect.height, bullet.rect.height);
      expect(bullet.rect.width, greaterThan(0));
      handle.dispose();
    });

    testWidgets('follows the text: a removed item is not spoken', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await showList(tester);

      controller.restore(const RichText.plain('none'));
      await tester.pump();

      expect(spoken(tester).keys, isNot(contains(formatting.bulletListItem)));
      handle.dispose();
    });

    testWidgets('a text with lists off has no marker to speak', (tester) async {
      final handle = tester.ensureSemantics();
      await showList(tester, lists: false);

      expect(spoken(tester).keys, isNot(contains(formatting.bulletListItem)));
      handle.dispose();
    });
  });
}
