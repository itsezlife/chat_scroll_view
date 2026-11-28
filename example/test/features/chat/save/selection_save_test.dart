/// The selection bar's save: offered on Android over a selection of files,
/// one job for a burst of taps, and gone as soon as protection turns on.
///
/// **Seam:** a pumped [SelectionAppBar] over a real
/// [ChatSelectionController], its save a [ChatMediaSaves] over a
/// [FakeMediaSaver].
library;

import 'package:chat_capabilities/chat_capabilities.dart';
import 'package:chat_scroll_view/chat_scroll_view.dart';
import 'package:chat_scroll_view_example/src/features/chat/save/chat_media_saves.dart';
import 'package:chat_scroll_view_example/src/features/chat/save/chat_save_entries.dart';
import 'package:chat_scroll_view_example/src/features/chat/save/chat_save_wiring.dart';
import 'package:chat_scroll_view_example/src/features/chat/widgets/selection_app_bar.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:message_media/message_media.dart';
import 'package:mpx_library/testing.dart';

MediaItem _file(String id) => MediaItem(
  id: MediaItemId(id),
  kind: MediaItemKind.file,
  descriptor: ContentDescriptor(
    key: ContentKey.document('doc-$id'),
    fileName: 'file-$id.pdf',
    mimeType: 'application/pdf',
  ),
);

void main() {
  final media = {
    2: [_file('2.0')],
    3: [_file('3.0'), _file('3.1')],
  };

  late FakeMediaSaver saver;
  late ChatProtection protection;
  late ChatSelectionController selection;
  late ChatMediaSaves saves;
  late RecordingDiagnostics diagnostics;

  setUp(() {
    diagnostics = RecordingDiagnostics.install();
    saver = FakeMediaSaver();
    protection = const ChatProtection();
    selection = ChatSelectionController(chatId: 'chat-1');
    addTearDown(selection.dispose);
  });

  Future<void> pumpBar(WidgetTester tester, ChatSaveEntries entries) async {
    saves = ChatMediaSaves(
      saver: saver,
      chatId: 'chat-1',
      entries: entries,
      mediaOf: (id) => media[id] ?? const [],
      allowedOf: (id, item) => MediaItemAction.allowedItemActions(
        item,
        protection: protection,
        messageProtected: false,
      ),
      reportDenied: (_) {},
    );
    addTearDown(saves.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionAppBar(
            selection: selection,
            saveEntryOf: saves.selectionEntryOf,
            onSave: (entry) =>
                saves.saveSelection(selection.selectedIds, entry),
          ),
        ),
      ),
    );
    selection
      ..startSelection(2)
      ..replaceSelectedIds({2, 3});
    await tester.pumpAndSettle();
  }

  testWidgets('Android saves the selected files to Downloads as one job, '
      'once for a burst of taps', (tester) async {
    await pumpBar(tester, ChatSaveEntries.android);
    final save = find.byTooltip('Save to Downloads');
    expect(save, findsOneWidget);

    for (var tap = 0; tap < 5; tap++) {
      await tester.tap(save);
      await tester.pump(const Duration(milliseconds: 40));
    }
    final batch = saver.contentBatches.single;
    expect(batch.requests, hasLength(3));
    expect(batch.destination, ChatSaveWiring.downloads);
    expect(diagnostics.whereOp(ChatSaveOp.saveDropped), hasLength(4));
    await tester.pump(ChatMediaSaves.guardWindow);
  });

  testWidgets('protection turning on takes the save away live', (tester) async {
    await pumpBar(tester, ChatSaveEntries.android);
    expect(find.byTooltip('Save to Downloads'), findsOneWidget);

    protection = const ChatProtection(save: false);
    // What the chat's protection host does on a change.
    selection.reapplyCanCopy();
    await tester.pump();
    expect(find.byTooltip('Save to Downloads'), findsNothing);
    expect(diagnostics.whereOp(ChatSaveOp.entriesHidden).single.fields, {
      'why': 'protection',
      'live': true,
    });
  });

  testWidgets('iOS and desktop offer no selection save', (tester) async {
    for (final entries in [ChatSaveEntries.iOS, ChatSaveEntries.desktop]) {
      await pumpBar(tester, entries);
      expect(find.byIcon(Icons.download_outlined), findsNothing);
      selection.clear();
      await tester.pumpAndSettle();
    }
  });
}
