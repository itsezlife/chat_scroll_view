import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_baseline/golden_baseline.dart';

/// A 10×10 PNG, black but for [white] white pixels in the top row.
Future<Uint8List> _png(int white) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..drawRect(
      const ui.Rect.fromLTWH(0, 0, 10, 10),
      ui.Paint()..color = const ui.Color(0xFF000000),
    );
  if (white > 0) {
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, white.toDouble(), 1),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
  }
  final image = await recorder.endRecording().toImage(10, 10);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

void main() {
  late Directory dir;
  late Uri testFile;
  final golden = Uri.parse('scene.png');

  setUp(() {
    dir = Directory.systemTemp.createTempSync('golden_baseline_test');
    testFile = Uri.file('${dir.path}/scene_test.dart');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  GoldenBaselineComparator comparator({
    required String host,
    double tolerance = 0,
    List<String>? skipped,
  }) => GoldenBaselineComparator(
    testFile,
    tolerance: tolerance,
    host: host,
    compareAnywhere: false,
    onSkip: (reason) => skipped?.add(reason),
  );

  group('on the baseline host', () {
    testWidgets('a matching scene passes', (tester) async {
      await tester.runAsync(() async {
        File('${dir.path}/scene.png').writeAsBytesSync(await _png(0));
        expect(
          await comparator(
            host: goldenBaselineHost,
          ).compare(await _png(0), golden),
          isTrue,
        );
      });
    });

    testWidgets('a scene past the tolerance fails', (tester) async {
      await tester.runAsync(() async {
        File('${dir.path}/scene.png').writeAsBytesSync(await _png(0));
        // 5 of 100 pixels differ.
        await expectLater(
          comparator(
            host: goldenBaselineHost,
            tolerance: 0.01,
          ).compare(await _png(5), golden),
          throwsA(isA<FlutterError>()),
        );
      });
    });

    testWidgets('a scene within the tolerance passes', (tester) async {
      await tester.runAsync(() async {
        File('${dir.path}/scene.png').writeAsBytesSync(await _png(0));
        expect(
          await comparator(
            host: goldenBaselineHost,
            tolerance: 0.06,
          ).compare(await _png(5), golden),
          isTrue,
        );
      });
    });

    testWidgets('a baseline is written', (tester) async {
      await tester.runAsync(() async {
        await comparator(
          host: goldenBaselineHost,
        ).update(golden, await _png(0));
        expect(File('${dir.path}/scene.png').existsSync(), isTrue);
      });
    });
  });

  group('a scene with a host of its own', () {
    testWidgets('is compared on that host', (tester) async {
      await tester.runAsync(() async {
        File('${dir.path}/scene.png').writeAsBytesSync(await _png(0));
        final mac = GoldenBaselineComparator(
          testFile,
          baselineHost: 'macos_arm64',
          host: 'macos_arm64',
          compareAnywhere: false,
        );
        await expectLater(
          mac.compare(await _png(5), golden),
          throwsA(isA<FlutterError>()),
        );
      });
    });

    testWidgets('is skipped on the runner', (tester) async {
      await tester.runAsync(() async {
        final skipped = <String>[];
        final runner = GoldenBaselineComparator(
          testFile,
          baselineHost: 'macos_arm64',
          host: goldenBaselineHost,
          compareAnywhere: false,
          onSkip: skipped.add,
        );
        expect(await runner.compare(await _png(5), golden), isTrue);
        expect(skipped.single, contains('macos_arm64'));
      });
    });
  });

  group('on another host', () {
    testWidgets('the comparison is skipped, not passed', (tester) async {
      await tester.runAsync(() async {
        final skipped = <String>[];
        // No baseline on disk: a comparison would throw.
        expect(
          await comparator(
            host: 'macos_arm64',
            skipped: skipped,
          ).compare(await _png(5), golden),
          isTrue,
        );
        expect(skipped.single, contains(goldenBaselineHost));
      });
    });

    testWidgets('regenerating a baseline fails', (tester) async {
      await tester.runAsync(() async {
        expect(
          () => comparator(host: 'macos_arm64').update(golden, Uint8List(0)),
          throwsStateError,
        );
        expect(File('${dir.path}/scene.png').existsSync(), isFalse);
      });
    });

    testWidgets('GOLDEN_BASELINE=compare compares anyway', (tester) async {
      await tester.runAsync(() async {
        File('${dir.path}/scene.png').writeAsBytesSync(await _png(0));
        final anywhere = GoldenBaselineComparator(
          testFile,
          host: 'macos_arm64',
          compareAnywhere: true,
        );
        await expectLater(
          anywhere.compare(await _png(5), golden),
          throwsA(isA<FlutterError>()),
        );
      });
    });
  });
}
