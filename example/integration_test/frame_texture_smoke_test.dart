import 'dart:ffi' show Pointer, Uint8, Uint8Pointer;
import 'dart:io';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:catalog_assets/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frame_texture/frame_texture.dart';
import 'package:integration_test/integration_test.dart';

/// The Android texture host on a device (ADR 043): the host contract over
/// real `SurfaceProducer`s and the plugin's library, then a test pattern
/// written through a lock and shown as a `Texture` for a few seconds, for
/// the eye.
///
/// What to see, over the grey and white checkerboard: a square whose top
/// left quarter is red, top right green, bottom left blue (orientation and
/// channel order), and bottom right a half-transparent white through which
/// the checkerboard shows (premultiplied alpha). A pink square means the
/// channels are swapped; a solid grey bottom right means alpha is ignored.
///
/// `flutter test integration_test/frame_texture_smoke_test.dart -d <device>`
/// from example/. It reinstalls the app, which wipes its data.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final android = Platform.isAndroid;

  group('on Android', skip: android ? false : 'Android only', () {
    FrameTextureHostContract.run(() => PlatformFrameTextureHost.forPlatform()!);

    testWidgets('a test pattern shows upright, in colour and alpha', (
      tester,
    ) async {
      final host = PlatformFrameTextureHost.forPlatform()!;
      const edge = 256;
      final created = await tester.runAsync(() => host.create(edge, edge));
      expect(created, isNotNull, reason: 'the platform refused a texture');
      final id = created!;
      addTearDown(() => host.destroy(id));

      final target = host.lock(id)!;
      expect(target.format, FrameTextureFormat.rgba8888);
      _writePattern(target);
      host.post(id);

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: CustomPaint(
              painter: _Checkerboard(),
              child: SizedBox.square(
                dimension: edge / tester.view.devicePixelRatio,
                child: Texture(textureId: id),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 50; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }
    });
  });
}

void _writePattern(FrameTextureTarget target) {
  final bytes = Pointer<Uint8>.fromAddress(
    target.address,
  ).asTypedList(target.rowStride * target.height);
  final half = target.width ~/ 2;
  for (var y = 0; y < target.height; y++) {
    for (var x = 0; x < target.width; x++) {
      final (r, g, b, a) = switch ((x < half, y < half)) {
        (true, true) => (255, 0, 0, 255),
        (false, true) => (0, 255, 0, 255),
        (true, false) => (0, 0, 255, 255),
        // White at half alpha, premultiplied.
        (false, false) => (128, 128, 128, 128),
      };
      final at = y * target.rowStride + x * 4;
      bytes[at] = r;
      bytes[at + 1] = g;
      bytes[at + 2] = b;
      bytes[at + 3] = a;
    }
  }
}

final class _Checkerboard extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const cell = 16.0;
    final grey = Paint()..color = const Color(0xFF808080);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        if (((x + y) / cell).round().isOdd) {
          canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), grey);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_Checkerboard oldDelegate) => false;
}
