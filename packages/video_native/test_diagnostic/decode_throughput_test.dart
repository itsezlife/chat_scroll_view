// Diagnostic (ticket 61), not in unit_test.dart. Frames per second one decode
// worker sustains through the real binding, per fixture and display edge, and
// how that scales with parallel workers (isolates, as the engine pool runs).
//
//   flutter test test_diagnostic/decode_throughput_test.dart
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_native/video_native.dart';

// ignore: always_use_package_imports
import '../test/support/fixtures.dart';

/// Decodes [fixture] looping for [millis], returns frames decoded.
int _run(Fixture fixture, int edge, int millis) {
  final binding = NativeVideoBinding.probe();
  final bytes = fixture.bytes;
  final h = edge * fixture.height ~/ fixture.width;
  final r = binding.open(bytes, width: edge, height: h) as VideoOpened;
  final target = calloc<Uint8>(edge * h * 4);
  final watch = Stopwatch()..start();
  var frames = 0;
  while (watch.elapsedMilliseconds < millis) {
    final res = binding.nextFrame(
      r.handle,
      target: target,
      strideBytes: edge * 4,
    );
    if (res.status == VideoFrameStatus.frame) {
      frames++;
    } else {
      binding.rewind(r.handle);
    }
  }
  calloc.free(target);
  binding.dispose(r.handle);
  return frames;
}

void main() {
  final binding = NativeVideoBinding.probe();
  test(
    'throughput',
    skip: nativeSkipReason(binding),
    () async {
      for (final fixture in [mp4, webm]) {
        for (final edge in [128, 256, 512]) {
          final row = StringBuffer('${fixture.file} edge=$edge:');
          for (final workers in [1, 2, 3, 4]) {
            final counts = await Future.wait([
              for (var i = 0; i < workers; i++)
                Isolate.run(() => _run(fixture, edge, 1500)),
            ]);
            final perWorker = counts.reduce((a, b) => a + b) / workers / 1.5;
            row.write(' w$workers=${perWorker.toStringAsFixed(0)}fps/worker');
          }
          // ignore: avoid_print
          print(row);
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
