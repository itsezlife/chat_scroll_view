import 'package:chat_scroll_view_example/src/features/chat/save/chat_save_wiring.dart';
import 'package:chat_scroll_view_example/src/features/logs/data/diagnostics_journal.dart';
import 'package:chat_scroll_view_example/src/features/logs/model/journal_record.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_core/mpx_core.dart' show MpxDiagnostics;
import 'package:mpx_library/mpx_library.dart';
import 'package:mpx_library/testing.dart';

void main() {
  late RecordingDiagnostics diagnostics;

  setUp(() => diagnostics = RecordingDiagnostics.install());

  ChatEvent wired() => diagnostics.events.singleWhere(
    (event) => event.op == ChatSaveOp.saverWired,
  );

  group('saverWired', () {
    test('reports the tracked transfers, the sub-folder and, off Apple, no '
        'define to need, at info in the save category', () async {
      await ChatSaveWiring.report(FakeMediaSaver(), transfers: true);

      final event = wired();
      expect(event.category, ChatEventCategory.save);
      expect(event.level, ChatEventLevel.info);
      expect(event.correlation, ChatCorrelation.none);
      expect(event.fields, {
        'transfers': true,
        'subfolder': true,
        'define': 'notNeeded',
      });
    });

    test('says when no tracked transfers are composed', () async {
      await ChatSaveWiring.report(FakeMediaSaver(), transfers: false);

      expect(wired().fields['transfers'], isFalse);
    });

    for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
      group('on ${platform.name}', () {
        setUp(() => debugDefaultTargetPlatformOverride = platform);
        tearDown(() => debugDefaultTargetPlatformOverride = null);

        test('reads the define as on when the gallery is not unavailable '
            '(the save code is compiled)', () async {
          final saver = FakeMediaSaver()..saveAccess = SaveAccess.notDetermined;

          await ChatSaveWiring.report(saver, transfers: true);

          expect(wired().fields['define'], 'on');
          expect(saver.accessRequests, 0, reason: 'it reads, never asks');
        });

        test(
          'reads the define as off when the gallery is unavailable',
          () async {
            final saver = FakeMediaSaver()..saveAccess = SaveAccess.unavailable;

            await ChatSaveWiring.report(saver, transfers: true);

            expect(wired().fields['define'], 'off');
          },
        );

        test('a read that throws reports the define unknown, with the '
            'error, at warning', () async {
          await ChatSaveWiring.report(_ThrowingAccess(), transfers: true);

          final event = wired();
          expect(event.level, ChatEventLevel.warning);
          expect(event.fields['define'], 'unknown');
          expect(event.error, isA<PlatformException>());
        });
      });
    }
  });

  test('the sub-folder is the example\'s own name, and the downloads '
      'destination carries it', () {
    expect(ChatSaveWiring.subfolder, isNotEmpty);
    expect(
      ChatSaveWiring.downloads,
      const SaveDestination.downloads(subfolder: ChatSaveWiring.subfolder),
    );
  });

  test(
    "mpx's save events reach the journal through the media bridge",
    () async {
      final journal = DiagnosticsJournal.memory();
      addTearDown(journal.dispose);
      final previous = MpxDiagnostics.current;
      MpxDiagnostics.current = journal.mediaDiagnostics;
      addTearDown(() => MpxDiagnostics.current = previous);

      final job = FakeMediaSaver().save([
        SaveItem.bytes(
          Uint8List(4),
          name: 'photo.jpg',
          mimeType: 'image/jpeg',
          kind: SaveItemKind.photo,
        ),
      ], ChatSaveWiring.downloads);
      await job.results;

      final saves = [
        for (final record in journal.records)
          if (record.source == JournalSource.media && record.category == 'save')
            record,
      ];
      expect(
        saves.map((record) => record.op),
        containsAllInOrder(['jobStarted', 'itemSaved', 'jobFinished']),
      );
      expect(saves.map((record) => record.correlation.jobId).toSet(), {job.id});
      for (final record in saves) {
        expect(record.encode(), isNot(contains('photo.jpg')));
        expect(record.encode(), isNot(contains(ChatSaveWiring.subfolder)));
      }
    },
  );
}

/// A saver whose access read fails, as a missing plugin would.
final class _ThrowingAccess implements MediaSaver {
  @override
  Future<SaveAccess> access(SaveDestination destination) async =>
      throw PlatformException(code: 'boom');

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}
