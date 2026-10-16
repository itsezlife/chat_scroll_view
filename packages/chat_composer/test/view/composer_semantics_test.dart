import 'dart:ui' show Tristate;

import 'package:chat_composer/chat_composer.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:flutter/material.dart';
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

    final data = tester.getSemantics(find.byType(TextField)).getSemanticsData();
    expect(data.flagsCollection.isTextField, isTrue);
    expect(data.flagsCollection.isMultiline, isTrue);
    expect(data.label, 'Message');
    handle.dispose();
  });
}
