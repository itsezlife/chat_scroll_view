import 'package:flutter_test/flutter_test.dart';
import 'package:video_native/video_native.dart';

// ignore: always_use_package_imports
import 'support/fixtures.dart';

void main() {
  final binding = NativeVideoBinding.probe();

  group('NativeVideoBinding.probe', () {
    test('finds the built library and its ABI version', () {
      expect(binding.availability, VideoAvailability.available);
    });
  });

  group('open', skip: nativeSkipReason(binding), () {
    test('describes each fixture as its generator made it', () {
      for (final fixture in fixtures) {
        final result = binding.open(fixture.bytes, width: 32, height: 24);

        expect(result, isA<VideoOpened>(), reason: fixture.file);
        final info = (result as VideoOpened).info;
        expect(info.width, fixture.width, reason: fixture.file);
        expect(info.height, fixture.height, reason: fixture.file);
        expect(info.frameRate, fixture.frameRate, reason: fixture.file);
        expect(info.hasAlpha, fixture.hasAlpha, reason: fixture.file);
        // 60 frames at 30 fps, 30 at 30, 10 at 10: one or two seconds.
        final seconds = fixture.frames / fixture.frameRate;
        expect(
          info.duration!.inMilliseconds,
          closeTo(seconds * 1000, 100),
          reason: fixture.file,
        );
        binding.dispose(result.handle);
      }
    });
  });
}
