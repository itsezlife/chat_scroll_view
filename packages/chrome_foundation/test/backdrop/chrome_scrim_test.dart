/// The chrome scrim: a still of the window taken before the surface paints,
/// under a dim, fading on two clocks, closed by a press outside, back or
/// Escape, cancelled at once, disposing its stills.
///
/// **Seam:** a `ChromeScrimController` opened from a context under a
/// `BackdropSnapshotSource` over a red window, a `ChromeScrim` over it in
/// the same frame with a green surface, read back as the window's pixels
/// (`captureImage`) and as the phases its owner is told. 800 x 600 at a
/// device pixel ratio of 1. The still is made off the fake clock: a test
/// waits for it with `runAsync`.
library;

import 'dart:async';

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _red = Color(0xFFFF0000);
const _green = Color(0xFF00FF00);
const _surfaceKey = ValueKey('surface');
const _windowKey = ValueKey('window');

// A plain preset to read pixels by: a sharp still, a 50 % black dim, linear
// 100 ms fades, closing on contact.
const _plain = ChromeScrimPreset(
  name: 'plain',
  still: ChromeScrimStill(downscale: 10, blurRadius: 0),
  dimDark: Color(0x80000000),
  dimLight: Color(0x80000000),
  dimFade: MotionSpec(Duration(milliseconds: 100), Curves.linear),
  closeOn: ChromeScrimCloseOn.down,
);

final class _Harness {
  _Harness(this.tester);

  final WidgetTester tester;
  final phases = <ChromeScrimPhase>[];
  final dismissals = <ChromeScrimDismissal>[];
  late BuildContext context;
  ChromeScrimController? scrim;
  bool showSurface = false;

  late StateSetter _setState;

  Future<void> pump() => tester.pumpWidget(
    ChromeThemeScope(
      palette: const ChromePalette.light(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: _windowKey,
          child: BackdropSnapshotSource(
            child: StatefulBuilder(
              builder: (context, setState) {
                this.context = context;
                _setState = setState;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: _red),
                    if (scrim case final scrim?)
                      ChromeScrim(
                        key: ObjectKey(scrim),
                        controller: scrim,
                        child: const Center(
                          child: SizedBox(
                            key: _surfaceKey,
                            width: 100,
                            height: 100,
                            child: ColoredBox(color: _green),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
  );

  /// Opens a scrim between frames, as an owner does, and builds it over the
  /// window in the next frame.
  ChromeScrimController open({
    ChromeScrimPreset preset = _plain,
    bool showStill = true,
    bool reduceTransparency = false,
  }) {
    final opened = ChromeScrimController(
      context,
      preset: preset,
      showStill: showStill,
      reduceTransparency: reduceTransparency,
      onPhase: phases.add,
      onDismiss: dismissals.add,
    );
    _setState(() => scrim = opened);
    return opened;
  }

  /// Lets the still be made: real time for the engine and the blur.
  Future<void> made() async {
    final still = scrim!.still!;
    var done = false;
    unawaited(still.ready.then((_) => done = true));
    for (var turn = 0; !done && turn < 200; turn++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    expect(done, isTrue, reason: 'the still was never made');
  }

  /// The window's pixel at [x], [y].
  Future<Color> pixel(double x, double y) async {
    final image = await tester.runAsync(
      () =>
          (tester.renderObject(find.byKey(_windowKey)) as RenderRepaintBoundary)
              .toImage(),
    );
    final bytes = await tester.runAsync(image!.toByteData);
    image.dispose();
    final rgba = Uint8List.sublistView(bytes!);
    final at = (y.toInt() * image.width + x.toInt()) * 4;
    return Color.fromARGB(rgba[at + 3], rgba[at], rgba[at + 1], rgba[at + 2]);
  }
}

Matcher _rgb(int r, int g, int b) => isA<Color>().having(
  (c) => [(c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round()],
  'rgb',
  [closeTo(r, 2), closeTo(g, 2), closeTo(b, 2)],
);

void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.single;
    view
      ..physicalSize = const Size(800, 600)
      ..devicePixelRatio = 1;
    addTearDown(view.reset);
  });

  testWidgets('the still is of the window without the surface', (tester) async {
    final h = _Harness(tester);
    await h.pump();
    final scrim = h.open();
    await tester.pump();
    expect(find.byKey(_surfaceKey), findsOneWidget);
    await h.made();
    final still = scrim.still!.image!;
    expect(still.width, 80);
    expect(still.height, 60);
    final bytes = await tester.runAsync(still.toByteData);
    final rgba = Uint8List.sublistView(bytes!);
    // Every pixel of the still is the red window: none is the green surface,
    // which painted after the capture.
    for (var at = 0; at < rgba.length; at += 4) {
      expect(rgba[at + 1], lessThan(8), reason: 'a green pixel at ${at ~/ 4}');
    }
    scrim.cancel();
  });

  testWidgets('the dim draws alone until the still is made, then the still '
      'fades in on its own clock', (tester) async {
    final h = _Harness(tester);
    await h.pump();
    final scrim = h.open(
      preset: _plain.copyWith(
        dimFade: const MotionSpec(Duration(milliseconds: 100), Curves.linear),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // The dim at its full 50 % over the red window, no still yet.
    expect(scrim.still!.image, isNull);
    expect(await h.pixel(10, 10), _rgb(127, 0, 0));
    await h.made();
    // The still is red too: what changes is that it is drawn. Its clock
    // starts once it is made.
    expect(
      tester.widget<RawImage>(find.byType(RawImage)).opacity!.value,
      lessThan(1),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<RawImage>(find.byType(RawImage)).opacity!.value, 1);
    scrim.cancel();
  });

  testWidgets('the dim and the still fade on separate clocks', (tester) async {
    final h = _Harness(tester);
    await h.pump();
    final scrim = h.open(showStill: false);
    await tester.pump();
    await h.made();
    await tester.pump(const Duration(milliseconds: 100));
    // The dim is up; the still waits for its owner.
    expect(find.byType(RawImage), findsNothing);
    scrim.showStill();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final opacity = tester.widget<RawImage>(find.byType(RawImage)).opacity!;
    expect(opacity.value, closeTo(0.5, 0.05));
    scrim.hideStill();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 51));
    expect(find.byType(RawImage), findsNothing);
    // The dim never moved.
    expect(await h.pixel(10, 10), _rgb(127, 0, 0));
    scrim.cancel();
  });

  testWidgets('the still\'s view stands while the still is wanted, before '
      'it is made, and goes once it is not', (tester) async {
    final h = _Harness(tester);
    await h.pump();
    final scrim = h.open(showStill: false);
    await tester.pump();
    expect(find.byType(BackdropSnapshotView), findsNothing);
    scrim.showStill();
    await tester.pump();
    expect(scrim.still!.image, isNull);
    expect(
      tester
          .widget<BackdropSnapshotView>(find.byType(BackdropSnapshotView))
          .snapshot,
      same(scrim.still),
    );
    expect(find.byType(RawImage), findsNothing, reason: 'nothing to draw yet');
    scrim.hideStill();
    await tester.pump();
    expect(find.byType(BackdropSnapshotView), findsNothing);
    scrim.cancel();
  });

  testWidgets('the dim fades in and out over the preset\'s fade', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.pump();
    final scrim = h.open(preset: ChromeScrimPreset.desktop);
    await tester.pump();
    expect(await h.pixel(10, 10), _rgb(255, 0, 0));
    // Ease-out-circ at half the time is about 0.87 of the way.
    await tester.pump(const Duration(milliseconds: 100));
    expect(await h.pixel(10, 10), _rgb(144, 0, 0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(await h.pixel(10, 10), _rgb(128, 0, 0));
    scrim.close();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 190));
    expect(scrim.isDone, isFalse);
    // A clock ends on the first frame past its duration.
    await tester.pump(const Duration(milliseconds: 11));
    expect(scrim.isDone, isTrue);
    expect(await h.pixel(10, 10), _rgb(255, 0, 0));
  });

  testWidgets('the owner is told each phase once, in order, with its '
      'numbers', (tester) async {
    final h = _Harness(tester);
    await h.pump();
    final scrim = h.open();
    await tester.pump();
    await h.made();
    await tester.tapAt(const Offset(10, 10));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(scrim.isDone, isTrue);
    expect(h.phases, [
      isA<ChromeScrimPhase$Captured>()
          .having((p) => p.stillSize, 'stillSize', const Size(80, 60))
          .having((p) => p.captureTime, 'captureTime', isNot(Duration.zero)),
      isA<ChromeScrimPhase$StillReady>().having(
        (p) => p.makeTime,
        'makeTime',
        greaterThan(Duration.zero),
      ),
      isA<ChromeScrimPhase$Dismissed>()
          .having((p) => p.by, 'by', ChromeScrimDismissal.outside)
          .having((p) => p.closeOn, 'closeOn', ChromeScrimCloseOn.down),
      isA<ChromeScrimPhase$Disposed>().having((p) => p.stills, 'stills', 1),
    ]);
    expect(h.dismissals, [ChromeScrimDismissal.outside]);
  });

  testWidgets('a preset without a still and the reduce-transparency setting '
      'skip the still and keep the dim', (tester) async {
    final h = _Harness(tester);
    await h.pump();
    final reduced = h.open(reduceTransparency: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(reduced.still, isNull);
    expect(await h.pixel(10, 10), _rgb(127, 0, 0));
    reduced.cancel();
    final bare = h.open(preset: ChromeScrimPreset.ipad);
    await tester.pump();
    expect(bare.still, isNull);
    bare.cancel();
    expect(
      h.phases.whereType<ChromeScrimPhase$StillSkipped>().map((p) => p.why),
      [
        ChromeScrimStillSkip.reduceTransparency,
        ChromeScrimStillSkip.presetNoBlur,
      ],
    );
  });

  testWidgets('outside a source the still is skipped', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      ChromeThemeScope(
        palette: const ChromePalette.light(),
        child: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    final phases = <ChromeScrimPhase>[];
    final scrim = ChromeScrimController(
      context,
      preset: _plain,
      onPhase: phases.add,
    );
    expect(scrim.still, isNull);
    expect(
      phases.single,
      isA<ChromeScrimPhase$StillSkipped>().having(
        (p) => p.why,
        'why',
        ChromeScrimStillSkip.noSource,
      ),
    );
    scrim.cancel();
  });

  group('closeOn', () {
    for (final (preset, closeOn) in [
      (ChromeScrimPreset.android, ChromeScrimCloseOn.up),
      (ChromeScrimPreset.ios, ChromeScrimCloseOn.down),
      (ChromeScrimPreset.ipad, ChromeScrimCloseOn.down),
      (ChromeScrimPreset.desktop, ChromeScrimCloseOn.up),
      (ChromeScrimPreset.web, ChromeScrimCloseOn.up),
      (ChromeScrimPreset.contentPreview, ChromeScrimCloseOn.down),
    ]) {
      testWidgets('${preset.name} closes on ${closeOn.name}', (tester) async {
        final h = _Harness(tester);
        await h.pump();
        final scrim = h.open(preset: preset);
        await tester.pump();
        final press = await tester.startGesture(const Offset(10, 10));
        expect(scrim.isClosing, closeOn == ChromeScrimCloseOn.down);
        await press.up();
        expect(scrim.isClosing, isTrue);
        expect(h.dismissals, [ChromeScrimDismissal.outside]);
        scrim.cancel();
      });
    }

    testWidgets('a press on the surface does not close it, and a cancelled '
        'press does not close on lift', (tester) async {
      final h = _Harness(tester);
      await h.pump();
      final scrim = h.open(preset: ChromeScrimPreset.android);
      await tester.pump();
      await tester.tapAt(const Offset(400, 300));
      final press = await tester.startGesture(const Offset(10, 10));
      await press.cancel();
      expect(scrim.isClosing, isFalse);
      expect(h.dismissals, isEmpty);
      scrim.cancel();
    });

    testWidgets('a burst of presses dismisses once', (tester) async {
      final h = _Harness(tester);
      await h.pump();
      final scrim = h.open();
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester.tapAt(const Offset(10, 10));
      }
      expect(h.dismissals, [ChromeScrimDismissal.outside]);
      expect(h.phases.whereType<ChromeScrimPhase$Dismissed>(), hasLength(1));
      scrim.cancel();
    });
  });

  testWidgets('back closes it, and is taken while it closes', (tester) async {
    final h = _Harness(tester);
    await h.pump();
    final scrim = h.open();
    await tester.pump();
    expect(await tester.binding.handlePopRoute(), isTrue);
    expect(scrim.isClosing, isTrue);
    expect(await tester.binding.handlePopRoute(), isTrue);
    expect(h.dismissals, [ChromeScrimDismissal.back]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(scrim.isDone, isTrue);
    await tester.pump();
    expect(await tester.binding.handlePopRoute(), isFalse);
  });

  testWidgets('Escape closes it where the preset says', (tester) async {
    final h = _Harness(tester);
    await h.pump();
    final mobile = h.open();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(mobile.isClosing, isFalse);
    mobile.cancel();
    final desktop = h.open(preset: ChromeScrimPreset.desktop);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(desktop.isClosing, isTrue);
    expect(h.dismissals, [ChromeScrimDismissal.escape]);
    desktop.cancel();
  });

  testWidgets('cancel takes it away at once and disposes the still', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.pump();
    final scrim = h.open();
    await tester.pump();
    await h.made();
    await tester.pump(const Duration(milliseconds: 100));
    final still = scrim.still!;
    final image = still.image!;
    scrim.cancel();
    expect(scrim.isDone, isTrue);
    expect(still.isDisposed, isTrue);
    expect(image.debugDisposed, isTrue);
    await tester.pump();
    expect(find.byKey(_surfaceKey), findsNothing);
    expect(await h.pixel(10, 10), _rgb(255, 0, 0));
    expect(h.phases.skip(2), [
      isA<ChromeScrimPhase$Cancelled>(),
      isA<ChromeScrimPhase$Disposed>().having((p) => p.stills, 'stills', 1),
    ]);
    scrim.cancel();
    expect(h.phases.whereType<ChromeScrimPhase$Disposed>(), hasLength(1));
  });

  testWidgets('the still is disposed once the fade out ends, not before', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.pump();
    final scrim = h.open();
    await tester.pump();
    await h.made();
    // Both clocks all the way up.
    await tester.pump(const Duration(milliseconds: 101));
    final still = scrim.still!;
    scrim.close();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(still.isDisposed, isFalse);
    await tester.pump(const Duration(milliseconds: 51));
    expect(still.isDisposed, isTrue);
    await expectLater(scrim.done, completes);
  });

  testWidgets('removed without a close, it lets go of its still', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.pump();
    final scrim = h.open();
    await tester.pump();
    final still = scrim.still!;
    await tester.pumpWidget(const SizedBox());
    expect(still.isDisposed, isTrue);
    expect(scrim.isDone, isTrue);
  });

  testWidgets('a close before it is built ends at once', (tester) async {
    final h = _Harness(tester);
    await h.pump();
    final scrim = ChromeScrimController(h.context, preset: _plain);
    scrim.close();
    expect(scrim.isDone, isTrue);
  });
}
