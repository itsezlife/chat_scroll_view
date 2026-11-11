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
