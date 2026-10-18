/// The demo composer's formatting shortcuts: the default map of the platform,
/// answered by the same commands as the menu.
///
/// **Seam:** the chat's input set under the app's scopes (`InputRig`), driven
/// by key events on the focused field.
library;

import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:content_model/content_model.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/input_harness.dart';
import '../support/test_services.dart';

Future<AppServices> _services(WidgetTester tester) async {
  final services = (await tester.runAsync(createTestServices))!;
  addTearDown(services.dispose);
  return services;
}

void main() {
  group('the shortcuts', () {
    testWidgets('Ctrl+B bolds the selection, and again unbolds it', (
      tester,
    ) async {
      final rig = await InputRig.pump(
        tester,
        services: await _services(tester),
      );
      await rig.typeInField(tester, 'one two three');
      rig.set.composer.select(
        const TextSelection(baseOffset: 4, extentOffset: 7),
      );
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(
        rig.set.composer.richText,
        RichText('one two three', const [Entity(4, 3, EntityKind.bold)]),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();

      expect(rig.set.composer.richText, const RichText.plain('one two three'));
    });
  });
}
