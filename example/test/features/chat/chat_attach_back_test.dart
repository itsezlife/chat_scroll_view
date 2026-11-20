/// Back with the attach sheet over the panel: the topmost surface takes it.
///
/// **Seam:** [ChatAttach.open] over the app's test services under the app's
/// chrome, with a claim standing in for the panel's under it; back is the
/// native pre-IME back ([ChatPreImeBackBinding.handleNativeBack]).
library;

import 'package:attach_sheet/attach_sheet.dart';
import 'package:bulletins/bulletins.dart';
import 'package:chat_composer/chat_composer.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart'
    show ChatPreImeBackBinding, ChatPreImeBackClaim;
import 'package:chat_scroll_view_example/src/app/app_chrome.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_attach.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_services.dart';

const _deviceChannels = ['dev.mpx.device_signals'];

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('back takes the keyboard down, then closes the attach sheet, '
      'then the panel under it', (tester) async {
    // The device's plugins answer nothing here: the gallery shows its
    // no-access state.
    final messenger = tester.binding.defaultBinaryMessenger;
    for (final name in _deviceChannels) {
      final channel = MethodChannel(name);
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    }
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
    final field = FocusNode();
    addTearDown(field.dispose);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AppChrome(services: services, child: child!),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              home = context;
              return Focus(focusNode: field, child: const SizedBox.expand());
            },
          ),
        ),
      ),
    );
    // The panel is open: its claim is under the sheet's.
    var panelOpen = true;
    final panel = ChatPreImeBackClaim.push(() async {
      panelOpen = false;
      return true;
    });
    addTearDown(panel.pop);

    final attach = ChatAttach(
      services: services,
      composer: composer,
      bulletins: bulletins,
      send: (_) async {},
    );
    final opened = attach.open(home);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await _settle(tester);
    expect(find.byType(AttachSheet), findsOneWidget);

    // A field focused with the keyboard up: the first back takes the
    // keyboard down and leaves the sheet.
    field.requestFocus();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    expect(field.hasFocus, isTrue);
    expect(await ChatPreImeBackBinding.handleNativeBack(), isTrue);
    await _settle(tester);
    expect(field.hasFocus, isFalse);
    expect(find.byType(AttachSheet), findsOneWidget);
    expect(panelOpen, isTrue);
    tester.view.resetViewInsets();
    await tester.pump();

    expect(await ChatPreImeBackBinding.handleNativeBack(), isTrue);
    await _settle(tester);
    expect(find.byType(AttachSheet), findsNothing);
    expect(panelOpen, isTrue);
    await opened;

    expect(await ChatPreImeBackBinding.handleNativeBack(), isTrue);
    expect(panelOpen, isFalse);
  });
}
