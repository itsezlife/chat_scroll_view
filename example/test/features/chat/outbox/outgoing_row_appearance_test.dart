/// A fresh outgoing row appears as its platform does: on Android at the
/// bottom the rows slide up by its height in 250 ms, off the bottom its
/// bubble fades and scales in after a delay by its place; on iOS a media
/// send with a send origin keeps the row still (its media flies), one
/// without as Android; desktop and reduce motion show it at once. The
/// outbox is asked once per row, and the row is entering while it moves.
///
/// **Seam:** `DemoMessageBubble` rows of a mounted `ChatScrollView` under a
/// `DemoRowAppearanceScope`, over a chat bound to a `DemoOutbox` (fake
/// transfers, the fake server); observed through rows' rects (their paint
/// transform), the bubble's opacity, `DemoRowEntering` and
/// `RecordingDiagnostics`.
library;

import 'package:attach_model/attach_model.dart';
import 'package:attach_model/testing.dart';
import 'package:chat_outbox/chat_outbox.dart';
import 'package:chat_outbox/testing.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/app/demo_chrome_strings.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/generated_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_delivery.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_outbox.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/fake_chat_server.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message_meta.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_row_appearance.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/message_row_frame.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_core/mpx_core.dart';

void main() {
  const chat = 'c1';
  const history = 30;
  const me = 'Hixie';

  late DemoOutbox demo;
  late GeneratedChatDataSource source;
  late DemoOutboxChat bound;
  late ChatScrollController controller;

  Future<void> pump(
    WidgetTester tester, {
    bool reduceMotion = false,
    OutgoingAppearancePolicy? appearance,
  }) async {
    final transfers = FakeOutboxTransfers();
    demo = DemoOutbox(
      transfers: transfers,
      server: FakeChatServer(peerDelay: Duration.zero),
      appearance: appearance,
    );
    addTearDown(demo.dispose);
    source = GeneratedChatDataSource(
      messageCount: history,
      senders: const ['Alice', 'Bob'],
    );
    bound = demo.chat(chat);
    controller = ChatScrollController()..jumpTo(history - 1);
    await tester.runAsync(
      () => bound.attach(source, atBottom: () => controller.isAtTail.value),
    );
    final selection = ChatSelectionController(chatId: chat);
    addTearDown(selection.dispose);
    addTearDown(controller.dispose);
    tester.view
      ..physicalSize = const Size(400, 700)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => ChromeThemeScope(
          palette: const ChromePalette.dark(),
          child: ChromeStringsScope(strings: demoChromeStrings, child: child!),
        ),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(400, 700),
            disableAnimations: reduceMotion,
          ),
          child: Scaffold(
            body: DemoRowAppearanceScope(
              atBottom: () => controller.isAtTail.value,
              child: ChatScrollView(
                dataSource: source,
                controller: controller,
                selectionController: selection,
                isSelfMessage: (message) => message.sender == me,
                messageBuilder: (context, id, message, status, runLayout) =>
                    switch (message) {
                      final message? => DemoMessageBubble(
                        message: message,
                        selection: selection,
                        outbox: bound,
                      ),
                      null => const SizedBox(height: 40),
                    },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Finder rowOf(int id) => find.byWidgetPredicate(
    (widget) => widget is DemoMessageBubble && widget.message.id == id,
  );

  // The row as drawn: the frame inside the row's slide.
  Rect rectOf(WidgetTester tester, int id) => tester.getRect(
    find.descendant(of: rowOf(id), matching: find.byType(MessageRowFrame)),
  );

  // A row outside any appearance is not entering.
  bool enteringOf(WidgetTester tester, int id) {
    final marks = find.descendant(
      of: rowOf(id),
      matching: find.byType(DemoRowEntering),
    );
    if (marks.evaluate().isEmpty) return false;
    return tester.widget<DemoRowEntering>(marks.first).entering;
  }

  double opacityOf(WidgetTester tester, int id) {
    // The bubble's own fade: the one around its scale.
    final fades = find.descendant(
      of: rowOf(id),
      matching: find.byWidgetPredicate(
        (widget) => widget is FadeTransition && widget.child is ScaleTransition,
      ),
    );
    if (fades.evaluate().isEmpty) return 1;
    return tester.widget<FadeTransition>(fades.first).opacity.value;
  }

  OutgoingMessage sendText() => bound.sendText('hello')!;

  // The fake server answers on a timer: let it before the test ends.
  Future<void> drain(WidgetTester tester) async {
    await tester.runAsync(pumpEventQueue);
    await tester.pump(const Duration(seconds: 1));
  }

  group('Android', () {
    testWidgets('at the bottom the rows slide up by the added height in '
        '250 ms', (tester) async {
      await pump(tester);
      const newest = history - 1;
      final before = rectOf(tester, newest);

      final message = sendText();
      await tester.pump();

      // The first frame keeps the rows where they were: no jump.
      final added = rectOf(tester, message.position).height;
      expect(rectOf(tester, newest).top, closeTo(before.top, 0.5));
      expect(enteringOf(tester, message.position), isTrue);

      await tester.pump(const Duration(milliseconds: 125));
      final midway = rectOf(tester, newest).top;
      expect(midway, lessThan(before.top - 1));
      expect(midway, greaterThan(before.top - added + 1));

      await tester.pump(const Duration(milliseconds: 126));
      expect(rectOf(tester, newest).top, closeTo(before.top - added, 0.5));
      await tester.pump();
      expect(enteringOf(tester, message.position), isFalse);

      await drain(tester);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets(
      'off the bottom the bubble fades in after its delay',
      (tester) async {
        await pump(tester);
        controller.jumpTo(5);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(controller.isAtTail.value, isFalse);

        final message = sendText();
        await tester.pump();
        // The self-insert follow brings the row in; wait for it to be built.
        for (
          var i = 0;
          i < 30 && rowOf(message.position).evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 16));
        }

        expect(opacityOf(tester, message.position), lessThan(1));
        expect(enteringOf(tester, message.position), isTrue);
        // The fade starts after the row is painted, then waits its delay.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(opacityOf(tester, message.position), 1);
        expect(enteringOf(tester, message.position), isFalse);
        await drain(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets(
      'the outbox is asked once per row, however often it rebuilds',
      (tester) async {
        await pump(tester);
        final diagnostics = RecordingDiagnostics.install();

        final message = sendText();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        // The send's statuses rebuild the bubble.
        await tester.runAsync(pumpEventQueue);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          diagnostics
              .whereOp(OutboxOp.freshOutgoingTaken)
              .where(
                (e) => e.correlation.clientMessageId == message.clientMessageId,
              ),
          hasLength(1),
        );
        expect(diagnostics.whereOp(OutboxOp.rowAppeared), [
          isChatEvent(
            fields: {
              'form': 'slideUp',
              'atBottom': true,
              'reduceMotion': false,
            },
          ),
        ]);
        await drain(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  });

  testWidgets('a send answered while its row slides in swaps the clock for '
      'the check without the cross-fade', (tester) async {
    await pump(tester);

    final message = sendText();
    await tester.pump();
    // The server answers within the slide.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(enteringOf(tester, message.position), isTrue);
    final meta = tester.widget<DemoMessageMeta>(
      find.descendant(
        of: rowOf(message.position),
        matching: find.byType(DemoMessageMeta),
      ),
    );
    expect(meta.delivery, DemoDelivery.sent);
    expect(meta.motion?.transition, isNull);
    await drain(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  group('iOS', () {
    testWidgets(
      'a media send with a send origin keeps the row still',
      (tester) async {
        await pump(tester);
        const newest = history - 1;
        final before = rectOf(tester, newest);

        final message = bound
            .sendPlanned(
              [
                PlannedSend.single(
                  AttachItems.photo('p1'),
                  form: SendForm.media,
                ),
              ],
              bodies: [''],
              prepared: {
                const AttachItemId('p1'): const PreparedMedia(
                  kind: PreparedKind.photo,
                  path: '/p1.jpg',
                  isOriginal: false,
                  byteSize: 10,
                ),
              },
              origins: [
                [const Rect.fromLTWH(10, 600, 80, 80)],
              ],
            )
            .single!;
        await tester.pump();

        // The rows jump at once: only the media flies.
        final added = rectOf(tester, message.position).height;
        expect(rectOf(tester, newest).top, closeTo(before.top - added, 0.5));
        expect(enteringOf(tester, message.position), isFalse);
        await drain(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );

    testWidgets(
      'a text send slides up as on Android',
      (tester) async {
        await pump(tester);
        const newest = history - 1;
        final before = rectOf(tester, newest);

        sendText();
        await tester.pump();

        expect(rectOf(tester, newest).top, closeTo(before.top, 0.5));
        await drain(tester);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  });

  testWidgets(
    'desktop shows the row at once',
    (tester) async {
      await pump(tester);
      const newest = history - 1;
      final before = rectOf(tester, newest);

      final message = sendText();
      await tester.pump();

      final added = rectOf(tester, message.position).height;
      expect(rectOf(tester, newest).top, closeTo(before.top - added, 0.5));
      expect(opacityOf(tester, message.position), 1);
      expect(enteringOf(tester, message.position), isFalse);
      await drain(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'reduce motion shows the row at once',
    (tester) async {
      await pump(tester, reduceMotion: true);
      const newest = history - 1;
      final before = rectOf(tester, newest);

      final message = sendText();
      await tester.pump();

      final added = rectOf(tester, message.position).height;
      expect(rectOf(tester, newest).top, closeTo(before.top - added, 0.5));
      expect(enteringOf(tester, message.position), isFalse);
      await drain(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'a row that is not fresh does not move',
    (tester) async {
      await pump(tester);
      const newest = history - 1;

      // Not the user's: the outbox is never asked.
      final diagnostics = RecordingDiagnostics.install();
      await tester.pump(const Duration(milliseconds: 100));

      expect(enteringOf(tester, newest), isFalse);
      expect(diagnostics.whereOp(OutboxOp.freshOutgoingTaken), isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}
