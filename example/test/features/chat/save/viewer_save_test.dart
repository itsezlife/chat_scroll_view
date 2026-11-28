/// The media viewer's save: the entry of the shown item's kind and
/// platform, under the chat's protection read live, and one job per burst
/// of taps.
///
/// **Seam:** `ChatMediaSaves.forViewer` over a [FakeMediaSaver], a real
/// [ChatProtectionHost] (for the denied report) and a
/// [RecordingDiagnostics]; and the same saves behind the pushed
/// `ChatMediaViewer`, composed as the chat screen composes them, over a
/// `ContentAssetScope` with a `FakeAssetProducer`.
library;

import 'dart:async';

import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_capabilities/testing.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/features/chat/capabilities/chat_protection_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/data/demo_photos.dart';
import 'package:chat_scroll_view_example/src/features/chat/save/chat_media_saves.dart';
import 'package:chat_scroll_view_example/src/features/chat/save/chat_save_entries.dart';
import 'package:chat_scroll_view_example/src/features/chat/save/chat_save_wiring.dart';
import 'package:chat_scroll_view_example/src/features/chat/utils/chat_media_host.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:content_assets/content_assets.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen/listen.dart' as listen;
import 'package:message_media/message_media.dart';
import 'package:mpx_core/mpx_core.dart' show AssetCacheProvider;
import 'package:mpx_core/testing.dart' show FakeAssetProducer;
import 'package:mpx_library/testing.dart';

MediaItem _item(String id, MediaItemKind kind) => MediaItem(
  id: MediaItemId(id),
  kind: kind,
  descriptor: ContentDescriptor(
    key: ContentKey.document('doc-$id'),
    fileName: '$id.bin',
    mimeType: 'image/jpeg',
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final photo = _item('1.0', MediaItemKind.photo);
  final video = _item('1.1', MediaItemKind.video);

  late listen.ValueNotifier<ChatCapabilities> capabilities;
  late Set<int> protectedMessages;
  late RecordingCapabilityFeedback feedback;
  late RecordingDiagnostics diagnostics;
  late FakeMediaSaver saver;

  setUp(() {
    capabilities = listen.ValueNotifier(const ChatCapabilities());
    addTearDown(capabilities.dispose);
    protectedMessages = {};
    feedback = RecordingCapabilityFeedback();
    diagnostics = RecordingDiagnostics.install();
    saver = FakeMediaSaver();
  });

  ChatMediaSaves savesOn(ChatSaveEntries entries, {DateTime Function()? now}) {
    final selection = ChatSelectionController(chatId: 'chat-1');
    addTearDown(selection.dispose);
    final protection = ChatProtectionHost(
      chatId: 'chat-1',
      capabilities: capabilities,
      feedback: feedback,
      selection: selection,
      messageProtected: protectedMessages.contains,
      setSecure: ({required secure}) async => false,
    );
    addTearDown(protection.dispose);
    final saves = ChatMediaSaves(
      saver: saver,
      chatId: 'chat-1',
      entries: entries,
      mediaOf: (id) => id == 1 ? [photo, video] : const [],
      allowedOf: (id, item) => MediaItemAction.allowedItemActions(
        item,
        protection: capabilities.value.protection,
        messageProtected: protectedMessages.contains(id),
      ),
      reportDenied: (id) => protection.reportDenied(CapabilityAction.save, id),
      now: now,
    );
    addTearDown(saves.dispose);
    return saves;
  }

  void protectChat() => capabilities.value = capabilities.value.copyWith(
    protection: const ChatProtection(save: false),
  );

  group('entry', () {
    test('the shown item gets the entry of its kind and platform, offered '
        'once however often the chrome asks', () {
      final android = savesOn(ChatSaveEntries.android).forViewer(1);
      expect(android.entryOf(photo), ChatSaveEntries.android.photo);
      expect(android.entryOf(photo), ChatSaveEntries.android.photo);
      expect(android.entryOf(video), ChatSaveEntries.android.video);

      final desktop = savesOn(ChatSaveEntries.desktop).forViewer(1);
      expect(desktop.entryOf(photo), ChatSaveEntries.desktop.photo);
      expect(desktop.entryOf(photo)!.label, 'Save Image As…');

      final offered = diagnostics.whereOp(ChatSaveOp.entriesOffered);
      expect(offered, hasLength(3), reason: 'once per item and viewer');
      expect(
        offered.first,
        isChatEvent(
          level: ChatEventLevel.debug,
          category: ChatEventCategory.save,
          correlation: ChatCorrelation(
            chatId: 'chat-1',
            scrollId: '1',
            mediaItemId: photo.id.toString(),
          ),
          fields: {
            'kind': 'photo',
            'platform': 'android',
            'destination': 'gallery',
            'batch': 'single',
          },
        ),
      );
    });

    test('absent for a protected message', () {
      protectedMessages.add(1);
      final viewer = savesOn(ChatSaveEntries.android).forViewer(1);
      expect(viewer.entryOf(photo), isNull);
      expect(viewer.entryOf(photo), isNull);
      expect(
        diagnostics.whereOp(ChatSaveOp.entriesHidden).single,
        isChatEvent(
          level: ChatEventLevel.info,
          correlation: ChatCorrelation(
            chatId: 'chat-1',
            scrollId: '1',
            mediaItemId: photo.id.toString(),
          ),
          fields: {'why': 'protection', 'live': false},
        ),
      );
    });

    test('removed live when protection turns on while the viewer is open', () {
      final viewer = savesOn(ChatSaveEntries.android).forViewer(1);
      expect(viewer.entryOf(photo), isNotNull);
      protectChat();
      expect(viewer.entryOf(photo), isNull);
      expect(diagnostics.whereOp(ChatSaveOp.entriesHidden).single.fields, {
        'why': 'protection',
        'live': true,
      });
    });
  });

  group('save', () {
    test('a save is one saveContent job from the viewer', () {
      final viewer = savesOn(ChatSaveEntries.android).forViewer(1);
      final entry = viewer.entryOf(photo)!;
      final job = viewer.save(photo);
      expect(job, isNotNull);
      final batch = saver.contentBatches.single;
      expect(batch.destination, entry.destination);
      expect(batch.requests.single.key, photo.descriptor.key.mediaKey);
      expect(
        diagnostics.whereOp(ChatSaveOp.saveStarted).single.fields,
        containsPair('source', 'viewer'),
      );
    });

    test('a burst of taps on the save starts one job', () {
      fakeAsync((async) {
        final viewer = savesOn(
          ChatSaveEntries.android,
          now: async.getClock(DateTime(2026)).now,
        ).forViewer(1);
        for (var tap = 0; tap < 5; tap++) {
          viewer.save(photo);
          async.elapse(const Duration(milliseconds: 40));
        }
        expect(saver.contentBatches, hasLength(1));
        expect(diagnostics.whereOp(ChatSaveOp.saveDropped), hasLength(4));
      });
    });

    test('a save protection turned on for meanwhile is denied and '
        'reported', () {
      final viewer = savesOn(ChatSaveEntries.android).forViewer(1);
      expect(viewer.entryOf(photo), isNotNull);
      protectChat();
      expect(viewer.save(photo), isNull);
      expect(saver.contentBatches, isEmpty);
      expect(
        diagnostics.whereOp(ChatSaveOp.saveDenied).single,
        isChatEvent(
          level: ChatEventLevel.info,
          correlation: const ChatCorrelation(chatId: 'chat-1', scrollId: '1'),
          fields: {'path': 'viewer'},
        ),
      );
      expect(feedback.denials.single.action, CapabilityAction.save);
    });
  });

  group('viewer', () {
    final shown = MediaItem(
      id: const MediaItemId('1.0'),
      descriptor: DemoPhotos.harbour.descriptor,
    );
    final more = find.byKey(const ValueKey('mpx-viewer-more'));
    final label = ChatSaveEntries.android.photo.label;

    // Opens the viewer on [shown] as the chat screen does: the viewer's
    // saves, the save row from its entry, rebuilt when protection changes.
    Future<void> openViewer(WidgetTester tester, ChatMediaSaves saves) async {
      final scope = ContentAssetScope.withMedia(producer: FakeAssetProducer());
      addTearDown(scope.dispose);
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => ChromeThemeScope(
            palette: const ChromePalette.dark(),
            child: child!,
          ),
          home: AssetCacheProvider(
            scope: scope.media,
            child: Builder(
              builder: (c) {
                context = c;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      final viewerSaves = saves.forViewer(1);
      unawaited(
        ChatMediaViewer.open(
          context,
          MediaViewerRequest(
            messageId: 1,
            items: [shown.id],
            index: 0,
            originRect: const Rect.fromLTWH(10, 10, 100, 100),
            rectOf: (_) => null,
          ),
          [shown],
          changes: capabilities.select((c) => c.protection),
          details: ChatViewerDetails(
            title: 'Ada',
            actionsOf: (item) => ChatMediaViewer.actionsFor(
              item,
              allowed: const {},
              saveLabel: viewerSaves.entryOf(item)?.label,
              canForward: false,
              canDelete: false,
              onAction: (item, action) => viewerSaves.save(item),
            ),
          ),
        ),
      );
      // The open morph runs to its end.
      for (var frame = 0; frame < 30; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> tapSave(WidgetTester tester) async {
      await tester.tap(more);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.tap(find.text(label));
      await tester.pump(const Duration(milliseconds: 16));
    }

    testWidgets('a burst of taps on the viewer\'s save starts one job', (
      tester,
    ) async {
      await openViewer(tester, savesOn(ChatSaveEntries.android));
      for (var tap = 0; tap < 5; tap++) {
        await tapSave(tester);
      }
      expect(saver.contentBatches, hasLength(1));
      expect(
        saver.contentBatches.single.destination,
        ChatSaveEntries.android.photo.destination,
      );
      expect(diagnostics.whereOp(ChatSaveOp.saveDropped), hasLength(4));
      expect(
        diagnostics.whereOp(ChatSaveOp.saveStarted).single.fields,
        containsPair('source', 'viewer'),
      );

      // Past the guard, the next tap is a save of its own.
      await tester.pump(ChatMediaSaves.guardWindow);
      await tapSave(tester);
      expect(saver.contentBatches, hasLength(2));
      await tester.pump(ChatMediaSaves.guardWindow);
    });

    testWidgets('the save is absent for a protected message', (tester) async {
      protectedMessages.add(1);
      await openViewer(tester, savesOn(ChatSaveEntries.android));
      expect(more, findsNothing, reason: 'the menu has nothing left');
      expect(find.text(label), findsNothing);
    });

    testWidgets('the save leaves the open viewer when protection turns on', (
      tester,
    ) async {
      await openViewer(tester, savesOn(ChatSaveEntries.android));
      await tester.tap(more);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(label), findsOneWidget);

      protectChat();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(label), findsNothing);
      expect(diagnostics.whereOp(ChatSaveOp.entriesHidden).single.fields, {
        'why': 'protection',
        'live': true,
      });
      expect(saver.contentBatches, isEmpty);
    });
  });
}
