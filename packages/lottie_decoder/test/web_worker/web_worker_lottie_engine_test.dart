import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie_decoder/lottie_decoder.dart';
import 'package:lottie_decoder/testing.dart';
import 'package:lottie_native/lottie_native.dart';

/// The protocol layer of the web engine, against a scripted worker: what the
/// engine posts, what it makes of each reply, and how it ends. The worker file
/// itself is exercised in Node by `lottie_native`.
void main() {
  final wasm = Uri.parse('https://host.test/chat_lottie.wasm');
  final wasmNoSimd = Uri.parse('https://host.test/chat_lottie_nosimd.wasm');

  Future<WebWorkerLottieEngine> spawn(
    FakeLottieWorker worker, {
    Duration? readyTimeout,
  }) => WebWorkerLottieEngine.spawn(
    worker.port,
    wasmUrl: wasm,
    wasmNoSimdUrl: wasmNoSimd,
    readyTimeout: readyTimeout ?? const Duration(seconds: 10),
  );

  group('the handshake', () {
    test('posts init with both wasm urls and waits for ready', () async {
      final worker = FakeLottieWorker();

      final engine = await spawn(worker);
      addTearDown(engine.close);

      expect(worker.received.first, {
        'type': 'init',
        'wasmUrl': 'https://host.test/chat_lottie.wasm',
        'wasmNoSimdUrl': 'https://host.test/chat_lottie_nosimd.wasm',
      });
      expect(engine.simd, isTrue);
    });

    test('ready reports which build the worker chose', () async {
      final engine = await spawn(FakeLottieWorker(simd: false));
      addTearDown(engine.close);

      expect(engine.simd, isFalse);
    });

    test('unavailable throws LottieUnavailable with the reason and ends the '
        'worker', () async {
      final worker = FakeLottieWorker(unavailableReason: 'wasm refused');

      await expectLater(
        spawn(worker),
        throwsA(
          isA<LottieUnavailable>()
              .having(
                (e) => e.availability,
                'availability',
                LottieAvailability.missingLibrary,
              )
              .having((e) => e.toString(), 'message', contains('wasm refused')),
        ),
      );
      expect(worker.terminated, isTrue);
    });

    test('a worker failure before ready is unavailable, and ends the '
        'worker', () async {
      final worker = FakeLottieWorker(answersInit: false);

      final spawning = spawn(worker);
      worker.die();

      await expectLater(
        spawning,
        throwsA(
          isA<LottieUnavailable>().having(
            (e) => e.availability,
            'availability',
            LottieAvailability.missingLibrary,
          ),
        ),
      );
      expect(worker.terminated, isTrue);
    });

    test('no answer within the timeout is unavailable, and ends the '
        'worker', () {
      fakeAsync((async) {
        final worker = FakeLottieWorker(answersInit: false);
        Object? error;
        spawn(
          worker,
          readyTimeout: const Duration(seconds: 3),
        ).then<void>((_) {}, onError: (Object e) => error = e);

        async.elapse(const Duration(seconds: 2));
        expect(error, isNull, reason: 'gave up before its timeout');
        expect(worker.terminated, isFalse);

        async.elapse(const Duration(seconds: 2));
        expect(error, isA<LottieUnavailable>());
        expect(worker.terminated, isTrue);
      });
    });

    test('the default timeout is ten seconds', () {
      fakeAsync((async) {
        final worker = FakeLottieWorker(answersInit: false);
        Object? error;
        WebWorkerLottieEngine.spawn(
          worker.port,
          wasmUrl: wasm,
          wasmNoSimdUrl: wasmNoSimd,
        ).then<void>((_) {}, onError: (Object e) => error = e);

        async.elapse(const Duration(milliseconds: 9999));
        expect(error, isNull);
        async.elapse(const Duration(milliseconds: 2));
        expect(error, isA<LottieUnavailable>());
      });
    });
  });

  group('requests', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final other = Uint8List.fromList([4, 5, 6]);
    const info = LottieInfo(
      width: 64,
      height: 48,
      frameCount: 10,
      frameRate: 30,
      features: LottieFeatures.textLayers,
    );
    const otherInfo = LottieInfo(
      width: 32,
      height: 32,
      frameCount: 3,
      frameRate: 24,
      features: LottieFeatures.none,
    );

    late FakeLottieWorker worker;
    late WebWorkerLottieEngine engine;

    setUp(() async {
      worker = FakeLottieWorker();
      worker.core
        ..accept(bytes, info)
        ..accept(other, otherInfo);
      engine = await spawn(worker);
      addTearDown(engine.close);
    });

    LottiePixelJob jobOf(LottieHandle handle, {int frame = 0}) =>
        LottiePixelJob(
          handle: handle,
          frame: frame.toDouble(),
          width: 4,
          height: 2,
        );

    Future<LottieHandle> load([Uint8List? file]) async =>
        ((await engine.load(file ?? bytes)) as LottieLoaded).handle;

    List<Map<String, Object?>> posted(String type) => [
      for (final m in worker.received)
        if (m['type'] == type) m,
    ];

    test(
      'load posts the bytes under a fresh id and reads the info back',
      () async {
        final result = await engine.load(bytes);

        expect((result as LottieLoaded).info, info);
        final request = posted('load').single;
        expect(request['bytes'], bytes);
        expect(request['id'], isA<int>());
      },
    );

    test('a load status becomes the rejection it stands for', () async {
      worker.core.reject(
        Uint8List.fromList([9]),
        LottieRejection.limitExceeded,
      );

      final result = await engine.load(Uint8List.fromList([9]));

      expect((result as LottieRejected).reason, LottieRejection.limitExceeded);
    });

    test('a failed load reply spares the next request', () async {
      worker.failNextRequest('boom');

      await expectLater(
        engine.load(bytes),
        throwsA(
          isA<LottieWorkerError>().having((e) => e.message, 'message', 'boom'),
        ),
      );
      expect(await engine.load(bytes), isA<LottieLoaded>());
    });

    test('renderPixels sends only the jobs that can render, and answers '
        'every job in order', () async {
      final handle = await load();

      final pixels = await engine.renderPixels([
        LottiePixelJob(handle: handle, frame: 1, width: 0, height: 2),
        jobOf(handle, frame: 5),
      ]);

      expect(pixels[0], isNull);
      expect(pixels[1], hasLength(4 * 2 * 4));
      final sent = (posted('render').single['jobs']! as List).single as Map;
      expect(sent, {
        'handle': handle.id,
        'frame': 5.0,
        'width': 4,
        'height': 2,
      });
    });

    test(
      'a buffer of the wrong size is a failed job, not an exception',
      () async {
        final handle = await load();
        worker.sendShortPixels();

        final pixels = await engine.renderPixels([
          jobOf(handle),
          jobOf(handle),
        ]);

        expect(pixels, [null, null]);
      },
    );

    test('replies are matched to their request by id, in any order', () async {
      final first = await load(bytes);
      final second = await load(other);
      worker.holdReplies = true;

      final firstInfo = engine.renderPixels([jobOf(first, frame: 7)]);
      final secondInfo = engine.renderPixels([jobOf(second, frame: 9)]);
      await pumpEventQueue();
      worker.release((replies) => replies.reversed.toList());

      expect((await firstInfo).single![2], 7, reason: 'frame 7 of the first');
      expect((await secondInfo).single![2], 9, reason: 'frame 9 of the second');
    });

    test('requests are posted in call order', () async {
      final handle = await load();

      await Future.wait([
        engine.renderPixels([jobOf(handle)]),
        engine.dispose(handle),
      ]);

      final types = [for (final m in worker.received) m['type']];
      expect(types, ['init', 'load', 'render', 'dispose']);
    });

    test('a failed request leaves the next one working', () async {
      final handle = await load();
      worker.failNextRequest('render blew up');

      await expectLater(
        engine.renderPixels([jobOf(handle)]),
        throwsA(isA<LottieWorkerError>()),
      );
      expect(await engine.renderPixels([jobOf(handle)]), isNotEmpty);
    });

    test('the worker dying fails every pending request and closes the '
        'engine', () async {
      final handle = await load();
      worker.holdReplies = true;
      final pending = [
        engine.renderPixels([jobOf(handle)]),
        engine.load(bytes),
      ];
      await pumpEventQueue();

      worker.die();

      for (final request in pending) {
        await expectLater(
          request,
          throwsA(
            isA<LottieEngineClosed>().having(
              (e) => e.message,
              'message',
              'the worker ended',
            ),
          ),
        );
      }
      expect(worker.terminated, isTrue);
      await expectLater(engine.load(bytes), throwsA(isA<LottieEngineClosed>()));
      await expectLater(engine.close(), completes);
    });

    test('close lets requests already made finish first, then ends the '
        'worker', () async {
      final handle = await load();

      final render = engine.renderPixels([jobOf(handle)]);
      final closing = engine.close();

      expect(await render, isNotEmpty);
      await closing;
      expect(worker.received.last['type'], 'close');
      expect(worker.terminated, isTrue);
    });
  });

  LottieEngineContract.run(() {
    final bytes = Uint8List.fromList(utf8.encode('{"fake": "lottie"}'));
    const info = LottieInfo(
      width: 64,
      height: 64,
      frameCount: 10,
      frameRate: 30,
      features: LottieFeatures.none,
    );
    return LottieEngineHarness<WebWorkerLottieEngine>(
      open: () {
        final worker = FakeLottieWorker();
        worker.core.accept(bytes, info);
        return spawn(worker);
      },
      validBytes: bytes,
      expectedInfo: info,
      malformedBytes: Uint8List.fromList(utf8.encode('not lottie')),
    );
  });
}
