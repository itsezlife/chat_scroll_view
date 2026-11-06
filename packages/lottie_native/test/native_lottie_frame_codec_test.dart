import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_native/lottie_native.dart';
import 'package:lottie_native/testing.dart';

// ignore: always_use_package_imports
import 'support/missing_abi_symbol.dart';

void main() {
  group('a codec over a library that lacks the symbols', () {
    test('is unavailable when the ABI symbol is missing', () {
      final codec = NativeLottieFrameCodec.probing(
        abiVersion: missingAbiVersion,
        bound: (_, _) => 0,
      );

      expect(codec.isAvailable, isFalse);
    });

    test('is unavailable when the ABI version differs', () {
      final codec = NativeLottieFrameCodec.probing(
        abiVersion: () => 2,
        bound: (_, _) => 0,
      );

      expect(codec.isAvailable, isFalse);
    });

    test('is unavailable when the lz4 symbol is missing', () {
      final codec = NativeLottieFrameCodec.probing(
        abiVersion: () => 1,
        bound: missingLz4Bound,
      );

      expect(codec.isAvailable, isFalse);
    });

    test('is available when both symbols answer', () {
      final codec = NativeLottieFrameCodec.probing(
        abiVersion: () => 1,
        bound: (_, _) => 1,
      );

      expect(codec.isAvailable, isTrue);
    });

    test('lets any other error out of the probe', () {
      expect(
        () => NativeLottieFrameCodec.probing(
          abiVersion: () => 1,
          bound: (_, _) => throw StateError('bug'),
        ),
        throwsStateError,
      );
    });
  });

  final probe = NativeLottieFrameCodec.probe();
  if (!probe.isAvailable) {
    test(
      'the frame codec contract over the native library',
      () {},
      skip:
          'The native library is absent or speaks another ABI version: the '
          'build hook compiles it with cargo on macOS only (rustup.rs).',
    );
    return;
  }

  LottieFrameCodecContract.run(
    () => LottieFrameCodecHarness(
      codec: NativeLottieFrameCodec.probe(),
      unavailable: () => NativeLottieFrameCodec.probing(
        abiVersion: missingAbiVersion,
        bound: (_, _) => 0,
      ),
    ),
  );
}
