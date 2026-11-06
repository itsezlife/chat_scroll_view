import 'dart:typed_data';

/// The pixel arithmetic of a frame a browser drew: straight RGBA in, the
/// engine contract's premultiplied BGRA out.
///
/// Here and not in the browser file so it runs on the VM, where the contract
/// and the unit tests are: `getImageData` is the only browser-specific step.
abstract final class VideoFramePixels {
  /// Writes [rgba] into the first `rgba.length` bytes of [bgra] as
  /// premultiplied BGRA.
  ///
  /// `getImageData` of a canvas with alpha hands back **straight** (not
  /// premultiplied) channels, while the engine contract, and the pool pages
  /// uploaded from it, are premultiplied: each colour is scaled by alpha and
  /// rounded to nearest, so a half-clear pixel is not drawn twice as bright.
  /// Red and blue swap places on the way.
  static void premultiplyRgbaIntoBgra(Uint8List rgba, Uint8List bgra) {
    for (var at = 0; at + 3 < rgba.length; at += 4) {
      final alpha = rgba[at + 3];
      if (alpha == 255) {
        bgra[at] = rgba[at + 2];
        bgra[at + 1] = rgba[at + 1];
        bgra[at + 2] = rgba[at];
      } else {
        bgra[at] = (rgba[at + 2] * alpha + 127) ~/ 255;
        bgra[at + 1] = (rgba[at + 1] * alpha + 127) ~/ 255;
        bgra[at + 2] = (rgba[at] * alpha + 127) ~/ 255;
      }
      bgra[at + 3] = alpha;
    }
  }

  /// Whether any pixel of [rgba] is not fully opaque.
  ///
  /// How the web engine decides `VideoInfo.hasAlpha`: a browser does not
  /// declare a stream's alpha, so the first frame is drawn and looked at.
  /// A clip whose first frame happens to be opaque reads as without alpha.
  static bool hasTransparency(Uint8List rgba) {
    for (var at = 3; at < rgba.length; at += 4) {
      if (rgba[at] != 255) return true;
    }
    return false;
  }
}
