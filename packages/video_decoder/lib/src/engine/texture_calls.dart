import 'dart:ffi';
import 'dart:typed_data';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:ffi/ffi.dart';

/// A texture locked on this isolate: where its frame goes, and the view of
/// its whole buffer.
typedef LockedTexture = ({
  int address,
  TextureFrameRegion region,
  Uint8List view,
});

/// A host's C `lock` and `post` (see [FrameTextureEntryPoints]) bound on the
/// isolate that calls them, once per isolate and pair of addresses.
///
/// Native only. A decoder writes into a texture through these and never
/// imports the plugin that made it (ADR 043, "Package").
final class TextureCalls {
  TextureCalls._(FrameTextureEntryPoints points)
    : _lock =
          Pointer<
                NativeFunction<Pointer<Uint8> Function(Int64, Pointer<Int32>)>
              >.fromAddress(points.lock)
              .asFunction<Pointer<Uint8> Function(int, Pointer<Int32>)>(
                isLeaf: true,
              ),
      _post = Pointer<NativeFunction<Void Function(Int64)>>.fromAddress(
        points.post,
      ).asFunction<void Function(int)>(isLeaf: true);

  /// The calls of [points] on this isolate, bound on first use.
  // A lookup of the isolate's bound pairs, not a construction.
  // ignore: prefer_constructors_over_static_methods
  static TextureCalls of(FrameTextureEntryPoints points) =>
      _bound[(points.lock, points.post)] ??= TextureCalls._(points);

  static final Map<(int, int), TextureCalls> _bound = {};

  // One stride cell for every lock of the isolate, never freed: an isolate
  // binds a handful of hosts at most.
  static final Pointer<Int32> _stride = malloc<Int32>();

  final Pointer<Uint8> Function(int, Pointer<Int32>) _lock;
  final void Function(int) _post;

  /// Locks [texture] for a frame of [width] x [height] pixels and clears its
  /// margins, or answers null when it cannot be locked at once.
  LockedTexture? lock(AssetTexture texture, int width, int height) {
    final bits = _lock(texture.id, _stride);
    if (bits == nullptr) return null;
    final TextureFrameRegion region;
    try {
      region = TextureFrameRegion(
        textureWidth: texture.width,
        textureHeight: texture.height,
        rowStride: _stride.value,
        width: width,
        height: height,
      );
      // A frame that does not fit is the caller's bug; the lock must not
      // outlive it.
      // ignore: avoid_catching_errors
    } on ArgumentError {
      _post(texture.id);
      rethrow;
    }
    final view = bits.asTypedList(region.rowStride * texture.height);
    region.clearMargins(view);
    return (
      address: bits.address + region.offsetBytes,
      region: region,
      view: view,
    );
  }

  /// Posts [texture], ending its lock.
  void post(AssetTexture texture) => _post(texture.id);
}
