import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_native/video_native.dart';

// ignore: always_use_package_imports
import 'support/missing_abi_symbol.dart';

void main() {
  group('a binding over a symbol the library does not export', () {
    test('reports unavailable, and open throws StateError', () {
      final binding = NativeVideoBinding.probing(missingAbiVersion);

      expect(binding.isAvailable, isFalse);
      expect(binding.availability, VideoAvailability.missingLibrary);
      expect(
        () => binding.open(Uint8List(8), width: 8, height: 8),
        throwsStateError,
      );
      expect(() => binding.rewind(const VideoHandle(1)), throwsStateError);
    });

    test('says the ABI differs for a version other than the expected', () {
      final other = NativeVideoBinding.probing(() => 2);
      final same = NativeVideoBinding.probing(() => 1);

      expect(other.availability, VideoAvailability.abiMismatch);
      expect(same.availability, VideoAvailability.available);
    });

    test('lets any other error out of the probe', () {
      expect(
        () => NativeVideoBinding.probing(() => throw StateError('bug')),
        throwsStateError,
      );
    });
  });

  group('rejectionFor', () {
    test('maps each open status to its rejection', () {
      expect(NativeVideoBinding.rejectionFor(-2), VideoRejection.tooLarge);
      expect(NativeVideoBinding.rejectionFor(-3), VideoRejection.malformed);
      expect(NativeVideoBinding.rejectionFor(-4), VideoRejection.limitExceeded);
      expect(NativeVideoBinding.rejectionFor(-5), VideoRejection.unsupported);
      expect(NativeVideoBinding.rejectionFor(-6), VideoRejection.internal);
      expect(NativeVideoBinding.rejectionFor(-7), VideoRejection.badSize);
    });

    test('treats a status it does not know as a malformed file', () {
      expect(NativeVideoBinding.rejectionFor(-99), VideoRejection.malformed);
    });
  });
}
