import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/lottie_decoder.dart';
import 'package:lottie_decoder/testing.dart';
import 'package:lottie_native/lottie_native.dart';
import 'package:lottie_native/testing.dart';

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

final _fakeBytes = Uint8List.fromList([1, 2, 3]);
const _fakeInfo = LottieInfo(
  width: 64,
  height: 64,
  frameCount: 10,
  frameRate: 30,
  features: LottieFeatures.none,
);

/// The isolate builds its binding from a top-level function: a binding is
/// single-isolate state and must be created where it is used.
LottieBinding _fakeBinding() =>
    FakeLottieBinding()..accept(_fakeBytes, _fakeInfo);

void main() {
  group('over the fake binding', () {
    LottieEngineContract.run(
      () => LottieEngineHarness(
        open: () async => InProcessLottieEngine(_fakeBinding()),
        validBytes: _fakeBytes,
        expectedInfo: _fakeInfo,
        malformedBytes: Uint8List.fromList([9]),
      ),
    );
  });

  group('in the render isolate over the fake binding', () {
    LottieEngineContract.run(
      () => LottieEngineHarness(
        open: () => IsolateLottieEngine.spawn(bindingFactory: _fakeBinding),
        validBytes: _fakeBytes,
        expectedInfo: _fakeInfo,
        malformedBytes: Uint8List.fromList([9]),
      ),
    );
  });

  final native = NativeLottieBinding.probe().isAvailable;
  group(
    'in the render isolate over the native library',
    () {
      LottieEngineContract.run(
        () => LottieEngineHarness(
          open: IsolateLottieEngine.spawn,
          validBytes: Uint8List.fromList(utf8.encode(_fixture)),
          expectedInfo: const LottieInfo(
            width: 100,
            height: 100,
            frameCount: 60,
            frameRate: 30,
            features: LottieFeatures.none,
          ),
          malformedBytes: Uint8List.fromList(utf8.encode('not a lottie file')),
          frame: 20,
        ),
      );
    },
    skip: native
        ? false
        : 'The native library is absent or speaks another ABI version: the '
              'build hook compiles it with cargo on macOS only (rustup.rs).',
  );
}
