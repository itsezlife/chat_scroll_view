/// The demo's notes field, the one composer with lists on, beside the chat's,
/// which keeps them off.
///
/// **Seam:** the dialog over the app's scopes, and the chat's input set,
/// driven by typing into their fields.
library;

import 'dart:async';

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_scroll_view_example/src/app/app_chrome.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/notes_dialog.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter_test/flutter_test.dart';

import '../support/input_harness.dart';
import '../support/test_services.dart';

Future<AppServices> _services(WidgetTester tester) async {
  final services = (await tester.runAsync(createTestServices))!;
  addTearDown(services.dispose);
  return services;
}

Future<void> _type(WidgetTester tester, String text) async {
  tester.testTextInput.enterText(text);
  await tester.pump();
}

void main() {
  testWidgets('typing "- " makes a bullet item in the notes field', (
    tester,
  ) async {
    final services = await _services(tester);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AppChrome(services: services, child: child!),
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox.expand();
          },
        ),
      ),
    );
    unawaited(showNotesDialog(context, clipboard: services.clipboard));
    await tester.pumpAndSettle();
    final notes = tester.widget<ComposerView>(find.byType(ComposerView));
    notes.controller.requestFocus();
    await tester.pump();

    // One key at a time: the marker is a keystroke's shortcut, not a paste's.
    await _type(tester, '-');
    await _type(tester, '- ');
    await _type(tester, 'one');

    expect(notes.controller.richText.plain, 'one');
    expect(
      notes.controller.richText.entities.single.kind,
      isA<EntityKind$List>(),
    );
  });

  testWidgets('the chat composer keeps "- " as text', (tester) async {
    final rig = await InputRig.pump(tester, services: await _services(tester));

    await rig.typeInField(tester, '-');
    await rig.typeInField(tester, '- ');
    await rig.typeInField(tester, '- one');

    expect(rig.set.composer.richText, const RichText.plain('- one'));
  });
}
