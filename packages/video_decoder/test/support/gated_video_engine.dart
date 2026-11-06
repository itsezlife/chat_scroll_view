import 'dart:async';
import 'dart:typed_data';

import 'package:video_decoder/testing.dart';
import 'package:video_decoder/video_decoder.dart';
import 'package:video_native/video_native.dart';

/// A [FakeVideoEngine] whose `nextFrame` a test can hold and release, and
/// that counts what it was asked: the slow engine of the scheduler tests.
final class GatedVideoEngine implements VideoEngine {
  GatedVideoEngine(this.inner);

  final FakeVideoEngine inner;
  final List<Completer<void>> _gates = [];
  bool _held = false;

  /// `nextFrame` calls per clip id.
  final Map<int, int> nextFrameCalls = {};

  /// Calls to `nextFrame` that have not completed, per clip id.
  final Map<int, int> inFlight = {};

  /// The most `nextFrame` calls of one clip that were ever pending at once.
  int maxInFlightPerClip = 0;

  /// Calls to `rewind`.
  int rewinds = 0;

  /// Clips closed.
  int closed = 0;

  /// Holds every later `nextFrame` until [release].
  void hold() => _held = true;

  /// Lets [count] held calls go (all when null) and stops holding.
  void release([int? count]) {
    final n = count ?? _gates.length;
    for (var i = 0; i < n && _gates.isNotEmpty; i++) {
      _gates.removeAt(0).complete();
    }
    if (count == null) _held = false;
  }

  @override
  Future<VideoClipOpenResult> open(
    Uint8List bytes, {
    required int width,
    required int height,
  }) => inner.open(bytes, width: width, height: height);

  @override
  Future<VideoFrameResult> nextFrame(
    VideoClip clip, {
    required Uint8List destination,
  }) async {
    nextFrameCalls[clip.id] = (nextFrameCalls[clip.id] ?? 0) + 1;
    final pending = inFlight[clip.id] = (inFlight[clip.id] ?? 0) + 1;
    if (pending > maxInFlightPerClip) maxInFlightPerClip = pending;
    try {
      if (_held) {
        final gate = Completer<void>();
        _gates.add(gate);
        await gate.future;
      }
      return await inner.nextFrame(clip, destination: destination);
    } finally {
      inFlight[clip.id] = inFlight[clip.id]! - 1;
    }
  }

  @override
  Future<bool> rewind(VideoClip clip) {
    rewinds++;
    return inner.rewind(clip);
  }

  @override
  Future<void> close(VideoClip clip) {
    closed++;
    return inner.close(clip);
  }

  @override
  Future<void> dispose() => inner.dispose();
}
