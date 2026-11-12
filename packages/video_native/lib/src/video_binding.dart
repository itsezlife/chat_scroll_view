import 'dart:ffi';
import 'dart:typed_data';

import 'package:video_native/src/video_availability.dart';
import 'package:video_native/src/video_frame_result.dart';
import 'package:video_native/src/video_handle.dart';
import 'package:video_native/src/video_open_result.dart';

/// The native video decoder as the host sees it: open a file, pull frames
/// into page memory, rewind to loop, dispose.
///
/// Contract that the native binding and the fake satisfy; `VideoBindingContract`
/// in `testing.dart` states the behaviour they share. A binding is
/// single-isolate state, and one handle is used by one caller at a time.
abstract interface class VideoBinding {
  /// Whether the native library loaded and speaks the ABI version this
  /// package expects, and why not when it does not.
  ///
  /// Decided once at construction, so it never changes.
  VideoAvailability get availability;

  /// Whether [availability] is [VideoAvailability.available].
  ///
  /// The host registers a binding only when it is available; [open] and
  /// [nextFrame] on one that is not throw a [StateError].
  bool get isAvailable;

  /// Opens [bytes] (any container the build reads) for frames of exactly
  /// [width] by [height] pixels: frames are scaled to that size, not
  /// letterboxed, so the host picks an aspect-correct size.
  ///
  /// Never throws for bad data: a refused file is a [VideoRejected].
  VideoOpenResult open(
    Uint8List bytes, {
    required int width,
    required int height,
  });

  /// Decodes the next frame into [target], the top-left pixel of a slot of
  /// the size the video was opened at. Premultiplied BGRA, byte order
  /// `[B, G, R, A]`. [strideBytes] is the distance between rows.
  VideoFrameResult nextFrame(
    VideoHandle handle, {
    required Pointer<Uint8> target,
    required int strideBytes,
  });

  /// Seeks to the start for looping. Returns false for an unknown handle or
  /// a stream that cannot seek.
  bool rewind(VideoHandle handle);

  /// Releases [handle]. Idempotent.
  void dispose(VideoHandle handle);

  /// Frees every live handle and retires the binding. Idempotent; [open] and
  /// [nextFrame] afterwards throw a [StateError], and [dispose] stays
  /// harmless.
  void close();
}
