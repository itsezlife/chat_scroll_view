/// Protection turns on live: the copy hook, the rows it takes away, the
/// selection on each platform, the capture block, and the denied copy.
///
/// **Seam:** [ChatProtectionHost] over a capabilities listenable, a real
/// [ChatSelectionController] and a [RecordingCapabilityFeedback]; the menus
/// through [MessageMenuCatalog] and a presented [MessageMenu].
library;

import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_capabilities/testing.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/capabilities/chat_protection_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/message_menu.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen/listen.dart' as listen;

class _Source extends ChatDataSource {
  _Source() {
    upsertMessages(<IChatMessage>[
      for (final id in [1, 2, 3])
        UserChatMessage(
          id: id,
          sender: 'User',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          content: 'message $id',
          isProtected: id == 3,
        ),
    ]);
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

List<String> _actionIds(List<ChatMessageMenuItem> items) => [
  for (final item in items)
    if (item case ChatMessageMenuAction(:final id)) id,
];

const _request = ChatMessageMenuRequest(
  messageId: 1,
  slotGlobal: Rect.fromLTWH(0, 100, 400, 80),
  tapGlobal: Offset(140, 130),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late listen.ValueNotifier<ChatCapabilities> capabilities;
  late RecordingCapabilityFeedback feedback;
  late RecordingDiagnostics diagnostics;
  late _Source source;
  late List<bool> secureCalls;

  setUp(() {
    capabilities = listen.ValueNotifier(const ChatCapabilities());
    addTearDown(capabilities.dispose);
    feedback = RecordingCapabilityFeedback();
    diagnostics = RecordingDiagnostics.install();
    source = _Source();
    addTearDown(source.dispose);
    secureCalls = [];
  });

  (ChatProtectionHost, ChatSelectionController) protect({
    ChatSelectionPolicy policy = const ChatSelectionPolicy.mobile(),
    bool applies = true,
  }) {
    late final ChatProtectionHost host;
    final selection = ChatSelectionController(
      policy: policy,
      chatId: 'chat-1',
      onInteraction: (interaction) {
        if (interaction case final ChatCopyRefused refused) {
          host.reportRefused(refused);
        }
      },
    );
    host = ChatProtectionHost(
      chatId: 'chat-1',
      capabilities: capabilities,
      feedback: feedback,
      selection: selection,
      messageProtected: (id) => source.getMessage(id)?.isProtected ?? false,
      setSecure: ({required secure}) async {
        secureCalls.add(secure);
        return applies;
      },
    );
    addTearDown(selection.dispose);
    addTearDown(host.dispose);
    return (host, selection);
  }

  void protectChat({bool copy = false, bool forward = false}) =>
      capabilities.value = capabilities.value.copyWith(
        protection: ChatProtection(copy: !copy, forward: !forward),
      );

  test('a message protected by its own flag denies copy, forward and save', () {
    final (host, selection) = protect();

    expect(host.canCopy(1), isTrue);
    expect(host.canCopy(3), isFalse);
    expect(selection.isCopyAllowed(3), isFalse);
    expect(host.deniedMenuActions([1]), isEmpty);
    expect(host.deniedMenuActions([1, 3]), {
      MessageMenuActionId.copy,
      MessageMenuActionId.copySelected,
      MessageMenuActionId.copyLink,
      MessageMenuActionId.copyCode,
      MessageMenuActionId.forward,
      MessageMenuActionId.saveGif,
    });
  });

  group('the menus', () {
    // Each platform with the selection policy it runs.
    for (final (platform, policy) in const [
      (TargetPlatform.android, ChatSelectionPolicy.mobile()),
      (TargetPlatform.iOS, ChatSelectionPolicy.mobile()),
      (TargetPlatform.macOS, ChatSelectionPolicy.desktop()),
    ]) {
      test('lose Copy and Forward on $platform', () {
        final (host, _) = protect(policy: policy);
        List<String> rows(Iterable<int> ids) => _actionIds(
          MessageMenuCatalog.excluding(
            MessageMenuCatalog.itemsFor(
              _request,
              policy,
              platform: platform,
              content: const MessageMenuContent.gif(
                key: ContentKey.document('7'),
              ),
            ),
            host.deniedMenuActions(ids),
          ),
        );

        final open = rows([1]);
        expect(open, containsAll(['copy', 'forward', 'save_gif']));

        protectChat(copy: true, forward: true);
        final protected = rows([1]);
        expect(protected, isNot(contains('copy')));
        expect(protected, isNot(contains('forward')));
        // Save is the chat's save right, still on.
        expect(protected, contains('save_gif'));
        expect(protected, contains('reply'));

        // A message protected on its own takes Save away as well.
        expect(rows([3]), isNot(contains('save_gif')));
      });
    }

    testWidgets('a presented menu of a protected message has no Copy', (
      tester,
    ) async {
      final (host, selection) = protect();
      final menu = MessageMenu(
        dataSource: source,
        selection: selection,
        actions: MessageMenuActions(onDelete: (_) {}, onEdit: (_) {}),
        clipboard: FakeRichClipboard(),
        deniedActionsOf: host.deniedMenuActions,
      );
      await tester.pumpWidget(
        ChromeThemeScope(
          palette: const ChromePalette.dark(),
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => menu.present(
                    context,
                    const ChatMessageMenuRequest(
                      messageId: 3,
                      slotGlobal: Rect.fromLTWH(0, 100, 400, 80),
                      tapGlobal: Offset(140, 130),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Copy'), findsNothing);
      expect(find.text('Forward'), findsNothing);
    });
  });

  group('Copy on a protected message', () {
    setUp(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (_) async => null),
    );
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );

    test('is refused with one onDenied(copy)', () async {
      final (_, selection) = protect();
      protectChat(copy: true);
      selection
        ..putBody(1, Markdown.fromString('message 1'))
        ..startSelection(1)
        ..enterTextSelection(1);

      expect(await selection.copyTextSelection(), isFalse);

      expect(feedback.denials, [
        (action: CapabilityAction.copy, reason: const DenialReason.everyone()),
      ]);
      final denied = diagnostics.whereOp(CapabilitiesOp.denied).single;
      expect(denied.fields['consumer'], CapabilityConsumer.selection);
      expect(denied.correlation.scrollId, '1');
      expect(diagnostics.whereOp(ChatSelectionOp.copyRefused), hasLength(1));
    });

    test('of its own is denied as protected content', () {
      final (_, selection) = protect();
      selection.startSelection(3);

      expect(selection.refusesCopy(selection.selectedIds), isTrue);

      expect(
        feedback.denials.single.reason,
        const DenialReason.other(ChatProtectionHost.protectedMessageTag),
      );
    });
  });

  group('turning protection on, live', () {
    test('keeps a mobile selection, its entries gone', () {
      final (host, selection) = protect();
      selection.startSelection(1);
      var notified = 0;
      selection.addListener(() => notified++);

      protectChat(copy: true);

      expect(selection.selectedIds, {1});
      expect(notified, greaterThan(0));
      expect(host.canCopy(1), isFalse);
      final event = diagnostics
          .whereOp(ChatProtectionOp.protectionApplied)
          .single;
      expect(event.fields, {
        'scope': 'chat',
        'bits': ProtectionFlags.copy.bits,
        'selection': 'kept',
      });
      expect(event.correlation.chatId, 'chat-1');
    });

    test('clears a desktop selection holding a protected message', () {
      final (_, selection) = protect(
        policy: const ChatSelectionPolicy.desktop(),
      );
      selection.startSelection(1);

      protectChat(forward: true);

      expect(selection.isSelectionMode, isFalse);
      expect(
        diagnostics
            .whereOp(ChatProtectionOp.protectionApplied)
            .single
            .fields['selection'],
        'cleared',
      );
    });

    test('leaves a selection that holds no protected message', () {
      final (host, selection) = protect(
        policy: const ChatSelectionPolicy.desktop(),
      );
      selection.startSelection(1);

      host.messageProtectionChanged(2);

      expect(selection.selectedIds, {1});
      final event = diagnostics
          .whereOp(ChatProtectionOp.protectionApplied)
          .single;
      expect(event.fields['scope'], 'message');
      expect(event.fields['selection'], 'none');
      expect(event.correlation.scrollId, '2');
    });
  });

  group('capture blocking', () {
    test('sets the secure flag on and off, reporting each', () async {
      protect();

      capabilities.value = capabilities.value.copyWith(
        protection: const ChatProtection(captureBlocked: true),
      );
      await pumpEventQueue();
      capabilities.value = const ChatCapabilities();
      await pumpEventQueue();

      expect(secureCalls, [true, false]);
      expect(
        diagnostics
            .whereOp(ChatProtectionOp.captureBlocked)
            .map((e) => e.fields),
        [
          {'on': true, 'applied': true},
          {'on': false, 'applied': true},
        ],
      );
      // Capture alone is no protection of what leaves the chat.
      expect(diagnostics.whereOp(ChatProtectionOp.protectionApplied), isEmpty);
    });

    test('reports a platform without a flag as not applied', () async {
      capabilities.value = const ChatCapabilities(
        protection: ChatProtection(captureBlocked: true),
      );
      protect(applies: false);
      await pumpEventQueue();

      expect(
        diagnostics.whereOp(ChatProtectionOp.captureBlocked).single.fields,
        {'on': true, 'applied': false},
      );
    });

    test('is lifted when the chat goes', () async {
      capabilities.value = const ChatCapabilities(
        protection: ChatProtection(captureBlocked: true),
      );
      final (host, _) = protect();
      host.dispose();
      await pumpEventQueue();

      expect(secureCalls, [true, false]);
    });
  });
}
