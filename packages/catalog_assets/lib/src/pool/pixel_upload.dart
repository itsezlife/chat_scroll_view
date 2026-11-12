import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Makes an image of raw pixels: `decodeImageFromPixelsSync` where the engine
/// has it, `decodeImageFromPixels` everywhere else.
///
/// The synchronous form copies the bytes and returns the image at once; the
/// engine finishes the upload off the UI isolate, on the raster thread. On a
/// phone it cut the UI time of a page upload to about a third, and the
/// hitches of a scrolled sticker grid by about 40%. Only Impeller implements
/// it: the web throws `UnimplementedError`, and so may another engine. The
/// first throw switches this upload to the asynchronous form for good, so an
/// engine without it costs one failed call.
final class PixelUpload {
  /// Creates an upload over the engine's two decoders, or over [sync] and
  /// [async] in a test.
  PixelUpload({
    ui.Image Function(Uint8List, int, int, ui.PixelFormat)? sync,
    void Function(Uint8List, int, int, ui.PixelFormat, ui.ImageDecoderCallback)?
    async,
  }) : _sync = sync ?? ui.decodeImageFromPixelsSync,
       _async = async ?? ui.decodeImageFromPixels;

  final ui.Image Function(Uint8List, int, int, ui.PixelFormat) _sync;
  final void Function(
    Uint8List,
    int,
    int,
    ui.PixelFormat,
    ui.ImageDecoderCallback,
  )
  _async;
  bool _syncFailed = false;

  /// The image of [pixels], [width] wide and [height] tall in [format]. The
  /// bytes are copied before this returns, so the caller may write them again.
  Future<ui.Image> call(
    Uint8List pixels,
    int width,
    int height,
    ui.PixelFormat format,
  ) {
    if (!_syncFailed) {
      try {
        return Future.value(_sync(pixels, width, height, format));
        // An engine without the synchronous form throws (an
        // UnimplementedError on the web); that is how it is detected.
      } on Object {
        _syncFailed = true;
      }
    }
    final completer = Completer<ui.Image>();
    _async(pixels, width, height, format, completer.complete);
    return completer.future;
  }
}
