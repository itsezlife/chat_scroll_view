import 'package:chat_scroll_view_example/src/features/chat/outbox/fake_chat_server.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/fake_server_script_sheet.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const chat = 'c1';
  late FakeChatServer server;

  setUp(() => server = FakeChatServer()..open(chat, nextId: 0));
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
                onPressed: () => FakeServerScriptSheet.show(
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
    expectChromeText(tester, within: find.byType(FakeServerScriptSheet));
  });

  testWidgets("a script's button arms it for the chat's next send", (
    tester,
  ) async {
    await open(tester);

    await tester.tap(
      find.byKey(FakeServerScriptSheet.scriptKey(FakeServerScript.conflict)),
    );
    await tester.pumpAndSettle();

    expect(server.armedOf(chat), FakeServerScript.conflict);
    expect(find.byType(FakeServerScriptSheet), findsNothing);
  });

  testWidgets('a peer posts now', (tester) async {
    await open(tester);

    await tester.tap(find.byKey(FakeServerScriptSheet.peerNowKey));
    await tester.pumpAndSettle();

    expect(server.nextIdOf(chat), 1);
  });
}
