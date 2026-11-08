import 'dart:async';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:frame_texture/src/frame_texture_natives.dart';

/// The [FrameTextureHost] of a platform plugin (ADR 043): the platform makes
/// and destroys textures over a method channel, and every lock and post goes
/// through the native texture table ([FrameTextureNatives]), which the
/// platform side attaches each texture's surface to.
///
/// On Android a texture is a `SurfaceProducer` whose window the table locks
/// (`ANativeWindow_lock`) and posts (`ANativeWindow_unlockAndPost`), in
/// premultiplied RGBA. On iOS and macOS it is a `FlutterTexture` over a ring
/// of IOSurface-backed `CVPixelBuffer`s, in premultiplied BGRA.
/// `createPlatformFrameTextureHost` builds the host where
/// the platform has one; the constructor is for a test, which passes a
/// channel it answers and a table of its own.
///
/// The host remembers the size of each texture it made, since a lock gives
/// the size the texture was asked at (the table checks the buffer is at least
/// that big). [create] and [destroy] run on the UI isolate; a render isolate
/// locks and posts through [entryPoints], never through this object.
final class PlatformFrameTextureHost implements FrameTextureHost {
  /// Creates a host over [channel] and [natives].
  PlatformFrameTextureHost({
    required MethodChannel channel,
    required FrameTextureNatives natives,
    this.format = FrameTextureFormat.rgba8888,
    this.buffersPerTexture = androidBuffersPerTexture,
  }) : _channel = channel,
       _natives = natives;

  /// The channel the platform side answers on.
  static const String channelName = 'dev.chatscrollview.frame_texture';

  /// The buffers one Android texture holds in steady state: one the worker
  /// writes, the newest posted one, and up to two the engine still draws
  /// from (its producer keeps two frames in flight). The producer's queue
  /// may allocate up to seven when the platform thread falls behind; the
  /// pool's budget counts the steady state.
  static const int androidBuffersPerTexture = 4;

  /// The buffers one Apple texture holds at most, its pool's allocation
  /// threshold: the newest posted one (which the engine may hold as its last
  /// frame), the one the engine drew before it while the GPU may still read
  /// it, and the one the worker writes. A lock with all three out answers
  /// null.
  static const int appleBuffersPerTexture = 3;

  final MethodChannel _channel;
  final FrameTextureNatives _natives;
  final Map<int, ({int width, int height})> _sizes = {};

  @override
  final FrameTextureFormat format;

  @override
  final int buffersPerTexture;

  @override
  FrameTextureEntryPoints get entryPoints => _natives.entryPoints;

  /// Throws an [ArgumentError] for a size that is not positive; answers null
  /// when the platform refuses, or has no plugin to ask.
  @override
  Future<int?> create(int width, int height) async {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('a texture of ${width}x$height pixels');
    }
    final int? id;
    try {
      id = await _channel.invokeMethod<int>('create', {
        'width': width,
        'height': height,
      });
    } on PlatformException catch (error, stackTrace) {
      _report(error, stackTrace, 'while creating a frame texture');
      return null;
    } on MissingPluginException {
      return null;
    }
    if (id == null) return null;
    _sizes[id] = (width: width, height: height);
    return id;
  }

  @override
  FrameTextureTarget? lock(int id) {
    final size = _sizes[id];
    if (size == null) return null;
    final buffer = _natives.lock(id);
    if (buffer == null) return null;
    return FrameTextureTarget(
      address: buffer.address,
      rowStride: buffer.rowStride,
      format: format,
      width: size.width,
      height: size.height,
    );
  }

  /// Always reaches the table, even for a texture destroyed since its lock:
  /// the table ends that lock only at its post.
  @override
  void post(int id) => _natives.post(id);

  /// Forgets the texture at once (it never locks here again) and asks the
  /// platform to release it, without waiting for the answer.
  @override
  void destroy(int id) {
    if (_sizes.remove(id) == null) return;
    unawaited(
      _channel.invokeMethod<void>('destroy', id).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        _report(error, stackTrace, 'while destroying a frame texture');
      }),
    );
  }

  static void _report(Object error, StackTrace stackTrace, String context) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'frame_texture',
        context: ErrorDescription(context),
      ),
    );
  }
}
