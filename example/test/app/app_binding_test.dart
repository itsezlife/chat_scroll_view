/// The app binding's messenger: the panel's search field, a stock
/// `EditableText` that asks for the text processing actions on every mount,
/// reaches the platform once however often it mounts.
///
/// **Seam:** the messenger [ComposerView.shareTextActions] makes over a
/// counting platform; the test binding's mock handler of the channel
/// forwards to it, as `AppBinding`'s messenger stands between the fields and
/// the platform.
library;

import 'dart:ui' as ui;

import 'package:chat_composer/chat_composer.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:panel_shell/panel_shell.dart';

void main() {
  testWidgets('the search field mounted again and again asks the platform '
      'for the text actions once', (tester) async {
    final platform = _Platform();
    final messenger = ComposerView.shareTextActions(platform);
    final channel = SystemChannels.processText.name;
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(
      channel,
      (message) => messenger.send(channel, message)!,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        channel,
        null,
      ),
    );
    final controller = PanelShellController(
      pages: [
        PanelPage(
          id: 'emoji',
          tab: const PanelTab(icon: ChromeIconId('emoji'), labelKey: 'emoji'),
          builder: (context, host) => const SizedBox(),
          capabilities: const PageCapabilities(search: true),
        ),
      ],
      preferences: FakePreferenceStore(),
    );
    addTearDown(controller.dispose);

    // A page switch builds the page, and its search field, anew.
    for (var i = 0; i < 6; i++) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: ChromeThemeScope(
              palette: ChromePalette.forBrightness(Brightness.light),
              child: ChromeStringsScope(
                strings: ChromeStringsPresets.english,
                child: PanelSearchField(
                  key: ValueKey(i),
                  controller: controller,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }
    expect(find.byType(EditableText), findsOneWidget);
    expect(platform.queries, 1);
  });
}

final class _Platform extends BinaryMessenger {
  int queries = 0;

  @override
  Future<ByteData?>? send(String channel, ByteData? message) async {
    final codec = SystemChannels.processText.codec;
    if (codec.decodeMethodCall(message).method ==
        'ProcessText.queryTextActions') {
      queries++;
    }
    return codec.encodeSuccessEnvelope(<String, String>{});
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) {}

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    ui.PlatformMessageResponseCallback? callback,
  ) async {}
}
