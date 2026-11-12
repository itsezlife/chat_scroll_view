import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:video_decoder/src/engine/video_element_port.dart';
import 'package:video_native/video_native.dart';

/// A browser without a browser: scripted files that open as
/// [VideoElementPort]s, for [WebVideoEngine] on the VM.
///
/// A frame `i` of an accepted file is the straight RGBA pixel
/// `[100 + i, 50, 20, 200]` over the whole target size, presented `i * 40` ms
/// in, so a test can name the premultiplied bytes it expects by hand. The
/// knobs make a port misbehave on purpose: never be ready, fail a frame, hold
/// frames back the way a hidden tab does.
final class FakeVideoElements {
  final _scripts = <String, _Script>{};
  final _ports = <_FakePort>[];

  /// How many ports were made and not disposed: the `<video>` elements alive.
  int get live => _ports.where((port) => !port.disposed).length;

  /// How many ports were ever made.
  int get created => _ports.length;

  /// While true, [VideoElementPort.nextFrame] waits for [releaseFrames], the
  /// way a browser presents nothing for a hidden tab.
  bool holdFrames = false;

  /// Makes [bytes] open as a video described by [metadata] with [frameCount]
  /// frames.
  void accept(
    Uint8List bytes,
    VideoElementMetadata metadata, {
    required int frameCount,
  }) => _scripts[_key(bytes)] = _Script(metadata, frameCount);

  /// Makes [bytes] fail to load for [reason]. Bytes never scripted fail as
  /// [VideoRejection.malformed].
  void reject(Uint8List bytes, VideoRejection reason) =>
      _scripts[_key(bytes)] = _Script.rejected(reason);

  /// Makes [bytes] never become ready.
  void neverReady(Uint8List bytes) =>
      _scripts[_key(bytes)] = const _Script.neverReady();

  /// Makes every frame of [bytes] after the first [after] frames throw.
  void failFramesFrom(Uint8List bytes, {required int after}) =>
      _scripts[_key(bytes)] = _scripts[_key(bytes)]!.failingAfter(after);

  /// Lets every frame waiting under [holdFrames] through.
  void releaseFrames() {
    for (final port in _ports) {
      port.release();
    }
  }

  static String _key(Uint8List bytes) => base64.encode(bytes);

  /// The factory a `WebVideoEngine` takes.
  VideoElementPort create(
    Uint8List bytes, {
    required int width,
    required int height,
  }) {
    final port = _FakePort(
      this,
      _scripts[_key(bytes)] ?? const _Script.rejected(VideoRejection.malformed),
      width,
      height,
    );
    _ports.add(port);
    return port;
  }
}

final class _Script {
  const _Script(this.metadata, this.frameCount)
    : rejection = null,
      ready = true,
      failFrom = null;
  const _Script.rejected(this.rejection)
    : metadata = null,
      frameCount = 0,
      ready = true,
      failFrom = null;
  const _Script.neverReady()
    : metadata = null,
      frameCount = 0,
      rejection = null,
      ready = false,
      failFrom = null;
  const _Script._(
    this.metadata,
    this.frameCount,
    this.rejection,
    this.ready,
    this.failFrom,
  );

  final VideoElementMetadata? metadata;
  final int frameCount;
  final VideoRejection? rejection;
  final bool ready;
  final int? failFrom;

  _Script failingAfter(int count) =>
      _Script._(metadata, frameCount, rejection, ready, count);
}

final class _FakePort implements VideoElementPort {
  _FakePort(this._owner, this._script, this._width, this._height);

  final FakeVideoElements _owner;
  final _Script _script;
  final int _width;
  final int _height;
  final _held = <Completer<void>>[];
  var _next = 0;
  bool disposed = false;

  @override
  Future<VideoElementMetadata> loadMetadata() async {
    if (!_script.ready) return Completer<VideoElementMetadata>().future;
    final rejection = _script.rejection;
    if (rejection != null) throw VideoElementFailure(rejection);
    return _script.metadata!;
  }

  @override
  Future<VideoElementFrameResult> nextFrame() async {
    if (_owner.holdFrames) {
      final gate = Completer<void>();
      _held.add(gate);
      await gate.future;
    }
    if (disposed) throw const VideoElementFailure(VideoRejection.internal);
    final failFrom = _script.failFrom;
    if (failFrom != null && _next >= failFrom) {
      throw const VideoElementFailure(VideoRejection.internal, 'scripted');
    }
    if (_next >= _script.frameCount) return const VideoElementEnded();
    final index = _next++;
    final rgba = Uint8List(_width * _height * 4);
    for (var at = 0; at < rgba.length; at += 4) {
      rgba.setRange(at, at + 4, [100 + index, 50, 20, 200]);
    }
    return VideoElementFrame(rgba, index * 40);
  }

  @override
  Future<void> rewind() async => _next = 0;

  void release() {
    for (final gate in _held) {
      if (!gate.isCompleted) gate.complete();
    }
    _held.clear();
  }

  @override
  void dispose() {
    disposed = true;
    release();
  }
}
