/// The backdrop snapshot: a small still of what a [BackdropSnapshotSource]
/// last painted, blurred and toned once, drawn stretched at an opacity.
///
/// **Seam:** the source over a coloured box in an 800 x 600 window at a
/// device pixel ratio of 1 (the test view's default is reset to it), the
/// snapshot's image read back through `toByteData`.
library;

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:chrome_foundation/chrome_foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

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

  testWidgets('a capture is the source at 1/downscale of its device pixels', (
    tester,
  ) async {
    final context = await pumpSource(tester);
    final snapshot = BackdropSnapshot.capture(context, downscale: 10)!;
    addTearDown(snapshot.dispose);
    expect(snapshot.image.width, 80);
    expect(snapshot.image.height, 60);
  });

  testWidgets('the capture keeps the colours of what the source painted', (
    tester,
  ) async {
    final context = await pumpSource(tester);
    final snapshot = BackdropSnapshot.capture(context, downscale: 10)!;
    addTearDown(snapshot.dispose);
    final middle = await pixelOf(tester, snapshot.image, 40, 30);
    expect(middle.r, closeTo(1, 0.02));
    expect(middle.g, closeTo(0, 0.02));
    expect(middle.a, closeTo(1, 0.02));
  });

  testWidgets('a tone matrix is applied once, with the blur', (tester) async {
    final context = await pumpSource(tester, color: const Color(0xFF808080));
    final snapshot = BackdropSnapshot.capture(
      context,
      downscale: 10,
      tone: BackdropSnapshot.toneMatrix(brightness: -0.25),
    )!;
    addTearDown(snapshot.dispose);
    final middle = await pixelOf(tester, snapshot.image, 40, 30);
    // 0x80 is 128; a brightness of -0.25 takes 64 off each channel.
    expect(middle.r * 255, closeTo(64, 3));
    expect(middle.b * 255, closeTo(64, 3));
  });

  testWidgets('dispose lets go of the image, once', (tester) async {
    final context = await pumpSource(tester);
    final snapshot = BackdropSnapshot.capture(context)!;
    final image = snapshot.image;
    expect(image.debugDisposed, isFalse);
    snapshot.dispose();
    expect(image.debugDisposed, isTrue);
    expect(snapshot.isDisposed, isTrue);
    snapshot.dispose();
  });

  testWidgets('the view draws the image stretched at its opacity, with no '
      'backdrop filter', (tester) async {
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
    final raw = tester.widget<RawImage>(find.byType(RawImage));
    expect(raw.image, same(snapshot.image));
    expect(raw.fit, BoxFit.fill);
    expect(raw.opacity!.value, 0.25);
    expect(tester.getSize(find.byType(RawImage)), const Size(800, 600));
    expect(find.byType(BackdropFilter), findsNothing);

    opacity.value = 0.75;
    await tester.pump();
    expect(tester.widget<RawImage>(find.byType(RawImage)).opacity!.value, 0.75);
  });

  group('over a sharp window', () {
    // A phone: 1080 x 2400 device pixels at 2.625, the session's 1/15 and
    // 6.5. The source is a checkerboard of 8 px squares, black and white, so
    // every pixel of a still that is evenly blurred is mid-grey, and any of
    // the window that shows through is black or white.
    const physical = Size(1080, 2400);
    const density = 2.625;

    // After the file's own setUp, whose tear-down resets the view.
    setUp(() {
      TestWidgetsFlutterBinding.instance.platformDispatcher.views.single
        ..physicalSize = physical
        ..devicePixelRatio = density;
    });

    // What the window shows: the still over [window] (the checkerboard),
    // read back at its device pixels. [nearest]: the still is stretched with
    // nearest-neighbour sampling, as the coarsest backend draws it, in place
    // of the view.
    Future<({Uint8List rgba, int width, int height})> shown(
      WidgetTester tester, {
      CustomPainter window = const _Checkerboard(8),
      int upscale = 1,
      bool nearest = false,
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
                nearest
                    ? RawImage(
                        image: snapshot.image,
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.none,
                      )
                    : BackdropSnapshotView(
                        snapshot: snapshot,
                        opacity: const AlwaysStoppedAnimation(1),
                      ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(build());
      snapshot = BackdropSnapshot.capture(
        inner,
        blurSigma: 6.5,
        upscale: upscale,
      );
      addTearDown(snapshot!.dispose);
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

    // The largest change between two neighbouring device pixels of what the
    // window shows, in levels of 255, and where.
    ({int step, (int, int) at}) steepest(
      ({Uint8List rgba, int width, int height}) shot,
    ) {
      final (:rgba, :width, :height) = shot;
      var step = 0;
      var at = (0, 0);
      for (var y = 0; y < height; y++) {
        for (var x = 0; x < width; x++) {
          final here = rgba[(y * width + x) * 4];
          for (final (dx, dy) in [(1, 0), (0, 1)]) {
            if (x + dx >= width || y + dy >= height) continue;
            final there = rgba[((y + dy) * width + x + dx) * 4];
            if ((here - there).abs() > step) {
              step = (here - there).abs();
              at = (x, y);
            }
          }
        }
      }
      return (step: step, at: at);
    }

    // A step of 255 blurred by 6.5 x 15 device pixels climbs about 1 level
    // per device pixel: a still stretched 3 times, nearest-neighbour, steps
    // about 3 at its pixel boundaries, one stretched 15 times about 16.
    const smooth = 6;

    testWidgets('upscaled once as it is made, the still shows no step at its '
        'pixel boundaries even where it is stretched nearest-neighbour', (
      tester,
    ) async {
      final (:step, :at) = steepest(
        await shown(tester, window: const _Halves(), upscale: 5, nearest: true),
      );
      expect(step, lessThanOrEqualTo(smooth), reason: 'a step at $at');
    });

    testWidgets('a still made at the captured pixels, stretched '
        'nearest-neighbour, shows its pixels as blocks', (tester) async {
      final (:step, at: _) = steepest(
        await shown(tester, window: const _Halves(), nearest: true),
      );
      expect(step, greaterThan(smooth));
    });

    testWidgets('the view draws an upscaled still smoothly', (tester) async {
      final (:step, :at) = steepest(
        await shown(tester, window: const _Halves(), upscale: 5),
      );
      expect(step, lessThanOrEqualTo(smooth), reason: 'a step at $at');
    });

    testWidgets('an upscaled still is the capture at upscale times its '
        'pixels, still opaque and evenly blurred', (tester) async {
      final (:rgba, :width, :height) = await shown(tester, upscale: 5);
      expect((width, height), (1080, 2400));
      var off = 0;
      for (var at = 0; at < rgba.length; at += 4) {
        if (rgba[at + 3] != 255 || (rgba[at] - 128).abs() > 56) off++;
      }
      expect(off, 0);
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
        blurSigma: 6.5,
        background: const Color(0xFF204060),
      )!;
      addTearDown(snapshot.dispose);
      for (final (x, y) in [(0, 0), (36, 80), (71, 159)]) {
        final pixel = await pixelOf(tester, snapshot.image, x, y);
        expect(pixel.a, 1);
        expect(pixel.r * 255, closeTo(0x20, 2));
        expect(pixel.b * 255, closeTo(0x60, 2));
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

// Black above and to the left of the middle, white elsewhere: two sharp
// edges across the window, which the blur turns into its steepest ramps.
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
