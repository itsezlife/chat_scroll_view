import 'package:catalog_assets/catalog_assets.dart';

import 'package:frame_texture/src/platform_frame_texture_host.dart';

/// The web hook behind [PlatformFrameTextureHost.forPlatform]: the web has no
/// texture host (ADR 043), and its playing assets keep the worker path of
/// ADR 042.
FrameTextureHost? $createPlatformFrameTextureHost() => null;
