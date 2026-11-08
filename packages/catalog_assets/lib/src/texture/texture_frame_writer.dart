import 'dart:typed_data';

import 'package:catalog_assets/src/asset/asset_texture.dart';
import 'package:meta/meta.dart';

/// One frame to write into one leased texture.
///
/// The texture counterpart of a `FrameJob`: [texture] is the whole square of
/// the size class, and the frame is [width] x [height] pixels, at most the
/// texture's size, written centred with transparent margins
/// ([TextureFrameRegion]).
@immutable
final class TextureFrameJob {
  /// Creates a job: frame [frame] of [source] at [width] x [height] pixels
  /// into [texture].
  const TextureFrameJob({
    required this.texture,
    required this.frame,
    required this.width,
    required this.height,
    required this.source,
  });

  /// The texture written: its id and its size.
  final AssetTexture texture;

  /// The frame to write, as the writer's source numbers them.
  final int frame;

  /// Pixels of a row of the frame, at most the texture's width.
  final int width;

  /// Rows of the frame, at most the texture's height.
  final int height;

  /// What to write, as the writer that made it understands it. The scheduler
  /// never looks inside.
  final Object source;
}

/// How one [TextureFrameJob] ended.
enum TextureFrameOutcome {
  /// The frame was written and posted: the texture shows it.
  posted,

  /// The texture could not be locked at once, so nothing was written and the
  /// texture keeps its previous frame (ADR 043, "Writing"). The frame may be
  /// asked again; a texture that keeps answering this goes back to a page
  /// slot (ADR 043, "Failure").
  notLocked,

  /// The source could not be rendered (a disposed handle, an engine error):
  /// the same as a failed job of a page, the asset shows its still.
  failed,
}

/// Writes frames into textures a render worker locks and posts, a batch at a
/// time (ADR 043, "Writing").
///
/// The texture counterpart of `FrameRenderer`: the scheduler that owns the
/// leases decides which frame each wants, and a writer (a decoder adapter)
/// locks each texture on its render isolate through the host's C entry
/// points, writes the frame at the target's stride in the host's channel
/// order, and posts.
///
/// ## Contract
///
/// - [write] completes with one [TextureFrameOutcome] per job, in job order.
///   It never throws for one bad job.
/// - A job that is posted was written whole: the frame centred, the margins
///   transparent, premultiplied in the host's format.
/// - A job that is not posted touches nothing the texture shows.
/// - An empty batch completes with an empty list.
abstract interface class TextureFrameWriter {
  /// Writes every job of [jobs].
  Future<List<TextureFrameOutcome>> write(List<TextureFrameJob> jobs);
}

/// Where a frame sits in a locked texture, and the byte work a writer does
/// there: clear the margins, copy packed rows in, swap red and blue.
///
/// A frame that is not the texture's shape is centred (rounding toward the
/// top left), so a surface that fits the whole texture into a cell shows it
/// where it would fit the frame. Every method takes the locked buffer as a
/// view of `rowStride * textureHeight` bytes from its first row; none
/// touches a byte past a row's pixels.
///
/// Pure Dart, so the decoders that write on their render isolates share it
/// and a test checks it without a texture.
@immutable
final class TextureFrameRegion {
  /// The region of a [width] x [height] frame in a [textureWidth] x
  /// [textureHeight] texture whose rows are [rowStride] bytes apart.
  ///
  /// Throws an [ArgumentError] for a frame larger than the texture or rows
  /// shorter than the texture's pixels.
  TextureFrameRegion({
    required this.textureWidth,
    required this.textureHeight,
    required this.rowStride,
    required this.width,
    required this.height,
  }) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError.value('${width}x$height', 'frame', 'has no pixels');
    }
    if (width > textureWidth || height > textureHeight) {
      throw ArgumentError.value(
        '${width}x$height',
        'frame',
        'is larger than the texture (${textureWidth}x$textureHeight)',
      );
    }
    if (rowStride < textureWidth * 4) {
      throw ArgumentError.value(
        rowStride,
        'rowStride',
        'is shorter than a row',
      );
    }
  }

  /// Pixels of a row of the texture.
  final int textureWidth;

  /// Rows of the texture.
  final int textureHeight;

  /// Bytes from the start of one row of the texture to the next.
  final int rowStride;

  /// Pixels of a row of the frame.
  final int width;

  /// Rows of the frame.
  final int height;

  /// The first column of the frame.
  int get left => (textureWidth - width) ~/ 2;

  /// The first row of the frame.
  int get top => (textureHeight - height) ~/ 2;

  /// Bytes from the texture's first byte to the frame's.
  int get offsetBytes => top * rowStride + left * 4;

  /// Zeroes (transparent) every pixel of the texture outside the frame: a
  /// pooled texture can hold another asset's frame, and a queue's buffers
  /// hold what was posted frames ago.
  void clearMargins(Uint8List target) {
    final top = this.top;
    final left = this.left;
    final rowBytes = textureWidth * 4;
    for (var y = 0; y < textureHeight; y++) {
      final row = y * rowStride;
      if (y < top || y >= top + height) {
        target.fillRange(row, row + rowBytes, 0);
        continue;
      }
      target
        ..fillRange(row, row + left * 4, 0)
        ..fillRange(row + (left + width) * 4, row + rowBytes, 0);
    }
  }

  /// Copies [pixels], `width * height * 4` bytes in packed rows, into the
  /// frame, swapping the first and third byte of each pixel when
  /// [swapRedBlue] is true (an engine's order is not the host's).
  void copyInto(
    Uint8List target,
    Uint8List pixels, {
    required bool swapRedBlue,
  }) {
    final start = offsetBytes;
    final rowBytes = width * 4;
    for (var y = 0; y < height; y++) {
      final to = start + y * rowStride;
      target.setRange(to, to + rowBytes, pixels, y * rowBytes);
    }
    if (swapRedBlue) this.swapRedBlue(target);
  }

  /// Swaps the first and third byte of every pixel of the frame, in place:
  /// RGBA to BGRA and back.
  void swapRedBlue(Uint8List target) {
    final start = offsetBytes;
    final aligned =
        (target.offsetInBytes + start) % 4 == 0 && rowStride % 4 == 0;
    for (var y = 0; y < height; y++) {
      final at = start + y * rowStride;
      if (aligned) {
        final words = Uint32List.view(
          target.buffer,
          target.offsetInBytes + at,
          width,
        );
        for (var x = 0; x < width; x++) {
          final v = words[x];
          // The first byte of the pixel is the low byte of the word on a
          // little-endian host and the high one otherwise.
          words[x] = Endian.host == Endian.little
              ? (v & 0xFF00FF00) | ((v >> 16) & 0xFF) | ((v & 0xFF) << 16)
              : (v & 0x00FF00FF) | ((v >> 16) & 0xFF00) | ((v & 0xFF00) << 16);
        }
      } else {
        for (var x = at; x < at + width * 4; x += 4) {
          final first = target[x];
          target[x] = target[x + 2];
          target[x + 2] = first;
        }
      }
    }
  }
}
