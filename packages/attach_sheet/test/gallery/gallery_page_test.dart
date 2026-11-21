import 'dart:async';
import 'dart:io';

import 'dart:math' as math;

import 'package:attach_model/attach_model.dart';
import 'package:attach_model/testing.dart';
import 'package:attach_sheet/attach_sheet.dart';
import 'package:chat_composer/chat_composer.dart';
import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:content_model/content_model.dart' as content;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_bytes_cache/http_bytes_cache.dart';
import 'package:mpx_capture/mpx_capture.dart';
import 'package:mpx_capture/testing.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_core/testing.dart';
import 'package:mpx_library/mpx_library.dart';
import 'package:mpx_library/testing.dart';
import 'package:mpx_player/mpx_player.dart';
import 'package:mpx_player/testing.dart';
import 'package:mpx_ui/mpx_ui.dart';
import 'package:viewport_scroll/viewport_scroll.dart';

import '../page/fake_caption_dock.dart';
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
  late FakeAssetProducer producer;

  setUp(() {
    library = FakeMediaLibrary(assets: 300);
    clock = PlaybackClock(ticks: ManualPlaybackTickSource());
    producer = FakeAssetProducer();
    scope = AssetCacheScope(producer: producer, clock: clock);
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
    PlayerPool? players,
    Size size = const Size(400, 800),
    bool viewBottomPadding = false,
    AttachPolicy attachPolicy = const AttachPolicy.android(),
    AttachSheetPolicy policy = const AttachSheetPolicy.android(),
  }) async {
    final rig = await PagesRig.open(
      tester,
      size: size,
      viewBottomPadding: viewBottomPadding,
      policy: policy,
      attachPolicy: attachPolicy,
      limits: limits,
      host: host,
      wrap: (app) => AssetCacheProvider(scope: scope, child: app),
      pages: [
        GalleryPage.create(
          library: source ?? library,
          camera: camera,
          players: players,
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

  testWidgets('the overflow menu stands in the pinned bar, and in the header '
      'while something is selected', (tester) async {
    final rig = await open(tester);
    final overflow = find.byKey(const ValueKey('attach-overflow'));
    final pinnedBar = find.byKey(const ValueKey('attach-sheet-header'));
    final header = find.byKey(const ValueKey('attach-selection-header'));
    expect(find.descendant(of: pinnedBar, matching: overflow), findsOneWidget);
    expect(find.descendant(of: header, matching: overflow), findsOneWidget);
    // Nothing selected: the header's is not there to tap.
    expect(
      find.descendant(of: header, matching: overflow).hitTestable(),
      findsNothing,
    );
    await tapCheck(tester, 0);
    expect(rig.selection.length, 1);
    expect(
      find.descendant(of: header, matching: overflow).hitTestable(),
      findsOneWidget,
    );
  });

  testWidgets('without access the page offers it; denied opens settings', (
    tester,
  ) async {
    final denied = FakeMediaLibrary(access: LibraryAccess.denied);
    addTearDown(denied.dispose);
    await open(tester, source: denied);
    expect(find.text('Access to media'), findsOneWidget);
    // The page is laid out at the sheet's full height: at its top the
    // button is clear of the tab bar.
    unawaited(
      AttachSheetController.of(
        tester.element(find.text('Access to media')),
      ).expand(),
    );
    await tester.pumpAndSettle();

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

  group("a swipe selection held at the screen's edges", () {
    testWidgets('a finger held still at the bottom raises the sheet all '
        'the way to its top, then scrolls the grid, as long as it stays', (
      tester,
    ) async {
      final rig = await open(tester);
      final rest = rig.top;
      expect(rest, greaterThan(24), reason: 'the sheet is not at its top');
      final grid = tester
          .widget<LibraryPicker>(find.byType(LibraryPicker))
          .controller!;
      final gesture = await tester.startGesture(tester.getCenter(cell(4)));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
      await gesture.moveTo(const Offset(200, 790));
      // Then still: no more pointer events while the sheet and the grid
      // move under it.
      final tops = <double>[];
      for (var i = 0; i < 120; i++) {
        // A tremor of the held finger while the sheet moves under it: its
        // event's own local position is through the grid's place at the
        // down, so the grid reads it against where it is now.
        if (i == 10) await gesture.moveBy(const Offset(0, 1));
        await tester.pump(const Duration(milliseconds: 16));
        tops.add(rig.top);
      }
      expect(rig.top, lessThanOrEqualTo(24 + 0.5), reason: 'at its top');
      for (var i = 1; i < tops.length; i++) {
        expect(tops[i], lessThanOrEqualTo(tops[i - 1]), reason: 'never back');
      }
      final scrolled = grid.offset;
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        grid.offset,
        greaterThan(scrolled + 100),
        reason: 'the grid goes on',
      );
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('the bottom edge raises a sheet that is not at its top; '
        "the sheet's top edge never moves it", (tester) async {
      final rig = await open(tester);
      final rest = rig.top;
      expect(rest, greaterThan(24), reason: 'the sheet is not at its top');
      final gesture = await tester.startGesture(tester.getCenter(cell(4)));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 20));
      // At the screen's bottom: the grid's band on its part on screen.
      await gesture.moveTo(const Offset(200, 798));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      final raised = rig.top;
      expect(raised, lessThan(rest - 20));

      // Up at the sheet's own top edge: the sheet stays.
      await gesture.moveTo(Offset(200, raised + 4));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(rig.top, lessThanOrEqualTo(raised));
      final held = rig.top;
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(rig.top, held);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(rig.top, held, reason: 'the selection leaves it where it is');
      expect(rig.selection.isNotEmpty, isTrue);
    });
  });

  group('camera', () {
    testWidgets('the live preview fades out with its page on a switch, '
        'gone by 0.7 of the out phase, and is whole again on return', (
      tester,
    ) async {
      final rig = await open(
        tester,
        camera: GalleryCamera(
          sessions: FakeCameraSessions(),
          outputDirectory: '/tmp',
          cache: CaptureCache(store: MemoryBytesCache()),
        ),
      );
      double camera() => tester
          .widget<Opacity>(
            find.byKey(
              const ValueKey('attach-gallery-camera-presence'),
              skipOffstage: false,
            ),
          )
          .opacity;
      expect(camera(), 1);
      await tester.tap(rig.tab('files'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 45));
      final early = camera();
      expect(early, inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 100));
      expect(camera(), 0, reason: 'past 0.7 of the phase');
      await tester.pumpAndSettle();
      await tester.tap(rig.tab('gallery'));
      await tester.pumpAndSettle();
      expect(camera(), 1);
    });

    testWidgets('the first cell is the live preview; a tap opens the '
        'capture surface', (tester) async {
      final sessions = FakeCameraSessions();
      // Wide enough for the capture surface's controls in the test font.
      await open(
        tester,
        size: const Size(1200, 900),
        camera: GalleryCamera(
          sessions: sessions,
          outputDirectory: '/tmp',
          cache: CaptureCache(store: MemoryBytesCache()),
        ),
      );
      expect(sessions.openCount, 1);
      expect(find.byType(CameraSlotPreview), findsOneWidget);

      await tester.tap(find.byType(CameraSlotPreview));
      await tester.pumpAndSettle();
      expect(find.byType(CameraCaptureSurface), findsOneWidget);
    });

    testWidgets('a shot lands in the capture cache under a local key, joins '
        'the grid ahead of the library and the selection last, and the '
        'first opens the viewer on it', (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('attach-capture'),
      ))!;
      addTearDown(() => directory.deleteSync(recursive: true));
      final store = MemoryBytesCache();
      final rig = await open(
        tester,
        size: const Size(1200, 900),
        camera: GalleryCamera(
          sessions: FakeCameraSessions(),
          outputDirectory: directory.path,
          cache: CaptureCache(store: store),
        ),
      );
      rig.selection.toggle(AttachItems.file('f'));
      await tester.tap(find.byType(CameraSlotPreview));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mpx-capture-shutter')));
      // The surface reads the shot for its strip, then keeps it: real IO.
      for (
        var i = 0;
        i < 50 &&
            tester
                .widget<LibraryPicker>(
                  find.byType(LibraryPicker, skipOffstage: false),
                )
                .captures!
                .value
                .isEmpty;
        i++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }

      final captures = tester
          .widget<LibraryPicker>(
            find.byType(LibraryPicker, skipOffstage: false),
          )
          .captures!
          .value;
      expect(captures, hasLength(1));
      final key = captures.single.key;
      expect(
        await tester.runAsync(() => store.read(CaptureCache.cacheKeyOf(key))),
        isNotNull,
      );
      final item = rig.selection.items.last;
      expect(item.source, AttachSource.captured(key.encoded));
      expect(rig.selection.orderOf(item.id), 2);

      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byKey(const ValueKey('attach-viewer-slot')), findsOneWidget);
    });

    testWidgets('Android: the surface keeps its own policy, the strip tiles '
        "are the host's, and removing a shot drops it", (tester) async {
      await open(
        tester,
        size: const Size(1200, 900),
        camera: GalleryCamera(
          sessions: FakeCameraSessions(),
          outputDirectory: '/tmp',
          cache: CaptureCache(store: MemoryBytesCache()),
        ),
      );
      await tester.tap(find.byType(CameraSlotPreview));
      await tester.pumpAndSettle();
      final surface = tester.widget<CameraCaptureSurface>(
        find.byType(CameraCaptureSurface),
      );
      expect(surface.policy, CaptureSurfacePolicy.$Android);
      expect(surface.labels.videoMode, 'Video');
      expect(surface.labels.photoMode, 'Photo');
      expect(surface.resultBuilder, isNull, reason: "the strip's own cells");
      expect(surface.shotOrder, isNotNull);
      expect(surface.onShotRemoved, isNotNull);
    });

    testWidgets('iOS: the surface takes the iOS policy with its mode names, '
        'and the grid opens the viewer on every 10th capture', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      await open(
        tester,
        size: const Size(1200, 900),
        policy: const AttachSheetPolicy.ios(),
        camera: GalleryCamera(
          sessions: FakeCameraSessions(),
          outputDirectory: '/tmp',
          cache: CaptureCache(store: MemoryBytesCache()),
        ),
      );
      expect(
        tester
            .widget<LibraryPicker>(find.byType(LibraryPicker))
            .policy
            .captureViewerEvery,
        10,
      );
      await tester.tap(find.byType(CameraSlotPreview));
      await tester.pumpAndSettle();
      final surface = tester.widget<CameraCaptureSurface>(
        find.byType(CameraCaptureSurface),
      );
      expect(surface.policy, CaptureSurfacePolicy.$IOS);
      expect(surface.labels.videoMode, 'Video');
      debugDefaultTargetPlatformOverride = null;
    });

    // Holds the shutter past the record delay, lets the session answer,
    // and lifts.
    Future<void> holdShutter(WidgetTester tester) async {
      final hold = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('mpx-capture-shutter'))),
      );
      await tester.pump(
        CameraCaptureSurface.holdToRecord + const Duration(milliseconds: 50),
      );
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      await hold.up();
      await tester.pump();
    }

    testWidgets('with video restricted the surface takes photos, and a hold '
        'tells the host videos are not allowed', (tester) async {
      final host = _Host();
      await open(
        tester,
        size: const Size(1200, 900),
        host: host,
        limits: const AttachLimits(allowedKinds: {AttachKind.photo}),
        camera: GalleryCamera(
          sessions: FakeCameraSessions(),
          outputDirectory: '/tmp',
          cache: CaptureCache(store: MemoryBytesCache()),
        ),
      );
      await tester.tap(find.byType(CameraSlotPreview));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<CameraCaptureSurface>(find.byType(CameraCaptureSurface))
            .kinds,
        CaptureKinds.photo,
      );
      await holdShutter(tester);
      expect(host.interactions, [
        const AttachInteraction.videoRefused(AttachVideoRefusal.notAllowed),
      ]);
    });

    testWidgets('a hold without the microphone asks for it; refused, the '
        'host hears it and nothing is recorded', (tester) async {
      final host = _Host();
      final sessions = FakeCameraSessions(
        microphone: MicrophoneAccess.notDetermined,
        microphoneOnRequest: MicrophoneAccess.denied,
      );
      final rig = await open(
        tester,
        size: const Size(1200, 900),
        host: host,
        camera: GalleryCamera(
          sessions: sessions,
          outputDirectory: '/tmp',
          cache: CaptureCache(store: MemoryBytesCache()),
        ),
      );
      await tester.tap(find.byType(CameraSlotPreview));
      await tester.pumpAndSettle();
      await holdShutter(tester);
      expect(sessions.microphoneRequests, 1);
      expect(host.interactions, [
        const AttachInteraction.videoRefused(AttachVideoRefusal.microphone),
      ]);
      expect(rig.selection.isEmpty, isTrue);
    });

    group('the capture flow', () {
      late Directory directory;
      late MemoryBytesCache store;

      // The gallery with a camera writing into a real folder, the surface
      // open.
      Future<PagesRig> openCamera(
        WidgetTester tester, {
        AttachLimits limits = const AttachLimits(),
        AttachSheetHost host = const AttachSheetHost(),
      }) async {
        directory = (await tester.runAsync(
          () => Directory.systemTemp.createTemp('attach-flow'),
        ))!;
        addTearDown(() => directory.deleteSync(recursive: true));
        store = MemoryBytesCache();
        final rig = await open(
          tester,
          size: const Size(1200, 900),
          limits: limits,
          host: host,
          camera: GalleryCamera(
            sessions: FakeCameraSessions(),
            outputDirectory: directory.path,
            cache: CaptureCache(store: store),
          ),
        );
        await tester.tap(find.byType(CameraSlotPreview));
        await tester.pumpAndSettle();
        return rig;
      }

      Future<void> settle(WidgetTester tester) async {
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
      }

      int landed(WidgetTester tester) => tester
          .widget<LibraryPicker>(
            find.byType(LibraryPicker, skipOffstage: false),
          )
          .captures!
          .value
          .length;

      // Waits in real time for the shot to land: the surface reads it for
      // its strip and keeps it in the cache, and a recording's poster is
      // kept too.
      Future<void> waitForShot(WidgetTester tester, int before) async {
        for (var i = 0; i < 50 && landed(tester) == before; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        await settle(tester);
      }

      Future<void> shoot(WidgetTester tester) async {
        final before = landed(tester);
        await tester.tap(find.byKey(const ValueKey('mpx-capture-shutter')));
        await waitForShot(tester, before);
      }

      final viewer = find.byKey(const ValueKey('attach-viewer-slot'));
      final addPhoto = find.byKey(const ValueKey('attach-caption-add-photo'));

      List<PickerCapture> capturesOf(WidgetTester tester) => tester
          .widget<LibraryPicker>(
            find.byType(LibraryPicker, skipOffstage: false),
          )
          .captures!
          .value;

      Future<void> back(WidgetTester tester) async {
        await tester.binding.handlePopRoute();
        await settle(tester);
      }

      testWidgets('the surface shows the shots this open keeps, counted in '
          "the host's words, numbered by the selection; the first shot "
          'changes nothing on the camera until add-photo', (tester) async {
        final rig = await openCamera(tester);
        final surface = tester.widget<CameraCaptureSurface>(
          find.byType(CameraCaptureSurface),
        );
        expect(surface.shots, isNotNull);
        expect(surface.onShotsTap, isNotNull);
        expect(surface.resultBuilder, isNull);
        expect(surface.labels.shotsCount!(1, 0), '1 PHOTO');
        expect(surface.labels.shotsCount!(3, 0), '3 PHOTOS');
        expect(surface.labels.shotsCount!(0, 2), '2 VIDEOS');
        expect(surface.labels.shotsCount!(2, 3), '5 MEDIA');

        await shoot(tester);
        expect(viewer, findsOneWidget);
        expect(surface.shots!.value, isEmpty, reason: 'no strip, no counter');
        // Add-photo keeps the shot: back on the camera the strip shows it.
        await tester.tap(addPhoto);
        await settle(tester);
        expect(surface.shots!.value, hasLength(1));
        expect(
          find.byKey(const ValueKey('mpx-capture-counter')),
          findsOneWidget,
        );
        final shot = surface.shots!.value.single;
        expect(surface.shotOrder!(shot), 1);

        // The strip's tap toggles it in the selection, and the strip hears.
        var heard = 0;
        void listener() => heard++;
        surface.shotSelection!.addListener(listener);
        addTearDown(() => surface.shotSelection!.removeListener(listener));
        surface.onShotToggle!(shot);
        await tester.pump();
        expect(rig.selection.isEmpty, isTrue);
        expect(surface.shotOrder!(shot), isNull);
        expect(heard, greaterThan(0));
        surface.onShotToggle!(shot);
        expect(surface.shotOrder!(shot), 1);

        // A later shot joins the strip at once, with the next number.
        await shoot(tester);
        expect(viewer, findsNothing);
        expect(surface.shots!.value, hasLength(2));
        expect(surface.shotOrder!(surface.shots!.value.last), 2);
      });

      testWidgets("the strip lists the grid's album after the shots: its "
          'items by their library keys, a video with its duration, and a '
          'tap picks one into the attach selection', (tester) async {
        final rig = await openCamera(tester);
        final surface = tester.widget<CameraCaptureSurface>(
          find.byType(CameraCaptureSurface),
        );
        final album = surface.gallery!;
        expect(album.count, greaterThan(0));
        // Read as the grid read it: the same pages.
        final first = album.itemAt(0, thumbnailPixels: 80)!;
        expect(first.key, LibraryKeys.keyOf(FakeMediaLibrary.assetAt(0).id));
        expect(first.thumbnail.kind, MediaKind.still);
        expect(album.itemAt(3, thumbnailPixels: 80)!.duration, isNotNull);
        expect(first.duration, isNull);

        expect(surface.galleryOrder!(first.key), isNull);
        surface.onGalleryToggle!(first.key);
        expect(surface.galleryOrder!(first.key), 1);
        expect(rig.selection.items.single.id.value, 'library:asset-0');
        surface.onGalleryToggle!(first.key);
        expect(rig.selection.isEmpty, isTrue);
      });

      testWidgets("the strip's album lives through the camera page's close: "
          'every frame of it rebuilds the page with the album still in use, '
          'and it goes with the page', (tester) async {
        await openCamera(tester);
        final album =
            tester
                    .widget<CameraCaptureSurface>(
                      find.byType(CameraCaptureSurface),
                    )
                    .gallery!
                as ChangeNotifier;
        var notified = 0;
        void count() => notified++;
        await tester.tap(find.byKey(const ValueKey('mpx-capture-close')));
        for (var ms = 0; ms < 300; ms += 16) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.takeException(), isNull, reason: '$ms ms');
          if (find.byType(CameraCaptureSurface).evaluate().isEmpty) break;
          // Still alive: a listener may join it, as the page's do.
          album
            ..addListener(count)
            ..removeListener(count);
        }
        await settle(tester);
        expect(find.byType(CameraCaptureSurface), findsNothing);
        expect(tester.takeException(), isNull);
        expect(
          () => album.addListener(count),
          throwsFlutterError,
          reason: 'freed once the page is gone',
        );
        expect(notified, 0);
      });

      testWidgets('the viewer from the camera pages every medium, the shots '
          'then the album, with no dismiss drag', (tester) async {
        await openCamera(tester);
        await shoot(tester);
        var media = tester.widget<MediaViewer>(find.byType(MediaViewer));
        expect(media.source.count, 1 + 300);
        expect(media.policy?.dismissDrag, isFalse);
        await tester.tap(addPhoto);
        await settle(tester);
        await shoot(tester);
        await tester.tap(find.byKey(const ValueKey('mpx-capture-counter')));
        await settle(tester);
        media = tester.widget<MediaViewer>(find.byType(MediaViewer));
        expect(media.source.count, 2 + 300);
        expect(media.policy?.dismissDrag, isFalse);
      });

      testWidgets("a recording's poster is kept as a still under its own key "
          "and is the grid's thumbnail for it; it goes with the shot", (
        tester,
      ) async {
        await openCamera(tester);
        final hold = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('mpx-capture-shutter'))),
        );
        await tester.pump(
          CameraCaptureSurface.holdToRecord + const Duration(milliseconds: 50),
        );
        for (var i = 0; i < 4; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        await hold.up();
        await waitForShot(tester, 0);

        final capture = capturesOf(tester).single;
        expect(capture.kind, LibraryAssetKind.video);
        final poster = capture.thumbnail;
        expect(poster, isNotNull);
        expect(poster, isNot(capture.key));
        expect(
          await tester.runAsync(
            () => store.read(CaptureCache.cacheKeyOf(poster!)),
          ),
          isNotNull,
        );
        // The grid draws the poster for the recording, as a still.
        final asset = capture.asset;
        expect(PickerCaptureKeys.thumbnailKeyOf(asset, 100), poster);
        expect(
          PickerCaptureKeys.thumbnailDescriptorOf(asset, 100).kind,
          MediaKind.still,
        );

        // Back from its viewer takes both away.
        await back(tester);
        expect(capturesOf(tester), isEmpty);
        expect(
          await tester.runAsync(
            () => store.read(CaptureCache.cacheKeyOf(poster!)),
          ),
          isNull,
        );
      });

      testWidgets('the first shot opens the viewer on it, whose page asks '
          "for the capture's own picture at the page's size", (tester) async {
        await openCamera(tester);
        await shoot(tester);
        expect(viewer, findsOneWidget);
        final key = capturesOf(tester).single.key;

        expect(producer.known.map((d) => d.key), contains(key));
        expect(
          producer.attempts
              .where((a) => a.request.key == key)
              .map((a) => a.request.spec.pixelHeight)
              .fold<int>(0, math.max),
          greaterThan(300),
          reason: 'the full picture, not a cell',
        );
      });

      testWidgets('back from the first shot takes it back: out of the '
          'captures, the shots, the selection and the cache', (tester) async {
        final rig = await openCamera(tester);
        await shoot(tester);
        final key = capturesOf(tester).single.key;
        await back(tester);

        expect(viewer, findsNothing);
        expect(find.byType(CameraCaptureSurface), findsOneWidget);
        expect(capturesOf(tester), isEmpty);
        expect(
          tester
              .widget<CameraCaptureSurface>(find.byType(CameraCaptureSurface))
              .shots!
              .value,
          isEmpty,
        );
        expect(rig.selection.isEmpty, isTrue);
        expect(
          await tester.runAsync(() => store.read(CaptureCache.cacheKeyOf(key))),
          isNull,
        );
      });

      testWidgets('add-photo leads the caption; a burst of taps closes the '
          'viewer once and keeps the shot; back from the counter later '
          'discards every shot of the session', (tester) async {
        final rig = await openCamera(tester);
        await shoot(tester);
        expect(addPhoto, findsOneWidget);
        expect(
          find.byKey(const ValueKey('attach-caption-panel')),
          findsNothing,
        );
        for (var i = 0; i < 5; i++) {
          await tester.tap(addPhoto, warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 16));
        }
        await settle(tester);

        expect(viewer, findsNothing);
        expect(find.byType(CameraCaptureSurface), findsOneWidget);
        expect(capturesOf(tester), hasLength(1));
        expect(rig.selection.length, 1);

        // A second shot: the viewer stays shut; the counter opens it, and
        // back takes the camera session's shots back, both of them.
        await shoot(tester);
        expect(viewer, findsNothing);
        expect(capturesOf(tester), hasLength(2));
        final keys = [for (final c in capturesOf(tester)) c.key];
        await tester.tap(find.byKey(const ValueKey('mpx-capture-counter')));
        await settle(tester);
        expect(viewer, findsOneWidget);
        await back(tester);
        expect(viewer, findsNothing);
        expect(capturesOf(tester), isEmpty);
        expect(rig.selection.isEmpty, isTrue);
        for (final key in keys) {
          expect(
            await tester.runAsync(
              () => store.read(CaptureCache.cacheKeyOf(key)),
            ),
            isNull,
          );
        }
      });

      testWidgets('the counter over one shot opens the viewer; back then '
          'takes that shot back', (tester) async {
        final rig = await openCamera(tester);
        await shoot(tester);
        await tester.tap(addPhoto);
        await settle(tester);
        // A burst on the counter opens one viewer.
        for (var i = 0; i < 3; i++) {
          await tester.tap(
            find.byKey(const ValueKey('mpx-capture-counter')),
            warnIfMissed: false,
          );
          await tester.pump(const Duration(milliseconds: 16));
        }
        await settle(tester);
        expect(viewer, findsOneWidget);
        await back(tester);
        expect(viewer, findsNothing);
        expect(capturesOf(tester), isEmpty);
        expect(rig.selection.isEmpty, isTrue);
      });

      testWidgets('a tap on add-photo while the caption is focused does '
          'nothing; focused, the panel button leads', (tester) async {
        await openCamera(tester);
        await shoot(tester);
        final bar = tester.state(find.byType(AttachCaptionBar));
        final caption = (bar.widget as AttachCaptionBar).caption!;
        final onTap = tester
            .widget<ComposerView>(find.byKey(const ValueKey('attach-caption')))
            .spec
            .actions
            .firstWhere((a) => a.id == 'attach-caption-add-photo')
            .onTap!;
        caption.requestFocus();
        await tester.pump();
        await tester.pump();
        expect(caption.focusNode.hasFocus, isTrue);
        expect(addPhoto, findsNothing);
        onTap();
        await settle(tester);
        expect(viewer, findsOneWidget);
      });

      testWidgets('on a dock, add-photo and the panel button share the '
          'leading place: the panel button while the panel is up, add-photo '
          'again when it goes', (tester) async {
        final host = DockHost();
        await openCamera(tester, host: host);
        await shoot(tester);
        final panelButton = find.byKey(const ValueKey('attach-caption-panel'));
        expect(addPhoto, findsOneWidget);
        expect(panelButton, findsNothing);

        final dock = host.docks.last;
        dock.show(panel: true);
        await tester.pump();
        expect(addPhoto, findsNothing);
        expect(panelButton, findsOneWidget);

        dock.show(panel: false);
        await tester.pump();
        expect(addPhoto, findsOneWidget);
        expect(panelButton, findsNothing);
      });

      testWidgets('with one item allowed there is no add-photo', (
        tester,
      ) async {
        await openCamera(
          tester,
          limits: const AttachLimits(singleSelect: true),
        );
        await shoot(tester);
        expect(viewer, findsOneWidget);
        expect(addPhoto, findsNothing);
      });

      testWidgets("a viewer opened from the grid is not the camera's: no "
          'add-photo, and back keeps the shot', (tester) async {
        await openCamera(tester);
        await shoot(tester);
        await tester.tap(addPhoto);
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('mpx-capture-close')));
        await tester.pumpAndSettle();
        expect(find.byType(CameraCaptureSurface), findsNothing);

        final key = capturesOf(tester).single.key;
        // The capture's cell in the grid opens the viewer on it.
        await tester.tap(find.byKey(ValueKey<MediaKey>(key)));
        await settle(tester);
        expect(viewer, findsOneWidget);
        expect(addPhoto, findsNothing);
        await back(tester);
        expect(capturesOf(tester), hasLength(1));
      });
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
          cache: CaptureCache(store: MemoryBytesCache()),
          systemCamera: intake,
        ),
      );
      await tapCheck(tester, 0);
      await tester.longPress(find.byType(CameraSlotPreview));
      await tester.pumpAndSettle();

      expect(intake.captureRequests, [IntakeCaptureKind.photo]);
      expect(
        rig.selection.items.first.source,
        const AttachSource.file('/dcim/shot.jpg'),
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
          cache: CaptureCache(store: MemoryBytesCache()),
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

  testWidgets("the viewer's bottom is the floating caption bar with Send "
      'beside it, on the safe area, in the chrome face; its strip reorders '
      'into the attach selection', (tester) async {
    final rig = await open(tester, size: const Size(800, 1200));
    rig.selection.toggle(AttachItems.file('f'));
    await tapCheck(tester, 0);
    await tapCheck(tester, 1);
    expect(
      tester.widget<LibraryPicker>(find.byType(LibraryPicker)).onReorder,
      isNotNull,
    );
    await tester.tap(cell(2));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final slot = find.byKey(const ValueKey('attach-viewer-slot'));
    expect(slot, findsOneWidget);
    final pill = find.descendant(
      of: slot,
      matching: find.byKey(const ValueKey('attach-caption')),
    );
    final send = find.descendant(
      of: slot,
      matching: find.byKey(const ValueKey('attach-send')),
    );
    // The chat's own composer, its island and margins, with Send beside it.
    expect(pill, findsOneWidget);
    expect(tester.widget(pill), isA<ComposerView>());
    expect(
      tester.getRect(send).left,
      greaterThanOrEqualTo(tester.getRect(pill).right),
    );
    expectChromeText(tester, within: slot);

    final chrome = tester.widget<PickerViewerChrome>(
      find.byType(PickerViewerChrome),
    );
    chrome.onReorder!(_key(1), 0);
    final focus = tester.widget<ComposerView>(pill).controller.focusNode;
    await tester.tap(pill);
    await tester.pump();
    expect(focus.hasFocus, isTrue);
    // Any close of the viewer takes the keyboard down.
    await tester.binding.handlePopRoute();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(slot, findsNothing);
    expect(focus.hasFocus, isFalse);
    expect(rig.selection.items.map((item) => item.id.value), [
      'f',
      'library:${FakeMediaLibrary.assetAt(1).id.value}',
      'library:${FakeMediaLibrary.assetAt(0).id.value}',
    ]);
  });

  testWidgets("the viewer's caption bar stands at max(keyboard, safe area) "
      'over the bottom at every frame of the keyboard going from 358 to 0: '
      'no dip below its rest', (tester) async {
    final rig = await open(
      tester,
      size: const Size(800, 1200),
      viewBottomPadding: true,
    );
    rig.selection.toggle(AttachItems.file('f'));
    final ratio = tester.view.devicePixelRatio;
    tester.view
      ..padding = FakeViewPadding(bottom: 34 * ratio)
      ..viewPadding = FakeViewPadding(bottom: 34 * ratio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);
    addTearDown(tester.view.resetViewInsets);
    await tester.tap(cell(1));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final screen = tester.view.physicalSize.height / ratio;
    final pill = find.descendant(
      of: find.byKey(const ValueKey('attach-viewer-slot')),
      matching: find.byKey(const ValueKey('attach-caption')),
    );
    double lift() => screen - tester.getRect(pill).bottom;
    final rest = lift();
    expect(rest, closeTo(34, 0.5), reason: 'on the safe area, once');

    tester.view
      ..padding = FakeViewPadding.zero
      ..viewInsets = FakeViewPadding(bottom: 358 * ratio);
    await tester.pump();
    final up = lift();
    expect(up - rest, closeTo(358 - 34, 0.5), reason: 'on the keyboard');
    for (var inset = 358.0; inset >= 0; inset -= 17) {
      final now = inset < 17 ? 0.0 : inset;
      tester.view
        ..viewInsets = FakeViewPadding(bottom: now * ratio)
        ..padding = FakeViewPadding(bottom: math.max(0, 34 - now) * ratio);
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        lift(),
        closeTo(rest + math.max(now, 34) - 34, 0.5),
        reason: 'keyboard $now',
      );
    }
    expect(lift(), closeTo(rest, 0.5));
  });

  group("the viewer's caption, on a dock of its own", () {
    final viewerSlot = find.byKey(const ValueKey('attach-viewer-slot'));
    Finder inViewer(Finder of) => find.descendant(of: viewerSlot, matching: of);
    final island = find.byKey(const ValueKey('attach-caption'));

    Future<(PagesRig, DockHost)> openViewer(
      WidgetTester tester, {
      AttachPolicy attachPolicy = const AttachPolicy.android(),
    }) async {
      final host = DockHost();
      final rig = await open(
        tester,
        size: const Size(800, 1200),
        host: host,
        viewBottomPadding: true,
        attachPolicy: attachPolicy,
      );
      rig.selection.toggle(AttachItems.file('f'));
      final ratio = tester.view.devicePixelRatio;
      tester.view
        ..padding = FakeViewPadding(bottom: 34 * ratio)
        ..viewPadding = FakeViewPadding(bottom: 34 * ratio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      addTearDown(tester.view.resetViewInsets);
      await tester.tap(cell(1));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(viewerSlot, findsOneWidget);
      return (rig, host);
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('the caption follows the item shown: typing gives it its '
        'own (selecting it), another page shows its own, back shows it '
        'again; the first item shows the sheet\'s', (tester) async {
      final (rig, _) = await openViewer(tester);
      ComposerController field() =>
          tester.widget<ComposerView>(inViewer(island)).controller;
      final shown = AttachPickerSelection.itemOf(FakeMediaLibrary.assetAt(1));

      field().restore(const content.RichText.plain('one'));
      await tester.pump();
      expect(rig.selection.contains(shown.id), isTrue);
      expect(
        rig.selection.ownCaptionOf(shown.id),
        const content.RichText.plain('one'),
      );

      await tester.drag(find.byType(PickerViewerChrome), const Offset(-700, 0));
      await settle(tester);
      expect(field().richText, content.RichText.empty);

      await tester.drag(find.byType(PickerViewerChrome), const Offset(700, 0));
      await settle(tester);
      expect(field().richText, const content.RichText.plain('one'));
    });

    testWidgets('iOS: with a sheet caption set, every item shows it and an '
        'edit edits it', (tester) async {
      final (rig, _) = await openViewer(
        tester,
        attachPolicy: const AttachPolicy.ios(),
      );
      rig.selection.caption = const content.RichText.plain('all');
      await tester.pump();
      ComposerController field() =>
          tester.widget<ComposerView>(inViewer(island)).controller;
      expect(field().richText, const content.RichText.plain('all'));
      field().restore(const content.RichText.plain('all!'));
      await tester.pump();
      expect(rig.selection.caption, const content.RichText.plain('all!'));

      await tester.drag(find.byType(PickerViewerChrome), const Offset(-700, 0));
      await settle(tester);
      expect(field().richText, const content.RichText.plain('all!'));
    });

    testWidgets('its own field and dock: the button, the place under it; the '
        'slot is never lifted, the island and Send follow the place and the '
        'pad at every frame of a keyboard going down', (tester) async {
      final (_, host) = await openViewer(tester);
      expect(host.docks, hasLength(2), reason: "the sheet's, the viewer's");
      final dock = host.docks.last;
      final viewerField = tester
          .widget<ComposerView>(inViewer(island))
          .controller;
      final sheetField = tester
          .widget<ComposerView>(
            find
                .byWidgetPredicate(
                  (w) =>
                      w is ComposerView &&
                      w.key == const ValueKey('attach-caption'),
                  skipOffstage: false,
                )
                .first,
          )
          .controller;
      expect(identical(viewerField, sheetField), isFalse);
      expect(
        identical(viewerField.text, sheetField.text),
        isFalse,
        reason: "the shown item's caption, not the sheet's text",
      );

      final screen =
          tester.view.physicalSize.height / tester.view.devicePixelRatio;
      final glass = inViewer(
        find.descendant(of: island, matching: find.byType(GlassSurface)),
      );
      final send = inViewer(find.byKey(const ValueKey('attach-send')));
      const bottomGap = ComposerMetrics.islandBottomGap;
      for (var place = 300.0; place >= 0; place -= 30) {
        final pad = place > 0 ? 0.0 : 34.0;
        tester.view.viewInsets = FakeViewPadding(
          bottom: place * tester.view.devicePixelRatio,
        );
        dock
          ..place = place
          ..pad.value = pad;
        dock.show(panel: false);
        await tester.pump(const Duration(milliseconds: 16));
        final bottom = tester.getRect(glass.first).bottom;
        expect(
          bottom,
          closeTo(screen - place - pad - bottomGap, 0.5),
          reason: 'place $place',
        );
        expect(tester.getRect(send).bottom, closeTo(bottom, 0.5));
      }
      await tester.tap(
        inViewer(
          find.bySemanticsLabel(
            ChromeStringsPresets.english.composer.showPanelAction,
          ),
        ),
      );
      await tester.pump();
      expect(dock.calls, contains('toggle'));
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(dock.disposed, isTrue);
    });

    // The keyboards asked of the platform: a show after a client of a
    // keyboard type.
    List<String> keyboardsShown(WidgetTester tester) {
      final shown = <String>[];
      String? type;
      for (final call in tester.testTextInput.log) {
        if (call.method == 'TextInput.setClient') {
          final config = (call.arguments as List)[1] as Map;
          type = (config['inputType'] as Map)['name'] as String?;
        }
        if (call.method == 'TextInput.show' && type != 'TextInputType.none') {
          shown.add('$type');
        }
      }
      return shown;
    }

    for (final start in ['panel up', 'keyboard down', 'keyboard up']) {
      testWidgets('the viewer opened and closed twice over a sheet caption '
          'with its $start leaves it as it was (a raised keyboard down): no '
          'keyboard asked for, no focus taken without a tap', (tester) async {
        final host = DockHost();
        final rig = await open(tester, size: const Size(800, 1200), host: host);
        rig.selection.toggle(AttachItems.file('f'));
        await settle(tester);
        final sheetDock = host.sheetDock;
        final caption = tester.widget<ComposerView>(island).controller;
        switch (start) {
          case 'panel up':
            caption
              ..setSoftKeyboard(SoftKeyboardMode.suppressed)
              ..requestFocus();
            sheetDock.show(panel: true);
          case 'keyboard up':
            caption.requestFocus();
        }
        await settle(tester);
        var gains = 0;
        void count() {
          if (caption.focusNode.hasFocus) gains++;
        }

        caption.focusNode.addListener(count);
        addTearDown(() => caption.focusNode.removeListener(count));
        tester.testTextInput.log.clear();

        for (var round = 0; round < 2; round++) {
          await tester.tap(cell(1));
          await settle(tester);
          expect(viewerSlot, findsOneWidget);
          await tester.binding.handlePopRoute();
          await settle(tester);
          expect(viewerSlot, findsNothing);

          expect(
            sheetDock.calls,
            isNot(contains('close')),
            reason: 'round $round',
          );
          expect(
            sheetDock.calls.where((c) => c == 'settle'),
            hasLength(round + 1),
            reason: "the sheet's caption settles as each viewer opens",
          );
          expect(
            sheetDock.panelUp,
            start == 'panel up',
            reason: 'round $round',
          );
          expect(keyboardsShown(tester), isEmpty, reason: 'round $round');
          final primary = FocusManager.instance.primaryFocus!;
          expect(
            ModalRoute.of(primary.context!)?.settings.name,
            AttachSheet.routeName,
          );
          if (start == 'panel up') {
            expect(
              caption.focusNode.hasFocus,
              isTrue,
              reason: 'under its panel',
            );
            expect(caption.softKeyboard.value, SoftKeyboardMode.suppressed);
          } else {
            expect(caption.focusNode.hasFocus, isFalse, reason: 'round $round');
            expect(gains, 0, reason: 'no focus without a tap');
          }
        }
      });
    }

    for (final close in ['back', 'drag start']) {
      testWidgets('closed by $close with its caption focused and its panel up, '
          "it lets go: the panel closes, the focus is back in the sheet's "
          "route, and the sheet's caption takes the keyboard on a tap", (
        tester,
      ) async {
        final (_, host) = await openViewer(tester);
        final dock = host.docks.last;
        final field = tester.widget<ComposerView>(inViewer(island)).controller;
        field.requestFocus();
        dock.show(panel: true);
        await tester.pump();
        expect(field.focusNode.hasFocus, isTrue);

        if (close == 'back') {
          await tester.binding.handlePopRoute();
        } else {
          // A dismiss drag starts: the chrome goes, the caption lets go.
          await tester.drag(
            find.byType(PickerViewerChrome),
            const Offset(0, 300),
          );
        }
        await settle(tester);
        expect(dock.calls, contains('close'));
        expect(field.focusNode.hasFocus, isFalse);
        if (close != 'back') {
          await tester.binding.handlePopRoute();
          await settle(tester);
        }
        expect(viewerSlot, findsNothing);

        final primary = FocusManager.instance.primaryFocus;
        expect(primary, isNotNull);
        expect(
          ModalRoute.of(primary!.context!)?.settings.name,
          AttachSheet.routeName,
          reason: 'not the root',
        );
        final sheetField = tester.widget<ComposerView>(island).controller;
        await tester.tap(island);
        await tester.pump();
        expect(sheetField.focusNode.hasFocus, isTrue);
      });
    }
  });

  testWidgets('the album switcher stands in the pinned bar, not in the '
      'resting header', (tester) async {
    final rig = await open(tester);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('attach-sheet-header')),
        matching: find.byType(LibraryAlbumSwitcher),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('attach-selection-header')),
        matching: find.byType(LibraryAlbumSwitcher),
      ),
      findsNothing,
    );
    // The grid's order numbers and the switcher's title read the chrome
    // face.
    await tapCheck(tester, 0);
    expect(rig.selection.length, 1);
    expectChromeText(tester, within: find.byType(AttachSheet));
  });

  group('the selected-items preview', () {
    final preview = find.byKey(const ValueKey('attach-gallery-preview'));
    final picker = find.byType(LibraryPicker);
    // The header's toggle ("N media selected ›").
    final count = find.byKey(const ValueKey('attach-selection-header-tap'));
    Finder item(int index) => find.descendant(
      of: preview,
      matching: find.byKey(ValueKey<MediaKey>(_key(index))),
    );

    Future<PagesRig> picked(WidgetTester tester) async {
      final rig = await open(tester);
      rig.selection.toggle(AttachItems.file('f'));
      await tapCheck(tester, 0);
      await tapCheck(tester, 1);
      await tapCheck(tester, 2);
      return rig;
    }

    testWidgets('the header swaps the grid for the picks in their order, '
        'and back', (tester) async {
      await picked(tester);
      await tester.tap(count);
      await tester.pumpAndSettle();
      expect(preview, findsOneWidget);
      expect(picker, findsNothing);
      // The library picks, in order; the file is not a library item.
      expect(tester.widget<PickerSelectionPreview>(preview).selection.keys, [
        _key(0),
        _key(1),
        _key(2),
      ]);
      expect(item(1), findsOneWidget);

      await tester.tap(count);
      await tester.pumpAndSettle();
      expect(preview, findsNothing);
      expect(picker, findsOneWidget);
    });

    testWidgets('a tap on a number deselects; emptying it returns to the '
        'grid', (tester) async {
      final rig = await picked(tester);
      await tester.tap(count);
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getTopRight(item(1)) + const Offset(-10, 10));
      await tester.pumpAndSettle();
      expect(rig.selection.length, 3);
      expect(item(1), findsNothing);

      rig.selection.clear();
      await tester.pumpAndSettle();
      expect(preview, findsNothing);
      expect(picker, findsOneWidget);
    });

    testWidgets('a reorder moves the pick among the library picks; the file '
        'keeps its place', (tester) async {
      final rig = await picked(tester);
      await tester.tap(count);
      await tester.pumpAndSettle();
      tester.widget<PickerSelectionPreview>(preview).onReorder!(_key(2), 0);
      await tester.pumpAndSettle();
      expect(rig.selection.items.map((item) => item.id.value), [
        'f',
        'library:${FakeMediaLibrary.assetAt(2).id.value}',
        'library:${FakeMediaLibrary.assetAt(0).id.value}',
        'library:${FakeMediaLibrary.assetAt(1).id.value}',
      ]);
    });

    testWidgets('back returns to the grid and keeps the sheet', (tester) async {
      await picked(tester);
      await tester.tap(count);
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(preview, findsNothing);
      expect(picker, findsOneWidget);
      expect(find.byType(AttachSheet), findsOneWidget);
    });

    testWidgets('a tap on a picture opens the viewer over the picks', (
      tester,
    ) async {
      await picked(tester);
      await tester.tap(count);
      await tester.pumpAndSettle();
      await tester.tap(item(1));
      await tester.pumpAndSettle();
      final chrome = tester.widget<PickerViewerChrome>(
        find.byType(PickerViewerChrome),
      );
      expect(chrome.source.count, 3);
      expect(chrome.index.value, 1);
      expect(
        chrome.source.itemAt(1)?.key,
        LibraryKeys.libraryKeyOf(FakeMediaLibrary.assetAt(1)),
      );
    });
  });

  testWidgets("the viewer's videos play on the host's players", (tester) async {
    final backend = FakePlayerBackend();
    final players = PlayerPool(backend: backend);
    addTearDown(players.dispose);
    await open(tester, players: players);
    expect(
      tester.widget<LibraryPicker>(find.byType(LibraryPicker)).players,
      same(players),
    );
  });

  testWidgets('the sheet moves with the grid: a drag up raises it to its top '
      'before the grid scrolls, a drag down at the top lowers it', (
    tester,
  ) async {
    final rig = await open(tester);
    final rest = rig.top;
    final grid = find.byType(LibraryGrid);
    double offset() => tester
        .state<ScrollableState>(
          find.descendant(of: grid, matching: find.byType(Scrollable)).first,
        )
        .position
        .pixels;

    // One gesture: the sheet takes the first part, the grid the rest.
    final gesture = await tester.startGesture(const Offset(200, 600));
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(0, -30));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(rest, greaterThan(24));
    expect(rig.top, 24, reason: 'raised to its top');
    expect(offset(), greaterThan(0), reason: 'then the grid scrolled');

    // Back to the grid's top, then on down: the sheet lowers.
    final down = await tester.startGesture(const Offset(200, 300));
    for (var i = 0; i < 30; i++) {
      await down.moveBy(const Offset(0, 30));
      await tester.pump();
    }
    expect(offset(), 0);
    expect(rig.top, greaterThan(24), reason: 'lowered at the grid top');
    await down.up();
    await tester.pumpAndSettle();
  });

  group('fast scroll', () {
    const thumb = ValueKey('fast-scrollbar-thumb');
    const label = ValueKey('fast-scrollbar-label');

    Future<void> expand(WidgetTester tester) async {
      final sheet = AttachSheetController.of(
        tester.element(find.byType(LibraryGrid)),
      );
      // Its future ends with the motion, which only pumping runs.
      unawaited(sheet.expand());
      await tester.pumpAndSettle();
    }

    ScrollPosition grid(WidgetTester tester) => tester
        .state<ScrollableState>(
          find.descendant(
            of: find.byType(LibraryGrid),
            matching: find.byType(Scrollable),
          ),
        )
        .position;

    testWidgets("the track ends where the grid's visible content ends: "
        'above the floating bar', (tester) async {
      await open(tester);
      await expand(tester);
      final bar = tester.getRect(
        find.byKey(const ValueKey('attach-sheet-bar')),
      );
      final scrollbar = tester.widget<FastScrollbar>(
        find.byType(FastScrollbar),
      );
      expect(scrollbar.padding.bottom, closeTo(bar.height, 0.5));
      grid(tester).jumpTo(grid(tester).maxScrollExtent);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.getRect(find.byKey(thumb)).bottom,
        lessThanOrEqualTo(bar.top + 0.5),
      );
    });

    testWidgets(r"$Android: the month is the item's last change, the date "
        'the grid is sorted by, not when it was taken', (tester) async {
      // An old photo edited lately sorts first, by its change.
      library.insert([
        LibraryAsset(
          id: const LibraryAssetId('edited'),
          kind: LibraryAssetKind.photo,
          created: DateTime.utc(2020, 4, 10),
          modified: DateTime.utc(2026, 11, 20),
        ),
      ]);
      await open(tester);
      await expand(tester);
      grid(tester).jumpTo(1);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final strings = ChromeStringsPresets.english.attach;
      expect(
        find.descendant(
          of: find.byKey(label),
          matching: find.text(
            strings.libraryMonth(DateTime.utc(2026, 11, 20).toLocal()),
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets(r'$Android: the thumb comes once the sheet is at its top, '
        'and the label names the month of the items in view', (tester) async {
      await open(tester);
      expect(find.byKey(thumb), findsNothing);
      await expand(tester);
      expect(find.byKey(thumb), findsOneWidget);

      grid(tester).jumpTo(300);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final top = tester
          .state<LibraryGridState>(find.byType(LibraryGrid))
          .pages
          .assetAt(9)!;
      final month = ChromeStringsPresets.english.attach.libraryMonth(
        top.created!.toLocal(),
      );
      expect(
        find.descendant(of: find.byKey(label), matching: find.text(month)),
        findsOneWidget,
      );
      // The label hides 2 s after the scroll; the thumb stays.
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(label), findsNothing);
      expect(find.byKey(thumb), findsOneWidget);
    });

    testWidgets(r'$Android: an album of 30 items or fewer has none', (
      tester,
    ) async {
      final small = FakeMediaLibrary(assets: 30);
      addTearDown(small.dispose);
      await open(tester, source: small, size: const Size(400, 300));
      await expand(tester);
      expect(find.byKey(thumb), findsNothing);
    });
  });

  testWidgets('a picked item deleted from the device leaves the attach '
      'selection, and the picks after it move up a number', (tester) async {
    final rig = await open(tester);
    await tapCheck(tester, 0);
    await tapCheck(tester, 1);
    rig.selection.toggle(AttachItems.file('f'));
    await tapCheck(tester, 2);
    expect(rig.selection.length, 4);

    library.remove({FakeMediaLibrary.assetAt(1).id});
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(rig.selection.items.map((item) => item.id.value), [
      'library:${FakeMediaLibrary.assetAt(0).id.value}',
      'f',
      'library:${FakeMediaLibrary.assetAt(2).id.value}',
    ]);
    await tester.pumpAndSettle();
    expect(tester.widget<LibraryGridCell>(cell(2)).order, 3);
  });

  testWidgets("the viewer's title is the chat's; a video's info line is what "
      'is sent, a photo has none', (tester) async {
    await PagesRig.open(
      tester,
      policy: const AttachSheetPolicy.android(),
      wrap: (app) => AssetCacheProvider(scope: scope, child: app),
      pages: [
        GalleryPage.create(
          library: library,
          label: 'Gallery',
          icon: const SizedBox(width: 24, height: 24),
          viewerTitle: 'Saved Messages',
        ),
      ],
    );
    await tester.pumpAndSettle();
    final picker = tester.widget<LibraryPicker>(find.byType(LibraryPicker));
    expect(picker.viewerTitle, 'Saved Messages');
    expect(picker.viewerSubtitleOf, isNotNull);

    final photo = FakeMediaLibrary.assetAt(0);
    final video = FakeMediaLibrary.assetAt(3);
    expect(GalleryView.viewerInfoOf(photo), isNull);
    final info = GalleryView.viewerInfoOf(
      video,
      policy: PreparationPolicy.forPlatform(TargetPlatform.android),
    );
    expect(info, isNotNull);
    expect(info, matches(RegExp(r'^\d+x\d+, \d+:\d\d, ~[\d.]+ (KB|MB)$')));
  });

  testWidgets('the grid shows HD on checked photos while the send options '
      'are high quality; the preview shows the grid marks of its items', (
    tester,
  ) async {
    final rig = await open(tester);
    LibraryPicker picker() =>
        tester.widget<LibraryPicker>(find.byType(LibraryPicker));
    expect(picker().highQuality, isFalse);
    expect(picker().labels.highQuality, 'HD');
    await tapCheck(tester, 0);
    final panel = AttachSheetController.of(
      tester.element(find.byType(LibraryPicker)),
    );
    expect(panel, isNotNull);
    final send = tester
        .widget<AttachSendButton>(find.byType(AttachSendButton))
        .controller;
    send.options.value = send.options.value.copyWith(highQuality: true);
    await tester.pumpAndSettle();
    expect(picker().highQuality, isTrue);

    await tapCheck(tester, 1);
    await tester.tap(find.byKey(const ValueKey('attach-selection-header-tap')));
    await tester.pumpAndSettle();
    final preview = tester.widget<PickerSelectionPreview>(
      find.byType(PickerSelectionPreview),
    );
    expect(preview.assetOf!(_key(0)), FakeMediaLibrary.assetAt(0));
    expect(rig.selection.length, 2);
  });
}
