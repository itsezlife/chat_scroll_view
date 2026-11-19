import 'package:attach_model/attach_model.dart';
import 'package:attach_model/testing.dart';
import 'package:attach_sheet/attach_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
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
  }) async {
    final rig = await PagesRig.open(
      tester,
      policy: const AttachSheetPolicy.android(),
      limits: limits,
      host: host,
      wrap: (app) => AssetCacheProvider(scope: scope, child: app),
      pages: [
        GalleryPage.create(
          library: source ?? library,
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
    expect(
      find.byKey(const ValueKey('attach-gallery-no-access')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('attach-gallery-allow')));
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
}
