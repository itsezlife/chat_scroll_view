import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:lottie_native/src/lottie_binding.dart';
import 'package:lottie_native/src/lottie_load_result.dart';

/// A [LottieBinding] without a native library: scripted files, and jobs that
/// fill their slot with one premultiplied colour derived from the frame.
final class FakeLottieBinding implements LottieBinding {
  /// Creates a fake; with [available] false it behaves as a missing library.
  FakeLottieBinding({this.available = true});

  /// Whether [isAvailable] reports true.
  final bool available;

  /// Whether every otherwise valid job reports [LottieRenderStatus.failed].
  bool renderFails = false;

  final _scripted = <String, LottieLoadResult Function(int handle)>{};
  final _live = <int, LottieInfo>{};
  var _nextHandle = 1;

  /// How many loaded handles are not yet disposed.
  int get liveHandles => _live.length;

  /// Makes [bytes] load as an animation described by [info].
  void accept(Uint8List bytes, LottieInfo info) {
    _scripted[_key(bytes)] = (id) {
      _live[id] = info;
      return LottieLoaded(LottieHandle(id), info);
    };
  }

  /// Makes [bytes] refuse to load for [reason]. Bytes never scripted are
  /// refused as [LottieRejection.malformed].
  void reject(Uint8List bytes, LottieRejection reason) {
    _scripted[_key(bytes)] = (_) => LottieRejected(reason);
  }

  static String _key(Uint8List bytes) => base64.encode(bytes);

  @override
  bool get isAvailable => available;

  void _requireAvailable() {
    if (!available) {
      throw StateError('The Lottie binding is not available.');
    }
  }

  @override
  LottieLoadResult load(Uint8List bytes) {
    _requireAvailable();
    final script = _scripted[_key(bytes)];
    if (script == null) return const LottieRejected(LottieRejection.malformed);
    return script(_nextHandle++);
  }

  @override
  List<LottieRenderStatus> renderBatch(List<LottieRenderJob> jobs) {
    _requireAvailable();
    return [for (final job in jobs) _render(job)];
  }

  LottieRenderStatus _render(LottieRenderJob job) {
    final info = _live[job.handle.id];
    if (info == null ||
        job.target.address == 0 ||
        !job.frame.isFinite ||
        job.frame < 0) {
      return LottieRenderStatus.badArgument;
    }
    if (job.width <= 0 || job.height <= 0 || job.strideBytes < job.width * 4) {
      return LottieRenderStatus.badSize;
    }
    if (renderFails) return LottieRenderStatus.failed;

    // Alpha is fixed and the colour channels stay under it, so the pixel is a
    // valid premultiplied one; red moves with the frame so frames differ.
    const alpha = 200;
    final red = (job.frame.floor() * 16) % (alpha + 1);
    final pixel = [red, red ~/ 2, 0, alpha];
    final bytes = job.target.asTypedList(
      job.strideBytes * (job.height - 1) + job.width * 4,
    );
    for (var y = 0; y < job.height; y++) {
      for (var x = 0; x < job.width; x++) {
        bytes.setRange(
          y * job.strideBytes + x * 4,
          y * job.strideBytes + x * 4 + 4,
          pixel,
        );
      }
    }
    return LottieRenderStatus.ok;
  }

  @override
  void dispose(LottieHandle handle) {
    _live.remove(handle.id);
  }
}
