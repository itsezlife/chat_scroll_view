import 'dart:math' as math;
import 'dart:ui';

/// How content of one proportion fills a rectangle of another.
///
/// A surface chooses it per attach (`AssetProfile.fit`), because the same
/// decoded asset is a whole picture in one place and a filling one in another:
/// a sticker is never cut, a GIF in a grid cell fills the cell.
enum AssetFit {
  /// The whole content, as large as the rectangle holds, centred; the
  /// rectangle keeps bars on the axis the content does not fill.
  contain,

  /// The rectangle is filled; the content is cut on the axis that overflows,
  /// anchored at the centre. The reference client's grid GIF
  /// (`ImageReceiver`, `isAspectFit` false).
  cover;

  /// Which part of a picture of size [source] is drawn into which part of
  /// [destination].
  ///
  /// The source rectangle is in the picture's own pixels and starts at the
  /// origin; a picture that sits on a page at some offset adds its own. The
  /// destination is the whole of [destination] for [cover] and the inscribed
  /// part of it for [contain]. An empty source or destination is returned as
  /// given: there is nothing to scale.
  ({Rect source, Rect destination}) place(Size source, Rect destination) {
    if (source.isEmpty || destination.isEmpty) {
      return (source: Offset.zero & source, destination: destination);
    }
    final wide = destination.width / source.width;
    final tall = destination.height / source.height;
    switch (this) {
      case AssetFit.contain:
        final scale = math.min(wide, tall);
        final size = Size(source.width * scale, source.height * scale);
        return (
          source: Offset.zero & source,
          destination: Rect.fromCenter(
            center: destination.center,
            width: size.width,
            height: size.height,
          ),
        );
      case AssetFit.cover:
        final scale = math.max(wide, tall);
        final size = Size(
          destination.width / scale,
          destination.height / scale,
        );
        return (
          source: Rect.fromCenter(
            center: Offset(source.width / 2, source.height / 2),
            width: size.width,
            height: size.height,
          ),
          destination: destination,
        );
    }
  }
}
