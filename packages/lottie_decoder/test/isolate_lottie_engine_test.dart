import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
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

LottieBinding _unavailableBinding() =>
    FakeLottieBinding(availability: LottieAvailability.abiMismatch);

LottieBinding _throwOnceBinding() => _ScriptedBinding(throwOnce: true);

LottieBinding _dyingBinding() => _ScriptedBinding();

/// A closure that captures only the port, so it can cross isolates.
LottieBinding Function() _reportingFactory(SendPort port) =>
    () => _ScriptedBinding(report: port);

/// The bytes that make [_ScriptedBinding] end its isolate on load.
final _poison = Uint8List.fromList([66]);

/// The fake, plus scripted trouble: a first render that throws, a load that
/// ends the isolate, and a report of the live handles when it is closed.
final class _ScriptedBinding implements LottieBinding {
  _ScriptedBinding({this.throwOnce = false, this.report}) {
    _fake.accept(_fakeBytes, _fakeInfo);
  }

  final bool throwOnce;
  final SendPort? report;
  final _fake = FakeLottieBinding();
  var _thrown = false;

  @override
  LottieAvailability get availability => _fake.availability;

  @override
  bool get isAvailable => _fake.isAvailable;

  @override
  LottieLoadResult load(Uint8List bytes) {
    if (bytes.length == 1 && bytes.first == _poison.first) Isolate.exit();
    return _fake.load(bytes);
  }

  @override
  List<LottieRenderStatus> renderBatch(List<LottieRenderJob> jobs) {
    if (throwOnce && !_thrown) {
      _thrown = true;
      throw StateError('scripted render failure');
    }
    return _fake.renderBatch(jobs);
  }

  @override
  void dispose(LottieHandle handle) => _fake.dispose(handle);

  @override
  void close() {
    report?.send(_fake.liveHandles);
    _fake.close();
  }
}

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

  group('the render isolate', () {
    test('spawn throws, carrying the reason, over an unavailable binding', () {
      expect(
        IsolateLottieEngine.spawn(bindingFactory: _unavailableBinding),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('abiMismatch'),
          ),
        ),
      );
    });

    test(
      'an exception in one request fails it and spares the engine',
      () async {
        final engine = await IsolateLottieEngine.spawn(
          bindingFactory: _throwOnceBinding,
        );
        addTearDown(engine.close);
        final handle = ((await engine.load(_fakeBytes)) as LottieLoaded).handle;
        final page = calloc<Uint8>(64 * 64 * 4);
        addTearDown(() => calloc.free(page));
        final job = LottieEngineJob(
          handle: handle,
          frame: 0,
          width: 64,
          height: 64,
          address: page.address,
          strideBytes: 64 * 4,
        );

        await expectLater(
          engine.renderBatch([job]),
          throwsA(
            isA<RemoteError>()
                .having(
                  (e) => e.toString(),
                  'description',
                  contains('scripted'),
                )
                .having((e) => e.stackTrace.toString(), 'stack', isNotEmpty),
          ),
        );
        expect(await engine.renderBatch([job]), [LottieRenderStatus.ok]);
      },
    );

    test('the isolate ending fails every pending request and closes', () async {
      final engine = await IsolateLottieEngine.spawn(
        bindingFactory: _dyingBinding,
      );
      final doomed = engine.load(_poison);
      final alsoPending = engine.load(_fakeBytes);

      await expectLater(doomed, throwsStateError);
      await expectLater(alsoPending, throwsStateError);
      await expectLater(engine.load(_fakeBytes), throwsStateError);
      await expectLater(engine.close(), completes);
    });

    test('requests pending at close fail', () async {
      final engine = await IsolateLottieEngine.spawn(
        bindingFactory: _fakeBinding,
      );
      final pending = engine.load(_fakeBytes);

      final closing = engine.close();

      await expectLater(pending, throwsStateError);
      await closing;
    });

    test('200 renders in a row leave no handle behind', () async {
      final reports = ReceivePort();
      addTearDown(reports.close);
      final live = reports.first;
      final engine = await IsolateLottieEngine.spawn(
        bindingFactory: _reportingFactory(reports.sendPort),
      );
      final page = calloc<Uint8>(64 * 64 * 4);
      addTearDown(() => calloc.free(page));

      for (var i = 0; i < 200; i++) {
        final handle = ((await engine.load(_fakeBytes)) as LottieLoaded).handle;
        final statuses = await engine.renderBatch([
          LottieEngineJob(
            handle: handle,
            frame: i % 10,
            width: 64,
            height: 64,
            address: page.address,
            strideBytes: 64 * 4,
          ),
        ]);
        expect(statuses, [LottieRenderStatus.ok]);
        await engine.dispose(handle);
      }
      await engine.close();

      expect(await live, 0);
    });
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
