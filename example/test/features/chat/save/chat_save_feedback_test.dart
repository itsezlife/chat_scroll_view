/// The feedback of a save job: a progress dialog only when the job runs
/// past the delay, a cancel from it, and the bulletin the results earn.
///
/// **Seams:** [ChatSaveFeedback] following a [FakeMediaSaver] job, with a
/// [BulletinController] for the bulletins and a [RecordingDiagnostics];
/// [SaveProgressDialog] as the presenter where the dialog itself is under
/// test.
library;

import 'dart:typed_data';

import 'package:bulletins/bulletins.dart';
import 'package:chat_scroll_view_example/src/features/chat/save/chat_save_feedback.dart';
import 'package:chat_scroll_view_example/src/features/chat/save/chat_save_strings.dart';
import 'package:chat_scroll_view_example/src/features/chat/save/chat_save_wiring.dart';
import 'package:chat_scroll_view_example/src/features/chat/save/save_progress_dialog.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_library/mpx_library.dart';
import 'package:mpx_library/testing.dart';

SaveItem _bytes(SaveItemKind kind) => SaveItem.bytes(
  Uint8List(4),
  name: 'item',
  mimeType: 'application/octet-stream',
  kind: kind,
);

void main() {
  const strings = ChatSaveStrings.english;
  const gallery = SaveDestination.gallery();
  const downloads = SaveDestination.downloads(subfolder: 'Demo');

  late RecordingDiagnostics diagnostics;
  late BulletinController bulletins;
  late List<ChatSaveProgress> presented;
  late int dismissed;
  late int downloadsOpened;

  setUp(() {
    diagnostics = RecordingDiagnostics.install();
    bulletins = BulletinController();
    addTearDown(bulletins.dispose);
    presented = [];
    dismissed = 0;
    downloadsOpened = 0;
  });

  ChatSaveFeedback feedbackOf(
    WidgetTester tester, {
    ChatSaveProgressPresenter? present,
  }) {
    final feedback = ChatSaveFeedback(
      chatId: 'chat-1',
      bulletins: bulletins,
      strings: strings,
      present:
          present ??
          (progress) {
            presented.add(progress);
            return () => dismissed++;
          },
      openDownloads: () => downloadsOpened++,
      now: () => tester.binding.clock.now(),
    );
    addTearDown(feedback.dispose);
    return feedback;
  }

  // A saver whose items each take [step] four times.
  FakeMediaSaver saverOf(
    Duration step, {
    SaveResult Function(FakeSaveWrite write)? resultFor,
  }) => FakeMediaSaver(stepDelay: step, resultFor: resultFor);

  SaveJob saveOn(
    FakeMediaSaver saver,
    List<SaveItemKind> kinds,
    SaveDestination destination,
  ) => saver.save([for (final kind in kinds) _bytes(kind)], destination);

  void follow(
    ChatSaveFeedback feedback,
    SaveJob job,
    List<MediaItemKind> kinds,
    SaveDestination destination,
  ) => feedback.follow(job, kinds: kinds, destination: destination);

  // The job's results, pumping fake time until they come: an await alone
  // would wait on timers that only a pump runs.
  Future<List<SaveResult>> ended(WidgetTester tester, SaveJob job) async {
    var done = false;
    final results = job.results.whenComplete(() => done = true);
    for (var step = 0; !done && step < 200; step++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    return results;
  }

  String? shownMessage() => bulletins.current.value?.bulletin.message;

  group('progress dialog', () {
    testWidgets('a job done under the delay shows no dialog', (tester) async {
      final feedback = feedbackOf(tester);
      final job = saveOn(saverOf(const Duration(milliseconds: 40)), [
        SaveItemKind.photo,
      ], gallery);
      follow(feedback, job, [MediaItemKind.photo], gallery);

      await tester.pump(const Duration(milliseconds: 200));
      await ended(tester, job);

      expect(presented, isEmpty);
      expect(shownMessage(), 'Photo saved to gallery');
    });

    testWidgets('a job running past the delay shows the dialog, closed when '
        'the job ends', (tester) async {
      final feedback = feedbackOf(tester);
      final job = saveOn(saverOf(const Duration(milliseconds: 100)), [
        SaveItemKind.photo,
      ], gallery);
      follow(feedback, job, [MediaItemKind.photo], gallery);

      await tester.pump(const Duration(milliseconds: 249));
      expect(presented, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(presented, hasLength(1));
      expect(presented.single.fraction, same(job.progress));

      await tester.pump(const Duration(milliseconds: 200));
      expect(dismissed, 1);
      expect(shownMessage(), 'Photo saved to gallery');
      expect(diagnostics.whereOp(ChatSaveOp.feedbackShown), [
        isChatEvent(
          level: ChatEventLevel.debug,
          category: ChatEventCategory.save,
          op: ChatSaveOp.feedbackShown,
          fields: {'form': 'progressDialog', 'ms': 250},
        ),
        isChatEvent(
          op: ChatSaveOp.feedbackShown,
          fields: {'form': 'savedBulletin', 'ms': 400},
        ),
      ]);
      expect(
        diagnostics.whereCorrelated(chatId: 'chat-1', jobId: job.id),
        hasLength(2),
      );
    });

    testWidgets('a cancel from the dialog cancels the job, closes the dialog '
        'and shows no bulletin', (tester) async {
      final feedback = feedbackOf(tester);
      final job = saveOn(saverOf(const Duration(milliseconds: 100)), [
        SaveItemKind.video,
        SaveItemKind.video,
      ], gallery);
      follow(feedback, job, [
        MediaItemKind.video,
        MediaItemKind.video,
      ], gallery);

      await tester.pump(const Duration(milliseconds: 300));
      presented.single.cancel();
      expect(dismissed, 1);

      final results = await ended(tester, job);
      await tester.pump(const Duration(milliseconds: 500));

      expect(results.whereType<SaveResult$Cancelled>(), isNotEmpty);
      expect(shownMessage(), isNull);
      expect(dismissed, 1);
      expect(diagnostics.whereOp(ChatSaveOp.feedbackCancelled), [
        isChatEvent(
          level: ChatEventLevel.debug,
          op: ChatSaveOp.feedbackCancelled,
          fields: allOf(
            containsPair('from', 'dialog'),
            containsPair('ms', 300),
            contains('percent'),
          ),
        ),
      ]);
      expect(
        diagnostics
            .whereOp(ChatSaveOp.feedbackShown)
            .map((event) => event.fields['form']),
        ['progressDialog'],
      );
    });

    testWidgets('a save to a place the user picks shows no dialog: the '
        'system dialog is the job', (tester) async {
      final feedback = feedbackOf(tester);
      final job = saveOn(saverOf(const Duration(milliseconds: 100)), [
        SaveItemKind.file,
      ], const SaveDestination.ask());
      follow(feedback, job, [MediaItemKind.file], const SaveDestination.ask());

      await tester.pump(const Duration(seconds: 1));
      await ended(tester, job);

      expect(presented, isEmpty);
      expect(shownMessage(), isNull);
    });
  });

  group('saved bulletin', () {
    Future<Bulletin?> savedOf(
      WidgetTester tester,
      List<MediaItemKind> kinds,
      SaveDestination destination,
    ) async {
      final feedback = feedbackOf(tester);
      final job = saveOn(saverOf(Duration.zero), [
        // The saver's item kinds do not matter here: what the bulletin says
        // comes from the chat's kinds.
        for (final _ in kinds) SaveItemKind.photo,
      ], destination);
      follow(feedback, job, kinds, destination);
      await ended(tester, job);
      return bulletins.current.value?.bulletin;
    }

    testWidgets('the gallery, per kind and in the plural', (tester) async {
      final cases = <(List<MediaItemKind>, String)>[
        ([MediaItemKind.photo], 'Photo saved to gallery'),
        (
          [MediaItemKind.photo, MediaItemKind.photo],
          '2 photos saved to gallery',
        ),
        ([MediaItemKind.video], 'Video saved to gallery'),
        (
          [MediaItemKind.video, MediaItemKind.video, MediaItemKind.video],
          '3 videos saved to gallery',
        ),
        ([MediaItemKind.animation], 'GIF saved to gallery'),
        (
          [MediaItemKind.animation, MediaItemKind.animation],
          '2 GIFs saved to gallery',
        ),
        (
          [MediaItemKind.photo, MediaItemKind.video],
          '2 items saved to gallery',
        ),
      ];
      for (final (kinds, message) in cases) {
        final bulletin = await savedOf(tester, kinds, gallery);
        expect(bulletin?.message, message, reason: '$kinds');
        expect(
          bulletin?.leading,
          const BulletinLeading.icon(ChatSaveFeedback.galleryIcon),
        );
        expect(bulletin?.links, isEmpty);
      }
    });

    testWidgets('Downloads, per kind and in the plural, with a link that '
        'opens them', (tester) async {
      final cases = <(List<MediaItemKind>, String)>[
        ([MediaItemKind.photo], 'Photo saved to Downloads.'),
        ([MediaItemKind.video], 'Video saved to Downloads.'),
        ([MediaItemKind.animation], 'GIF saved to Downloads.'),
        ([MediaItemKind.file], 'File saved to Downloads.'),
        (
          [MediaItemKind.file, MediaItemKind.file, MediaItemKind.file],
          '3 files saved to Downloads.',
        ),
        (
          [MediaItemKind.photo, MediaItemKind.file],
          '2 files saved to Downloads.',
        ),
      ];
      for (final (kinds, message) in cases) {
        final bulletin = await savedOf(tester, kinds, downloads);
        expect(bulletin?.message, message, reason: '$kinds');
        expect(
          bulletin?.leading,
          const BulletinLeading.icon(ChatSaveFeedback.downloadsIcon),
        );
        final link = bulletin!.links.single;
        expect(message.substring(link.start, link.end), 'Downloads');
      }

      bulletins.current.value!.bulletin.links.single.onTap();
      expect(downloadsOpened, 1);
    });

    testWidgets('the demo language counts in Russian', (tester) async {
      const russian = ChatSaveStrings.russian;
      expect(russian.savedToGallery(MediaItemKind.photo, 1), isNotEmpty);
      expect(
        russian.savedToDownloads(MediaItemKind.file, 2),
        contains(russian.downloadsLink),
      );
      expect(
        russian.savedToDownloads(MediaItemKind.file, 5),
        isNot(russian.savedToDownloads(MediaItemKind.file, 2)),
      );
    });
  });

  group('failed bulletin', () {
    testWidgets('says the reason, which its event names', (tester) async {
      for (final reason in SaveFailure.values) {
        final feedback = feedbackOf(tester);
        final job = saveOn(
          saverOf(Duration.zero, resultFor: (_) => SaveResult.failed(reason)),
          [SaveItemKind.photo, SaveItemKind.photo],
          gallery,
        );
        follow(feedback, job, [
          MediaItemKind.photo,
          MediaItemKind.photo,
        ], gallery);
        await ended(tester, job);

        final bulletin = bulletins.current.value?.bulletin;
        expect(bulletin?.message, strings.failed(reason));
        expect(bulletin?.leading, isA<BulletinLeading$Icon>());
        expect(
          diagnostics.whereOp(ChatSaveOp.feedbackShown).last,
          isChatEvent(
            fields: allOf(
              containsPair('form', 'failedBulletin'),
              containsPair('reason', reason.name),
            ),
          ),
        );
      }
      expect({
        for (final reason in SaveFailure.values) strings.failed(reason),
      }, hasLength(SaveFailure.values.length));
    });

    testWidgets('one failed item in a batch fails the bulletin', (
      tester,
    ) async {
      final feedback = feedbackOf(tester);
      final job = saveOn(
        saverOf(
          Duration.zero,
          resultFor: (write) => write.index == 1
              ? const SaveResult.failed(SaveFailure.noSpace)
              : const SaveResult.saved('ref'),
        ),
        [SaveItemKind.photo, SaveItemKind.photo],
        gallery,
      );
      follow(feedback, job, [
        MediaItemKind.photo,
        MediaItemKind.photo,
      ], gallery);
      await ended(tester, job);

      expect(shownMessage(), strings.failed(SaveFailure.noSpace));
    });
  });

  testWidgets('after dispose a job ends with no bulletin, its dialog closed', (
    tester,
  ) async {
    final feedback = feedbackOf(tester);
    final job = saveOn(saverOf(const Duration(milliseconds: 100)), [
      SaveItemKind.photo,
    ], gallery);
    follow(feedback, job, [MediaItemKind.photo], gallery);
    await tester.pump(const Duration(milliseconds: 300));
    feedback.dispose();
    await tester.pump(const Duration(milliseconds: 200));

    expect(dismissed, 1);
    expect(shownMessage(), isNull);
  });

  group('SaveProgressDialog', () {
    late GlobalKey<NavigatorState> navigator;

    Future<ChatSaveFeedback> mount(WidgetTester tester) async {
      navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ChromeThemeScope(
          palette: const ChromePalette.dark(),
          child: MaterialApp(
            navigatorKey: navigator,
            home: const Scaffold(body: Text('chat')),
          ),
        ),
      );
      return feedbackOf(
        tester,
        present: (progress) => SaveProgressDialog.show(
          navigator.currentContext!,
          progress,
          strings: strings,
        ),
      );
    }

    Future<SaveJob> runLong(WidgetTester tester) async {
      final feedback = await mount(tester);
      final job = saveOn(saverOf(const Duration(milliseconds: 500)), [
        SaveItemKind.photo,
      ], gallery);
      follow(feedback, job, [MediaItemKind.photo], gallery);
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 300));
      return job;
    }

    testWidgets('shows the progress in the chrome face', (tester) async {
      await runLong(tester);

      expect(find.text(strings.progressMessage), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expectChromeText(tester, within: find.byType(AlertDialog));

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('a burst of taps on cancel cancels once and leaves the chat', (
      tester,
    ) async {
      final job = await runLong(tester);

      for (var tap = 0; tap < 5; tap++) {
        await tester.tap(
          find.byKey(SaveProgressDialog.cancelKey),
          warnIfMissed: false,
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();
      final results = await ended(tester, job);

      expect(results.single, const SaveResult.cancelled());
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('chat'), findsOneWidget);
      expect(diagnostics.whereOp(ChatSaveOp.feedbackCancelled), hasLength(1));
      expect(shownMessage(), isNull);
    });

    testWidgets('back cancels, as the cancel button does', (tester) async {
      final job = await runLong(tester);

      await navigator.currentState!.maybePop();
      await tester.pumpAndSettle();

      expect(await ended(tester, job), [const SaveResult.cancelled()]);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('chat'), findsOneWidget);
    });
  });
}
