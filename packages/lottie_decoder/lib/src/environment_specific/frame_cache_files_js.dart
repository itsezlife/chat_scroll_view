import 'package:lottie_decoder/src/cache/frame_cache_files.dart';

/// The web hook behind `FrameCache(directoryPath:)`: the web has no directory
/// to keep entries in, so a cache there is memory only and a path is a host
/// mistake. It fails at construction, where it is made, instead of surfacing
/// later as a write that never lands.
FrameCacheFiles $openFrameCacheFiles(String path) => throw ArgumentError.value(
  path,
  'directoryPath',
  'the web keeps no frame cache files; pass null for memory only',
);
