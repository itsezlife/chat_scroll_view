import 'dart:async';

import 'package:attach_model/attach_model.dart';
import 'package:attach_sheet/attach_sheet.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_core/testing.dart';
import 'package:mpx_library/mpx_library.dart';
import 'package:mpx_library/testing.dart';

import '../page/pages_rig.dart';

final class _Host extends AttachSheetHost {
  final interactions = <AttachInteraction>[];

  @override
  void interaction(AttachInteraction interaction) =>
      interactions.add(interaction);
}

final class _Recent implements RecentFilesSource {
  final completer = Completer<List<IntakeFile>>();

  @override
  Future<List<IntakeFile>> load() => completer.future;
}

IntakeFile _file(String name, {int size = 1000, String? mime}) => IntakeFile(
  source: IntakeSource.path('/files/$name'),
  name: name,
  size: size,
  mimeType: mime,
);

void main() {
  late FakeFileIntake intake;
  late FakeMediaLibrary library;
  late PlaybackClock clock;
  late AssetCacheScope scope;

  setUp(() {
    intake = FakeFileIntake();
    library = FakeMediaLibrary(assets: 40);
    clock = PlaybackClock(ticks: ManualPlaybackTickSource());
    scope = AssetCacheScope(producer: FakeAssetProducer(), clock: clock);
  });
  tearDown(() async {
    scope.dispose();
    clock.dispose();
    await library.dispose();
  });

  Future<PagesRig> open(
    WidgetTester tester, {
    AttachLimits limits = const AttachLimits(),
    AttachSheetHost host = const AttachSheetHost(),
    RecentFilesSource? recent,
  }) async {
    final rig = await PagesRig.open(
      tester,
      policy: const AttachSheetPolicy.android(),
      limits: limits,
      host: host,
      initial: AttachPageId.files,
      wrap: (app) => AssetCacheProvider(scope: scope, child: app),
      pages: [
        rowsPage('gallery'),
        FilesPage.create(
          intake: intake,
          library: library,
          recent: recent,
          label: 'File',
          icon: const SizedBox(width: 24, height: 24),
        ),
      ],
    );
    await tester.pumpAndSettle();
    return rig;
  }

  testWidgets('Choose from files adds the picks as files and audio', (
    tester,
  ) async {
    final rig = await open(tester);
    intake.enqueuePick([
      _file('report.pdf', mime: 'application/pdf'),
      _file('song.mp3', mime: 'audio/mpeg'),
      _file('photo.jpg', mime: 'image/jpeg'),
    ]);

    await tester.tap(find.byKey(const ValueKey('attach-files-dialog')));
    await tester.pumpAndSettle();

    expect(intake.pickRequests.single.multiple, isTrue);
    expect(rig.selection.items.map((i) => i.kind), [
      AttachKind.file,
      AttachKind.audio,
      AttachKind.file,
    ]);
    expect(
      rig.selection.items.first.source,
      const AttachSource.file('/files/report.pdf'),
    );
    expect(rig.selection.items.first.facts.byteSize, 1000);
    expect(
      find.byKey(const ValueKey('attach-files-picked-file:/files/song.mp3')),
      findsOneWidget,
    );
  });

  testWidgets('single select asks the dialog for one file', (tester) async {
    await open(tester, limits: const AttachLimits(singleSelect: true));
    await tester.tap(find.byKey(const ValueKey('attach-files-dialog')));
    await tester.pumpAndSettle();
    expect(intake.pickRequests.single.multiple, isFalse);
  });

  testWidgets('an oversize or empty file is refused with an interaction', (
    tester,
  ) async {
    final host = _Host();
    final rig = await open(
      tester,
      host: host,
      limits: const AttachLimits(fileSizeLimit: 500),
    );
    intake.enqueuePick([
      _file('big.zip', size: 501),
      _file('empty.txt', size: 0),
    ]);

    await tester.tap(find.byKey(const ValueKey('attach-files-dialog')));
    await tester.pumpAndSettle();

    expect(rig.selection.isEmpty, isTrue);
    expect(host.interactions, [
      const AttachInteraction.refused(AttachRefusal.fileTooLarge),
      const AttachInteraction.refused(AttachRefusal.emptyFile),
    ]);
  });

  testWidgets('recent files load behind placeholder rows, then toggle', (
    tester,
  ) async {
    final recent = _Recent();
    final rig = await open(tester, recent: recent);
    expect(
      find.byKey(const ValueKey('attach-files-shimmer-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('attach-files-shimmer-10')),
      findsOneWidget,
    );

    recent.completer.complete([_file('a.pdf'), _file('b.pdf')]);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('attach-files-shimmer-0')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('attach-files-recent-b.pdf')));
    await tester.pumpAndSettle();
    expect(rig.selection.items.single.facts.name, 'b.pdf');
    expect(find.text('1'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('attach-files-recent-b.pdf')));
    await tester.pumpAndSettle();
    expect(rig.selection.isEmpty, isTrue);
  });

  testWidgets('Choose from gallery picks into the selection and sends as '
      'files', (tester) async {
    final rig = await open(tester);
    await tester.tap(find.byKey(const ValueKey('attach-files-gallery')));
    await tester.pumpAndSettle();
    expectChromeText(
      tester,
      within: find.byKey(const ValueKey('attach-files-gallery-send')),
    );

    final cell = find.byKey(
      ValueKey<MediaKey>(LibraryKeys.libraryKeyOf(FakeMediaLibrary.assetAt(0))),
    );
    await tester.tapAt(tester.getTopRight(cell) + const Offset(-10, 10));
    await tester.pumpAndSettle();
    expect(rig.selection.length, 1);

    await tester.tap(find.byKey(const ValueKey('attach-files-gallery-send')));
    await tester.pumpAndSettle();

    final outcome = rig.outcome! as AttachOutcome$Send;
    expect(outcome.request.options.asFiles, isTrue);
    expect(outcome.request.items.single.kind, AttachKind.photo);
    final plan = planSend(
      outcome.request,
      const AttachPolicy.android(),
      const AttachLimits(),
    );
    expect(
      ((plan as SendPlan$Ready).sends.single as PlannedSend$Single).form,
      SendForm.file,
    );
  });
}
