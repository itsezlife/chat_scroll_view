import 'package:attach_model/attach_model.dart';
import 'package:attach_model/testing.dart';
import 'package:attach_sheet/attach_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_capture/mpx_capture.dart';
import 'package:mpx_capture/testing.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_core/testing.dart';
import 'package:mpx_library/mpx_library.dart';
import 'package:mpx_library/testing.dart';
import 'package:mpx_ui/mpx_ui.dart';

import '../page/pages_rig.dart';

final class _Host extends AttachSheetHost {
  final interactions = <AttachInteraction>[];

  @override
  void interaction(AttachInteraction interaction) =>
      interactions.add(interaction);
}

MediaKey _key(int index) =>
    LibraryKeys.libraryKeyOf(FakeMediaLibrary.assetAt(index));

void main() {
  late FakeMediaLibrary library;
  late PlaybackClock clock;
  late AssetCacheScope scope;

  setUp(() {
    library = FakeMediaLibrary(assets: 300);
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
    FakeMediaLibrary? source,
    GalleryCamera? camera,
    Size size = const Size(400, 800),
  }) async {
    final rig = await PagesRig.open(
      tester,
      size: size,
      policy: const AttachSheetPolicy.android(),
      limits: limits,
      host: host,
      wrap: (app) => AssetCacheProvider(scope: scope, child: app),
      pages: [
        GalleryPage.create(
          library: source ?? library,
          camera: camera,
          label: 'Gallery',
          icon: const SizedBox(width: 24, height: 24),
        ),
        rowsPage('files'),
      ],
    );
    await tester.pumpAndSettle();
    return rig;
  }

  Finder cell(int index) => find.byKey(ValueKey<MediaKey>(_key(index)));

  Future<void> tapCheck(WidgetTester tester, int index) async {
    await tester.tapAt(tester.getTopRight(cell(index)) + const Offset(-10, 10));
    await tester.pumpAndSettle();
  }

  testWidgets('a library pick takes the next order number after a file', (
    tester,
  ) async {
    final rig = await open(tester);
    rig.selection.toggle(AttachItems.file('f'));

    await tapCheck(tester, 0);

    expect(rig.selection.length, 2);
    final picked = rig.selection.items.last;
    expect(
      picked.source,
      AttachSource.library(FakeMediaLibrary.assetAt(0).id.value),
    );
    expect(picked.kind, AttachKind.photo);
    expect(picked.facts.dimensions, const AttachDimensions(4032, 3024));
    expect(tester.widget<LibraryGridCell>(cell(0)).order, 2);
  });

  testWidgets('a video asset becomes a video item', (tester) async {
    final rig = await open(tester);
    await tapCheck(tester, 3);
    expect(rig.selection.items.single.kind, AttachKind.video);
  });

  testWidgets('the 101st pick is refused and raised to the host', (
    tester,
  ) async {
    final host = _Host();
    final rig = await open(tester, host: host);
    for (var i = 0; i < 100; i++) {
      rig.selection.toggle(AttachItems.photo('p$i'));
    }
    await tester.pumpAndSettle();
    expect(tester.widget<LibraryGridCell>(cell(0)).dimmed, isTrue);

    await tapCheck(tester, 0);

    expect(rig.selection.length, 100);
    expect(host.interactions, [
      const AttachInteraction.refused(AttachRefusal.capReached),
    ]);
  });

  testWidgets('a kind the limits forbid is dimmed and refused', (tester) async {
    final host = _Host();
    final rig = await open(
      tester,
      host: host,
      limits: const AttachLimits(allowedKinds: {AttachKind.photo}),
    );
    expect(tester.widget<LibraryGridCell>(cell(3)).dimmed, isTrue);
    expect(tester.widget<LibraryGridCell>(cell(0)).dimmed, isFalse);

    await tapCheck(tester, 3);

    expect(rig.selection.isEmpty, isTrue);
    expect(host.interactions, [
      const AttachInteraction.refused(AttachRefusal.kindNotAllowed),
    ]);
  });

  testWidgets('the header carries the overflow menu', (tester) async {
    await open(tester);
    expect(find.byKey(const ValueKey('attach-overflow')), findsOneWidget);
  });

  testWidgets('without access the page offers it; denied opens settings', (
    tester,
  ) async {
    final denied = FakeMediaLibrary(access: LibraryAccess.denied);
    addTearDown(denied.dispose);
    await open(tester, source: denied);
    expect(find.text('Access to media'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mpx-denied-access')));
    await tester.pump();
    expect(denied.openSettingsCalls, 1);
  });

  testWidgets('a library not yet asked is asked on open', (tester) async {
    final fresh = FakeMediaLibrary(
      assets: 5,
      access: LibraryAccess.notDetermined,
    );
    addTearDown(fresh.dispose);
    await open(tester, source: fresh);
    expect(fresh.requestAccessCalls, 1);
    expect(cell(0), findsOneWidget);
  });

  test('the grid policy follows the sheet family', () {
    expect(
      const AttachSheetPolicy.android().libraryGrid,
      LibraryGridPolicy.$Android,
    );
    expect(const AttachSheetPolicy.ios().libraryGrid, LibraryGridPolicy.$IOS);
  });

  group('camera', () {
    testWidgets('the first cell is the live preview; a tap opens the '
        'capture surface', (tester) async {
      final sessions = FakeCameraSessions();
      // Wide enough for the capture surface's controls in the test font.
      await open(
        tester,
        size: const Size(1200, 900),
        camera: GalleryCamera(sessions: sessions, outputDirectory: '/tmp'),
      );
      expect(sessions.openCount, 1);
      expect(find.byType(CameraSlotPreview), findsOneWidget);

      await tester.tap(find.byType(CameraSlotPreview));
      await tester.pumpAndSettle();
      expect(find.byType(CameraCaptureSurface), findsOneWidget);
    });

    testWidgets('a long press takes a photo with the system camera, first', (
      tester,
    ) async {
      final intake = FakeFileIntake()
        ..enqueueCapture(
          const IntakeFile(
            source: IntakeSource.path('/dcim/shot.jpg'),
            name: 'shot.jpg',
            size: 2000,
            mimeType: 'image/jpeg',
          ),
        );
      final rig = await open(
        tester,
        camera: GalleryCamera(
          sessions: FakeCameraSessions(),
          outputDirectory: '/tmp',
          systemCamera: intake,
        ),
      );
      await tapCheck(tester, 0);
      await tester.longPress(find.byType(CameraSlotPreview));
      await tester.pumpAndSettle();

      expect(intake.captureRequests, [IntakeCaptureKind.photo]);
      expect(
        rig.selection.items.first.source,
        const AttachSource.captured('/dcim/shot.jpg'),
      );
      expect(rig.selection.orderOf(rig.selection.items.last.id), 2);
    });

    testWidgets('a denied camera falls back to the system camera', (
      tester,
    ) async {
      final intake = FakeFileIntake()..enqueueCapture(null);
      await open(
        tester,
        camera: GalleryCamera(
          sessions: FakeCameraSessions(allowed: false),
          outputDirectory: '/tmp',
          systemCamera: intake,
        ),
      );
      final camera = find.text('Camera');
      if (camera.evaluate().isNotEmpty) {
        await tester.tap(camera.first);
        await tester.pumpAndSettle();
      } else {
        await tester.tap(find.byType(CameraSlotPreview));
        await tester.pumpAndSettle();
      }
      expect(intake.captureRequests, isNotEmpty);
    });
  });

  testWidgets('the viewer carries the caption and sends the item shown when '
      'nothing is selected', (tester) async {
    final rig = await open(tester, size: const Size(800, 1200));
    await tester.tap(cell(1));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final sends = find.byKey(const ValueKey('attach-send'));
    expect(sends, findsWidgets);
    await tester.tap(sends.last);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final outcome = rig.outcome! as AttachOutcome$Send;
    expect(
      outcome.request.items.single.source,
      AttachSource.library(FakeMediaLibrary.assetAt(1).id.value),
    );
  });

  testWidgets('the header carries the album switcher', (tester) async {
    await open(tester);
    expect(find.byType(LibraryAlbumSwitcher), findsOneWidget);
  });
}
