/// The save entry of a presented message menu: offered per platform over
/// the item pressed (or the album, on Android), one job per save, none once
/// protection turned on while the menu was up.
///
/// **Seam:** a presented [MessageMenu] whose save entry and save are a
/// [ChatMediaSaves] over a [FakeMediaSaver].
library;

import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/common/models/chat_message.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/demo_photos.dart';
import 'package:chat_scroll_view_example/src/features/chat/save/chat_media_saves.dart';
import 'package:chat_scroll_view_example/src/features/chat/save/chat_save_entries.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/message_menu.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';
import 'package:mpx_library/testing.dart';

final _photo = MediaItem(
  id: const MediaItemId('1.0'),
  descriptor: DemoPhotos.harbour.descriptor,
);
final _second = MediaItem(
  id: const MediaItemId('1.1'),
  descriptor: DemoPhotos.meadow.descriptor,
);

class _Source extends ChatDataSource {
  _Source() {
    upsertMessages(<IChatMessage>[
      UserChatMessage(
        id: 1,
        sender: 'User',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        content: '',
        media: [_photo, _second],
      ),
    ]);
  }

  @override
  Future<List<IChatMessage>> fetchRange({
    required int fromId,
    required int toId,
  }) async => const <IChatMessage>[];
}

ChatMessageMenuRequest _on(MediaItem? item) => ChatMessageMenuRequest(
  messageId: 1,
  slotGlobal: const Rect.fromLTWH(0, 100, 400, 200),
  tapGlobal: const Offset(140, 130),
  inlineHit: switch (item) {
    final item? => ChatInlineHit.bodyPart(
      messageId: 1,
      partId: MediaHitPart(item.id, part: MediaPart.content),
      role: ChatBodyPartRole.menu,
      rect: const Rect.fromLTWH(0, 100, 400, 200),
    ),
    null => null,
  },
);

void main() {
  late _Source source;
  late FakeMediaSaver saver;
  late ChatProtection protection;
  late ChatMediaSaves saves;
  late MessageMenu menu;

  setUp(() {
    RecordingDiagnostics.install();
    source = _Source();
    addTearDown(source.dispose);
    saver = FakeMediaSaver();
    protection = const ChatProtection();
  });

  // The saves and the menu on [platform], which the entries and the menu's
  // reach read.
  void build(TargetPlatform platform) {
    debugDefaultTargetPlatformOverride = platform;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    Set<MediaItemAction> allowedOf(int id, MediaItem item) =>
        MediaItemAction.allowedItemActions(
          item,
          protection: protection,
          messageProtected: false,
        );
    saves = ChatMediaSaves(
      saver: saver,
      chatId: 'chat-1',
      entries: ChatSaveEntries.current(),
      mediaOf: (id) => source.getMessage(id)?.media ?? const [],
      allowedOf: allowedOf,
      reportDenied: (_) {},
    );
    addTearDown(saves.dispose);
    menu = MessageMenu(
      dataSource: source,
      actions: MessageMenuActions(
        onDelete: (_) {},
        onEdit: (_) {},
        onMediaSave: (id, items, entry) => saves.save(
          id,
          items,
          entry,
          source: items.length > 1 ? ChatSaveSource.album : ChatSaveSource.menu,
        ),
      ),
      clipboard: FakeRichClipboard(),
      mediaOf: (id) => source.getMessage(id)?.media ?? const [],
      itemActionsOf: allowedOf,
      saveEntryOf: saves.entryFor,
    );
  }

  Future<void> open(WidgetTester tester, ChatMessageMenuRequest request) async {
    await tester.pumpWidget(
      ChromeThemeScope(
        palette: const ChromePalette.dark(),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => menu.present(context, request),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  for (final (platform, label) in [
    (TargetPlatform.android, 'Save to Gallery'),
    (TargetPlatform.iOS, 'Save Image'),
    (TargetPlatform.macOS, 'Save Image As…'),
  ]) {
    testWidgets('the menu on a photo offers "$label" on ${platform.name}, '
        'which saves it', (tester) async {
      build(platform);
      await open(tester, _on(_second));
      expect(find.text(label), findsOneWidget);

      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(saver.contentBatches.single.requests.single.key, isNotNull);
      expect(
        saver.contentBatches.single.requests.single.name,
        DemoPhotos.meadow.fileName,
      );
      // The input guard's window runs out.
      await tester.pump(ChatMediaSaves.guardWindow);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('a press beside an album on Android saves the album as one '
      'job', (tester) async {
    build(TargetPlatform.android);
    await open(tester, _on(null));
    await tester.tap(find.text('Save to Gallery'));
    await tester.pumpAndSettle();
    expect(saver.contentBatches.single.requests, hasLength(2));
    await tester.pump(ChatMediaSaves.guardWindow);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('protection turned on while the menu was up starts no job', (
    tester,
  ) async {
    build(TargetPlatform.android);
    await open(tester, _on(_photo));
    protection = const ChatProtection(save: false);
    await tester.tap(find.text('Save to Gallery'));
    await tester.pumpAndSettle();
    expect(saver.contentBatches, isEmpty);

    await open(tester, _on(_photo));
    expect(find.text('Save to Gallery'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
