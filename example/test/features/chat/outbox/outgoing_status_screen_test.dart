/// The demo chat's own messages as the app draws them: the status in the
/// time pill, the error badge of a failed message and the menu it opens,
/// Retry and Delete, the status semantics and announcements, each control
/// guarded against a burst.
library;

import 'package:chat_outbox/chat_outbox.dart';
import 'package:chat_outbox/testing.dart';
import 'package:chat_scroll_view_example/main.dart';
import 'package:chat_scroll_view_example/src/app/app_services.dart';
import 'package:chat_scroll_view_example/src/app/demo_chrome_strings.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/generated_chat_data_source.dart';
import 'package:chat_scroll_view_example/src/features/chat/input/chat_composer_spec.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_chat_server.dart';
import 'package:chat_scroll_view_example/src/features/chat/outbox/demo_delivery.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_error_badge.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/demo_message_meta.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/fake_soft_keyboard.dart';
import '../../../support/test_services.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const chat = 'chat';
  const history = 200;

  late FakeSoftKeyboard keyboard;
  late FakeOutboxTransfers transfers;
  late GeneratedChatDataSource source;

  setUp(() {
    keyboard = FakeSoftKeyboard();
    transfers = FakeOutboxTransfers();
    source = GeneratedChatDataSource(messageCount: history);
  });

  tearDown(() async {
    await keyboard.dispose();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<AppServices> pumpApp(WidgetTester tester) async {
    final services = (await tester.runAsync(
      () => createTestServices(outboxTransfers: transfers),
    ))!;
    addTearDown(services.dispose);
    await tester.pumpWidget(
      ChatDemoApp(
        services: services,
        softKeyboard: keyboard,
        chatDataSourceLoader: () async => source,
      ),
    );
    await settle(tester);
    return services;
  }

  Future<void> sendFromComposer(WidgetTester tester, String text) async {
    // The composer's field is a leaf package's type, which a host does not
    // name.
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == 'ComposerField',
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    tester.testTextInput.enterText(text);
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>(ChatComposerActions.primary)),
    );
    await settle(tester);
  }

  Finder bubbleOf(String text) => find.byWidgetPredicate(
    (widget) => switch (widget) {
      DemoMessageBubble(message: UserChatMessage(:final content)) =>
        content.contains(text),
      _ => false,
    },
  );

  Finder metaOf(String text) => find.descendant(
    of: bubbleOf(text),
    matching: find.byType(DemoMessageMeta),
  );

  Finder badgeOf(String text) => find.descendant(
    of: bubbleOf(text),
    matching: find.byType(DemoErrorBadge),
  );

  DemoDelivery? deliveryOf(WidgetTester tester, String text) =>
      tester.widget<DemoMessageMeta>(metaOf(text)).delivery;

  Future<void> sendFailed(WidgetTester tester, AppServices services) async {
    services.outbox.server.script(chat, DemoServerScript.reject);
    await sendFromComposer(tester, 'not this time');
  }

  testWidgets('the pill shows a clock while sending, one check once sent and '
      'the second only when the server says it was read', (tester) async {
    final semantics = tester.ensureSemantics();
    final services = await pumpApp(tester);
    final outbox = services.outbox.chat(chat);

    final message = outbox.sendText('on its way')!;
    await tester.pump();
    expect(deliveryOf(tester, 'on its way'), DemoDelivery.sending);
    expect(
      tester.getSemantics(metaOf('on its way')).label,
      contains(DemoOutgoingStrings.sending),
    );

    await settle(tester);
    expect(
      services.outbox.outbox
          .byClientMessageId(chat, message.clientMessageId)
          ?.status,
      const OutgoingStatus.sent(),
    );
    expect(deliveryOf(tester, 'on its way'), DemoDelivery.sent);
    expect(
      tester.getSemantics(metaOf('on its way')).label,
      contains(DemoOutgoingStrings.sent),
    );

    services.outbox.server.markRead(chat, history);
    await tester.pump();
    expect(deliveryOf(tester, 'on its way'), DemoDelivery.read);
    semantics.dispose();
  });

  testWidgets('a failed message shows the error badge beside its time, '
      'labelled not sent, with a retry action and hint', (tester) async {
    final semantics = tester.ensureSemantics();
    final services = await pumpApp(tester);

    await sendFailed(tester, services);

    expect(badgeOf('not this time'), findsOneWidget);
    expect(deliveryOf(tester, 'not this time'), DemoDelivery.notSent);
    expect(
      tester.getSemantics(metaOf('not this time')).label,
      contains(DemoOutgoingStrings.notSent),
    );
    final badge = tester.getSemantics(badgeOf('not this time'));
    expect(badge.hint, DemoOutgoingStrings.retryHint);
    const retry = CustomSemanticsAction(label: DemoOutgoingStrings.retry);
    expect(
      badge.getSemanticsData().customSemanticsActionIds,
      contains(CustomSemanticsAction.getIdentifier(retry)),
    );

    tester.binding.renderViews.first.owner!.semanticsOwner!.performAction(
      badge.id,
      SemanticsAction.customAction,
      CustomSemanticsAction.getIdentifier(retry),
    );
    await settle(tester);

    expect(transfers.retried, hasLength(1));
    semantics.dispose();
  });

  testWidgets('a tap on the badge opens the menu as a menu interaction, with '
      'Retry and Delete, reported once for a burst', (tester) async {
    final services = await pumpApp(tester);
    await sendFailed(tester, services);
    final diagnostics = RecordingDiagnostics.install();

    for (var i = 0; i < 5; i++) {
      await tester.tap(badgeOf('not this time'));
    }
    await settle(tester);

    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Reply'), findsNothing);
    expect(diagnostics.whereOp(DemoOutgoingOp.badgeMenuOpened), [
      isChatEvent(
        level: ChatEventLevel.debug,
        category: ChatEventCategory.outbox,
        correlation: ChatCorrelation(
          chatId: chat,
          clientMessageId: transfers.requests.last.idempotencyKey,
          scrollId: '$history',
        ),
        fields: {'pointer': 'touch'},
      ),
    ]);
    expectChromeText(tester, within: find.text('Retry'));
  });

  testWidgets('a burst of taps on Retry repeats the message once', (
    tester,
  ) async {
    final services = await pumpApp(tester);
    await sendFailed(tester, services);
    await tester.tap(badgeOf('not this time'));
    await settle(tester);

    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('Retry'), warnIfMissed: false);
    }
    await settle(tester);

    expect(transfers.retried, hasLength(1));
    expect(find.text('Retry'), findsNothing);
  });

  testWidgets('a burst of taps on Delete takes the message away once', (
    tester,
  ) async {
    final services = await pumpApp(tester);
    await sendFailed(tester, services);
    await tester.tap(badgeOf('not this time'));
    await settle(tester);

    for (var i = 0; i < 5; i++) {
      await tester.tap(find.text('Delete'), warnIfMissed: false);
    }
    await settle(tester);

    expect(transfers.cancelled, hasLength(1));
    expect(bubbleOf('not this time'), findsNothing);
  });

  testWidgets('on desktop a click on the badge opens the menu, Delete only', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final services = await pumpApp(tester);
    await sendFailed(tester, services);
    final diagnostics = RecordingDiagnostics.install();

    await tester.tap(badgeOf('not this time'), kind: PointerDeviceKind.mouse);
    await settle(tester);

    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(
      diagnostics.whereOp(DemoOutgoingOp.badgeMenuOpened).single.fields,
      containsPair('pointer', 'mouse'),
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a send announces its start and its end only', (tester) async {
    final services = await pumpApp(tester);
    tester.takeAnnouncements();

    services.outbox.chat(chat).sendText('announced');
    await settle(tester);

    expect(
      [
        for (final announcement in tester.takeAnnouncements())
          announcement.message,
      ],
      [DemoOutgoingStrings.sending, DemoOutgoingStrings.sent],
    );
  });
}
