import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_decoder/src/engine/video_engine.dart';
import 'package:video_native/video_native.dart';

/// What a [VideoEngineContract] run needs besides the engine.
final class VideoEngineHarness {
  /// Creates a harness whose engines come from [open].
  VideoEngineHarness({
    required this.open,
    required this.validBytes,
    required this.expectedInfo,
    required this.frameCount,
    required this.malformedBytes,
    this.width = 16,
    this.height = 12,
  });

  /// Opens a fresh engine over an available binding; the contract closes it.
  final Future<VideoEngine> Function() open;

  /// A file the engine opens.
  final Uint8List validBytes;

  /// What [validBytes] declares.
  final VideoInfo expectedInfo;

  /// How many frames [validBytes] holds.
  final int frameCount;

  /// Bytes the engine refuses (not a video).
  final Uint8List malformedBytes;

  /// The target width the contract opens at.
  final int width;

  /// The target height the contract opens at.
  final int height;
}

/// The behaviour every [VideoEngine] shares: the in-process and isolate
/// engines on the fake and the real binding, and the pure-Dart fake.
abstract final class VideoEngineContract {
  /// Registers the contract's tests; [create] builds a fresh harness for
  /// each.
  static void run(VideoEngineHarness Function() create) {
    group('VideoEngine contract', () {
      late VideoEngineHarness harness;
      late VideoEngine engine;

      setUp(() async {
        harness = create();
        engine = await harness.open();
      });
      tearDown(() => engine.dispose());

      Future<VideoClip> open() async {
        final result = await engine.open(
          harness.validBytes,
          width: harness.width,
          height: harness.height,
        );
        expect(result, isA<VideoClipOpened>());
        return (result as VideoClipOpened).clip;
      }

      test('valid bytes open as a clip that carries the declared info', () async {
        final clip = await open();

        expect(clip.info, harness.expectedInfo);
        expect(clip.width, harness.width);
        expect(clip.height, harness.height);
      });
    });
  }
}
