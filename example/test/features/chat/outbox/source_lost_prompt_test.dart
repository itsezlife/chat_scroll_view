import 'package:chat_scroll_view_example/src/app/demo_chrome_strings.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/source_lost_prompt.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_library/mpx_library.dart';
import 'package:mpx_library/testing.dart';
import 'package:mpx_transfer/mpx_transfer.dart';

void main() {
  late FakeFileIntake intake;
  Future<SourceBytes?>? asked;

  setUp(() => intake = FakeFileIntake());

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      ChromeThemeScope(
        palette: const ChromePalette.dark(),
        child: MaterialApp(
          home: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () =>
                    asked = SourceLostPrompt.ask(context, intake: intake),
                child: const Text('retry'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('retry'));
    await tester.pumpAndSettle();
  }

  testWidgets('says why, in the chrome face', (tester) async {
    await open(tester);

    expect(find.text(DemoTransferStrings.sourceLostTitle), findsOneWidget);
    expectChromeText(tester, within: find.byType(AlertDialog));
  });

  testWidgets('the picked file is the new source', (tester) async {
    intake.enqueuePick([
      const IntakeFile(
        source: IntakeSource.path('/photos/again.jpg'),
        name: 'again.jpg',
        size: 42,
      ),
    ]);
    await open(tester);

    await tester.tap(find.byKey(SourceLostPrompt.pickKey));
    await tester.pumpAndSettle();
    final source = await asked;

    expect(source?.size, 42);
    expect(intake.pickRequests.single.multiple, isFalse);
  });

  testWidgets('a cancel, of the prompt or of the file dialog, gives none', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.text(DemoTransferStrings.cancel));
    await tester.pumpAndSettle();
    expect(await asked, isNull);
    expect(intake.pickRequests, isEmpty);

    await tester.tap(find.text('retry'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SourceLostPrompt.pickKey));
    await tester.pumpAndSettle();
    expect(await asked, isNull);
  });
}
