import 'package:catalog_assets/catalog_assets.dart';
import 'package:flutter/services.dart';
import 'package:frame_texture/src/ffi_frame_texture_natives.dart';
import 'package:frame_texture/src/platform_frame_texture_host.dart';

/// The texture host of this platform, or null where there is none.
///
/// Android answers a [PlatformFrameTextureHost] once the plugin's library is
/// in the app; every other platform answers null for now (the Apple host is
/// a later ticket), and so does the web. Call it once: each call makes a new
/// host.
FrameTextureHost? createPlatformFrameTextureHost() {
  final natives = FfiFrameTextureNatives.openAndroid();
  if (natives == null) return null;
  return PlatformFrameTextureHost(
    channel: const MethodChannel(PlatformFrameTextureHost.channelName),
    natives: natives,
  );
}
