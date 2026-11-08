/// The platform texture hosts of ADR 043.
///
/// A host calls `createPlatformFrameTextureHost` once at start-up and, when
/// it answers a host, registers it with the asset scope through a
/// `FrameTexturePool` (both from `catalog_assets`). Where it answers null
/// (every platform but Android so far, and the web), playing assets keep
/// their slots on dynamic pages.
library;

export 'src/frame_texture_natives.dart';
export 'src/platform_frame_texture_host.dart';
export 'src/platform_host.dart';
