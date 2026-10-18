/// Edit from the real chat screen: the selection bar on a touch platform and
/// the message menu on a pointer platform.
///
/// **Seam:** the whole chat screen over a generated message source, driven by
/// real gestures (a touch long press, a mouse secondary click), observed
/// through the composer's focus and the platform's text input channel. In a
/// file of its own because it builds the full screen.
library;

import 'package:chat_composer/chat_composer.dart' show ComposerView;
import 'package:chat_scroll_view_example/main.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/generated_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_soft_keyboard.dart';
import '../support/test_services.dart';

Future<void> _frames(WidgetTester tester, [int count = 20]) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _openChat(WidgetTester tester) async {
  final services = (await tester.runAsync(createTestServices))!;
  addTearDown(services.dispose);
  final keyboard = FakeSoftKeyboard();
  addTearDown(keyboard.dispose);
  await tester.pumpWidget(
    ChatDemoApp(
      services: services,
      softKeyboard: keyboard,
      chatDataSourceLoader: () async =>
          GeneratedChatDataSource(messageCount: 200),
    ),
  );
  await _frames(tester);
}

ComposerView _composer(WidgetTester tester) =>
    tester.widget<ComposerView>(find.byType(ComposerView));

// The type the platform's text input was last attached with.
String? _attachedType(WidgetTester tester) {
  final attaches = tester.testTextInput.log.where(
    (call) => call.method == 'TextInput.setClient',
  );
  if (attaches.isEmpty) return null;
  final config =
      (attaches.last.arguments as List<Object?>)[1]! as Map<String, dynamic>;
  return '${(config['inputType']! as Map<String, dynamic>)['name']}';
}

void main() {
  testWidgets(
    'Edit on the selection bar brings the keyboard up with the caret at the '
    'end of the message',
    (tester) async {
      await _openChat(tester);
      expect(_attachedType(tester), 'TextInputType.none', reason: 'on open');

      // A long press selects the message and the selection bar replaces the
      // composer.
      await tester.longPress(
        find.byType(DemoMessageBubble).last,
        warnIfMissed: false,
      );
      await _frames(tester);
      expect(find.byType(ComposerView), findsNothing);

      await tester.tap(find.byTooltip('Изменить'));
      await _frames(tester, 30);

      final controller = _composer(tester).controller;
      expect(controller.hasFocus, isTrue);
      expect(controller.text.text, isNotEmpty);
      expect(
        controller.text.selection,
        TextSelection.collapsed(offset: controller.text.text.length),
      );
      expect(_attachedType(tester), startsWith('TextInputType.multiline'));
      expect(tester.testTextInput.isVisible, isTrue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'Edit on the message menu focuses the composer with the caret at the end',
    (tester) async {
      await _openChat(tester);
      final controller = _composer(tester).controller;
      controller.unfocus();
      await tester.pump();

      final bubble = find.byType(DemoMessageBubble).last;
      await tester.tap(
        bubble,
        buttons: kSecondaryButton,
        kind: PointerDeviceKind.mouse,
        warnIfMissed: false,
      );
      await _frames(tester);
      await tester.tap(find.text('Edit'));
      await _frames(tester, 30);

      expect(controller.hasFocus, isTrue);
      expect(controller.text.text, isNotEmpty);
      expect(
        controller.text.selection,
        TextSelection.collapsed(offset: controller.text.text.length),
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
