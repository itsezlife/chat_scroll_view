/// The attach button spammed opens one sheet.
///
/// **Seam:** [ChatAttach.open] over the app's test services under the app's
/// chrome.
library;

import 'package:attach_sheet/attach_sheet.dart';
import 'package:bulletins/bulletins.dart';
import 'package:chat_composer/chat_composer.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart'
    show ChatPreImeBackBinding;
import 'package:chat_scroll_view_example/src/app/app_chrome.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_attach.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_services.dart';

void main() {
  testWidgets('the attach button tapped again while its sheet opens or is '
      'open opens nothing more', (tester) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    const channel = MethodChannel('dev.mpx.device_signals');
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final services = (await tester.runAsync(createTestServices))!;
    addTearDown(services.dispose);
    final bulletins = BulletinController(
      policy: const BulletinPolicy.android(),
    );
    addTearDown(bulletins.dispose);
    final composer = ComposerController();
    addTearDown(composer.dispose);
    addTearDown(ChatPreImeBackBinding.debugReset);
    tester.view
      ..physicalSize = const Size(400, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late BuildContext home;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AppChrome(services: services, child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              home = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );
    final attach = ChatAttach(
      services: services,
      composer: composer,
      bulletins: bulletins,
      send: (_) async {},
    );
    final opens = [for (var i = 0; i < 4; i++) attach.open(home)];
    // The open's own async steps run in real time: wait for the sheet,
    // however long a loaded run takes, then let it settle.
    for (
      var i = 0;
      i < 100 && find.byType(AttachSheet).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(AttachSheet), findsOneWidget);
    attach.open(home).ignore();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(AttachSheet), findsOneWidget);

    await tester.binding.handlePopRoute();
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    for (final open in opens) {
      await open;
    }
  });
}
