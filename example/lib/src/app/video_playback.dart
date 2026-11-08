import 'dart:async';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:chat_scroll_view_example/src/app/environment_specific/video_playback.dart'
    as environment_specific;
import 'package:chat_scroll_view_example/src/common/scroll_lab.dart';
import 'package:flutter/foundation.dart';
import 'package:l/l.dart';
import 'package:video_decoder/video_decoder.dart';

/// The video decoder of a host that can run one, and how to stop what it
/// needs.
///
/// A [VideoPlayback] exists only after the engine was probed by starting it;
/// a host without the library has none. [close] runs the [shutdown] steps in
/// the order given and only once; the platform file that built the playback
/// owns the order (the frame scheduler, then the engine it decodes with).
///
/// This is the shape of `LottiePlayback`, written out again rather than
/// shared: two facades are not yet a repetition worth a third type, and the
/// two differ in what they own (a cache and page memory there, nothing here).
final class VideoPlayback {
  /// Creates a playback of [decoder] that [close] stops by running [shutdown].
  VideoPlayback({
    required this.decoder,
    required List<FutureOr<void> Function()> shutdown,
  }) : _shutdown = List.unmodifiable(shutdown);

  /// The decoder to register for video-coded media.
  final Decoder decoder;

  /// The platform's [VideoPlaybackStarter]: the native library behind
  /// `dart:ffi` where there is one, the browser's own `<video>` element behind
  /// `dart:js_interop` on the web.
  ///
  /// Decided by which file the build picks (the `$startVideoPlayback` hook):
  /// `dart:ffi` is not importable in a web build, so the native file must not
  /// be reachable from it.
  static Future<VideoPlayback?> start({
    required PlaybackClock clock,
    required Listenable memoryPressure,
    FrameTexturePool? textures,
  }) => environment_specific.$startVideoPlayback(
    clock: clock,
    memoryPressure: memoryPressure,
    textures: textures,
  );

  /// Starts the video decoder over an engine from [engineFactory], or answers
  /// null.
  ///
  /// [textures] and [textureWriter] (which makes the writer of the engine, or
  /// null for one that cannot write textures) let playing clips take platform
  /// textures (ADR 043).
  ///
  /// [engineFactory] is the probe: any failure to produce an engine (the native
  /// library missing, a browser that refuses) logs once, with the error's type,
  /// and gives no playback, so nothing is registered and video keeps its
  /// placeholder. Neutral Dart on purpose, with no `dart:js_interop` and no
  /// `dart:ffi`, so the composition runs on the VM in tests over an engine on a
  /// fake; the platform files supply only the factory.
  static Future<VideoPlayback?> startPixel({
    required PlaybackClock clock,
    required Listenable memoryPressure,
    required Future<VideoEngine> Function() engineFactory,
    FrameTexturePool? textures,
    TextureFrameWriter? Function(VideoEngine engine)? textureWriter,
  }) async {
    final VideoEngine engine;
    try {
      engine = await engineFactory();
    } on Object catch (reason, stackTrace) {
      // The probe's answer, not a bug to propagate: whatever stopped the
      // engine starting, the app boots without video.
      VideoPlayback.reportUnavailable(reason, stackTrace);
      return null;
    }
    final scheduler = VideoFrameScheduler(
      engine: engine,
      atlas: VideoFrameAtlas.create(memoryPressure: memoryPressure),
      clock: clock,
      maxAdvancing: ScrollLab.videoCap.value,
      textures: textures,
      textureWriter: textureWriter?.call(engine),
    )..texturesEnabled = ScrollLab.textures.value;
    // The scroll lab's `video_cap` and `textures` switches change the live
    // scheduler.
    void applyCap() => scheduler.maxAdvancing = ScrollLab.videoCap.value;
    void applyTextures() =>
        scheduler.texturesEnabled = ScrollLab.textures.value;
    ScrollLab.videoCap.addListener(applyCap);
    ScrollLab.textures.addListener(applyTextures);
    // The scheduler goes first: it may still be asking the engine for frames.
    // The engine is disposed last and frees every clip still open.
    return VideoPlayback(
      decoder: VideoDecoder(engine: engine, scheduler: scheduler),
      shutdown: [
        () => ScrollLab.videoCap.removeListener(applyCap),
        () => ScrollLab.textures.removeListener(applyTextures),
        scheduler.dispose,
        engine.dispose,
      ],
    );
  }

  /// Says, once, that the engine could not start and no decoder is
  /// registered: the one log line of "the probe failed", with the error's
  /// type so a missing library and a bug read apart.
  static void reportUnavailable(Object reason, StackTrace stackTrace) => l.w(
    'Video stickers are off (${reason.runtimeType}): $reason',
    stackTrace,
  );

  final List<FutureOr<void> Function()> _shutdown;
  Future<void>? _closing;

  /// Stops the playback. Idempotent: every call answers the same future.
  ///
  /// A step that fails does not skip the ones after it: the engine must be
  /// disposed even when the scheduler would not stop. The first failure is
  /// rethrown once every step has run.
  Future<void> close() => _closing ??= _run();

  Future<void> _run() async {
    Object? failure;
    StackTrace? trace;
    for (final step in _shutdown) {
      try {
        await step();
        // Every step runs; the first failure is the one reported.
        // ignore: avoid_catches_without_on_clauses
      } catch (error, stack) {
        failure ??= error;
        trace ??= stack;
      }
    }
    if (failure != null) Error.throwWithStackTrace(failure, trace!);
  }
}

/// Starts the video decoder over [clock] (the one the frame scheduler
/// follows) and [memoryPressure] (which releases the idle frames), or answers
/// null when this build cannot run one and the decoder must not be registered.
/// `textures` is the platform's texture pool (ADR 043), null where there is
/// none; a platform whose engine cannot write textures ignores it.
typedef VideoPlaybackStarter =
    Future<VideoPlayback?> Function({
      required PlaybackClock clock,
      required Listenable memoryPressure,
      FrameTexturePool? textures,
    });
