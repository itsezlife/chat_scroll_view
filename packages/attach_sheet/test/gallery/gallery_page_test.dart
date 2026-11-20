import 'dart:async';

import 'package:attach_model/attach_model.dart';
import 'package:attach_model/testing.dart';
import 'package:attach_sheet/attach_sheet.dart';
import 'package:chat_composer/chat_composer.dart';
import 'package:chrome_foundation/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
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
    PlayerPool? players,
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

  testWidgets('the header carries the album switcher', (tester) async {
    final rig = await open(tester);
    expect(find.byType(LibraryAlbumSwitcher), findsOneWidget);
    // The grid's order numbers and the switcher's title read the chrome
    // face.
    await tapCheck(tester, 0);
    expect(rig.selection.length, 1);
    expectChromeText(tester, within: find.byType(AttachSheet));
  });

  group('the selected-items preview', () {
    final preview = find.byKey(const ValueKey('attach-gallery-preview'));
    final picker = find.byKey(const ValueKey('attach-gallery-picker'));
    final count = find.byKey(const ValueKey('attach-send-count-tap'));
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

    testWidgets('the count swaps the grid for the picks in their order, '
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

    await tester.tap(find.byKey(const ValueKey('attach-send-count-tap')));
    await tester.pumpAndSettle();
    final preview = tester.widget<PickerSelectionPreview>(
      find.byType(PickerSelectionPreview),
    );
    expect(preview.assetOf!(_key(0)), FakeMediaLibrary.assetAt(0));
    expect(rig.selection.length, 1);
  });
}
