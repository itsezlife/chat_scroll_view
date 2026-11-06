import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:catalog_assets/frame_pool.dart';
import 'package:flutter/foundation.dart' show Listenable;
import 'package:video_decoder/src/renderer/video_frame_renderer.dart';
import 'package:video_decoder/src/renderer/video_frame_size.dart';

/// The frame pool of video: one `FrameAtlas` of its own, never the Lottie one.
abstract final class VideoFrameAtlas {
  /// Default byte budget of the video pages.
  ///
  /// Smaller than the Lottie pool's 48 MiB: a clip plays a handful at a time
  /// (the scheduler's cap) and each also keeps a few decoded frames outside
  /// the pool, so the pages are not where the memory goes.
  static const int defaultBudgetBytes = 32 * 1024 * 1024;

  /// Builds the atlas the `VideoFrameScheduler` owns.
  ///
  /// ## Why not the Lottie pool
  ///
  /// A separate instance, not a shared one, for three reasons ([ADR 042]):
  /// the budgets are independent (a screen of video must not evict stickers,
  /// nor the reverse); the page bytes are **BGRA** here because the engine
  /// decodes BGRA, and a pool takes one byte order for all its pages; and the
  /// renderer differs (it copies frames decoded ahead, it does not render).
  /// The pieces are the same `catalog_assets` ones: `FrameSlotAllocator`
  /// through `FramePool`, `FramePageImages`, `FrameAtlas`.
  ///
  /// [memory] holds the pages (Dart heap by default). [upload] turns a page
  /// into an image and defaults to [uploadBgraFramePage]; a test passes a
  /// stub. [memoryPressure], when given, evicts idle entries each time it
  /// fires.
  ///
  /// [ADR 042]: ../../../../docs/adr/042-native-media-decoding.md
  static FrameAtlas<Object> create({
    int budgetBytes = defaultBudgetBytes,
    List<int> sizeClasses = VideoFrameSize.defaultClasses,
    FramePageMemory? memory,
    FramePageUploader upload = uploadBgraFramePage,
    Listenable? memoryPressure,
  }) => FrameAtlas<Object>(
    renderer: const VideoFrameRenderer(),
    memory: memory ?? ListFramePageMemory(),
    budgetBytes: budgetBytes,
    sizeClasses: sizeClasses,
    upload: upload,
    memoryPressure: memoryPressure,
  );

  /// The upload of a BGRA page: `decodeImageFromPixels` as
  /// `rgba8888`, which copies the bytes when called.
  static Future<ui.Image> uploadBgraFramePage(Uint8List pixels, int side) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      pixels,
      side,
      side,
      ui.PixelFormat.bgra8888,
      completer.complete,
    );
    return completer.future;
  }
}
