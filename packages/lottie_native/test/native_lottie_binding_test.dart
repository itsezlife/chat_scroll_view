import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_native/lottie_native.dart';
import 'package:lottie_native/testing.dart';

// ignore: always_use_package_imports
import 'support/missing_abi_symbol.dart';

/// A hand-authored 100x100, 30 fps, 60 frame animation: one rotating 60x60
/// square filled with 50% opaque orange. Not a corpus sticker.
const _fixture = '''
{"v":"5.5.2","fr":30,"ip":0,"op":60,"w":100,"h":100,"nm":"fixture","ddd":0,
"assets":[],
"layers":[{"ddd":0,"ind":1,"ty":4,"nm":"square","sr":1,
"ks":{"o":{"a":0,"k":100},
"r":{"a":1,"k":[{"t":0,"s":[0],"i":{"x":[0.5],"y":[1]},"o":{"x":[0.5],"y":[0]}},{"t":60,"s":[90]}]},
"p":{"a":0,"k":[50,50,0]},"a":{"a":0,"k":[0,0,0]},"s":{"a":0,"k":[100,100,100]}},
"ao":0,
"shapes":[{"ty":"gr","it":[
{"ty":"rc","d":1,"s":{"a":0,"k":[60,60]},"p":{"a":0,"k":[0,0]},"r":{"a":0,"k":0}},
{"ty":"fl","c":{"a":0,"k":[1,0.5,0.25,1]},"o":{"a":0,"k":50},"r":1},
{"ty":"tr","p":{"a":0,"k":[0,0]},"a":{"a":0,"k":[0,0]},"s":{"a":0,"k":[100,100]},"r":{"a":0,"k":0},"o":{"a":0,"k":100}}
]}],"ip":0,"op":60,"st":0,"bm":0}]}''';

void main() {
  group('a binding over a symbol the library does not export', () {
    test('reports unavailable, and load throws StateError', () {
      final binding = NativeLottieBinding.probing(missingAbiVersion);

      expect(binding.isAvailable, isFalse);
      expect(
        () => binding.load(Uint8List.fromList(utf8.encode(_fixture))),
        throwsStateError,
      );
      expect(() => binding.renderBatch(const []), throwsStateError);
    });

    test('says the library is missing', () {
      expect(
        NativeLottieBinding.probing(missingAbiVersion).availability,
        LottieAvailability.missingLibrary,
      );
    });

    test('says the ABI differs for a version other than 1', () {
      final other = NativeLottieBinding.probing(() => 2);

      expect(other.isAvailable, isFalse);
      expect(other.availability, LottieAvailability.abiMismatch);
      final same = NativeLottieBinding.probing(() => 1);
      expect(same.isAvailable, isTrue);
      expect(same.availability, LottieAvailability.available);
    });

    test('lets any other error out of the probe', () {
      expect(
        () => NativeLottieBinding.probing(() => throw StateError('bug')),
        throwsStateError,
      );
    });
  });

  group('status mapping', () {
    test('each load status reads as one rejection', () {
      expect(
        {
          for (final status in [-2, -3, -4, -5, -6])
            status: NativeLottieBinding.rejectionFor(status),
        },
        {
          -2: LottieRejection.tooLarge,
          -3: LottieRejection.malformed,
          -4: LottieRejection.limitExceeded,
          -5: LottieRejection.unsupported,
          -6: LottieRejection.internal,
        },
      );
    });

    test('each render status reads as one job status', () {
      expect(
        {
          for (final status in [0, -1, -6, -7, -8])
            status: NativeLottieBinding.renderStatusFor(status),
        },
        {
          0: LottieRenderStatus.ok,
          -1: LottieRenderStatus.badArgument,
          -6: LottieRenderStatus.failed,
          -7: LottieRenderStatus.badSize,
          -8: LottieRenderStatus.failed,
        },
      );
    });
  });

  final probe = NativeLottieBinding.probe();
  if (!probe.isAvailable) {
    test(
      'the contract over the native library',
      () {},
      skip:
          'The native library is absent or speaks another ABI version: the '
          'build hook compiles it with cargo on macOS only (rustup.rs).',
    );
    return;
  }

  NativeBindingContract.run(
    () => NativeBindingHarness(
      binding: NativeLottieBinding.probe(),
      validBytes: Uint8List.fromList(utf8.encode(_fixture)),
      expectedInfo: const LottieInfo(
        width: 100,
        height: 100,
        frameCount: 60,
        frameRate: 30,
        features: LottieFeatures.none,
      ),
      malformedBytes: Uint8List.fromList(utf8.encode('not a lottie file')),
      earlyFrame: 0,
      laterFrame: 20,
      unavailable: () => NativeLottieBinding.probing(missingAbiVersion),
    ),
  );
}
