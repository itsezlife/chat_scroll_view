import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_decoder/testing.dart';
import 'package:video_decoder/video_decoder.dart';
import 'package:video_native/testing.dart';
import 'package:video_native/video_native.dart';

final _bytes = Uint8List.fromList([1, 2, 3]);
const _info = VideoInfo(
  width: 64,
  height: 48,
  duration: Duration(milliseconds: 1200),
  frameRate: 10,
  hasAlpha: false,
);
const _frames = 12;

/// Bytes that make [_ScriptedBinding] misbehave on the first `nextFrame`.
final _endsIsolate = Uint8List.fromList([66]);
final _throws = Uint8List.fromList([67]);
final _blocks = Uint8List.fromList([68]);

// The isolate builds its binding from a top-level function: a binding is
// single-isolate state and must be created where it is used.
VideoBinding _fakeBinding() => _ScriptedBinding(null);

VideoBinding _unavailableBinding() =>
    FakeVideoBinding(availability: VideoAvailability.abiMismatch);

/// A closure that captures only a string, so it can cross isolates.
VideoBinding Function() _blockingFactory(String flag) =>
    () => _ScriptedBinding(flag);

/// The fake, plus scripted trouble on `nextFrame`: an isolate that ends, a
/// binding that throws, and one that does not return until the file [flag]
/// exists.
final class _ScriptedBinding implements VideoBinding {
  _ScriptedBinding(this.flag) {
    for (final bytes in [_bytes, _endsIsolate, _throws, _blocks]) {
      _fake.accept(bytes, _info, frameCount: _frames);
    }
  }

  final String? flag;
  final _fake = FakeVideoBinding();
  final _trouble = <int, Uint8List>{};

  @override
  VideoAvailability get availability => _fake.availability;
  @override
  bool get isAvailable => _fake.isAvailable;

  @override
  VideoOpenResult open(
    Uint8List bytes, {
    required int width,
    required int height,
  }) {
    final result = _fake.open(bytes, width: width, height: height);
    if (result is VideoOpened) _trouble[result.handle.id] = bytes;
    return result;
  }

  @override
  VideoFrameResult nextFrame(
    VideoHandle handle, {
    required Pointer<Uint8> target,
    required int strideBytes,
  }) {
    final bytes = _trouble[handle.id];
    if (bytes != null && bytes.length == 1) {
      switch (bytes.single) {
        case 66:
          Isolate.exit();
        case 67:
          throw StateError('scripted decode failure');
        case 68:
          while (!File(flag!).existsSync()) {
            sleep(const Duration(milliseconds: 5));
          }
      }
    }
    return _fake.nextFrame(handle, target: target, strideBytes: strideBytes);
  }

  @override
  bool rewind(VideoHandle handle) => _fake.rewind(handle);

  @override
  void dispose(VideoHandle handle) {
    _trouble.remove(handle.id);
    _fake.dispose(handle);
  }

  @override
  void close() => _fake.close();
}

Future<IsolateVideoEngine> _spawn({
  int workers = 2,
  VideoBinding Function()? bindingFactory,
  Duration closeTimeout = const Duration(seconds: 10),
}) => IsolateVideoEngine.spawn(
  workers: workers,
  bindingFactory: bindingFactory ?? _fakeBinding,
  closeTimeout: closeTimeout,
);

Future<VideoClip> _open(VideoEngine engine, [Uint8List? bytes]) async {
  final result = await engine.open(bytes ?? _bytes, width: 8, height: 6);
  return (result as VideoClipOpened).clip;
}

void main() {
  group('IsolateVideoEngine over the fake binding', () {
    VideoEngineContract.run(
      () => VideoEngineHarness(
        open: _spawn,
        validBytes: _bytes,
        expectedInfo: _info,
        frameCount: _frames,
        malformedBytes: Uint8List.fromList([9, 9]),
      ),
    );

    test('a pool size outside 1..4 is refused', () {
      expect(() => _spawn(workers: 0), throwsRangeError);
      expect(() => _spawn(workers: 5), throwsRangeError);
    });

    test('a binding that is not available is VideoUnavailable', () async {
      await expectLater(
        _spawn(bindingFactory: _unavailableBinding),
        throwsA(
          isA<VideoUnavailable>().having(
            (e) => e.availability,
            'availability',
            VideoAvailability.abiMismatch,
          ),
        ),
      );
    });

    test('clips spread over the workers, fewest clips first', () async {
      final engine = await _spawn();
      addTearDown(engine.dispose);

      final clips = [for (var i = 0; i < 4; i++) await _open(engine)];

      expect([for (final c in clips) engine.workerOf(c)], [0, 1, 0, 1]);
      await engine.close(clips[0]);
      expect(engine.workerOf(await _open(engine)), 0);
    });

    test('eight clips on two workers all progress, each in order', () async {
      final engine = await _spawn();
      addTearDown(engine.dispose);
      final clips = [for (var i = 0; i < 8; i++) await _open(engine)];

      // Every clip asks for all its frames at once, un-awaited: the workers
      // interleave the clips, and each clip's answers must still be in order
      // and match the frame written to their own destination.
      final runs = [
        for (final clip in clips)
          () async {
            final destinations = [
              for (var i = 0; i < _frames; i++) Uint8List(clip.frameBytes),
            ];
            final results = await Future.wait([
              for (final d in destinations)
                engine.nextFrame(clip, destination: d),
            ]);
            return (results, destinations);
          }(),
      ];

      for (final (results, destinations) in await Future.wait(runs)) {
        expect([
          for (final r in results) r.status,
        ], everyElement(VideoFrameStatus.frame));
        for (var i = 0; i < _frames; i++) {
          expect(results[i].ptsMs, i * 100, reason: 'frame $i in order');
          // The fake's blue channel is a function of the frame index, so a
          // destination crossed with another request's frame shows here.
          expect(destinations[i][0], (i * 16) % 201, reason: 'pixels $i');
        }
      }
    });

    test('a decode that blocks one worker does not hold the other', () async {
      final flag = '${Directory.systemTemp.path}/video_block_${pid}_flag';
      final file = File(flag);
      if (file.existsSync()) file.deleteSync();
      final engine = await _spawn(bindingFactory: _blockingFactory(flag));
      addTearDown(() async {
        if (!file.existsSync()) file.createSync();
        await engine.dispose();
        file.deleteSync();
      });
      final blocked = await _open(engine, _blocks);
      final free = await _open(engine);
      expect(engine.workerOf(blocked), isNot(engine.workerOf(free)));

      final stuck = engine.nextFrame(
        blocked,
        destination: Uint8List(blocked.frameBytes),
      );
      final results = [
        for (var i = 0; i < 3; i++)
          await engine.nextFrame(free, destination: Uint8List(free.frameBytes)),
      ];
      var stuckDone = false;
      unawaited(stuck.then((_) => stuckDone = true));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect([
        for (final r in results) r.status,
      ], everyElement(VideoFrameStatus.frame));
      expect(stuckDone, isFalse);
      file.createSync();
      expect((await stuck).status, VideoFrameStatus.frame);
    });

    test('a Dart exception in a decode fails that request only', () async {
      final engine = await _spawn();
      addTearDown(engine.dispose);
      final bad = await _open(engine, _throws);
      final good = await _open(engine);

      await expectLater(
        engine.nextFrame(bad, destination: Uint8List(bad.frameBytes)),
        throwsA(isA<RemoteError>()),
      );

      final after = await engine.nextFrame(
        good,
        destination: Uint8List(good.frameBytes),
      );
      expect(after.status, VideoFrameStatus.frame);
      expect(await engine.rewind(bad), isTrue, reason: 'the worker lives');
    });

    test('a worker that ends fails only its own clips', () async {
      final engine = await _spawn();
      addTearDown(engine.dispose);
      final dying = await _open(engine, _endsIsolate); // worker 0
      final sibling = await _open(engine); // worker 1
      final alsoOnDying = await _open(engine); // worker 0
      final otherSurvivor = await _open(engine); // worker 1
      expect(engine.workerOf(dying), engine.workerOf(alsoOnDying));
      final dyingCall = engine.nextFrame(
        dying,
        destination: Uint8List(dying.frameBytes),
      );
      // Sent after the call that ends the worker, so still pending when it
      // goes.
      final queued = engine.nextFrame(
        alsoOnDying,
        destination: Uint8List(alsoOnDying.frameBytes),
      );
      unawaited(queued.then((_) {}, onError: (_) {}));

      await expectLater(dyingCall, throwsA(isA<VideoClipLost>()));

      await expectLater(queued, throwsA(isA<VideoClipLost>()));
      await expectLater(
        engine.rewind(alsoOnDying),
        throwsA(isA<VideoClipLost>()),
      );
      await engine.close(dying); // harmless
      for (final survivor in [sibling, otherSurvivor]) {
        final result = await engine.nextFrame(
          survivor,
          destination: Uint8List(survivor.frameBytes),
        );
        expect(result.status, VideoFrameStatus.frame);
      }
      // New clips land on the worker that still runs.
      final fresh = await _open(engine);
      expect(engine.workerOf(fresh), engine.workerOf(sibling));
    });

    test('when every worker has ended the engine reports it closed', () async {
      final engine = await _spawn(workers: 1);
      addTearDown(engine.dispose);
      final dying = await _open(engine, _endsIsolate);
      await expectLater(
        engine.nextFrame(dying, destination: Uint8List(dying.frameBytes)),
        throwsA(isA<VideoClipLost>()),
      );

      await expectLater(_open(engine), throwsA(isA<VideoEngineClosed>()));
    });

    test('dispose lets requests already made finish', () async {
      final engine = await _spawn();
      final clip = await _open(engine);
      final pending = [
        for (var i = 0; i < 5; i++)
          engine.nextFrame(clip, destination: Uint8List(clip.frameBytes)),
      ];

      await engine.dispose();

      final results = await Future.wait(pending);
      expect([for (final r in results) r.ptsMs], [0, 100, 200, 300, 400]);
    });

    test(
      'dispose is bounded: a decode that never returns is abandoned',
      () async {
        final flag = '${Directory.systemTemp.path}/video_never_${pid}_flag';
        final engine = await _spawn(
          workers: 1,
          bindingFactory: _blockingFactory(flag),
          closeTimeout: const Duration(milliseconds: 200),
        );
        final stuck = await _open(engine, _blocks);
        final pending = engine.nextFrame(
          stuck,
          destination: Uint8List(stuck.frameBytes),
        );
        unawaited(pending.then((_) {}, onError: (_) {}));

        await engine.dispose().timeout(const Duration(seconds: 5));

        await expectLater(pending, throwsA(isA<VideoEngineClosed>()));
      },
    );
  });
}
