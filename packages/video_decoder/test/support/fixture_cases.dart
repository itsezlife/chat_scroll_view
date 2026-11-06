/// What the real fixtures must do through any engine, shared by the
/// in-process and the isolate native tests.
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_decoder/video_decoder.dart';
import 'package:video_native/video_native.dart';

import 'fixtures.dart';

/// Registers one case per fixture type over engines from [open].
void fixtureCases(Future<VideoEngine> Function() open) {
  for (final fixture in fixtures) {
    test('${fixture.file}: ${fixture.frames} frames, then the end; alpha '
        'only where declared; rewind loops', () async {
      final engine = await open();
      addTearDown(engine.dispose);
      final (width, height) = fixture.target;

      final opened = await engine.open(
        fixture.bytes,
        width: width,
        height: height,
      );
      final clip = (opened as VideoClipOpened).clip;
      final destination = Uint8List(clip.frameBytes);

      expect(clip.info.width, fixture.width);
      expect(clip.info.hasAlpha, fixture.hasAlpha);
      var sawTransparent = false;
      for (var loop = 0; loop < 2; loop++) {
        var count = 0;
        while (true) {
          final result = await engine.nextFrame(clip, destination: destination);
          if (result.status == VideoFrameStatus.endOfStream) break;
          expect(result.status, VideoFrameStatus.frame);
          count++;
          for (var i = 3; i < destination.length; i += 4) {
            if (destination[i] != 255) sawTransparent = true;
          }
        }
        expect(count, fixture.frames, reason: 'loop $loop');
        expect(await engine.rewind(clip), isTrue);
      }
      expect(sawTransparent, fixture.hasAlpha);
    });
  }
}
