import 'package:chat_scroll_view_example/src/features/chat/outbox/fake_chat_server.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/material.dart';

/// The fake server's script switch (debug builds): arms one event for the
/// chat's next send, or has a peer post now, so each of the outbox's paths
/// can be seen in the chat.
class FakeServerScriptSheet extends StatelessWidget {
  /// The switch of [chatId] on [server].
  const FakeServerScriptSheet({
    required this.server,
    required this.chatId,
    super.key,
  });

  /// The server the chat sends to.
  final FakeChatServer server;

  /// The chat.
  final String chatId;

  /// Key of the chat chrome's button that opens the sheet.
  static const ValueKey<String> openKey = ValueKey('fake-server-scripts');

  /// Key of the button that has a peer post now.
  static const ValueKey<String> peerNowKey = ValueKey('fake-server-peer-now');

  /// Key of [script]'s button.
  static ValueKey<String> scriptKey(FakeServerScript script) =>
      ValueKey('fake-server-script-${script.name}');

  /// Shows the sheet over [context]'s navigator, under a chrome text root.
  static Future<void> show(
    BuildContext context, {
    required FakeChatServer server,
    required String chatId,
  }) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => ChromeTextRoot(
      child: FakeServerScriptSheet(server: server, chatId: chatId),
    ),
  );

  static String _labelOf(FakeServerScript script) => switch (script) {
    FakeServerScript.peer => 'A peer posts during the next upload',
    FakeServerScript.conflict => 'The next send conflicts',
    FakeServerScript.reject => 'The next send is rejected',
    FakeServerScript.deny => 'The next send is denied',
    FakeServerScript.reupload => 'The next send asks for its media again',
    FakeServerScript.replay => 'The next send lands at another id',
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = ChromeTypography.of(context).copyWith(color: colors.onSurface);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Fake server',
              style: text.copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 8),
            for (final script in FakeServerScript.values)
              TextButton(
                key: scriptKey(script),
                style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                onPressed: () {
                  server.script(chatId, script);
                  Navigator.of(context).pop();
                },
                child: Text(_labelOf(script), style: text),
              ),
            TextButton(
              key: peerNowKey,
              style: TextButton.styleFrom(alignment: Alignment.centerLeft),
              onPressed: () {
                server.postPeer(chatId);
                Navigator.of(context).pop();
              },
              child: Text('A peer posts now', style: text),
            ),
          ],
        ),
      ),
    );
  }
}
