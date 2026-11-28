import 'package:chat_scroll_view_example/src/features/chat/save/chat_save_wiring.dart';
import 'package:chat_scroll_view_example/src/features/chat/save/save_debug_actions.dart';
import 'package:chat_scroll_view_example/src/features/chat/save/save_debug_panel.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_library/mpx_library.dart';
import 'package:mpx_library/testing.dart';

void main() {
  late FakeMediaSaver saver;
  late SaveDebugActions actions;

  setUp(() {
    RecordingDiagnostics.install();
    saver = FakeMediaSaver();
    actions = SaveDebugActions(
      saver: saver,
      demoItem: () async => SaveItem.bytes(
        Uint8List(8),
        name: 'demo.jpg',
        mimeType: 'image/jpeg',
        kind: SaveItemKind.photo,
      ),
    );
  });

  tearDown(() => actions.dispose());

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      ChromeThemeScope(
        palette: const ChromePalette.dark(),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).push(SaveDebugPanel.route(actions: actions)),
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

  testWidgets('its text starts from the chrome typography', (tester) async {
    await open(tester);

    expectChromeText(tester, within: find.byType(SaveDebugPanel));
  });

  testWidgets('each destination\'s button saves the demo item there once, '
      'and shows the outcome', (tester) async {
    await open(tester);

    for (final destination in SaveDebugActions.destinations) {
      await tester.tap(find.byKey(SaveDebugPanel.saveKey(destination)));
      await tester.pumpAndSettle();
    }

    expect(
      saver.batches.map((batch) => batch.destination),
      SaveDebugActions.destinations,
    );
    expect(find.text('saved'), findsNWidgets(3));
  });

  testWidgets('a burst of taps on one button saves once', (tester) async {
    await open(tester);
    final button = find.byKey(SaveDebugPanel.saveKey(ChatSaveWiring.downloads));

    for (var tap = 0; tap < 5; tap++) {
      await tester.tap(button);
    }
    await tester.pumpAndSettle();

    expect(saver.batches, hasLength(1));
    await tester.pump(SaveDebugActions.guardWindow);
  });
}
