/// The attach caption's emoji panel: the chat's emoji page alone, typing
/// into the caption.
///
/// **Seam:** [CaptionEmojiPanel] over the app's test services under the
/// app's chrome, and [ChatAttach.buildCaptionPanel].
library;

import 'package:bulletins/bulletins.dart';
import 'package:chat_composer/chat_composer.dart';
import 'package:chat_scroll_view_example/src/app/app_chrome.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/caption_emoji_panel.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_attach.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/emoji_panel_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_shell/panel_shell.dart';

import '../../support/test_services.dart';

void main() {
  testWidgets("the caption's panel is the chat's emoji page, alone", (
    tester,
  ) async {
    final services = (await tester.runAsync(createTestServices))!;
    addTearDown(services.dispose);
    final caption = ComposerController();
    addTearDown(caption.dispose);
    final bulletins = BulletinController(
      policy: const BulletinPolicy.android(),
    );
    addTearDown(bulletins.dispose);
    final attach = ChatAttach(
      services: services,
      composer: ComposerController(),
      bulletins: bulletins,
      send: (_) async {},
    );
    late BuildContext home;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            AppChrome(services: services, child: child!),
        home: Builder(
          builder: (context) {
            home = context;
            return Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                height: 300,
                child: attach.buildCaptionPanel(context, caption),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(attach.buildCaptionPanel(home, caption), isA<CaptionEmojiPanel>());
    final shell = tester.widget<PanelShell>(find.byType(PanelShell));
    expect(shell.controller.pages.map((page) => page.id), [EmojiPanelPage.id]);
  });
}
