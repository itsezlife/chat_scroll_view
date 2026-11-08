import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
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

LottieFrameCodec _fakeCodec() => FakeLottieFrameCodec();

LottieFrameCodec _unavailableCodec() =>
    FakeLottieFrameCodec(isAvailable: false);

LottieBinding _unavailableBinding() =>
    FakeLottieBinding(availability: LottieAvailability.abiMismatch);

LottieBinding _throwOnceBinding() => _ScriptedBinding(throwOnce: true);

LottieBinding _dyingBinding() => _ScriptedBinding();

/// A closure that captures only the port, so it can cross isolates.
LottieBinding Function() _reportingFactory(SendPort port) =>
    () => _ScriptedBinding(report: port);

/// A binding whose render does not return until the file [flag] exists, so a
/// render stays in flight in the isolate for as long as a test wants.
LottieBinding Function() _blockingFactory(String flag) =>
    () => _BlockingBinding(flag);

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

LottieBinding _throwingBinding() => throw StateError('scripted factory');

/// A port that remembers whether it was closed.
final class _RecordingPort extends Stream<dynamic> implements ReceivePort {
  final _inner = ReceivePort();
  bool closed = false;

  @override
  StreamSubscription<dynamic> listen(
    void Function(Object? event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _inner.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  SendPort get sendPort => _inner.sendPort;

  @override
  void close() {
    closed = true;
    _inner.close();
  }
}

final class _BlockingBinding implements LottieBinding {
  _BlockingBinding(this.flag) {
    _fake.accept(_fakeBytes, _fakeInfo);
  }

  final String flag;
  final _fake = FakeLottieBinding();

  @override
  LottieAvailability get availability => _fake.availability;

  @override
  bool get isAvailable => _fake.isAvailable;

  @override
  LottieLoadResult load(Uint8List bytes) => _fake.load(bytes);

  @override
  List<LottieRenderStatus> renderBatch(List<LottieRenderJob> jobs) {
    while (!File(flag).existsSync()) {
      sleep(const Duration(milliseconds: 5));
    }
    return _fake.renderBatch(jobs);
  }

  @override
  void dispose(LottieHandle handle) => _fake.dispose(handle);

  @override
  void close() => _fake.close();
}

void main() {
  group('over the fake binding', () {
    LottieSlotEngineContract.run(
      () => LottieEngineHarness<LottieSlotEngine>(
        open: () async =>
            InProcessLottieEngine(_fakeBinding(), codec: _fakeCodec()),
        validBytes: _fakeBytes,
        expectedInfo: _fakeInfo,
        malformedBytes: Uint8List.fromList([9]),
      ),
    );
  });

  group('in the render isolate over the fake binding', () {
    LottieSlotEngineContract.run(
      () => LottieEngineHarness<LottieSlotEngine>(
        open: () => IsolateLottieEngine.spawn(
          bindingFactory: _fakeBinding,
          codecFactory: _fakeCodec,
        ),
        validBytes: _fakeBytes,
        expectedInfo: _fakeInfo,
        malformedBytes: Uint8List.fromList([9]),
      ),
    );
  });

  group('in the render isolate without a usable frame codec', () {
    late IsolateLottieEngine engine;
    setUp(() async {
      engine = await IsolateLottieEngine.spawn(
        bindingFactory: _fakeBinding,
        codecFactory: _unavailableCodec,
      );
      addTearDown(engine.close);
    });

    test('renderCapturing renders and carries no bytes', () async {
      final handle = ((await engine.load(_fakeBytes)) as LottieLoaded).handle;
      final page = calloc<Uint8>(64 * 64 * 4);
      addTearDown(() => calloc.free(page));

      final captures = await engine.renderCapturing([
        LottieEngineJob(
          handle: handle,
          frame: 3,
          width: 64,
          height: 64,
          address: page.address,
          strideBytes: 64 * 4,
        ),
      ]);

      expect(captures.single.status, LottieRenderStatus.ok);
      expect(captures.single.compressed, isNull);
      expect(page[3], isNot(0));
    });

    test('restore fails every job', () async {
      final page = calloc<Uint8>(64 * 64 * 4);
      addTearDown(() => calloc.free(page));

      final statuses = await engine.restore([
        LottieRestoreJob(
          frame: CachedFrame.bytes(Uint8List.fromList([1, 2, 3])),
          width: 64,
          height: 64,
          address: page.address,
          strideBytes: 64 * 4,
        ),
      ]);

      expect(statuses, [LottieRenderStatus.failed]);
    });
  });

  group('the render isolate', () {
    test('spawn throws, carrying the reason, over an unavailable binding', () {
      expect(
        IsolateLottieEngine.spawn(bindingFactory: _unavailableBinding),
        throwsA(
          isA<LottieUnavailable>().having(
            (e) => e.availability,
            'availability',
            LottieAvailability.abiMismatch,
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

      final closed = throwsA(isA<LottieEngineClosed>());
      await expectLater(doomed, closed);
      await expectLater(alsoPending, closed);
      await expectLater(engine.load(_fakeBytes), closed);
      await expectLater(engine.close(), completes);
    });

    test('a request that cannot be sent leaves nothing pending', () async {
      final engine = await IsolateLottieEngine.spawn(
        bindingFactory: _fakeBinding,
      );
      final jobs = _UnsendableJobs();
      addTearDown(jobs.port.close);

      // A list of a class the isolate protocol cannot copy: send throws.
      expect(() => engine.renderBatch(jobs), throwsArgumentError);

      // A leftover completer would fail unobserved when the isolate ends,
      // and the test would die of an uncaught error.
      await expectLater(engine.close(), completes);
    });

    test('close gives up on a render that never returns, and fails it '
        'with LottieEngineClosed', () async {
      final dir = Directory.systemTemp.createTempSync('isolate_close_');
      final flag = '${dir.path}/release';
      addTearDown(() {
        File(flag).createSync();
        dir.deleteSync(recursive: true);
      });
      final engine = await IsolateLottieEngine.spawn(
        bindingFactory: _blockingFactory(flag),
        closeTimeout: const Duration(milliseconds: 200),
      );
      final handle = ((await engine.load(_fakeBytes)) as LottieLoaded).handle;
      final buffer = calloc<Uint8>(64 * 64 * 4);
      // Never freed while native code may still write: leaked on purpose.
      final render = engine.renderBatch([
        LottieEngineJob(
          handle: handle,
          frame: 0,
          width: 64,
          height: 64,
          address: buffer.address,
          strideBytes: 64 * 4,
        ),
      ]);
      final failed = expectLater(render, throwsA(isA<LottieEngineClosed>()));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      await engine.close().timeout(const Duration(seconds: 5));

      await failed;
    });

    group('a failed spawn', () {
      late List<_RecordingPort> ports;
      late ReceivePort Function() previous;

      setUp(() {
        ports = [];
        previous = IsolateLottieEngine.debugPortFactory;
        IsolateLottieEngine.debugPortFactory = () {
          final port = _RecordingPort();
          ports.add(port);
          return port;
        };
      });
      tearDown(() => IsolateLottieEngine.debugPortFactory = previous);

      test('before the isolate starts surfaces the original error', () async {
        // A closure over a port cannot cross isolates: Isolate.spawn throws.
        final unsendable = ReceivePort();
        addTearDown(unsendable.close);

        await expectLater(
          IsolateLottieEngine.spawn(
            bindingFactory: () {
              unsendable.close();
              return _fakeBinding();
            },
          ),
          throwsA(isA<ArgumentError>()),
        );

        expect(ports, hasLength(3));
        expect(ports.every((p) => p.closed), isTrue);
      });

      test('before ready surfaces the error and closes every port', () async {
        await expectLater(
          IsolateLottieEngine.spawn(bindingFactory: _throwingBinding),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('scripted factory'),
            ),
          ),
        );

        expect(ports, hasLength(3));
        expect(ports.every((p) => p.closed), isTrue);
      });

      test('over an unavailable binding closes every port', () async {
        await expectLater(
          IsolateLottieEngine.spawn(bindingFactory: _unavailableBinding),
          throwsA(isA<LottieUnavailable>()),
        );

        expect(ports, hasLength(3));
        expect(ports.every((p) => p.closed), isTrue);
      });
    });

    test('requests sent before close run to completion', () async {
      final engine = await IsolateLottieEngine.spawn(
        bindingFactory: _fakeBinding,
      );
      final pending = engine.load(_fakeBytes);

      final closing = engine.close();

      expect(await pending, isA<LottieLoaded>());
      await closing;
    });

    test('close waits for a render in flight, which still succeeds', () async {
      // The decoder frees its buffer when the render's future completes, so
      // that future must not complete (least of all with an error) while
      // native code may still write to the buffer.
      final dir = Directory.systemTemp.createTempSync('lottie_close');
      addTearDown(() => dir.deleteSync(recursive: true));
      final flag = '${dir.path}/release';
      final engine = await IsolateLottieEngine.spawn(
        bindingFactory: _blockingFactory(flag),
      );
      final handle = ((await engine.load(_fakeBytes)) as LottieLoaded).handle;
      final buffer = calloc<Uint8>(64 * 64 * 4);
      addTearDown(() => calloc.free(buffer));
      final events = <String>[];
      final render = engine
          .renderBatch([
            LottieEngineJob(
              handle: handle,
              frame: 0,
              width: 64,
              height: 64,
              address: buffer.address,
              strideBytes: 64 * 4,
            ),
          ])
          .then(
            (statuses) {
              events.add('render finished: ${statuses.single.name}');
              return statuses;
            },
            onError: (Object error) {
              events.add('render failed: $error');
              return const <LottieRenderStatus>[];
            },
          );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final closing = engine.close().then((_) => events.add('close completed'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(events, isEmpty, reason: 'the render is still running');

      File(flag).createSync();
      await closing;

      expect(events, ['render finished: ok', 'close completed']);
      expect(await render, [LottieRenderStatus.ok]);
      expect(buffer[3], isNot(0), reason: 'the render wrote its pixels');
    });

    test('a request after close is refused', () async {
      final engine = await IsolateLottieEngine.spawn(
        bindingFactory: _fakeBinding,
      );
      final closing = engine.close();

      await expectLater(
        engine.load(_fakeBytes),
        throwsA(isA<LottieEngineClosed>()),
      );
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
  for (final (name, open) in <(String, Future<LottieSlotEngine> Function())>[
    ('in the render isolate', IsolateLottieEngine.spawn),
    (
      'in process',
      () async => InProcessLottieEngine(
        NativeLottieBinding.probe(),
        codec: NativeLottieFrameCodec.probe(),
      ),
    ),
  ]) {
    group(
      '$name over the native library',
      () {
        LottieSlotEngineContract.run(
          () => LottieEngineHarness<LottieSlotEngine>(
            open: open,
            validBytes: Uint8List.fromList(utf8.encode(_fixture)),
            expectedInfo: const LottieInfo(
              width: 100,
              height: 100,
              frameCount: 60,
              frameRate: 30,
              features: LottieFeatures.none,
            ),
            malformedBytes: Uint8List.fromList(
              utf8.encode('not a lottie file'),
            ),
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

  test('the web-neutral pixel job limit is the binding limit', () {
    expect(LottiePixelJob.maxEdge, LottieRenderJob.maxEdge);
  });
}

/// A list the isolate protocol cannot copy: it holds a port.
final class _UnsendableJobs extends ListBase<LottieEngineJob> {
  final ReceivePort port = ReceivePort();

  @override
  int length = 0;

  @override
  LottieEngineJob operator [](int index) => throw RangeError.index(index, this);

  @override
  void operator []=(int index, LottieEngineJob value) {}
}
