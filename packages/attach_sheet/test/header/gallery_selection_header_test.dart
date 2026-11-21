/// The Gallery's selection header in the sheet: nothing selected, "N
/// selected" with the preview toggle, the bar pinned at the top with the
/// album switcher, the close button and the menu; and the host's choices
/// over it.
///
/// **Seams:** the sheet with the Gallery page over a fake library and a
/// fake asset scope; the header's controller from the panel.
library;

import 'dart:async';

import 'package:attach_sheet/attach_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mpx_core/mpx_core.dart';
import 'package:mpx_core/testing.dart';
import 'package:mpx_library/mpx_library.dart';
import 'package:mpx_library/testing.dart';
import 'package:mpx_ui/mpx_ui.dart';

import '../page/pages_rig.dart';

MediaKey _key(int index) =>
    LibraryKeys.libraryKeyOf(FakeMediaLibrary.assetAt(index));

final class _HostPolicy extends AttachSheetPolicy$Android {
  const _HostPolicy(this.selectionHeader);

  @override
  final AttachSelectionHeaderStyle selectionHeader;
}

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
    AttachSheetPolicy policy = const AttachSheetPolicy.android(),
    GalleryHeaderBuilder? headerBuilder,
    GalleryHeaderBuilder? pinnedItemsBuilder,
    Widget Function(BuildContext context, Widget preview)? previewBuilder,
  }) async {
    final rig = await PagesRig.open(
      tester,
      policy: policy,
      wrap: (app) => AssetCacheProvider(scope: scope, child: app),
      pages: [
        GalleryPage.create(
          library: library,
          label: 'Gallery',
          icon: const SizedBox(width: 24, height: 24),
          headerBuilder: headerBuilder,
          pinnedItemsBuilder: pinnedItemsBuilder,
          previewBuilder: previewBuilder,
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

  final header = find.byKey(const ValueKey('attach-selection-header'));
  final toggle = find.byKey(const ValueKey('attach-selection-header-tap'));
  final arrow = find.byKey(const ValueKey('attach-selection-header-arrow'));
  final pinnedBar = find.byKey(const ValueKey('attach-sheet-header'));
  final preview = find.byKey(const ValueKey('attach-gallery-preview'));

  AttachSelectionHeaderController controller(WidgetTester tester) => tester
      .widget<AttachSendButton>(find.byType(AttachSendButton))
      .controller
      .header;

  // The opacity the words are drawn at: every fade above them.
  double opacityOf(WidgetTester tester, Finder finder) => tester
      .widgetList<Opacity>(
        find.ancestor(of: finder, matching: find.byType(Opacity)),
      )
      .fold(1, (a, o) => a * o.opacity);

  testWidgets('nothing selected: the header shows nothing and takes no tap; '
      'the album switcher is only in the pinned bar', (tester) async {
    await open(tester);
    expect(header, findsOneWidget);
    expect(toggle.hitTestable(), findsNothing);
    expect(
      find.descendant(of: header, matching: find.byType(LibraryAlbumSwitcher)),
      findsNothing,
    );
    expect(
      find.descendant(
        of: pinnedBar,
        matching: find.byType(LibraryAlbumSwitcher),
      ),
      findsOneWidget,
    );
  });

  testWidgets('one pick: "1 photo selected" rises 26 into place as it fades '
      'in over 180 ms; no arrow, and a tap opens no preview', (tester) async {
    await open(tester);
    await tester.tapAt(tester.getTopRight(cell(0)) + const Offset(-10, 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final words = find.text('1 photo selected');
    expect(words, findsOneWidget);
    expect(opacityOf(tester, words), inExclusiveRange(0.3, 0.7));
    final halfway = tester.getTopLeft(words).dy;
    await tester.pump(const Duration(milliseconds: 100));
    expect(opacityOf(tester, words), 1);
    // Halfway through the fade it stood halfway down its 26.
    expect(halfway - tester.getTopLeft(words).dy, closeTo(13, 2));
    expect(arrow, findsNothing);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(preview, findsNothing);
  });

  testWidgets('the words follow the kinds: photos, videos, media', (
    tester,
  ) async {
    await open(tester);
    // The fourth asset is a video.
    await tapCheck(tester, 3);
    expect(find.text('1 video selected'), findsOneWidget);
    await tapCheck(tester, 0);
    expect(find.text('2 media selected'), findsOneWidget);
  });

  testWidgets('from two picks the arrow shows and a tap opens the preview '
      'under "Message preview"; a tap goes back', (tester) async {
    await open(tester);
    await tapCheck(tester, 0);
    await tapCheck(tester, 1);
    expect(arrow, findsOneWidget);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(preview, findsOneWidget);
    expect(controller(tester).value.previewing, isTrue);
    expect(find.text('Message preview'), findsOneWidget);
    // The pinned bar's switcher fades out while the preview shows.
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('attach-pinned-switcher')),
          )
          .opacity,
      0,
    );

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(preview, findsNothing);
    expect(controller(tester).value.previewing, isFalse);
  });

  testWidgets('a burst of taps on the header is one switch', (tester) async {
    await open(tester);
    await tapCheck(tester, 0);
    await tapCheck(tester, 1);
    for (var i = 0; i < 5; i++) {
      await tester.tap(toggle, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();
    expect(controller(tester).value.previewing, isTrue);
    expect(preview, findsOneWidget);
  });

  testWidgets("the send button's count only sends here: no preview tap", (
    tester,
  ) async {
    await open(tester);
    await tapCheck(tester, 0);
    await tapCheck(tester, 1);
    expect(find.byKey(const ValueKey('attach-send-count-tap')), findsNothing);
  });

  group('at the top', () {
    Future<PagesRig> pinned(WidgetTester tester) async {
      final rig = await open(tester);
      await tapCheck(tester, 0);
      await tapCheck(tester, 1);
      // Its future ends with the motion, which only pumping runs.
      unawaited(AttachSheetController.of(tester.element(header)).expand());
      await tester.pumpAndSettle();
      return rig;
    }

    final close = find.byKey(const ValueKey('attach-pinned-close'));

    testWidgets('the pinned bar shows the close button, the album switcher '
        "and the menu; the header's words fade out", (tester) async {
      await pinned(tester);
      expect(controller(tester).value.pinned, isTrue);
      expect(close.hitTestable(), findsOneWidget);
      expect(
        find
            .descendant(
              of: pinnedBar,
              matching: find.byType(LibraryAlbumSwitcher),
            )
            .hitTestable(),
        findsOneWidget,
      );
      expect(
        find
            .descendant(
              of: pinnedBar,
              matching: find.byKey(const ValueKey('attach-overflow')),
            )
            .hitTestable(),
        findsOneWidget,
      );
      expect(opacityOf(tester, find.text('2 photos selected')), 0);
      expect(toggle.hitTestable(), findsNothing);
    });

    testWidgets('close over the preview goes back to the grid; a burst '
        'while the switch moves asks nothing', (tester) async {
      await pinned(tester);
      controller(tester).togglePreview();
      await tester.pumpAndSettle();
      expect(preview, findsOneWidget);

      for (var i = 0; i < 4; i++) {
        await tester.tap(close, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pumpAndSettle();
      expect(preview, findsNothing);
      expect(find.text('Discard selection?'), findsNothing);
      expect(find.byType(AttachSheet), findsOneWidget);
    });

    testWidgets('close over the grid closes the sheet as back does: with a '
        'selection it asks first', (tester) async {
      await pinned(tester);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.text('Discard selection?'), findsOneWidget);
    });
  });

  group("the host's choices", () {
    testWidgets('no preview at all: no arrow, and the header takes no '
        'tap to it', (tester) async {
      await open(
        tester,
        policy: _HostPolicy(
          AttachSelectionHeaderStyle.android.copyWith(previewEnabled: false),
        ),
      );
      await tapCheck(tester, 0);
      await tapCheck(tester, 1);
      expect(arrow, findsNothing);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(preview, findsNothing);
    });

    testWidgets('the preview from the count instead of the header', (
      tester,
    ) async {
      await open(
        tester,
        policy: _HostPolicy(
          AttachSelectionHeaderStyle.android.copyWith(
            previewEntries: {AttachPreviewEntry.sendCount},
          ),
        ),
      );
      await tapCheck(tester, 0);
      await tapCheck(tester, 1);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(preview, findsNothing, reason: 'not from the header');
      await tester.tap(find.byKey(const ValueKey('attach-send-count-tap')));
      await tester.pumpAndSettle();
      expect(preview, findsOneWidget);
    });

    testWidgets('its own header, pinned items and preview over the same '
        'behaviour', (tester) async {
      await open(
        tester,
        headerBuilder: (context, parts) => ValueListenableBuilder(
          valueListenable: parts.header,
          builder: (context, value, _) => GestureDetector(
            key: const ValueKey('host-header'),
            onTap: parts.header.togglePreview,
            child: SizedBox(height: 40, child: Text(value.phase.name)),
          ),
        ),
        pinnedItemsBuilder: (context, parts) =>
            const SizedBox(key: ValueKey('host-pinned'), height: 40),
        previewBuilder: (context, preview) =>
            KeyedSubtree(key: const ValueKey('host-preview'), child: preview),
      );
      expect(find.text('empty'), findsOneWidget);
      expect(header, findsNothing);
      expect(find.byKey(const ValueKey('host-pinned')), findsOneWidget);
      await tapCheck(tester, 0);
      await tapCheck(tester, 1);
      expect(find.text('selected'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('host-header')));
      await tester.pumpAndSettle();
      expect(find.text('previewing'), findsOneWidget);
      expect(find.byKey(const ValueKey('host-preview')), findsOneWidget);
      expect(preview, findsOneWidget);
    });

    testWidgets('a switcher header (the other platforms): the switcher in '
        'the header, the preview from the count', (tester) async {
      await open(tester, policy: const AttachSheetPolicy.ios());
      expect(
        find.descendant(
          of: find.byType(LibraryPicker),
          matching: find.byType(LibraryAlbumSwitcher),
        ),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('attach-pinned-close')), findsNothing);
    });
  });
}
