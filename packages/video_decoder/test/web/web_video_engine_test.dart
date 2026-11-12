import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_decoder/src/engine/video_element_port.dart';
import 'package:video_decoder/src/engine/video_engine.dart';
import 'package:video_decoder/src/engine/web_video_engine.dart';
import 'package:video_decoder/testing.dart';
import 'package:video_native/video_native.dart';

final _bytes = Uint8List.fromList([1, 2, 3]);
const _metadata = VideoElementMetadata(
  width: 64,
  height: 48,
  duration: Duration(seconds: 1),
  hasAlpha: true,
);

void main() {
  VideoEngineContract.run(() {
    final elements = FakeVideoElements()
      ..accept(_bytes, _metadata, frameCount: 4);
    return VideoEngineHarness(
      open: () async => WebVideoEngine(createPort: elements.create),
      validBytes: _bytes,
      expectedInfo: const VideoInfo(
        width: 64,
        height: 48,
        duration: Duration(seconds: 1),
        frameRate: 0,
        hasAlpha: true,
      ),
      frameCount: 4,
      malformedBytes: Uint8List.fromList([9, 9]),
    );
  });

  group('WebVideoEngine', () {
    late FakeVideoElements elements;

    setUp(() {
      elements = FakeVideoElements()..accept(_bytes, _metadata, frameCount: 3);
    });

    Future<VideoClip> open(WebVideoEngine engine, {Uint8List? bytes}) async {
      final result = await engine.open(bytes ?? _bytes, width: 2, height: 1);
      return (result as VideoClipOpened).clip;
    }

    test(
      'delivers the browser\'s straight RGBA as premultiplied BGRA',
      () async {
        final engine = WebVideoEngine(createPort: elements.create);
        final clip = await open(engine);
        final destination = Uint8List(clip.frameBytes);

        final result = await engine.nextFrame(clip, destination: destination);

        expect(result.status, VideoFrameStatus.frame);
        // [100, 50, 20, 200] straight is [78, 39, 16, 200] premultiplied, and
        // blue comes first.
        expect(destination, [16, 39, 78, 200, 16, 39, 78, 200]);
        await engine.dispose();
      },
    );

    test(
      'opens no more clips than the element cap, and frees a place on close',
      () async {
        final engine = WebVideoEngine(
          createPort: elements.create,
          maxElements: 2,
        );
        final a = await open(engine);
        await open(engine);

        final third = await engine.open(_bytes, width: 2, height: 1);

        expect(
          third,
          isA<VideoClipRejected>().having(
            (r) => r.reason,
            'reason',
            VideoRejection.limitExceeded,
          ),
        );
        expect(elements.created, 2, reason: 'a refused open makes no element');
        await engine.close(a);
        expect(elements.live, 1);
        expect(
          await engine.open(_bytes, width: 2, height: 1),
          isA<VideoClipOpened>(),
        );
        await engine.dispose();
      },
    );

    test('a video that never gets ready is rejected after the timeout and its '
        'element is released', () async {
      final stuck = Uint8List.fromList([7]);
      elements.neverReady(stuck);
      final engine = WebVideoEngine(
        createPort: elements.create,
        metadataTimeout: const Duration(milliseconds: 20),
      );

      final result = await engine.open(stuck, width: 2, height: 1);

      expect(
        result,
        isA<VideoClipRejected>().having(
          (r) => r.reason,
          'reason',
          VideoRejection.unsupported,
        ),
      );
      expect(elements.live, 0);
      await engine.dispose();
    });

    test('the reason the browser gave is the rejection', () async {
      final refused = Uint8List.fromList([8]);
      elements.reject(refused, VideoRejection.unsupported);
      final engine = WebVideoEngine(createPort: elements.create);

      final result = await engine.open(refused, width: 2, height: 1);

      expect((result as VideoClipRejected).reason, VideoRejection.unsupported);
      expect(elements.live, 0);
      await engine.dispose();
    });

    test('a frame the browser cannot draw is a failure, not a throw', () async {
      elements.failFramesFrom(_bytes, after: 1);
      final engine = WebVideoEngine(createPort: elements.create);
      final clip = await open(engine);
      final destination = Uint8List(clip.frameBytes);

      await engine.nextFrame(clip, destination: destination);
      final failed = await engine.nextFrame(clip, destination: destination);

      expect(failed.status, VideoFrameStatus.failed);
      await engine.dispose();
    });

    test('close removes the element', () async {
      final engine = WebVideoEngine(createPort: elements.create);
      final clip = await open(engine);
      expect(elements.live, 1);

      await engine.close(clip);

      expect(elements.live, 0);
      await engine.dispose();
    });

    test(
      'dispose does not wait for a frame a hidden tab never presents',
      () async {
        elements.holdFrames = true;
        final engine = WebVideoEngine(
          createPort: elements.create,
          disposeTimeout: const Duration(milliseconds: 20),
        );
        final clip = await open(engine);
        final destination = Uint8List(clip.frameBytes)..fillRange(0, 8, 0x7f);
        final pending = engine.nextFrame(clip, destination: destination);

        await engine.dispose();

        expect((await pending).status, VideoFrameStatus.failed);
        expect(destination, everyElement(0x7f), reason: 'nothing written late');
        expect(elements.live, 0);
      },
    );
  });
}
