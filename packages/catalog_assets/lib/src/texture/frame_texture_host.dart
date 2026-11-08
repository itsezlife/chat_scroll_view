import 'package:meta/meta.dart';

/// The order of the four bytes of a pixel in a locked texture. Pixels are
/// always premultiplied; the host says which channel order it locks with, and
/// the writer swizzles if its own output differs.
enum FrameTextureFormat {
  /// Red, green, blue, alpha, one byte each, in that order in memory.
  rgba8888,

  /// Blue, green, red, alpha, one byte each, in that order in memory.
  bgra8888,
}

/// Where a writer puts the pixels of one frame of a locked texture.
///
/// [address] is the first byte of the top row in the host's own memory, valid
/// from the lock until the post; rows are [rowStride] bytes apart, which is at
/// least `width * 4`. A writer writes inside `width x height` only.
@immutable
final class FrameTextureTarget {
  /// Creates a target.
  const FrameTextureTarget({
    required this.address,
    required this.rowStride,
    required this.format,
    required this.width,
    required this.height,
  });

  /// The first byte of the top row, as a native address.
  final int address;

  /// Bytes from the start of one row to the start of the next.
  final int rowStride;

  /// The channel order of the bytes.
  final FrameTextureFormat format;

  /// Pixels of a row the writer may write.
  final int width;

  /// Rows the writer may write.
  final int height;

  @override
  String toString() =>
      'FrameTextureTarget(${width}x$height, stride $rowStride, ${format.name})';
}

/// The addresses of a host's C entry points that a render isolate calls
/// through FFI, so a decoder writes into a texture without importing the
/// plugin that made it.
///
/// Their C signatures:
///
/// ```c
/// // The first byte of the texture's next buffer, its row stride in bytes
/// // written to *row_stride, or NULL when the texture cannot be locked at
/// // once (unknown, destroyed, already locked, or the platform refused).
/// void* lock(int64_t texture_id, int32_t* row_stride);
///
/// // Publishes what was written since the lock; does nothing for a texture
/// // that is not locked.
/// void post(int64_t texture_id);
/// ```
///
/// The pixel format is the host's [FrameTextureHost.format], the same for
/// every lock, so the C lock does not repeat it.
@immutable
final class FrameTextureEntryPoints {
  /// Creates the pair.
  const FrameTextureEntryPoints({required this.lock, required this.post});

  /// The address of the C `lock`.
  final int lock;

  /// The address of the C `post`.
  final int post;
}

/// The platform's maker of textures a render worker writes frames into
/// (ADR 043).
///
/// This package defines the seam and depends on no platform code; a plugin
/// implements it (an Android surface producer, an Apple pixel-buffer ring),
/// and a host registers one, through a `FrameTexturePool`, with the
/// `AssetCacheScope` at start-up. A platform without a host has none: every
/// playing asset keeps its slot on a dynamic page.
///
/// The host makes and destroys textures and gives write access to them. It
/// keeps no pool, no budget and no idea of size classes: the
/// `FrameTexturePool` above it does. [create] and [destroy] run on the UI
/// isolate; [lock] and [post] may also run on a render isolate, through the
/// C functions of [entryPoints].
///
/// ## Contract
///
/// - [create] gives a texture of the size asked, with an id no live texture
///   of this host has, or null when the platform cannot make one now. It
///   never throws for a refusal.
/// - [lock] gives a target for a live texture that is not locked, and null
///   otherwise; it never waits for the compositor. Every lock of a texture
///   gives the texture's size and the host's [format].
/// - [post] publishes the locked buffer and ends the lock; for a texture that
///   is not locked it does nothing.
/// - [destroy] ends a texture for good; a second call, or an unknown id, does
///   nothing. A destroyed texture never locks again.
///
/// `FrameTextureHostContract` in `testing.dart` checks these; every host runs
/// it.
abstract interface class FrameTextureHost {
  /// The channel order every lock gives.
  FrameTextureFormat get format;

  /// How many buffers one texture holds (the platform's queue), so a pool
  /// counts what a texture really costs: `width * height * 4` bytes each.
  int get buffersPerTexture;

  /// The C entry points a render isolate locks and posts through, or null for
  /// a host that has none (a fake, or a host only the UI isolate writes to).
  FrameTextureEntryPoints? get entryPoints;

  /// Makes a texture of [width] x [height] pixels and answers its id, or null
  /// when the platform cannot make one now.
  Future<int?> create(int width, int height);

  /// Locks texture [id] for writing.
  FrameTextureTarget? lock(int id);

  /// Publishes what was written into texture [id] since its lock.
  void post(int id);

  /// Destroys texture [id].
  void destroy(int id);
}
