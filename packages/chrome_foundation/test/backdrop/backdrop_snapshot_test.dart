/// The backdrop snapshot: a small still of what a [BackdropSnapshotSource]
/// last painted, blurred and toned once on the CPU, drawn stretched at an
/// opacity once it is made.
///
/// **Seam:** the source over a coloured box in an 800 x 600 window at a
/// device pixel ratio of 1 (the test view's default is reset to it), the
/// snapshot's image read back through `toByteData`. The still is made off
/// the test's fake clock: a test waits for it with `runAsync`.
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// Lets the still of [snapshot] be made: real time for the engine and the
// blur, and the test's microtasks between.
Future<void> settle(WidgetTester tester, BackdropSnapshot snapshot) async {
  var done = false;
  unawaited(snapshot.ready.then((_) => done = true));
  for (var turn = 0; !done && turn < 200; turn++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump();
  }
  expect(done, isTrue, reason: 'the still was never made');
}

void main() {
  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.single;
    view
      ..physicalSize = const Size(800, 600)
      ..devicePixelRatio = 1;
    addTearDown(view.reset);
  });

  Future<BuildContext> pumpSource(
    WidgetTester tester, {
    Color color = const Color(0xFFFF0000),
    bool source = true,
  }) async {
    late BuildContext inner;
    final child = ColoredBox(
      color: color,
      child: Builder(
        builder: (context) {
          inner = context;
          return const SizedBox.expand();
        },
      ),
    );
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: source ? BackdropSnapshotSource(child: child) : child,
      ),
    );
    return inner;
  }

  // The still of [snapshot], once it is made.
  Future<ui.Image> made(WidgetTester tester, BackdropSnapshot snapshot) async {
    await settle(tester, snapshot);
    return snapshot.image!;
  }

  Future<Color> pixelOf(WidgetTester tester, ui.Image image, int x, int y) =>
      tester
          .runAsync(() async {
            final bytes = (await image.toByteData())!;
            final at = (y * image.width + x) * 4;
            final rgba = Uint8List.sublistView(bytes);
            return Color.fromARGB(
              rgba[at + 3],
              rgba[at],
              rgba[at + 1],
              rgba[at + 2],
            );
          })
          .then((color) => color!);

  testWidgets('outside a source there is nothing to capture', (tester) async {
    final context = await pumpSource(tester, source: false);
    expect(BackdropSnapshot.capture(context), isNull);
  });

  testWidgets('a capture is the source at 1/downscale of its device pixels, '
      'made after it is taken', (tester) async {
    final context = await pumpSource(tester);
    final snapshot = BackdropSnapshot.capture(context, downscale: 10)!;
    addTearDown(snapshot.dispose);
    expect(snapshot.image, isNull);
    var told = 0;
    snapshot.addListener(() => told++);
    final image = await made(tester, snapshot);
    expect(told, 1);
    expect(image.width, 80);
    expect(image.height, 60);
  });

  testWidgets('the capture keeps the colours of what the source painted', (
    tester,
  ) async {
    final context = await pumpSource(tester);
    final snapshot = BackdropSnapshot.capture(
      context,
      downscale: 10,
      blurRadius: 15,
    )!;
    addTearDown(snapshot.dispose);
    final middle = await pixelOf(tester, await made(tester, snapshot), 40, 30);
    expect(middle.r, closeTo(1, 0.02));
    expect(middle.g, closeTo(0, 0.02));
    expect(middle.a, 1);
  });

  testWidgets('a tone matrix is applied once, with the blur', (tester) async {
    final context = await pumpSource(tester, color: const Color(0xFF808080));
    final snapshot = BackdropSnapshot.capture(
      context,
      downscale: 10,
      blurRadius: 15,
      tone: BackdropSnapshot.toneMatrix(brightness: -0.25),
    )!;
    addTearDown(snapshot.dispose);
    final middle = await pixelOf(tester, await made(tester, snapshot), 40, 30);
    // 0x80 is 128; a brightness of -0.25 takes 64 off each channel.
    expect(middle.r * 255, closeTo(64, 1));
    expect(middle.b * 255, closeTo(64, 1));
  });

  testWidgets('dispose lets go of the image, once', (tester) async {
    final context = await pumpSource(tester);
    final snapshot = BackdropSnapshot.capture(context)!;
    final image = await made(tester, snapshot);
    expect(image.debugDisposed, isFalse);
    snapshot.dispose();
    expect(image.debugDisposed, isTrue);
    expect(snapshot.isDisposed, isTrue);
    expect(snapshot.image, isNull);
    snapshot.dispose();
  });

  testWidgets('disposed before it is made, the still is let go as it comes', (
    tester,
  ) async {
    final context = await pumpSource(tester);
    final snapshot = BackdropSnapshot.capture(context)!..dispose();
    await settle(tester, snapshot);
    expect(snapshot.image, isNull);
  });

  testWidgets('the view draws nothing until the still is made, then the '
      'still stretched at its opacity, with no backdrop filter', (
    tester,
  ) async {
    final context = await pumpSource(tester);
    final snapshot = BackdropSnapshot.capture(context, downscale: 10)!;
    addTearDown(snapshot.dispose);
    final opacity = AnimationController(vsync: tester, value: 0.25);
    addTearDown(opacity.dispose);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: BackdropSnapshotView(snapshot: snapshot, opacity: opacity),
      ),
    );
    expect(find.byType(RawImage), findsNothing);

    final image = await made(tester, snapshot);
    await tester.pump();
    final raw = tester.widget<RawImage>(find.byType(RawImage));
    expect(raw.image, same(image));
    expect(raw.fit, BoxFit.fill);
    expect(raw.filterQuality, FilterQuality.low);
    expect(raw.opacity!.value, 0.25);
    expect(tester.getSize(find.byType(RawImage)), const Size(800, 600));
    expect(find.byType(BackdropFilter), findsNothing);

    opacity.value = 0.75;
    await tester.pump();
    expect(tester.widget<RawImage>(find.byType(RawImage)).opacity!.value, 0.75);

    snapshot.dispose();
    await tester.pump();
    expect(find.byType(RawImage), findsNothing);
  });

  group('over a sharp window', () {
    // A phone: 1080 x 2400 device pixels at 2.625, the session's 1/15 and
    // radius 15.
    const physical = Size(1080, 2400);
    const density = 2.625;

    // After the file's own setUp, whose tear-down resets the view.
    setUp(() {
      TestWidgetsFlutterBinding.instance.platformDispatcher.views.single
        ..physicalSize = physical
        ..devicePixelRatio = density;
    });

    // What the window shows: the still over [window], read back at its
    // device pixels.
    Future<({Uint8List rgba, int width, int height})> shown(
      WidgetTester tester, {
      CustomPainter window = const _Checkerboard(8),
    }) async {
      late BuildContext inner;
      final boundary = GlobalKey();
      BackdropSnapshot? snapshot;
      Widget build() => RepaintBoundary(
        key: boundary,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Stack(
            fit: StackFit.expand,
            children: [
              BackdropSnapshotSource(
                child: CustomPaint(
                  painter: window,
                  child: Builder(
                    builder: (context) {
                      inner = context;
                      return const SizedBox.expand();
                    },
                  ),
                ),
              ),
              if (snapshot case final snapshot?)
                BackdropSnapshotView(
                  snapshot: snapshot,
                  opacity: const AlwaysStoppedAnimation(1),
                ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(build());
      snapshot = BackdropSnapshot.capture(inner, blurRadius: 15);
      addTearDown(snapshot!.dispose);
      await made(tester, snapshot);
      await tester.pumpWidget(build());
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = render.toImageSync(pixelRatio: density);
      addTearDown(image.dispose);
      final bytes = await tester.runAsync(image.toByteData);
      return (
        rgba: Uint8List.sublistView(bytes!),
        width: image.width,
        height: image.height,
      );
    }

    // The black and white checkerboard of 8 px squares: every pixel of a
    // still that is evenly blurred is mid-grey, and any of the window that
    // shows through is black or white.
    testWidgets('the still covers the whole window, opaque and evenly '
        'blurred out to its edges', (tester) async {
      final (:rgba, :width, :height) = await shown(tester);
      expect((width, height), (1080, 2400));
      var clear = 0;
      var sharp = 0;
      final sharpAt = <(int, int)>[];
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final at = (y * width + x) * 4;
          if (rgba[at + 3] != 255) clear++;
          // Mid-grey is 128; the clamped edges of the still lean a little
          // toward the squares they hold. The window showing through is 0
          // or 255.
          if ((rgba[at] - 128).abs() > 56) {
            sharp++;
            if (sharpAt.length < 4) sharpAt.add((x, y));
          }
        }
      }
      expect(clear, 0, reason: 'pixels the still leaves see-through');
      expect(sharp, 0, reason: 'pixels left unblurred, first at $sharpAt');
    });

    // Black above and to the left of the middle, white elsewhere: the
    // blur's steepest ramps. A step of 255 blurred by radius 15 (about 6.5
    // captured pixels, 97 device pixels) climbs about 1 level per device
    // pixel; a grid of the still's pixels would step about 16 at their
    // boundaries, every 15 device pixels.
    testWidgets('the still shows no step at its pixel boundaries', (
      tester,
    ) async {
      final (:rgba, :width, :height) = await shown(
        tester,
        window: const _Halves(),
      );
      var step = 0;
      var stepAt = (0, 0);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final here = rgba[(y * width + x) * 4];
          for (final (dx, dy) in [(1, 0), (0, 1)]) {
            if (x + dx >= width || y + dy >= height) continue;
            final there = rgba[((y + dy) * width + x + dx) * 4];
            if ((here - there).abs() > step) {
              step = (here - there).abs();
              stepAt = (x, y);
            }
          }
        }
      }
      expect(step, lessThanOrEqualTo(4), reason: 'a step at $stepAt');
    });

    testWidgets('where the source painted nothing, the still shows the '
        'background', (tester) async {
      late BuildContext inner;
      await tester.pumpWidget(
        BackdropSnapshotSource(
          child: Builder(
            builder: (context) {
              inner = context;
              return const SizedBox.expand();
            },
          ),
        ),
      );
      final snapshot = BackdropSnapshot.capture(
        inner,
        blurRadius: 15,
        background: const Color(0xFF204060),
      )!;
      addTearDown(snapshot.dispose);
      final image = await made(tester, snapshot);
      for (final (x, y) in [(0, 0), (36, 80), (71, 159)]) {
        final pixel = await pixelOf(tester, image, x, y);
        expect(pixel.a, 1);
        expect(pixel.r * 255, closeTo(0x20, 1));
        expect(pixel.b * 255, closeTo(0x60, 1));
      }
    });
  });

  test('the tone matrix: saturation about the luminance, brightness as an '
      'offset of 255', () {
    expect(BackdropSnapshot.toneMatrix(), BackdropSnapshot.identityTone);
    final grey = BackdropSnapshot.toneMatrix(saturation: -1);
    // Saturation -1 leaves the luminance alone in every channel.
    expect(grey.sublist(0, 3), grey.sublist(5, 8));
    final darker = BackdropSnapshot.toneMatrix(brightness: -0.1);
    expect(darker[4], closeTo(-25.5, 1e-9));
    expect(darker[19], 0);
  });
}

// Black and white squares of [side] logical pixels.
final class _Checkerboard extends CustomPainter {
  const _Checkerboard(this.side);

  final double side;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFF000000),
    );
    final white = Paint()..color = const Color(0xFFFFFFFF);
    for (var row = 0; row * side < size.height; row++) {
      for (var x = row.isEven ? 0 : 1; x * side < size.width; x += 2) {
        canvas.drawRect(Rect.fromLTWH(x * side, row * side, side, side), white);
      }
    }
  }

  @override
  bool shouldRepaint(_Checkerboard old) => old.side != side;
}

// Black above and to the left of the middle, white elsewhere.
final class _Halves extends CustomPainter {
  const _Halves();

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF))
      ..drawRect(
        Offset.zero & size / 2,
        Paint()..color = const Color(0xFF000000),
      );
  }

  @override
  bool shouldRepaint(_Halves old) => false;
}
