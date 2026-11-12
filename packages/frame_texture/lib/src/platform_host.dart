/// Whether this platform has a texture host, decided by which file the build
/// picks: the hub behind [PlatformFrameTextureHost.forPlatform].
library;

export 'platform_host_vm.dart'
    if (dart.library.js_interop) 'platform_host_js.dart';
