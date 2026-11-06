// The C ABI of native/include/chat_video.h, bound by hand: six functions are
// too few to be worth putting LLVM (ffigen) on every contributor. The asset
// id of these `@Native`s is this file's library URI, which is the name
// hook/build.dart registers the library under; moving this file means
// changing `chatVideoAssetName` there.
// The names mirror the header one to one and are documented there.
// ignore_for_file: public_member_api_docs
import 'dart:ffi';

/// The ABI version of `chat_video.h` the bindings were written against.
const chatVideoExpectedAbiVersion = 1;

/// The status numbers of `chat_video.h`, in one place so no other file
/// carries a bare literal. A test compares them with the header.
abstract final class ChatVideoStatus {
  static const endOfStream = 1;
  static const ok = 0;
  static const invalidArgument = -1;
  static const tooLarge = -2;
  static const malformed = -3;
  static const limitExceeded = -4;
  static const unsupported = -5;
  static const internal = -6;
  static const badSize = -7;
  static const decodeFailed = -8;
}

/// `ChatVideoInfo`.
final class ChatVideoInfo extends Struct {
  @Uint32()
  external int width;

  @Uint32()
  external int height;

  @Int64()
  external int durationMs;

  @Float()
  external double frameRate;

  @Uint32()
  external int hasAlpha;
}

/// The load probe: returns 1. A leaf: it is instant.
@Native<Uint32 Function()>(isLeaf: true, symbol: 'chat_video_abi_version')
external int chatVideoAbiVersion();

/// Not a leaf: probing a container and opening a decoder run long enough to
/// stall the isolate group at a safepoint.
@Native<
  Int32 Function(Pointer<Uint8>, Size, Uint32, Uint32, Pointer<Pointer<Void>>)
>(symbol: 'chat_video_open')
external int chatVideoOpen(
  Pointer<Uint8> data,
  int len,
  int targetW,
  int targetH,
  Pointer<Pointer<Void>> outHandle,
);

/// A leaf: it only copies a few fields.
@Native<Int32 Function(Pointer<Void>, Pointer<ChatVideoInfo>)>(
  isLeaf: true,
  symbol: 'chat_video_info',
)
external int chatVideoInfo(Pointer<Void> handle, Pointer<ChatVideoInfo> out);

/// Not a leaf: a decode and a scale are long.
@Native<Int32 Function(Pointer<Void>, Pointer<Uint8>, Size, Pointer<Int64>)>(
  symbol: 'chat_video_next',
)
external int chatVideoNext(
  Pointer<Void> handle,
  Pointer<Uint8> dst,
  int stride,
  Pointer<Int64> outPtsMs,
);

/// Not a leaf: a seek reads the container.
@Native<Int32 Function(Pointer<Void>)>(symbol: 'chat_video_rewind')
external int chatVideoRewind(Pointer<Void> handle);

/// Not a leaf: closing a decoder joins its threads.
@Native<Void Function(Pointer<Void>)>(symbol: 'chat_video_free')
external void chatVideoFree(Pointer<Void> handle);
