import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:lottie_native/src/lottie_availability.dart';
import 'package:lottie_native/src/lottie_binding.dart';
import 'package:lottie_native/src/lottie_handle.dart';
import 'package:lottie_native/src/lottie_load_result.dart';
import 'package:lottie_native/src/lottie_render_status.dart';

/// A [LottieBinding] without a native library: scripted files, and jobs that
/// fill their slot with one premultiplied colour derived from the frame.
final class FakeLottieBinding implements LottieBinding {
  /// Creates a fake that reports [availability]; anything but
  /// [LottieAvailability.available] behaves as an unusable library.
  FakeLottieBinding({this.availability = LottieAvailability.available});

  @override
  final LottieAvailability availability;

  /// Whether every otherwise valid job reports [LottieRenderStatus.failed].
  bool renderFails = false;

  // What each scripted file answers. A scripted LottieLoaded carries a
  // placeholder handle: load issues a fresh one per call.
  final _scripted = <String, LottieLoadResult>{};
  var _closed = false;
  final _live = <int, LottieInfo>{};
  var _nextHandle = 1;

  /// How many loaded handles are not yet disposed.
  int get liveHandles => _live.length;

  /// Makes [bytes] load as an animation described by [info].
  void accept(Uint8List bytes, LottieInfo info) {
    _scripted[_key(bytes)] = LottieLoaded(const LottieHandle(0), info);
  }

  /// Makes [bytes] refuse to load for [reason]. Bytes never scripted are
  /// refused as [LottieRejection.malformed].
  void reject(Uint8List bytes, LottieRejection reason) {
    _scripted[_key(bytes)] = LottieRejected(reason);
  }

  static String _key(Uint8List bytes) => base64.encode(bytes);

  @override
  bool get isAvailable => availability == LottieAvailability.available;

  void _requireAvailable() {
    if (!isAvailable) {
      throw StateError('The Lottie binding is not available.');
    }
    if (_closed) throw StateError('The Lottie binding is closed.');
  }

  @override
  LottieLoadResult load(Uint8List bytes) {
    _requireAvailable();
    return switch (_scripted[_key(bytes)]) {
      LottieLoaded(:final info) => _issue(info),
      final LottieRejected rejected => rejected,
      null => const LottieRejected(LottieRejection.malformed),
    };
  }

  LottieLoaded _issue(LottieInfo info) {
    final id = _nextHandle++;
    _live[id] = info;
    return LottieLoaded(LottieHandle(id), info);
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
    if (job.width <= 0 ||
        job.height <= 0 ||
        job.width > LottieRenderJob.maxEdge ||
        job.height > LottieRenderJob.maxEdge ||
        job.strideBytes < job.width * 4) {
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

  @override
  void close() {
    _closed = true;
    _live.clear();
  }
}
