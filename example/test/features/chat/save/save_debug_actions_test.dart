import 'package:chat_scroll_view_example/src/features/chat/save/chat_save_wiring.dart';
import 'package:chat_scroll_view_example/src/features/chat/save/save_debug_actions.dart';
import 'package:content_model/content_model.dart';
import 'package:content_model/testing.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_library/mpx_library.dart';
import 'package:mpx_library/testing.dart';

void main() {
  late RecordingDiagnostics diagnostics;
  late FakeMediaSaver saver;
  late int loads;
  late SaveDebugActions actions;

  setUp(() {
    diagnostics = RecordingDiagnostics.install();
    saver = FakeMediaSaver();
    loads = 0;
    actions = SaveDebugActions(
      saver: saver,
      demoItem: () async {
        loads++;
        return SaveItem.bytes(
          Uint8List(8),
          name: 'demo.jpg',
          mimeType: 'image/jpeg',
          kind: SaveItemKind.photo,
        );
      },
    );
  });

  tearDown(() => actions.dispose());

  test('offers the gallery, the example\'s Downloads sub-folder and the '
      'save dialog', () {
    expect(SaveDebugActions.destinations, const [
      SaveDestination.gallery(),
      ChatSaveWiring.downloads,
      SaveDestination.ask(),
    ]);
  });

  test(
    'saves the demo item once to each destination, loading it once',
    () async {
      for (final destination in SaveDebugActions.destinations) {
        final job = await actions.saveDemoTo(destination);
        await job!.results;
      }

      expect(
        saver.batches.map((batch) => batch.destination),
        SaveDebugActions.destinations,
      );
      for (final batch in saver.batches) {
        expect(batch.items.single.kind, SaveItemKind.photo);
      }
      expect(loads, 1);
    },
  );

  test('reports debugSave with the destination and the job, no name', () async {
    final job = await actions.saveDemoTo(ChatSaveWiring.downloads);
    await job!.results;

    final event = diagnostics.events.singleWhere(
      (event) => event.op == ChatSaveOp.debugSave,
    );
    expect(event.category, ChatEventCategory.save);
    expect(event.level, ChatEventLevel.info);
    expect(event.fields, {'destination': 'downloads'});
    expect(event.correlation.jobId, job.id);
  });

  test('shows each destination\'s outcome: saving, then saved or the '
      'failure', () async {
    saver.resultFor = (write) => switch (write.destination) {
      SaveDestination$Ask() => const SaveResult.failed(SaveFailure.noSpace),
      _ => const SaveResult.saved('ref'),
    };

    final saving = actions.saveDemoTo(const SaveDestination.gallery());
    await pumpEventQueue(times: 1);
    expect(actions.outcomes.value['gallery'], 'saving');
    await (await saving)!.results;
    await pumpEventQueue();
    expect(actions.outcomes.value['gallery'], 'saved');

    await (await actions.saveDemoTo(const SaveDestination.ask()))!.results;
    await pumpEventQueue();
    expect(actions.outcomes.value['ask'], 'failed: noSpace');
  });

  test('a burst of taps on one destination starts one job; another '
      'destination is not held back', () {
    fakeAsync((async) {
      final first = actions.saveDemoTo(const SaveDestination.gallery());
      final second = actions.saveDemoTo(const SaveDestination.gallery());
      final third = actions.saveDemoTo(const SaveDestination.gallery());
      final other = actions.saveDemoTo(const SaveDestination.ask());
      async.flushMicrotasks();

      SaveJob? job;
      SaveJob? dropped1;
      SaveJob? dropped2;
      SaveJob? otherJob;
      first.then((value) => job = value);
      second.then((value) => dropped1 = value);
      third.then((value) => dropped2 = value);
      other.then((value) => otherJob = value);
      async
        ..flushMicrotasks()
        ..elapse(const Duration(seconds: 1));

      expect(job, isNotNull);
      expect(dropped1, isNull);
      expect(dropped2, isNull);
      expect(otherJob, isNotNull);
      expect(saver.batches.map((batch) => batch.destination), const [
        SaveDestination.gallery(),
        SaveDestination.ask(),
      ]);

      // Once the window passed, the destination saves again.
      actions.saveDemoTo(const SaveDestination.gallery());
      async
        ..flushMicrotasks()
        ..elapse(const Duration(seconds: 1));
      expect(saver.batches, hasLength(3));
    });
  });

  test('a demo item that cannot be read fails that tap at warning and is '
      'read again on the next', () {
    fakeAsync((async) {
      var fail = true;
      final reading = SaveDebugActions(
        saver: saver,
        demoItem: () async {
          if (fail) throw StateError('no asset');
          return SaveItem.bytes(
            Uint8List(8),
            name: 'demo.jpg',
            mimeType: 'image/jpeg',
            kind: SaveItemKind.photo,
          );
        },
      );
      addTearDown(reading.dispose);

      reading.saveDemoTo(const SaveDestination.gallery());
      async.flushMicrotasks();
      expect(reading.outcomes.value['gallery'], 'failed: demoItem');
      final event = diagnostics.events.singleWhere(
        (event) => event.op == ChatSaveOp.debugSave,
      );
      expect(event.level, ChatEventLevel.warning);
      expect(event.error, isA<StateError>());
      expect(saver.batches, isEmpty);

      fail = false;
      async.elapse(SaveDebugActions.guardWindow);
      reading.saveDemoTo(const SaveDestination.gallery());
      async
        ..flushMicrotasks()
        ..elapse(const Duration(seconds: 1));
      expect(saver.batches, hasLength(1));
    });
  });

  test('does nothing once disposed', () async {
    actions.dispose();

    expect(await actions.saveDemoTo(const SaveDestination.gallery()), isNull);
    expect(saver.batches, isEmpty);
  });
}
