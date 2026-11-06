import 'dart:convert';
import 'dart:typed_data';

import 'package:lottie_decoder/src/engine/lottie_engine.dart';
import 'package:lottie_native/lottie_native.dart';

/// A [LottieEngine] without a library, and without any slot method: the
/// engine a web host has, over scripted files.
///
/// Every pixel of a frame is opaque and carries its place, so a copy that
/// moves a row, a pixel or a frame to the wrong place shows:
/// `[x % 256, y % 256, frame % 256, 255]`, which [pixelAt] spells out.
final class FakePixelLottieEngine implements LottieEngine {
  final _scripted = <String, LottieInfo>{};
  final _live = <int, LottieInfo>{};
  var _nextHandle = 1;
  var _closed = false;

  /// How many loaded handles are not yet disposed.
  int get liveHandles => _live.length;

  /// Makes [bytes] load as an animation described by [info]; other bytes are
  /// refused as [LottieRejection.malformed].
  void accept(Uint8List bytes, LottieInfo info) {
    _scripted[base64.encode(bytes)] = info;
  }

  /// The pixel this engine draws at column [x], row [y] of [frame].
  static List<int> pixelAt(int x, int y, int frame) => [
    x % 256,
    y % 256,
    frame % 256,
    255,
  ];

  void _requireOpen() {
    if (_closed) throw LottieEngineClosed();
  }

  @override
  Future<LottieLoadResult> load(Uint8List bytes) async {
    _requireOpen();
    final info = _scripted[base64.encode(bytes)];
    if (info == null) {
      return const LottieRejected(LottieRejection.malformed);
    }
    final id = _nextHandle++;
    _live[id] = info;
    return LottieLoaded(LottieHandle(id), info);
  }

  @override
  Future<List<LottiePixels?>> renderPixels(List<LottiePixelJob> jobs) async {
    _requireOpen();
    return [
      for (final job in jobs)
        if (!_live.containsKey(job.handle.id) ||
            !job.hasValidSize ||
            !job.frame.isFinite ||
            job.frame < 0)
          null
        else
          _draw(job),
    ];
  }

  LottiePixels _draw(LottiePixelJob job) {
    final pixels = Uint8List(job.width * job.height * 4);
    final frame = job.frame.floor();
    for (var y = 0; y < job.height; y++) {
      for (var x = 0; x < job.width; x++) {
        pixels.setRange(
          (y * job.width + x) * 4,
          (y * job.width + x) * 4 + 4,
          pixelAt(x, y, frame),
        );
      }
    }
    return pixels;
  }

  @override
  Future<void> dispose(LottieHandle handle) async {
    _requireOpen();
    _live.remove(handle.id);
  }

  @override
  Future<void> close() async {
    _closed = true;
    _live.clear();
  }
}
