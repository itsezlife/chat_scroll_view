/// The chat's save entries and saves: which entry a menu, an album or a
/// selection offers under the chat's protection, and the one job a tap on
/// it starts.
///
/// **Seam:** [ChatMediaSaves] over a [FakeMediaSaver], a real
/// [ChatProtectionHost] (for the denied report) and a
/// [RecordingDiagnostics].
library;

import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_capabilities/testing.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/features/chat/capabilities/chat_protection_host.dart';
import 'package:chat_scroll_view_example/src/features/chat/save/chat_media_saves.dart';
import 'package:chat_scroll_view_example/src/features/chat/save/chat_save_entries.dart';
import 'package:chat_scroll_view_example/src/features/chat/save/chat_save_wiring.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:listen/listen.dart' as listen;
import 'package:message_media/message_media.dart';
import 'package:mpx_core/mpx_core.dart' show MediaKey;
import 'package:mpx_library/mpx_library.dart';
import 'package:mpx_library/testing.dart';

MediaItem _item(
  String id,
  MediaItemKind kind, {
  String? fileName,
  String? mimeType,
}) => MediaItem(
  id: MediaItemId(id),
  kind: kind,
  descriptor: ContentDescriptor(
    key: ContentKey.document('doc-$id'),
    fileName: fileName,
    mimeType: mimeType,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final photo = _item(
    '1.0',
    MediaItemKind.photo,
    fileName: 'harbour.jpg',
    mimeType: 'image/jpeg',
  );
  final video = _item(
    '1.1',
    MediaItemKind.video,
    fileName: 'clip.mp4',
    mimeType: 'video/mp4',
  );
  final report = _item(
    '2.0',
    MediaItemKind.file,
    fileName: 'report.pdf',
    mimeType: 'application/pdf',
  );
  final notes = _item(
    '3.0',
    MediaItemKind.file,
    fileName: 'notes.txt',
    mimeType: 'text/plain',
  );
  final media = <int, List<MediaItem>>{
    1: [photo, video],
    2: [report],
    3: [notes],
    4: const [],
  };

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

  ChatMediaSaves savesOn(
    ChatSaveEntries entries, {
    DateTime Function()? now,
    ChatSaveStarted? onStarted,
  }) {
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
      mediaOf: (id) => media[id] ?? const [],
      allowedOf: (id, item) => MediaItemAction.allowedItemActions(
        item,
        protection: capabilities.value.protection,
        messageProtected: protectedMessages.contains(id),
      ),
      reportDenied: (id) => protection.reportDenied(CapabilityAction.save, id),
      now: now,
      onStarted: onStarted,
    );
    addTearDown(saves.dispose);
    return saves;
  }

  void protectChat() => capabilities.value = capabilities.value.copyWith(
    protection: const ChatProtection(save: false),
  );

  group('entries', () {
    test('an item gets the entry of its kind and platform', () {
      final android = savesOn(ChatSaveEntries.android);
      expect(
        android.entryFor(1, [
          photo,
        ], part: MediaHitPart(photo.id, part: MediaPart.options)),
        ChatSaveEntries.android.photo,
      );
      expect(android.entryFor(2, [report]), ChatSaveEntries.android.file);

      final iOS = savesOn(ChatSaveEntries.iOS);
      expect(iOS.entryFor(1, [video]), ChatSaveEntries.iOS.video);

      final desktop = savesOn(ChatSaveEntries.desktop);
      expect(desktop.entryFor(2, [report]), ChatSaveEntries.desktop.file);

      expect(
        diagnostics.whereOp(ChatSaveOp.entriesOffered).first,
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

    test('an album offers the entry its items share as one batch', () {
      final saves = savesOn(ChatSaveEntries.android);
      expect(saves.entryFor(1, [photo, video]), ChatSaveEntries.android.photo);
      expect(
        diagnostics.whereOp(ChatSaveOp.entriesOffered).single.fields,
        containsPair('batch', 'album'),
      );
    });

    test('a link preview card offers none', () {
      final saves = savesOn(ChatSaveEntries.android);
      expect(
        saves.entryFor(1, [
          photo,
        ], part: const LinkPreviewHitPart(1, zone: LinkPreviewZone.body)),
        isNull,
      );
      expect(
        diagnostics.whereOp(ChatSaveOp.entriesHidden).single,
        isChatEvent(
          level: ChatEventLevel.info,
          correlation: ChatCorrelation(
            chatId: 'chat-1',
            scrollId: '1',
            mediaItemId: photo.id.toString(),
          ),
          fields: {'why': 'linkPreviewPart', 'live': false},
        ),
      );
    });

    test('protection hides them, the chat\'s or the message\'s own', () {
      final saves = savesOn(ChatSaveEntries.android);
      protectedMessages.add(2);
      expect(saves.entryFor(2, [report]), isNull);
      expect(saves.entryFor(1, [photo]), isNotNull);

      protectChat();
      expect(saves.entryFor(1, [photo]), isNull);
      expect(
        diagnostics
            .whereOp(ChatSaveOp.entriesHidden)
            .map((event) => event.fields['why']),
        ['protection', 'protection'],
      );
    });

    test('a selection of files offers Save to Downloads on Android only; '
        'protection takes it away live', () {
      final android = savesOn(ChatSaveEntries.android);
      expect(android.selectionEntryOf([2, 3]), ChatSaveEntries.android.file);
      expect(android.selectionEntryOf([1, 2]), isNull, reason: 'a photo');
      expect(android.selectionEntryOf([2, 4]), isNull, reason: 'no media');
      expect(
        diagnostics.whereOp(ChatSaveOp.entriesOffered).last.fields,
        containsPair('batch', 'selection'),
      );

      expect(android.selectionEntryOf([2, 3]), isNotNull);
      protectChat();
      expect(android.selectionEntryOf([2, 3]), isNull);
      expect(diagnostics.whereOp(ChatSaveOp.entriesHidden).last.fields, {
        'why': 'protection',
        'live': true,
      });

      for (final entries in [ChatSaveEntries.iOS, ChatSaveEntries.desktop]) {
        expect(savesOn(entries).selectionEntryOf([2, 3]), isNull);
      }
    });
  });

  group('saves', () {
    test('an item is saved through saveContent with its name, MIME type and '
        'kind', () {
      final saves = savesOn(ChatSaveEntries.android);
      final job = saves.save(
        1,
        [photo],
        ChatSaveEntries.android.photo,
        source: ChatSaveSource.menu,
      );

      final batch = saver.contentBatches.single;
      expect(batch.jobId, job!.id);
      expect(batch.destination, ChatSaveEntries.android.photo.destination);
      final request = batch.requests.single;
      expect(request.key, const MediaKey.remote('doc-1.0'));
      expect(request.name, 'harbour.jpg');
      expect(request.mimeType, 'image/jpeg');
      expect(request.kind, SaveItemKind.photo);
      expect(saver.batches, isEmpty);

      expect(
        diagnostics.whereOp(ChatSaveOp.saveStarted).single,
        isChatEvent(
          level: ChatEventLevel.info,
          category: ChatEventCategory.save,
          correlation: ChatCorrelation(
            chatId: 'chat-1',
            scrollId: '1',
            mediaItemId: photo.id.toString(),
            mediaKey: const MediaKey.remote('doc-1.0').encoded,
            jobId: job.id,
          ),
          fields: {'source': 'menu', 'items': 1, 'destination': 'gallery'},
        ),
      );
    });

    test('an item the host knows no name or type of gets a default of its '
        'kind', () {
      final saves = savesOn(ChatSaveEntries.android);
      final bare = _item('5.0', MediaItemKind.video);
      saves.save(
        5,
        [bare],
        ChatSaveEntries.android.video,
        source: ChatSaveSource.menu,
      );
      final request = saver.contentBatches.single.requests.single;
      expect(request.mimeType, 'video/mp4');
      expect(request.name, 'video.mp4');
      expect(request.kind, SaveItemKind.video);
    });

    test('an album and a selection are one job each', () {
      final saves = savesOn(ChatSaveEntries.android);
      saves.save(
        1,
        [photo, video],
        ChatSaveEntries.android.photo,
        source: ChatSaveSource.album,
      );
      saves.saveSelection([2, 3], ChatSaveEntries.android.file);

      expect(saver.contentBatches, hasLength(2));
      expect(saver.contentBatches.first.requests.map((r) => r.kind), [
        SaveItemKind.photo,
        SaveItemKind.video,
      ]);
      expect(saver.contentBatches.last.requests.map((r) => r.name), [
        'report.pdf',
        'notes.txt',
      ]);
      expect(saver.contentBatches.last.destination, ChatSaveWiring.downloads);
      expect(
        diagnostics
            .whereOp(ChatSaveOp.saveStarted)
            .map((event) => (event.fields['source'], event.fields['items'])),
        [('album', 2), ('selection', 2)],
      );
      // A batch names no single item.
      expect(
        diagnostics.whereOp(ChatSaveOp.saveStarted).first.correlation,
        ChatCorrelation(
          chatId: 'chat-1',
          scrollId: '1',
          jobId: saver.contentBatches.first.jobId,
        ),
      );
    });

    test('each job started reaches its feedback with its items and entry; a '
        'dropped tap reaches none', () {
      final started = <(SaveJob, List<MediaItem>, ChatSaveEntry)>[];
      final saves = savesOn(
        ChatSaveEntries.android,
        onStarted: (job, items, entry) => started.add((job, items, entry)),
      );
      final job = saves.save(
        1,
        [photo, video],
        ChatSaveEntries.android.photo,
        source: ChatSaveSource.album,
      );
      saves.save(
        1,
        [photo, video],
        ChatSaveEntries.android.photo,
        source: ChatSaveSource.album,
      );
      final selection = saves.saveSelection([
        2,
        3,
      ], ChatSaveEntries.android.file);

      expect(started.map((start) => start.$1), [job, selection]);
      expect(started.first.$2, [photo, video]);
      expect(started.last.$2, [report, notes]);
      expect(started.last.$3, ChatSaveEntries.android.file);
    });

    test('a burst of taps on one entry starts one job', () {
      fakeAsync((async) {
        final saves = savesOn(
          ChatSaveEntries.android,
          now: async.getClock(DateTime(2026)).now,
        );
        for (var tap = 0; tap < 5; tap++) {
          saves.save(
            1,
            [photo],
            ChatSaveEntries.android.photo,
            source: ChatSaveSource.menu,
          );
          async.elapse(const Duration(milliseconds: 50));
        }
        expect(saver.contentBatches, hasLength(1));
        expect(diagnostics.whereOp(ChatSaveOp.saveDropped), hasLength(4));
        expect(
          diagnostics.whereOp(ChatSaveOp.saveDropped).first,
          isChatEvent(
            level: ChatEventLevel.debug,
            correlation: const ChatCorrelation(chatId: 'chat-1', scrollId: '1'),
            fields: {'ms': 50},
          ),
        );

        // Another item is its own tap.
        saves.save(
          2,
          [report],
          ChatSaveEntries.android.file,
          source: ChatSaveSource.menu,
        );
        expect(saver.contentBatches, hasLength(2));

        async.elapse(ChatMediaSaves.guardWindow);
        saves.save(
          1,
          [photo],
          ChatSaveEntries.android.photo,
          source: ChatSaveSource.menu,
        );
        expect(saver.contentBatches, hasLength(3));
      });
    });

    test('a save protection turned on for meanwhile is denied and '
        'reported', () {
      final saves = savesOn(ChatSaveEntries.android);
      final entry = saves.entryFor(1, [photo])!;
      protectChat();

      expect(
        saves.save(1, [photo], entry, source: ChatSaveSource.menu),
        isNull,
      );
      expect(
        saves.save(1, [video], entry, source: ChatSaveSource.viewer),
        isNull,
      );
      expect(saver.contentBatches, isEmpty);

      expect(
        diagnostics
            .whereOp(ChatSaveOp.saveDenied)
            .map((event) => event.fields['path']),
        ['staleMenu', 'viewer'],
      );
      expect(
        diagnostics.whereOp(ChatSaveOp.saveDenied).first.correlation,
        const ChatCorrelation(chatId: 'chat-1', scrollId: '1'),
      );
      expect(feedback.denials.map((d) => d.action), [
        CapabilityAction.save,
        CapabilityAction.save,
      ]);
      expect(
        diagnostics.whereOp(CapabilitiesOp.denied).first.fields,
        containsPair('action', CapabilityAction.save),
      );
    });

    test('no event carries a file name', () {
      final saves = savesOn(ChatSaveEntries.android);
      saves
        ..entryFor(2, [report])
        ..save(
          2,
          [report],
          ChatSaveEntries.android.file,
          source: ChatSaveSource.menu,
        )
        ..save(
          2,
          [report],
          ChatSaveEntries.android.file,
          source: ChatSaveSource.menu,
        );
      for (final event in diagnostics.whereCategory(ChatEventCategory.save)) {
        expect('${event.fields}', isNot(contains('report')));
      }
    });
  });
}
