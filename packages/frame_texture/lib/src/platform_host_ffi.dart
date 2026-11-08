import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter/services.dart';
import 'package:frame_texture/src/ffi_frame_texture_natives.dart';
import 'package:frame_texture/src/platform_frame_texture_host.dart';

/// The texture host of this platform, or null where there is none.
///
/// Android, iOS and macOS answer a [PlatformFrameTextureHost] once the
/// plugin's native side is in the app; every other platform answers null,
/// and so does the web. Call it once: each call makes a new host.
FrameTextureHost? createPlatformFrameTextureHost() {
  const channel = MethodChannel(PlatformFrameTextureHost.channelName);
  if (FfiFrameTextureNatives.openAndroid() case final natives?) {
    return PlatformFrameTextureHost(channel: channel, natives: natives);
  }
  if (FfiFrameTextureNatives.openApple() case final natives?) {
    return PlatformFrameTextureHost(
      channel: channel,
      natives: natives,
      format: FrameTextureFormat.bgra8888,
      buffersPerTexture: PlatformFrameTextureHost.appleBuffersPerTexture,
    );
  }
  return null;
}
