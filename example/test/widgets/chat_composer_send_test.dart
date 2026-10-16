import 'dart:async';

import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_composer_spec.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/input_harness.dart';
import '../support/test_services.dart';

Future<AppServices> _services(WidgetTester tester) async {
  final services = (await tester.runAsync(createTestServices))!;
  addTearDown(services.dispose);
  return services;
}

Future<void> _type(WidgetTester tester, InputRig rig, String text) async {
  await tester.enterText(rig.field, text);
  await tester.pump();
}

Future<void> _pumpAsync(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('the composer sends', () {
    testWidgets('the trimmed text, and empties on success', (tester) async {
      final rig = await InputRig.pump(
        tester,
        services: await _services(tester),
      );

      await _type(tester, rig, '  hello world  ');
      await rig.tapAction(tester, ChatComposerActions.primary);
      await _pumpAsync(tester);

      expect(rig.sent, ['hello world']);
      expect(rig.set.composer.text.text, isEmpty);
    });

    testWidgets('nothing for a whitespace-only message', (tester) async {
      final rig = await InputRig.pump(
        tester,
        services: await _services(tester),
      );

      await _type(tester, rig, '   \n  ');
      await rig.tapAction(tester, ChatComposerActions.primary);
      await _pumpAsync(tester);

      expect(rig.sent, isEmpty);
    });

    testWidgets('and keeps the text when the send fails, so it can be tried '
        'again', (tester) async {
      final services = await _services(tester);
      Object? asyncError;
      var attempts = 0;
      await runZonedGuarded(() async {
        final rig = await InputRig.pump(
          tester,
          services: services,
          failSends: () => attempts++ == 0,
        );

        await _type(tester, rig, 'retry me');
        await rig.tapAction(tester, ChatComposerActions.primary);
        await _pumpAsync(tester);

        expect(rig.sent, isEmpty);
        expect(rig.set.composer.text.text, 'retry me');
        expect(rig.set.busy.value, isFalse);

        await rig.tapAction(tester, ChatComposerActions.primary);
        await _pumpAsync(tester);

        expect(rig.sent, ['retry me']);
        expect(rig.set.composer.text.text, isEmpty);
      }, (error, stack) => asyncError = error);

      expect(asyncError, isA<Exception>());
    });
  });

  group('the primary action', () {
    testWidgets('is the voice button while the composer is empty', (
      tester,
    ) async {
      final rig = await InputRig.pump(
        tester,
        services: await _services(tester),
      );

      expect(
        tester.getSemantics(rig.action(ChatComposerActions.primary)).label,
        'Записать голосовое сообщение',
      );

      await _type(tester, rig, 'a');

      expect(
        tester.getSemantics(rig.action(ChatComposerActions.primary)).label,
        'Отправить',
      );
    });
  });
}
