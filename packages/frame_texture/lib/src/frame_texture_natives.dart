import 'package:catalog_assets/catalog_assets.dart';
import 'package:meta/meta.dart';

/// A buffer of a texture, locked for writing: its first byte as a native
/// address and the bytes from one row to the next.
@immutable
final class LockedBuffer {
  /// Creates the pair.
  const LockedBuffer({required this.address, required this.rowStride});

  /// The first byte of the top row.
  final int address;

  /// Bytes from the start of one row to the start of the next.
  final int rowStride;
}

/// The native texture table a [PlatformFrameTextureHost] locks and posts
/// through: the C library the platform side attaches its surfaces to
/// (`native/include/frame_texture.h`).
///
/// The platform side owns which ids exist; the table answers by id. Its
/// rules are the C functions': [lock] answers null for a texture that is
/// unknown, destroyed, without a surface now, already locked or refused by
/// the platform, and never waits for another caller; [post] ends a lock and
/// does nothing for a texture that is not locked.
///
/// See also [PlatformFrameTextureHost], which keeps the sizes and the ids.
abstract interface class FrameTextureNatives {
  /// The addresses of the C `lock` and `post` a render isolate calls.
  FrameTextureEntryPoints get entryPoints;

  /// Locks texture [id], or answers null.
  LockedBuffer? lock(int id);

  /// Publishes texture [id]'s locked buffer and ends the lock.
  void post(int id);
}
