import 'dart:ffi';
import 'dart:io';

import 'package:catalog_assets/catalog_assets.dart';
import 'package:ffi/ffi.dart';
import 'package:frame_texture/src/frame_texture_natives.dart';

typedef _LockNative = Pointer<Void> Function(Int64 id, Pointer<Int32> stride);
typedef _Lock = Pointer<Void> Function(int id, Pointer<Int32> stride);
typedef _PostNative = Void Function(Int64 id);
typedef _Post = void Function(int id);

/// [FrameTextureNatives] over the C library (`native/include/frame_texture.h`).
///
/// Neither call is a leaf: `ANativeWindow_lock` may wait for a buffer of the
/// queue, an Apple lock may allocate a pixel buffer, and a leaf call would
/// hold every isolate of the group at a safepoint meanwhile.
final class FfiFrameTextureNatives implements FrameTextureNatives {
  /// Binds the functions of [library].
  FfiFrameTextureNatives(DynamicLibrary library)
    : _lockPointer = library.lookup<NativeFunction<_LockNative>>(
        'frame_texture_lock',
      ),
      _postPointer = library.lookup<NativeFunction<_PostNative>>(
        'frame_texture_post',
      ),
      _count = library.lookupFunction<Int32 Function(), int Function()>(
        'frame_texture_count',
      ) {
    _lock = _lockPointer.asFunction<_Lock>();
    _post = _postPointer.asFunction<_Post>();
  }

  /// The file the Android plugin builds (`android/CMakeLists.txt`). The
  /// plugin loads it first (`System.loadLibrary`); opening it by name here
  /// gives the same instance, since both loads go through the app's linker
  /// namespace, so the windows the plugin attaches are the ones locked here.
  static const String androidLibrary = 'libframe_texture.so';

  /// The table of the Android plugin, or null where it is not loaded (not
  /// Android, or an app built without the plugin).
  static FfiFrameTextureNatives? openAndroid() {
    if (!Platform.isAndroid) return null;
    try {
      return FfiFrameTextureNatives(DynamicLibrary.open(androidLibrary));
    } on Object {
      // ArgumentError (no such file) or a missing symbol.
      return null;
    }
  }

  /// The table of the Apple plugin (`darwin/Classes/FrameTexturePlugin.m`),
  /// or null where it is not linked (not iOS or macOS, or an app built
  /// without the plugin). The plugin's framework is loaded with the app, so
  /// its exported functions are found in the process.
  static FfiFrameTextureNatives? openApple() {
    if (!Platform.isIOS && !Platform.isMacOS) return null;
    try {
      return FfiFrameTextureNatives(DynamicLibrary.process());
    } on Object {
      // ArgumentError: a missing symbol (no plugin in this process).
      return null;
    }
  }

  final Pointer<NativeFunction<_LockNative>> _lockPointer;
  final Pointer<NativeFunction<_PostNative>> _postPointer;
  late final _Lock _lock;
  late final _Post _post;
  final int Function() _count;

  // The stride out-parameter of the UI isolate's locks: one cell, reused
  // (the UI isolate is single-threaded) and kept for the process.
  static final Pointer<Int32> _stride = malloc<Int32>();

  @override
  FrameTextureEntryPoints get entryPoints => FrameTextureEntryPoints(
    lock: _lockPointer.address,
    post: _postPointer.address,
  );

  /// How many textures the table holds: the probe that the plugin and this
  /// side share one copy of the library.
  int get textureCount => _count();

  @override
  LockedBuffer? lock(int id) {
    final bits = _lock(id, _stride);
    if (bits == nullptr) return null;
    return LockedBuffer(address: bits.address, rowStride: _stride.value);
  }

  @override
  void post(int id) => _post(id);
}
