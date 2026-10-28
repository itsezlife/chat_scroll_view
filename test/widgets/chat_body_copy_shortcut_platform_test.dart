/// The copy key over a body's text selection follows the platform of the
/// moment, not the platform of the first body the process ever built.
///
/// **Seam:** a [ChatMarkdownBody] with a text selection, driven by real key
/// events; the platform clipboard channel is mocked and read back.
///
/// **Why it exists.** The key map was a top-level `final`, evaluated once: a
/// body built on one platform fixed Ctrl+C for the rest of the process, and
/// a later macOS test pressing Cmd+C copied nothing.
library;

import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_md/flutter_md.dart';
import 'package:flutter_test/flutter_test.dart';

import '../chat_message.dart';

class _LoadedSource extends ChatDataSource {
  _LoadedSource() {
    upsertMessages([
      UserChatMessage(
        id: 1,
        sender: 'User',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        content: 'x',
      ),
    ]);
    seedBoundaries(
      oldestKnownId: 1,
      newestKnownId: 1,
      reachedOldest: true,
      reachedNewest: true,
    );
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<String?> copyWith(
    WidgetTester tester,
    TargetPlatform platform,
    LogicalKeyboardKey modifier,
    String keyPlatform,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      String? copied;
      // A host writer: only the facade's own copy intent reaches it, the
      // markdown scope's default copy writes the platform clipboard instead.
      final selection = ChatSelectionController(
        policy: const ChatSelectionPolicy.desktop(),
        copyWriter: (copy) async => copied = copy.plainText,
      );
      addTearDown(selection.dispose);
      final source = _LoadedSource();
      addTearDown(source.dispose);
      final scroll = ChatScrollController();
      addTearDown(scroll.dispose);
      selection.putBody(1, Markdown.fromString('Hello world'));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatScrollView(
              dataSource: source,
              controller: scroll,
              selectionController: selection,
              messageBuilder: (context, id, message, status, run) =>
                  ChatMarkdownBody(controller: selection, messageId: id),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(selection.enterTextSelection(1), isTrue);
      // The scope's own focus, which a pointer press gives it on a device.
      final inner = find.descendant(
        of: find.byType(MarkdownSelectionScope).first,
        matching: find.byType(Focus),
      );
      tester.widget<Focus>(inner.first).focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyDownEvent(modifier, platform: keyPlatform);
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.keyC,
        platform: keyPlatform,
      );
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.keyC,
        platform: keyPlatform,
      );
      await tester.sendKeyUpEvent(modifier, platform: keyPlatform);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpWidget(const SizedBox());
      return copied;
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  testWidgets('Ctrl+C copies on Windows, then Cmd+C copies on macOS', (
    tester,
  ) async {
    expect(
      await copyWith(
        tester,
        TargetPlatform.windows,
        LogicalKeyboardKey.controlLeft,
        'windows',
      ),
      'Hello world',
    );
    expect(
      await copyWith(
        tester,
        TargetPlatform.macOS,
        LogicalKeyboardKey.metaLeft,
        'macos',
      ),
      'Hello world',
    );
  });
}
