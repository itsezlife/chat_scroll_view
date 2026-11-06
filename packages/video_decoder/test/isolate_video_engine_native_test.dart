import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_decoder/testing.dart';
import 'package:video_decoder/video_decoder.dart';
import 'package:video_native/video_native.dart';

import 'support/fixture_cases.dart';
import 'support/fixtures.dart';

Future<VideoEngine> _open() => IsolateVideoEngine.spawn();

void main() {
  group(
    'IsolateVideoEngine over the native binding',
    skip: nativeSkipReason(),
    () {
      VideoEngineContract.run(
        () => VideoEngineHarness(
          open: _open,
          validBytes: mp4.bytes,
          expectedInfo: const VideoInfo(
            width: 320,
            height: 240,
            duration: Duration(milliseconds: 2000),
            frameRate: 30,
            hasAlpha: false,
          ),
          frameCount: mp4.frames,
          malformedBytes: Uint8List(2048),
        ),
      );
      group('fixtures', () => fixtureCases(_open));

      test('mixed fixtures decode at once on a pool of two', () async {
        final engine = await IsolateVideoEngine.spawn();
        addTearDown(engine.dispose);

        final counts = await Future.wait([
          for (final fixture in fixtures)
            () async {
              final (w, h) = fixture.target;
              final opened = await engine.open(
                fixture.bytes,
                width: w,
                height: h,
              );
              final clip = (opened as VideoClipOpened).clip;
              final destination = Uint8List(clip.frameBytes);
              var count = 0;
              while ((await engine.nextFrame(
                    clip,
                    destination: destination,
                  )).status ==
                  VideoFrameStatus.frame) {
                count++;
              }
              return count;
            }(),
        ]);

        expect(counts, [for (final f in fixtures) f.frames]);
      });
    },
  );
}
