import 'package:meta/meta.dart';

/// What one cached animation is: its content, the size it is displayed at and
/// the engine build that rendered it.
///
/// The size is the DISPLAY pixel size, not the size class of a pool cell: two
/// stickers of one file shown at 96 and at 100 px keep separate frames, since
/// a frame drawn for one is the wrong scale for the other. The engine version
/// is part of the key so an engine update, which may change pixels, never
/// serves frames the old engine drew; the old files age out through the disk
/// budget, or through the host's store when the cache has none.
///
/// Every part is validated and normalised here, once, because the key names a
/// file: [contentHash] and [engineVersion] are lower-cased (a case-insensitive
/// disk would otherwise alias two keys that compare unequal) and limited to
/// characters no path treats specially.
@immutable
final class FrameCacheKey {
  /// Creates a key; throws [ArgumentError] for a [contentHash] or an
  /// [engineVersion] outside its alphabet, or for a negative size.
  ///
  /// - [contentHash]: letters, digits and `-`;
  /// - [engineVersion]: letters, digits, `-` and `.`, starting with a letter or
  ///   a digit.
  ///
  /// `_` is in neither alphabet: it separates the parts of [toFileStem], so two
  /// different keys (or parities) can never spell one stem.
  factory FrameCacheKey({
    required String contentHash,
    required int width,
    required int height,
    required String engineVersion,
  }) {
    if (!_hashPattern.hasMatch(contentHash)) {
      throw ArgumentError.value(
        contentHash,
        'contentHash',
        'must be 1 to 128 letters, digits or "-"',
      );
    }
    if (!_enginePattern.hasMatch(engineVersion)) {
      throw ArgumentError.value(
        engineVersion,
        'engineVersion',
        'must be 1 to 64 letters, digits, "-" or ".", starting with a letter '
            'or a digit',
      );
    }
    if (width < 0) throw ArgumentError.value(width, 'width', 'is negative');
    if (height < 0) throw ArgumentError.value(height, 'height', 'is negative');
    return FrameCacheKey._(
      contentHash.toLowerCase(),
      width,
      height,
      engineVersion.toLowerCase(),
    );
  }

  const FrameCacheKey._(
    this.contentHash,
    this.width,
    this.height,
    this.engineVersion,
  );

  static final RegExp _hashPattern = RegExp(r'^[A-Za-z0-9-]{1,128}$');
  static final RegExp _enginePattern = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9.-]{0,63}$',
  );

  /// The default edge above which an animation is not cached: a frame that
  /// large costs more to hold than it saves to render.
  static const int defaultMaxEdge = 512;

  /// Identifies the animation's content (lower-cased).
  final String contentHash;

  /// Display width in pixels.
  final int width;

  /// Display height in pixels.
  final int height;

  /// The engine build that renders the frames (lower-cased).
  final String engineVersion;

  /// Whether the display size is cacheable: each edge from 1 to [maxEdge].
  bool admitted([int maxEdge = defaultMaxEdge]) =>
      width >= 1 && width <= maxEdge && height >= 1 && height <= maxEdge;

  /// The file name, without extension, of the [parity] frames of this key:
  /// safe characters only, and distinct for distinct keys and parities.
  String toFileStem(FrameParity parity) => '${_stem}_${parity.name}';

  String get _stem => '${contentHash}_${width}x${height}_$engineVersion';

  @override
  bool operator ==(Object other) =>
      other is FrameCacheKey &&
      other.contentHash == contentHash &&
      other.width == width &&
      other.height == height &&
      other.engineVersion == engineVersion;

  @override
  int get hashCode => Object.hash(contentHash, width, height, engineVersion);

  @override
  String toString() => 'FrameCacheKey($_stem)';
}

/// Which frames of an animation one cached file holds: the even ones or the
/// odd ones, each in order.
///
/// A playback at half rate (`AssetPaintContext.frameStepFor` is 2) asks only
/// for the even frames of a pass; one at full rate asks for all of them. A
/// file of every frame would never complete for the first, so it would stay
/// in RAM and never reach the disk; a file of the frames asked for, keyed by
/// the step, would hold the even frames twice and need the step to travel
/// with every frame job, which knows only its source and index (and an entry
/// played at both rates would switch keys at every paint).
/// Split by parity, the even file completes over one pass at either rate and
/// serves both, and the odd file completes over one pass at full rate. A file
/// never claims a frame it does not hold, so a half-rate fill never stands in
/// for a full one.
///
/// Parity covers the steps a playback has, 1 and 2; a step of 3 would need
/// a split by that step instead.
enum FrameParity {
  /// Frames 0, 2, 4 and so on.
  even,

  /// Frames 1, 3, 5 and so on.
  odd;

  /// The parity of frame [index] of an animation.
  static FrameParity of(int index) => index.isEven ? even : odd;

  /// Where frame [index] of an animation is among the frames of its parity.
  static int slotOf(int index) => index ~/ 2;

  /// How many frames of this parity an animation of [frameCount] frames has.
  int countIn(int frameCount) => switch (this) {
    even => (frameCount + 1) ~/ 2,
    odd => frameCount ~/ 2,
  };
}
