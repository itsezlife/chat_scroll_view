/// The draft options overlay's keyboard intent, stated through the composer
/// controller: Android holds a raised keyboard and reopens it on close, the
/// remove row closes with `hide`, iOS keeps the keyboard.
///
/// **Seam:** `DraftOptionsController` given a `ComposerController`, opened
/// over a window whose keyboard is up or down, with a `ManualComposerClock`
/// for the reopen and release delays and `RecordingDiagnostics` installed.
library;

import 'package:chat_composer/chat_composer.dart';
import 'package:chat_composer/testing.dart';
import 'package:content_model/content_model.dart' hide RichText;
import 'package:content_model/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/composer_harness.dart';

final _url = Uri.parse('https://news.example/story?id=7');
final _initial = DraftLinkPart(options: LinkPreviewOptions(url: _url));

const _ms = Duration(milliseconds: 1);

void main() {
  late RecordingDiagnostics diagnostics;
  late ManualComposerClock clock;
  late ComposerController composer;
  late int requests;

  setUp(() {
    diagnostics = RecordingDiagnostics.install();
    clock = ManualComposerClock(DateTime(2026, 11, 28));
    composer = ComposerController();
    addTearDown(composer.dispose);
    requests = 0;
    composer.keyboardRequests.addListener(() => requests++);
  });

  ComposerKeyboardIntent intent() => composer.keyboardIntent.value;

  List<Map<String, Object?>> intentEvents() => [
    for (final event in diagnostics.whereOp(OverlayOp.keyboardIntent))
      event.fields,
  ];

  /// Opens a controller of [policy] over a window whose keyboard takes
  /// [keyboard] at the bottom.
  Future<DraftOptionsController> openOver(
    WidgetTester tester,
    DraftOptionsOverlayPolicy policy, {
    double keyboard = 300,
  }) async {
    final controller = DraftOptionsController(
      policy: policy,
      host: RecordingDraftOptionsHost(),
      bubbleBuilder: FakeDraftBubbleBuilder().call,
      composer: composer,
      clock: clock,
      correlation: () => const ChatCorrelation(chatId: 'chat-1'),
    );
    addTearDown(controller.dispose);
    late BuildContext opener;
    await tester.pumpWidget(
      composerHarness(
        Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(viewInsets: EdgeInsets.only(bottom: keyboard)),
            child: Builder(
              builder: (context) {
                opener = context;
                return const SizedBox(height: 40);
              },
            ),
          ),
        ),
      ),
    );
    expect(
      controller.open(opener, value: _initial, page: LinkPreviewState.pending),
      isTrue,
    );
    await tester.pumpAndSettle();
    return controller;
  }

  group('Android', () {
    testWidgets('holds a raised keyboard while the overlay is up; a keyboard '
        'request does nothing', (tester) async {
      await openOver(tester, const DraftOptionsPolicy$Android());

      expect(intent(), ComposerKeyboardIntent.hold);
      composer.requestKeyboard();
      expect(requests, 0);
      expect(intentEvents(), [
        {'intent': 'hold', 'keyboardWasUp': true, 'reopened': false},
      ]);
      expect(
        diagnostics.whereOp(OverlayOp.keyboardIntent).single,
        isChatEvent(
          level: ChatEventLevel.debug,
          category: ChatEventCategory.overlay,
          correlation: const ChatCorrelation(chatId: 'chat-1'),
        ),
      );
    });

    testWidgets('on close the keyboard reopens 50 ms later and the hold ends '
        '15 ms after the full close', (tester) async {
      final controller = await openOver(
        tester,
        const DraftOptionsPolicy$Android(),
      );

      controller.session!.close(DraftOptionsCloseTrigger.outside);
      await tester.pump();
      clock.advance(_ms * 49);
      expect(requests, 0);
      clock.advance(_ms);
      expect(requests, 1);
      expect(intent(), ComposerKeyboardIntent.hold);

      await tester.pumpAndSettle();
      expect(controller.isOpen, isFalse);
      clock.advance(_ms * 14);
      expect(intent(), ComposerKeyboardIntent.hold);
      clock.advance(_ms);
      expect(intent(), ComposerKeyboardIntent.keep);
      expect(intentEvents().last, {
        'intent': 'keep',
        'keyboardWasUp': true,
        'reopened': true,
      });
    });

    testWidgets('remove closes with hide: the hold ends without reopening', (
      tester,
    ) async {
      final controller = await openOver(
        tester,
        const DraftOptionsPolicy$Android(),
      );

      controller.session!.close(DraftOptionsCloseTrigger.remove);
      await tester.pumpAndSettle();
      clock.advance(const Duration(seconds: 1));

      expect(requests, 0);
      expect(intent(), ComposerKeyboardIntent.hide);
      expect(intentEvents().last, {
        'intent': 'hide',
        'keyboardWasUp': true,
        'reopened': false,
      });
    });

    testWidgets('keeps a keyboard that was down on open', (tester) async {
      final controller = await openOver(
        tester,
        const DraftOptionsPolicy$Android(),
        keyboard: 0,
      );

      expect(intent(), ComposerKeyboardIntent.keep);
      expect(intentEvents(), [
        {'intent': 'keep', 'keyboardWasUp': false, 'reopened': false},
      ]);

      controller.session!.close(DraftOptionsCloseTrigger.outside);
      await tester.pumpAndSettle();
      clock.advance(const Duration(seconds: 1));
      expect(requests, 0);
      expect(intentEvents(), hasLength(1));
    });

    testWidgets('disposing the controller ends the hold at once, without '
        'reopening', (tester) async {
      final controller = await openOver(
        tester,
        const DraftOptionsPolicy$Android(),
      );

      controller.dispose();
      await tester.pumpAndSettle();
      clock.advance(const Duration(seconds: 1));

      expect(intent(), ComposerKeyboardIntent.hide);
      expect(requests, 0);
    });

    testWidgets('disposing while a hold waits for its release ends it at '
        'once', (tester) async {
      final controller = await openOver(
        tester,
        const DraftOptionsPolicy$Android(),
      );
      controller.session!.close(DraftOptionsCloseTrigger.outside);
      await tester.pumpAndSettle();
      expect(intent(), ComposerKeyboardIntent.hold);

      controller.dispose();

      expect(intent(), ComposerKeyboardIntent.keep);
      expect(clock.pendingCount, 0);
    });
  });

  testWidgets('iOS keeps the keyboard: the overlay draws above it', (
    tester,
  ) async {
    final controller = await openOver(tester, const DraftOptionsPolicy$IOS());

    expect(intent(), ComposerKeyboardIntent.keep);
    expect(intentEvents(), [
      {'intent': 'keep', 'keyboardWasUp': true, 'reopened': false},
    ]);

    controller.session!.close(DraftOptionsCloseTrigger.outside);
    await tester.pumpAndSettle();
    clock.advance(const Duration(seconds: 1));
    expect(requests, 0);
    expect(intent(), ComposerKeyboardIntent.keep);
  });

  testWidgets('without a composer the overlay states nothing', (tester) async {
    final controller = DraftOptionsController(
      policy: const DraftOptionsPolicy$Android(),
      host: RecordingDraftOptionsHost(),
      bubbleBuilder: FakeDraftBubbleBuilder().call,
      clock: clock,
    );
    addTearDown(controller.dispose);
    late BuildContext opener;
    await tester.pumpWidget(
      composerHarness(
        Builder(
          builder: (context) {
            opener = context;
            return const SizedBox(height: 40);
          },
        ),
      ),
    );
    controller.open(opener, value: _initial, page: LinkPreviewState.pending);
    await tester.pumpAndSettle();

    expect(diagnostics.whereOp(OverlayOp.keyboardIntent), isEmpty);
  });
}
