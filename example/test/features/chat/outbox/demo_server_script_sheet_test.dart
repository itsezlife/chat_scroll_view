import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_chat_server.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_server_script_sheet.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const chat = 'c1';
  late DemoChatServer server;

  setUp(() => server = DemoChatServer()..open(chat, nextId: 0));
  tearDown(() => server.dispose());

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChromeThemeScope(
        palette: const ChromePalette.dark(),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => DemoServerScriptSheet.show(
                  context,
                  server: server,
                  chatId: chat,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('reads the chrome face', (tester) async {
    await open(tester);
    expectChromeText(tester, within: find.byType(DemoServerScriptSheet));
  });

  testWidgets("a script's button arms it for the chat's next send", (
    tester,
  ) async {
    await open(tester);

    await tester.tap(
      find.byKey(DemoServerScriptSheet.scriptKey(DemoServerScript.conflict)),
    );
    await tester.pumpAndSettle();

    expect(server.armedOf(chat), DemoServerScript.conflict);
    expect(find.byType(DemoServerScriptSheet), findsNothing);
  });

  testWidgets('a peer posts now', (tester) async {
    await open(tester);

    await tester.tap(find.byKey(DemoServerScriptSheet.peerNowKey));
    await tester.pumpAndSettle();

    expect(server.nextIdOf(chat), 1);
  });
}
